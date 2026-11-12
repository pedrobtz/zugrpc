# Make a server-streaming gRPC call

Sends one request message and returns a stream that yields the response
messages one at a time, as they arrive. The server sends only as far
ahead as you read, so a stream you stop reading holds the server back
rather than filling memory.

## Usage

``` r
grpc_stream(channel, method, request, metadata = NULL, deadline = NULL)
```

## Arguments

- channel:

  A channel from
  [`grpc_channel()`](https://pedrobtz.github.io/zugrpc/reference/grpc_channel.md).

- method:

  The full method name, `"/package.Service/Method"`.

- request:

  The encoded request message, a raw vector.

- metadata:

  Request metadata: a named character vector, or a named list whose
  `-bin` entries are raw vectors. Names are lower-cased. Names starting
  with `grpc-` or `:` are reserved, and so are `te`, `content-type`,
  `content-length`, `accept-encoding`, `host` and the connection headers
  HTTP/2 forbids, such as `connection`. Each name may be given once. A
  `user-agent` is sent before zugrpc's own.

- deadline:

  Seconds from now, or an absolute `POSIXct`, by which the whole stream
  must end. It is sent as `grpc-timeout`. Locally it is checked before
  each read, and each wait for more data is bounded by the time the
  deadline allowed when the call began, so a stall can overrun a
  deadline that is already partly used. `NULL` sets no deadline.

## Value

A `zugrpc_stream`.

## Details

The stream is an object with five methods:

- `$headers()` returns the initial metadata, a named list.

- `$next_message()` returns the next message as a raw vector, or `NULL`
  at the end of the stream. It raises a condition, as
  [`grpc_call()`](https://pedrobtz.github.io/zugrpc/reference/grpc_call.md)
  does, when the call ends with a status other than `OK`. A stream that
  fails any other way, such as a lost connection, a passed deadline or a
  broken message, raises the same condition again on every later call.
  The complete messages that arrived before a broken one are returned
  first.

- `$trailers()` returns the trailing metadata once `$next_message()` has
  returned `NULL`, and `NULL` before.

- `$status()` returns the final status name once the stream has ended,
  and `NULL` before: `"OK"`, the server's status, or the status the
  stream failed with, such as `"CANCELLED"` or `"DEADLINE_EXCEEDED"`. A
  stream that failed without a status, on a protocol error, stays
  `NULL`.

- `$cancel()` stops the call. The connection stays open for other calls.
  A second `$cancel()` does nothing. A later `$next_message()` raises
  `zugrpc_error_cancelled`.

A stream that is no longer referenced is cancelled when it is
garbage-collected, and
[`grpc_close()`](https://pedrobtz.github.io/zugrpc/reference/grpc_close.md)
cancels every open stream of its channel.

## Examples

``` r
# A test server, from zuhttp's mock transport: it streams two messages
# and ends with status OK.
fake <- zuhttp::zu_mock_transport(function(req) {
  zuhttp::zu_response(
    200L,
    headers = c("content-type" = "application/grpc+proto"),
    body = as.raw(c(0, 0, 0, 0, 1, 0x61, 0, 0, 0, 0, 1, 0x62)),
    trailers = c("grpc-status" = "0")
  )
})
ch <- grpc_channel(
  "http://localhost:50051",
  client = zuhttp::zu_client(transport = fake)
)
st <- grpc_stream(ch, "/grpc.testing.TestService/StreamingOutputCall", raw())
while (!is.null(m <- st$next_message())) print(rawToChar(m))
#> [1] "a"
#> [1] "b"
st$status()
#> [1] "OK"
```
