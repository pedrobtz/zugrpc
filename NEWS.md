# zugrpc 0.0.0.9000

* `grpc_channel()` opens a channel to a gRPC server over cleartext HTTP/2
  (`http://`) or TLS (`https://`). It can build on a `zuhttp::zu_client()`
  you supply, so proxies, TLS settings and test transports carry over.
  `grpc_close()` closes it.
* `grpc_call()` makes a unary call. It returns the response message with
  its initial and trailing metadata, and raises `zugrpc_error_status`, with
  a class per status code, when the call fails. Responses that are not gRPC
  or break its framing raise `zugrpc_error_protocol`.
* A failed call's condition carries `details`, the `google.rpc.Status`
  decoded from the `grpc-status-details-bin` trailer, with each error
  detail such as `ErrorInfo` unpacked. A trailer that does not decode is a
  `zugrpc_warning_details` warning, and the status is kept.
* Failures below gRPC raise `zugrpc_error_transport`, which is also
  `zugrpc_error_unavailable`. A timeout is `DEADLINE_EXCEEDED`, and an
  interrupt raises `zugrpc_error_interrupt`.
* `grpc_status_codes()` lists the 17 gRPC status codes.
* The gRPC wire format, internal for now: message framing, metadata with
  `-bin` values in base64, the `grpc-timeout` header, `grpc-status` and
  `grpc-message` decoding, and the HTTP-status fallback.
