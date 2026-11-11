// Raw HTTP/2 (h2c prior knowledge) server with scripted scenarios.
// Scenario is taken from request header x-scn: a comma separated list of steps:
//   h            response HEADERS (200, application/grpc)
//   mN           N one-byte-payload gRPC messages in ONE DATA frame (payload = running index)
//   MN           one message with N-byte payload
//   p            partial message: prefix says 10 bytes, sends 3
//   b            bad flag prefix (flag=7,len=1,payload)
//   sN           sleep N ms
//   tN           trailers with grpc-status N (END_STREAM)
//   e            empty DATA with END_STREAM (no trailers)
//   g            GOAWAY
//   x            RST_STREAM from server
//   c            close the connection
//   w            wait forever (until peer RST or connection closes)
// Logs every received frame of interest with conn id and stream id.
package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

var logMu sync.Mutex
var logF *os.File
var connSeq int
var t0 = time.Now()

func logf(format string, a ...any) {
	logMu.Lock()
	defer logMu.Unlock()
	fmt.Fprintf(logF, "%7.3f "+format+"\n", append([]any{time.Since(t0).Seconds()}, a...)...)
	
}

type conn struct {
	id   int
	c    net.Conn
	fr   *http2.Framer
	wmu  sync.Mutex
	enc  *hpack.Encoder
	ebuf bytes.Buffer
	rst  map[uint32]chan struct{}
	mu   sync.Mutex
	dead chan struct{}
}

func (c *conn) headers(sid uint32, end bool, kv ...string) {
	c.wmu.Lock()
	defer c.wmu.Unlock()
	c.ebuf.Reset()
	for i := 0; i < len(kv); i += 2 {
		c.enc.WriteField(hpack.HeaderField{Name: kv[i], Value: kv[i+1]})
	}
	c.fr.WriteHeaders(http2.HeadersFrameParam{StreamID: sid, BlockFragment: c.ebuf.Bytes(), EndHeaders: true, EndStream: end})
}
func (c *conn) data(sid uint32, end bool, b []byte) {
	c.wmu.Lock()
	defer c.wmu.Unlock()
	for len(b) > 16384 {
		c.fr.WriteData(sid, false, b[:16384])
		b = b[16384:]
	}
	c.fr.WriteData(sid, end, b)
}

func msg(payload []byte) []byte {
	out := make([]byte, 5+len(payload))
	binary.BigEndian.PutUint32(out[1:5], uint32(len(payload)))
	copy(out[5:], payload)
	return out
}

func (c *conn) run(sid uint32, scn string, cancel chan struct{}) {
	idx := 0
	for _, st := range strings.Split(scn, ",") {
		if st == "" {
			continue
		}
		select {
		case <-cancel:
			logf("conn=%d stream=%d scenario-stopped-by-rst at=%s", c.id, sid, st)
			return
		case <-c.dead:
			return
		default:
		}
		n, _ := strconv.Atoi(st[1:])
		switch st[0] {
		case 'h':
			c.headers(sid, false, ":status", "200", "content-type", "application/grpc")
		case 'm':
			var b []byte
			for i := 0; i < n; i++ {
				idx++
				b = append(b, msg([]byte{byte(idx)})...)
			}
			c.data(sid, false, b)
		case 'M':
			idx++
			c.data(sid, false, msg(bytes.Repeat([]byte{byte(idx)}, n)))
		case 'J': // two good messages + bad-flag prefix of an incomplete message, one frame
			b := append(msg([]byte{1}), msg([]byte{2})...)
			c.data(sid, false, append(b, 7, 0, 0, 0, 9, 1))
		case 'K': // two good messages + prefix declaring 1000 bytes + 3 bytes, one frame
			b := append(msg([]byte{1}), msg([]byte{2})...)
			c.data(sid, false, append(b, 0, 0, 0, 3, 0xe8, 1, 2, 3))
		case 'p':
			c.data(sid, false, []byte{0, 0, 0, 0, 10, 1, 2, 3})
		case 'b':
			c.data(sid, false, []byte{7, 0, 0, 0, 1, 9})
		case 's':
			select {
			case <-time.After(time.Duration(n) * time.Millisecond):
			case <-cancel:
				logf("conn=%d stream=%d scenario-stopped-by-rst at=%s", c.id, sid, st)
				return
			case <-c.dead:
				return
			}
		case 't':
			c.headers(sid, true, "grpc-status", strconv.Itoa(n), "grpc-message", "scn", "x-tr", "v")
		case 'T': // trailers with a -bin value that is not base64
			c.headers(sid, true, "grpc-status", strconv.Itoa(n), "grpc-message", "scn", "x-bad-bin", "!!!*")
		case 'D': // trailers with undecodable status details
			c.headers(sid, true, "grpc-status", strconv.Itoa(n), "grpc-message", "scn", "grpc-status-details-bin", "AAAA////")
		case 'V':
			c.headers(sid, true, "grpc-status", strconv.Itoa(n), "grpc-message", "scn", "grpc-status-details-bin", "CAUSAXg")
		case 'e':
			c.data(sid, true, nil)
		case 'g':
			c.wmu.Lock()
			c.fr.WriteGoAway(sid, http2.ErrCodeNo, nil)
			c.wmu.Unlock()
		case 'x':
			c.wmu.Lock()
			c.fr.WriteRSTStream(sid, http2.ErrCodeInternal)
			c.wmu.Unlock()
		case 'c':
			c.c.Close()
		case 'w':
			select {
			case <-cancel:
				logf("conn=%d stream=%d scenario-stopped-by-rst at=%s", c.id, sid, st)
			case <-c.dead:
			}
			return
		}
	}
	logf("conn=%d stream=%d scenario-complete", c.id, sid)
}

func serve(nc net.Conn) {
	logMu.Lock()
	connSeq++
	id := connSeq
	logMu.Unlock()
	c := &conn{id: id, c: nc, rst: map[uint32]chan struct{}{}, dead: make(chan struct{})}
	logf("conn=%d OPEN", id)
	defer func() { close(c.dead); nc.Close() }()
	pre := make([]byte, len(http2.ClientPreface))
	if _, err := io.ReadFull(nc, pre); err != nil {
		logf("conn=%d CLOSED-before-preface %v", id, err)
		return
	}
	c.fr = http2.NewFramer(nc, nc)
	c.enc = hpack.NewEncoder(&c.ebuf)
	dec := hpack.NewDecoder(4096, nil)
	c.wmu.Lock()
	c.fr.WriteSettings(http2.Setting{ID: http2.SettingMaxConcurrentStreams, Val: 1000})
	c.wmu.Unlock()
	var hb []byte
	var hsid uint32
	for {
		f, err := c.fr.ReadFrame()
		if err != nil {
			logf("conn=%d CLOSED %v", id, err)
			return
		}
		switch f := f.(type) {
		case *http2.SettingsFrame:
			if !f.IsAck() {
				c.wmu.Lock()
				c.fr.WriteSettingsAck()
				c.wmu.Unlock()
			}
		case *http2.PingFrame:
			logf("conn=%d PING ack=%v", id, f.IsAck())
			if !f.IsAck() && os.Getenv("NO_PING_ACK") == "" {
				c.wmu.Lock()
				c.fr.WritePing(true, f.Data)
				c.wmu.Unlock()
			}
		case *http2.HeadersFrame:
			hb = append(hb[:0], f.HeaderBlockFragment()...)
			hsid = f.StreamID
			if f.HeadersEnded() {
				c.start(dec, hsid, hb)
			}
		case *http2.ContinuationFrame:
			hb = append(hb, f.HeaderBlockFragment()...)
			if f.HeadersEnded() {
				c.start(dec, hsid, hb)
			}
		case *http2.DataFrame:
			logf("conn=%d stream=%d DATA len=%d end=%v", id, f.StreamID, len(f.Data()), f.StreamEnded())
			if len(f.Data()) > 0 {
				c.wmu.Lock()
				c.fr.WriteWindowUpdate(0, uint32(len(f.Data())))
				c.wmu.Unlock()
			}
		case *http2.RSTStreamFrame:
			logf("conn=%d stream=%d RST_STREAM code=%v", id, f.StreamID, f.ErrCode)
			c.mu.Lock()
			if ch, ok := c.rst[f.StreamID]; ok {
				select {
				case <-ch:
				default:
					close(ch)
				}
			}
			c.mu.Unlock()
		case *http2.GoAwayFrame:
			logf("conn=%d GOAWAY code=%v last=%d", id, f.ErrCode, f.LastStreamID)
		case *http2.WindowUpdateFrame:
			logf("conn=%d stream=%d WINDOW_UPDATE inc=%d", id, f.StreamID, f.Increment)
		}
	}
}

func (c *conn) start(dec *hpack.Decoder, sid uint32, hb []byte) {
	fs, _ := dec.DecodeFull(hb)
	scn, path, to := "h,m1,t0", "", ""
	for _, f := range fs {
		switch f.Name {
		case "x-scn":
			scn = f.Value
		case ":path":
			path = f.Value
		case "grpc-timeout":
			to = f.Value
		}
	}
	logf("conn=%d stream=%d HEADERS path=%s scn=%s grpc-timeout=%s", c.id, sid, path, scn, to)
	ch := make(chan struct{})
	c.mu.Lock()
	c.rst[sid] = ch
	c.mu.Unlock()
	go c.run(sid, scn, ch)
}

func main() {
	port := flag.Int("port", 0, "")
	logp := flag.String("log", "srv.log", "")
	flag.Parse()
	var err error
	logF, err = os.Create(*logp)
	if err != nil {
		panic(err)
	}
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", *port))
	if err != nil {
		panic(err)
	}
	fmt.Println("listening", ln.Addr())
	for {
		nc, err := ln.Accept()
		if err != nil {
			return
		}
		go serve(nc)
	}
}
