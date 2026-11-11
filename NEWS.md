# zugrpc 0.0.0.9000

* Metadata named `r`, `re` or `req` is sent, instead of failing the call
  with an error from zuhttp (#81).
* A metadata name given more than once is sent once, its values joined by
  commas, instead of failing at call time. Every `user-agent` given is
  kept, and an empty one no longer adds a leading space (#82).
* Requests no longer ask for HTTP content coding (`accept-encoding: gzip`),
  and a response with one is not decoded. `content-length` and
  `accept-encoding` are reserved names. A client passed to `grpc_channel()`
  may not set a reserved header, and its `query` is dropped (#83).
* `grpc_channel()` refuses a URL whose host or port cannot be used, with
  `zugrpc_error_argument`, instead of every call failing as `UNAVAILABLE`
  (#84).
* `grpc_keepalive()` refuses values outside 1 ms to 2147483.647 s, which
  zuhttp would refuse or clamp, and prints its values in full (#85).
* A positive deadline below a femtosecond is sent as `1n`, not `0n` (#87).
* A stream decides its status as a unary call does. A status in the headers
  counts only when no body came, a status in the trailers wins over a body
  that ends inside a message, and an `OK` status in the headers no longer
  makes an HTML body acceptable. The not-gRPC error keeps the first 1 KiB
  of the body (#58).
* A stream returns the complete messages that arrived before a broken one,
  then raises, however the server's bytes were split (#76).
* A warning while a stream ends, such as from undecodable `-bin` trailers,
  can no longer make a failed stream read as a clean end (#77).
* A unary response larger than `max_message` is still `UNAVAILABLE` for a
  503 and a protocol error for a body that is not gRPC, instead of
  `RESOURCE_EXHAUSTED`. Its condition carries `http_status` (#79).
* One error detail that does not decode no longer discards the whole
  `google.rpc.Status`. It is kept as it came, with a warning (#80).
* A stream's `$status()` names how it ended, such as `"CANCELLED"` or
  `"DEADLINE_EXCEEDED"`, and a stream of a closed channel prints as
  cancelled (#86).
* A comma-joined `-bin` value with a trailing comma gives an empty last
  value, as a leading comma gives an empty first one (#88).
* A call or stream with no deadline no longer fails with
  `DEADLINE_EXCEEDED` after 30 seconds, zuhttp's default timeout (#23).
* A server's malformed `grpc-message` or `-bin` metadata no longer hides
  the call's status. A `-bin` value that is not base64 is dropped with a
  `zugrpc_warning_metadata` warning, and comma-joined values are split
  (#25, #26).
* `grpc_close()` no longer closes the connections of the `zuhttp` client a
  channel was built on, or of other channels built on it (#27).
* Every condition of a call carries `method`, and `http_status` once there
  is a response (#28).
* A stream that failed raises the same condition on every later
  `$next_message()`, instead of reading as a clean end (#35).
* Metadata named `host`, or a connection header HTTP/2 forbids, is an
  argument error. A `user-agent` you set is sent before zugrpc's own
  instead of being replaced (#36).
* A method name must use protobuf name characters (#50).
* Reading many small messages from a stream no longer slows down with the
  number in each read (#34).

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
