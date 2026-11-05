// The test servers zugrpc's live tests need besides grpc-go's interop
// server, all from grpc-go v1.67.1 and the Go standard library:
//
//   - -grpc_port: a gRPC server (h2c) whose methods are under
//     /zugrpc.test.Status/: Spark and Every fail with google.rpc error
//     details shaped as Spark Connect's ErrorUtils.scala builds them, and
//     Stall sends its headers and then nothing until the client goes.
//   - -h1_tls_port: a TLS server that offers ALPN http/1.1 only, so that
//     a client requiring HTTP/2 must refuse it.
//   - -h2_port: a plain HTTP/2 (h2c) server that is not gRPC, answering
//     every request with 200 and text/html.
//   - -cert_dir: writes ca.pem, cert.pem and key.pem, a CA and a
//     certificate for localhost and 127.0.0.1 signed by it, then exits.
//
// tools/record-fixtures.R records the Spark and Every responses.
//
//	(cd tools && go run ./test-server -grpc_port 10002)
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"flag"
	"fmt"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"
	"google.golang.org/genproto/googleapis/rpc/errdetails"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/durationpb"
)

func handle(stream grpc.ServerStream) error {
	method, _ := grpc.MethodFromServerStream(stream)
	switch method {
	case "/zugrpc.test.Status/Spark":
		st := status.New(codes.Internal, "[TABLE_OR_VIEW_NOT_FOUND] The table or view `nope` cannot be found.")
		st, err := st.WithDetails(&errdetails.ErrorInfo{
			Reason: "org.apache.spark.sql.catalyst.ExtendedAnalysisException",
			Domain: "org.apache.spark",
			Metadata: map[string]string{
				"classes":           `["org.apache.spark.sql.catalyst.ExtendedAnalysisException","org.apache.spark.sql.AnalysisException"]`,
				"sqlState":          "42P01",
				"errorClass":        "TABLE_OR_VIEW_NOT_FOUND",
				"messageParameters": `{"relationName":"` + "`nope`" + `"}`,
				"errorId":           "5f3c2a9e-0d1b-4c8e-9a7f-2b6d1e4c8a01",
			},
		})
		if err != nil {
			return err
		}
		return st.Err()
	case "/zugrpc.test.Status/Every":
		st := status.New(codes.Unavailable, "try again")
		st, err := st.WithDetails(
			&errdetails.RetryInfo{RetryDelay: durationpb.New(1500 * time.Millisecond)},
			&errdetails.DebugInfo{StackEntries: []string{"a", "b"}, Detail: "debug"},
			&errdetails.QuotaFailure{Violations: []*errdetails.QuotaFailure_Violation{{Subject: "s", Description: "d"}}},
			&errdetails.PreconditionFailure{Violations: []*errdetails.PreconditionFailure_Violation{{Type: "TOS", Subject: "s", Description: "d"}}},
			&errdetails.BadRequest{FieldViolations: []*errdetails.BadRequest_FieldViolation{{Field: "f", Description: "d"}}},
			&errdetails.RequestInfo{RequestId: "r1", ServingData: "x"},
			&errdetails.ResourceInfo{ResourceType: "table", ResourceName: "t", Owner: "o", Description: "d"},
			&errdetails.Help{Links: []*errdetails.Help_Link{{Description: "docs", Url: "https://example.org"}}},
			&errdetails.LocalizedMessage{Locale: "en-GB", Message: "colour"},
			durationpb.New(2*time.Second),
		)
		if err != nil {
			return err
		}
		return st.Err()
	case "/zugrpc.test.Status/Stall":
		// Headers now, then nothing for a minute or until the client resets
		// the stream. The client's grpc-timeout is ignored on purpose, so
		// the deadline the test sees is the one zugrpc enforces.
		if err := stream.SendHeader(metadata.Pairs("x-stall", "1")); err != nil {
			return err
		}
		ctx := stream.Context()
		end := time.After(time.Minute)
		select {
		case <-end:
		case <-ctx.Done():
			if ctx.Err() == context.DeadlineExceeded {
				// The server-side deadline passed. Keep stalling: once it
				// has, the context cannot report a later client reset, so
				// this handler simply waits out its minute.
				<-end
			}
		}
		return status.Error(codes.OK, "")
	}
	return status.Error(codes.Unimplemented, "unknown method "+method)
}

func writeCerts(dir string) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	ca := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "zugrpc test CA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(7 * 24 * time.Hour),
		IsCA:                  true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, ca, ca, &caKey.PublicKey, caKey)
	if err != nil {
		return err
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	leaf := &x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: "localhost"},
		DNSNames:     []string{"localhost"},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(7 * 24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	caCert, err := x509.ParseCertificate(caDER)
	if err != nil {
		return err
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leaf, caCert, &key.PublicKey, caKey)
	if err != nil {
		return err
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return err
	}
	files := map[string]*pem.Block{
		"ca.pem":   {Type: "CERTIFICATE", Bytes: caDER},
		"cert.pem": {Type: "CERTIFICATE", Bytes: leafDER},
		"key.pem":  {Type: "EC PRIVATE KEY", Bytes: keyDER},
	}
	for name, block := range files {
		if err := os.WriteFile(filepath.Join(dir, name), pem.EncodeToMemory(block), 0o644); err != nil {
			return err
		}
	}
	return nil
}

func listen(port int) net.Listener {
	lis, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		log.Fatal(err)
	}
	return lis
}

func main() {
	grpcPort := flag.Int("grpc_port", 0, "gRPC (h2c) port")
	h1Port := flag.Int("h1_tls_port", 0, "TLS port offering only http/1.1")
	h2Port := flag.Int("h2_port", 0, "plain HTTP/2 (h2c) port, not gRPC")
	certFile := flag.String("tls_cert_file", "", "certificate for -h1_tls_port")
	keyFile := flag.String("tls_key_file", "", "key for -h1_tls_port")
	certDir := flag.String("cert_dir", "", "write a CA and a localhost certificate here and exit")
	flag.Parse()

	if *certDir != "" {
		if err := writeCerts(*certDir); err != nil {
			log.Fatal(err)
		}
		return
	}

	page := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprintf(w, "<html><body>not gRPC: %s</body></html>\n", r.Proto)
	})
	running := 0
	if *h1Port != 0 {
		cert, err := tls.LoadX509KeyPair(*certFile, *keyFile)
		if err != nil {
			log.Fatal(err)
		}
		srv := &http.Server{
			Handler: page,
			TLSConfig: &tls.Config{
				Certificates: []tls.Certificate{cert},
				NextProtos:   []string{"http/1.1"},
			},
			// A non-nil, empty map turns off the server's own h2.
			TLSNextProto: map[string]func(*http.Server, *tls.Conn, http.Handler){},
		}
		lis := listen(*h1Port)
		go func() { log.Fatal(srv.ServeTLS(lis, "", "")) }()
		running++
	}
	if *h2Port != 0 {
		srv := &http.Server{Handler: h2c.NewHandler(page, &http2.Server{})}
		lis := listen(*h2Port)
		go func() { log.Fatal(srv.Serve(lis)) }()
		running++
	}
	if *grpcPort != 0 {
		s := grpc.NewServer(grpc.UnknownServiceHandler(func(_ any, stream grpc.ServerStream) error {
			return handle(stream)
		}))
		lis := listen(*grpcPort)
		go func() { log.Fatal(s.Serve(lis)) }()
		running++
	}
	if running == 0 {
		log.Fatal("nothing to serve: give -grpc_port, -h1_tls_port, -h2_port or -cert_dir")
	}
	select {}
}
