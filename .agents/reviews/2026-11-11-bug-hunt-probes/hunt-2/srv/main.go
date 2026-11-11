// Byte-scripted h2c (prior knowledge) server. Scenario file (JSON) maps the
// method name (last path segment) to steps; it is re-read on every request.
// Every request is appended to the log file as one JSON line.
package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

type Step struct {
	H      [][]string `json:"h"`
	D      *string    `json:"d"`
	Fill   int        `json:"fill"`
	Chunk  int        `json:"chunk"`
	End    bool       `json:"end"`
	Rst    *uint32    `json:"rst"`
	Goaway *uint32    `json:"goaway"`
	Sleep  int        `json:"sleep"`
	Close  bool       `json:"close"`
	Raw    string     `json:"raw"`
	GapMs  int        `json:"gap"`
}

type Req struct {
	Time    string     `json:"time"`
	Stream  uint32     `json:"stream"`
	Headers [][]string `json:"headers"`
	BodyHex string     `json:"body_hex"`
	BodyLen int        `json:"body_len"`
	Frames  []int      `json:"data_frames"`
	Events  []string   `json:"events"`
}

var scenFile, logFile string
var logMu sync.Mutex

func logLine(v any) {
	logMu.Lock()
	defer logMu.Unlock()
	f, _ := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	b, _ := json.Marshal(v)
	f.Write(append(b, '\n'))
	f.Close()
}

type conn struct {
	c       net.Conn
	fr      *http2.Framer
	wmu     sync.Mutex
	henc    *hpack.Encoder
	hbuf    bytes.Buffer
	cond    *sync.Cond
	connWin int64
	initWin int64
	swin    map[uint32]*int64
	dead    bool
}

type sreq struct {
	id      uint32
	headers [][]string
	body    bytes.Buffer
	frames  []int
}

func (cn *conn) writeHeaders(id uint32, kv [][]string, end bool) {
	cn.wmu.Lock()
	defer cn.wmu.Unlock()
	cn.hbuf.Reset()
	for _, p := range kv {
		v := p[1]
		if strings.HasPrefix(v, "hex:") {
			b, _ := hex.DecodeString(v[4:])
			v = string(b)
		}
		cn.henc.WriteField(hpack.HeaderField{Name: p[0], Value: v})
	}
	cn.fr.WriteHeaders(http2.HeadersFrameParam{StreamID: id, BlockFragment: cn.hbuf.Bytes(), EndHeaders: true, EndStream: end})
}

func (cn *conn) writeData(id uint32, data []byte, end bool, chunk int, gap int) {
	if chunk <= 0 {
		chunk = 16384
	}
	if len(data) == 0 {
		cn.wmu.Lock()
		cn.fr.WriteData(id, end, nil)
		cn.wmu.Unlock()
		return
	}
	for off := 0; off < len(data); {
		n := chunk
		if off+n > len(data) {
			n = len(data) - off
		}
		cn.cond.L.Lock()
		for !cn.dead && (cn.connWin <= 0 || *cn.swin[id] <= 0) {
			cn.cond.Wait()
		}
		if cn.dead {
			cn.cond.L.Unlock()
			return
		}
		if int64(n) > cn.connWin {
			n = int(cn.connWin)
		}
		if int64(n) > *cn.swin[id] {
			n = int(*cn.swin[id])
		}
		cn.connWin -= int64(n)
		*cn.swin[id] -= int64(n)
		cn.cond.L.Unlock()
		last := off+n == len(data)
		cn.wmu.Lock()
		cn.fr.WriteData(id, end && last, data[off:off+n])
		cn.wmu.Unlock()
		off += n
		if gap > 0 && !last {
			time.Sleep(time.Duration(gap) * time.Millisecond)
		}
	}
}

func (cn *conn) run(r *sreq) {
	var path string
	for _, p := range r.headers {
		if p[0] == ":path" {
			path = p[1]
		}
	}
	name := path[strings.LastIndex(path, "/")+1:]
	logLine(Req{Time: time.Now().Format(time.RFC3339Nano), Stream: r.id, Headers: r.headers,
		BodyHex: hexCap(r.body.Bytes()), BodyLen: r.body.Len(), Frames: r.frames})
	b, err := os.ReadFile(scenFile)
	var scen map[string][]Step
	if err == nil {
		err = json.Unmarshal(b, &scen)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "scenario error:", err)
	}
	steps, ok := scen[name]
	if !ok {
		cn.writeHeaders(r.id, [][]string{{":status", "200"}, {"content-type", "application/grpc"}, {"grpc-status", "12"}, {"grpc-message", "no scenario " + name}}, true)
		return
	}
	for _, s := range steps {
		switch {
		case s.H != nil:
			cn.writeHeaders(r.id, s.H, s.End)
		case s.D != nil || s.Fill > 0:
			var data []byte
			if s.D != nil {
				data, _ = hex.DecodeString(*s.D)
			}
			if s.Fill > 0 {
				data = append(data, make([]byte, s.Fill)...)
			}
			cn.writeData(r.id, data, s.End, s.Chunk, s.GapMs)
		case s.Rst != nil:
			cn.wmu.Lock()
			cn.fr.WriteRSTStream(r.id, http2.ErrCode(*s.Rst))
			cn.wmu.Unlock()
		case s.Goaway != nil:
			cn.wmu.Lock()
			cn.fr.WriteGoAway(r.id, http2.ErrCode(*s.Goaway), nil)
			cn.wmu.Unlock()
		case s.Raw != "":
			raw, _ := hex.DecodeString(s.Raw)
			cn.wmu.Lock()
			cn.c.Write(raw)
			cn.wmu.Unlock()
		case s.Close:
			cn.c.Close()
		}
		if s.Sleep > 0 {
			time.Sleep(time.Duration(s.Sleep) * time.Millisecond)
		}
	}
}

func hexCap(b []byte) string {
	if len(b) > 4096 {
		return hex.EncodeToString(b[:4096]) + "..."
	}
	return hex.EncodeToString(b)
}

func serve(c net.Conn) {
	defer c.Close()
	preface := make([]byte, len(http2.ClientPreface))
	if _, err := io.ReadFull(c, preface); err != nil || string(preface) != http2.ClientPreface {
		logLine(map[string]string{"event": "bad preface", "got": string(preface)})
		return
	}
	cn := &conn{c: c, fr: http2.NewFramer(c, c), connWin: 65535, initWin: 65535, swin: map[uint32]*int64{}}
	cn.cond = sync.NewCond(&sync.Mutex{})
	cn.henc = hpack.NewEncoder(&cn.hbuf)
	cn.fr.ReadMetaHeaders = hpack.NewDecoder(4096, nil)
	cn.fr.MaxHeaderListSize = 1 << 24
	cn.fr.WriteSettings(http2.Setting{ID: http2.SettingInitialWindowSize, Val: 1 << 30}, http2.Setting{ID: http2.SettingMaxFrameSize, Val: 1 << 20})
	cn.fr.WriteWindowUpdate(0, 1<<30)
	reqs := map[uint32]*sreq{}
	defer func() {
		cn.cond.L.Lock()
		cn.dead = true
		cn.cond.Broadcast()
		cn.cond.L.Unlock()
	}()
	for {
		f, err := cn.fr.ReadFrame()
		if err != nil {
			logLine(map[string]string{"event": "conn end", "err": err.Error()})
			return
		}
		switch f := f.(type) {
		case *http2.SettingsFrame:
			if f.IsAck() {
				continue
			}
			f.ForeachSetting(func(s http2.Setting) error {
				if s.ID == http2.SettingInitialWindowSize {
					cn.cond.L.Lock()
					d := int64(s.Val) - cn.initWin
					cn.initWin = int64(s.Val)
					for _, w := range cn.swin {
						*w += d
					}
					cn.cond.Broadcast()
					cn.cond.L.Unlock()
				}
				return nil
			})
			cn.wmu.Lock()
			cn.fr.WriteSettingsAck()
			cn.wmu.Unlock()
		case *http2.PingFrame:
			if !f.IsAck() {
				cn.wmu.Lock()
				cn.fr.WritePing(true, f.Data)
				cn.wmu.Unlock()
			}
		case *http2.WindowUpdateFrame:
			cn.cond.L.Lock()
			if f.StreamID == 0 {
				cn.connWin += int64(f.Increment)
			} else if w, ok := cn.swin[f.StreamID]; ok {
				*w += int64(f.Increment)
			}
			cn.cond.Broadcast()
			cn.cond.L.Unlock()
		case *http2.MetaHeadersFrame:
			r := &sreq{id: f.StreamID}
			for _, hf := range f.Fields {
				r.headers = append(r.headers, []string{hf.Name, hf.Value})
			}
			reqs[f.StreamID] = r
			cn.cond.L.Lock()
			w := cn.initWin
			cn.swin[f.StreamID] = &w
			cn.cond.L.Unlock()
			if f.StreamEnded() {
				go cn.run(r)
			}
		case *http2.DataFrame:
			r := reqs[f.StreamID]
			if r == nil {
				continue
			}
			r.body.Write(f.Data())
			r.frames = append(r.frames, len(f.Data()))
			if f.StreamEnded() {
				go cn.run(r)
			}
		case *http2.RSTStreamFrame:
			logLine(map[string]any{"event": "rst_stream", "stream": f.StreamID, "code": uint32(f.ErrCode)})
		case *http2.GoAwayFrame:
			logLine(map[string]any{"event": "goaway", "code": uint32(f.ErrCode)})
		}
	}
}

func main() {
	port := flag.Int("port", 0, "")
	flag.StringVar(&scenFile, "scen", "scen.json", "")
	flag.StringVar(&logFile, "log", "req.log", "")
	flag.Parse()
	l, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", *port))
	if err != nil {
		panic(err)
	}
	fmt.Println(l.Addr().(*net.TCPAddr).Port)
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		go serve(c)
	}
}
