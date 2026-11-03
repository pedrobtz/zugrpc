# Changelog

## zugrpc 0.0.0.9000

- [`grpc_status_codes()`](https://pedrobtz.github.io/zugrpc/reference/grpc_status_codes.md)
  lists the 17 gRPC status codes.
- The gRPC wire format, internal for now: message framing, metadata with
  `-bin` values in base64, the `grpc-timeout` header, `grpc-status` and
  `grpc-message` decoding, and the HTTP-status fallback.
