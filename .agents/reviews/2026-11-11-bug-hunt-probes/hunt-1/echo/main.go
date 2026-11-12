// Echo server for the hunt: answers any method with one BytesValue-free raw
// message holding a JSON dump of the request metadata, the deadline left and
// the request message length.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/encoding"
	"google.golang.org/grpc/metadata"
)

type rawCodec struct{}

func (rawCodec) Marshal(v any) ([]byte, error)      { return *(v.(*[]byte)), nil }
func (rawCodec) Unmarshal(d []byte, v any) error    { *(v.(*[]byte)) = append([]byte(nil), d...); return nil }
func (rawCodec) Name() string                       { return "proto" }

func handle(srv any, stream grpc.ServerStream) error {
	var in []byte
	if err := stream.RecvMsg(&in); err != nil {
		return err
	}
	md, _ := metadata.FromIncomingContext(stream.Context())
	method, _ := grpc.MethodFromServerStream(stream)
	out := map[string]any{"md": md, "method": method, "len": len(in)}
	if dl, ok := stream.Context().Deadline(); ok {
		out["deadline_left"] = time.Until(dl).Seconds()
	}
	b, _ := json.Marshal(out)
	fmt.Println(string(b))
	return stream.SendMsg(&b)
}

func main() {
	port := flag.Int("port", 0, "port")
	flag.Parse()
	encoding.RegisterCodec(rawCodec{})
	lis, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", *port))
	if err != nil {
		panic(err)
	}
	s := grpc.NewServer(grpc.UnknownServiceHandler(handle))
	panic(s.Serve(lis))
}
