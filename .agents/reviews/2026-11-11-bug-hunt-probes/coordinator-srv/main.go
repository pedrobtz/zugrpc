// Minimal raw-framer h2c server: logs request headers, RST_STREAM and EOF.
// Mode "stall": sends response headers, then waits. Mode "ok": one empty message, status 0.
package main

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"os"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

func main() {
	ln, err := net.Listen("tcp", "127.0.0.1:"+os.Args[1])
	if err != nil {
		panic(err)
	}
	conn := 0
	for {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		conn++
		go serve(c, conn)
	}
}

func serve(c net.Conn, id int) {
	defer c.Close()
	pre := make([]byte, len(http2.ClientPreface))
	if _, err := io.ReadFull(c, pre); err != nil {
		return
	}
	fr := http2.NewFramer(c, c)
	fr.WriteSettings()
	dec := hpack.NewDecoder(4096, nil)
	for {
		f, err := fr.ReadFrame()
		if err != nil {
			fmt.Printf("conn %d: EOF (%v)\n", id, err)
			return
		}
		switch f := f.(type) {
		case *http2.SettingsFrame:
			if !f.IsAck() {
				fr.WriteSettingsAck()
			}
		case *http2.HeadersFrame:
			hf, _ := dec.DecodeFull(f.HeaderBlockFragment())
			path := ""
			for _, h := range hf {
				fmt.Printf("conn %d stream %d header %s: %q\n", id, f.StreamID, h.Name, h.Value)
				if h.Name == ":path" {
					path = h.Value
				}
			}
			var buf bytes.Buffer
			enc := hpack.NewEncoder(&buf)
			enc.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})
			enc.WriteField(hpack.HeaderField{Name: "content-type", Value: "application/grpc"})
			fr.WriteHeaders(http2.HeadersFrameParam{StreamID: f.StreamID, BlockFragment: buf.Bytes(), EndHeaders: true})
			if path == "/a.B/Ok" {
				fr.WriteData(f.StreamID, false, []byte{0, 0, 0, 0, 0})
				var tb bytes.Buffer
				te := hpack.NewEncoder(&tb)
				te.WriteField(hpack.HeaderField{Name: "grpc-status", Value: "0"})
				fr.WriteHeaders(http2.HeadersFrameParam{StreamID: f.StreamID, BlockFragment: tb.Bytes(), EndHeaders: true, EndStream: true})
			}
		case *http2.RSTStreamFrame:
			fmt.Printf("conn %d stream %d: RST_STREAM %v\n", id, f.StreamID, f.ErrCode)
		case *http2.PingFrame:
			if !f.IsAck() {
				fr.WritePing(true, f.Data)
			}
		}
	}
}
