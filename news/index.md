# Changelog

## zugrpc 0.0.0.9000

- [`grpc_channel()`](https://pedrobtz.github.io/zugrpc/reference/grpc_channel.md)
  opens a channel to a gRPC server over cleartext HTTP/2 (`http://`) or
  TLS (`https://`). It can build on a
  [`zuhttp::zu_client()`](https://pedrobtz.github.io/zuhttp/reference/zu_client.html)
  you supply, so proxies, TLS settings and test transports carry over.
  [`grpc_close()`](https://pedrobtz.github.io/zugrpc/reference/grpc_close.md)
  closes it.
- [`grpc_call()`](https://pedrobtz.github.io/zugrpc/reference/grpc_call.md)
  makes a unary call. It returns the response message with its initial
  and trailing metadata, and raises `zugrpc_error_status`, with a class
  per status code, when the call fails. Responses that are not gRPC or
  break its framing raise `zugrpc_error_protocol`.
- [`grpc_status_codes()`](https://pedrobtz.github.io/zugrpc/reference/grpc_status_codes.md)
  lists the 17 gRPC status codes.
- The gRPC wire format, internal for now: message framing, metadata with
  `-bin` values in base64, the `grpc-timeout` header, `grpc-status` and
  `grpc-message` decoding, and the HTTP-status fallback.
