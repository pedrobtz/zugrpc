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
* `grpc_stream()` makes a server-streaming call. Its `$next_message()`
  returns one message at a time as it arrives, so the server sends only as
  fast as you read. `$cancel()` stops the call and keeps the connection.
  `grpc_close()` cancels a channel's open streams, and a stream that is no
  longer referenced is cancelled when it is garbage-collected.
* A call whose deadline has already passed fails with `DEADLINE_EXCEEDED`
  without being sent.
* `grpc_keepalive()` sets HTTP/2 keepalive for a channel. By default a
  connection idle for 60 seconds is checked with a PING before its next
  call, as Spark Connect's Python client does.
* Each call no longer spends about a millisecond rebuilding the user-agent
  string.
* `zugrpc_info()` reports the zuhttp version, whether it speaks HTTP/2, and
  its TLS backend.
* Failures below gRPC raise `zugrpc_error_transport`, which is also
  `zugrpc_error_unavailable`. A timeout is `DEADLINE_EXCEEDED`, and an
  interrupt raises `zugrpc_error_interrupt`.
* `grpc_status_codes()` lists the 17 gRPC status codes.
* The gRPC wire format, internal for now: message framing, metadata with
  `-bin` values in base64, the `grpc-timeout` header, `grpc-status` and
  `grpc-message` decoding, and the HTTP-status fallback.
