# Changelog

## zugrpc 0.0.0.9000

- A call or stream with no deadline no longer fails with
  `DEADLINE_EXCEEDED` after 30 seconds, zuhttp’s default timeout
  ([\#23](https://github.com/pedrobtz/zugrpc/issues/23)).

- A server’s malformed `grpc-message` or `-bin` metadata no longer hides
  the call’s status. A `-bin` value that is not base64 is dropped with a
  `zugrpc_warning_metadata` warning, and comma-joined values are split
  ([\#25](https://github.com/pedrobtz/zugrpc/issues/25),
  [\#26](https://github.com/pedrobtz/zugrpc/issues/26)).

- [`grpc_close()`](https://pedrobtz.github.io/zugrpc/reference/grpc_close.md)
  no longer closes the connections of the `zuhttp` client a channel was
  built on, or of other channels built on it
  ([\#27](https://github.com/pedrobtz/zugrpc/issues/27)).

- Every condition of a call carries `method`, and `http_status` once
  there is a response
  ([\#28](https://github.com/pedrobtz/zugrpc/issues/28)).

- A stream that failed raises the same condition on every later
  `$next_message()`, instead of reading as a clean end
  ([\#35](https://github.com/pedrobtz/zugrpc/issues/35)).

- Metadata named `host`, or a connection header HTTP/2 forbids, is an
  argument error. A `user-agent` you set is sent before zugrpc’s own
  instead of being replaced
  ([\#36](https://github.com/pedrobtz/zugrpc/issues/36)).

- A method name must use protobuf name characters
  ([\#50](https://github.com/pedrobtz/zugrpc/issues/50)).

- Reading many small messages from a stream no longer slows down with
  the number in each read
  ([\#34](https://github.com/pedrobtz/zugrpc/issues/34)).

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

- A failed call’s condition carries `details`, the `google.rpc.Status`
  decoded from the `grpc-status-details-bin` trailer, with each error
  detail such as `ErrorInfo` unpacked. A trailer that does not decode is
  a `zugrpc_warning_details` warning, and the status is kept.

- [`grpc_stream()`](https://pedrobtz.github.io/zugrpc/reference/grpc_stream.md)
  makes a server-streaming call. Its `$next_message()` returns one
  message at a time as it arrives, so the server sends only as fast as
  you read. `$cancel()` stops the call and keeps the connection.
  [`grpc_close()`](https://pedrobtz.github.io/zugrpc/reference/grpc_close.md)
  cancels a channel’s open streams, and a stream that is no longer
  referenced is cancelled when it is garbage-collected.

- A call whose deadline has already passed fails with
  `DEADLINE_EXCEEDED` without being sent.

- [`grpc_keepalive()`](https://pedrobtz.github.io/zugrpc/reference/grpc_keepalive.md)
  sets HTTP/2 keepalive for a channel. By default a connection idle for
  60 seconds is checked with a PING before its next call, as Spark
  Connect’s Python client does.

- Each call no longer spends about a millisecond rebuilding the
  user-agent string.

- [`zugrpc_info()`](https://pedrobtz.github.io/zugrpc/reference/zugrpc_info.md)
  reports the zuhttp version, whether it speaks HTTP/2, and its TLS
  backend.

- Failures below gRPC raise `zugrpc_error_transport`, which is also
  `zugrpc_error_unavailable`. A timeout is `DEADLINE_EXCEEDED`, and an
  interrupt raises `zugrpc_error_interrupt`.

- [`grpc_status_codes()`](https://pedrobtz.github.io/zugrpc/reference/grpc_status_codes.md)
  lists the 17 gRPC status codes.

- The gRPC wire format, internal for now: message framing, metadata with
  `-bin` values in base64, the `grpc-timeout` header, `grpc-status` and
  `grpc-message` decoding, and the HTTP-status fallback.
