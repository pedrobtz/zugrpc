// A gRPC server that answers every method with one fixed error status
// carrying google.rpc error details, shaped as Spark Connect's
// ErrorUtils.scala builds them. tools/record-fixtures.R records its
// responses for tests/testthat/fixtures/details/.
//
//	go run ./tools/status-server -port 50052
package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"time"

	"google.golang.org/genproto/googleapis/rpc/errdetails"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/durationpb"
)

func spark(stream grpc.ServerStream) error {
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
	}
	return status.Error(codes.Unimplemented, "unknown method "+method)
}

func main() {
	port := flag.Int("port", 50052, "port to listen on")
	flag.Parse()
	lis, err := net.Listen("tcp", fmt.Sprintf("localhost:%d", *port))
	if err != nil {
		log.Fatal(err)
	}
	s := grpc.NewServer(grpc.UnknownServiceHandler(func(_ any, stream grpc.ServerStream) error {
		return spark(stream)
	}))
	log.Fatal(s.Serve(lis))
}
