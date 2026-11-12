# Make a unary gRPC call

Sends one request message to a method and returns the one response
message, with the server's initial and trailing metadata. The request is
already encoded, for example by
[`zuproto::proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.html);
zugrpc only frames it. A call that ends with a status other than `OK`
raises a condition instead of returning.

## Usage

``` r
grpc_call(channel, method, request, metadata = NULL, deadline = NULL)
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

  Seconds from now, or an absolute `POSIXct`, by which the call must
  finish. It is sent to the server as `grpc-timeout` and also bounds the
  request locally. `NULL` sets no deadline.

## Value

A list with elements `message` (raw, the response message), `headers`
and `trailers` (named lists of the initial and trailing metadata, with
`-bin` values as raw vectors) and `status` (`"OK"`). A `-bin` value
holding several, joined by commas, gives one entry each. One that is not
base64 is dropped with a `zugrpc_warning_metadata` warning.

## Errors

A non-`OK` status raises `zugrpc_error_status`, whose class also carries
the status as `zugrpc_error_<name>`, for example
`zugrpc_error_unavailable`. Its fields are `grpc_status`, `grpc_code`,
`grpc_message`, `details`, `http_status`, `method`, `headers` and
`trailers`. `details` is the decoded `google.rpc.Status` from the
`grpc-status-details-bin` trailer, or `NULL` when there is none: a list
of `code`, `message` and `details`. Its `details` are the decoded error
details, named by type, such as `ErrorInfo` with its `reason`, `domain`
and `metadata`. Two details of one type share its name, so
`d[names(d) == "BadRequest"]` selects them all. A trailer that does not
decode gives a `zugrpc_warning_details` warning, and `details` is
`NULL`.

A failure below gRPC, such as a refused connection or a TLS error,
raises `zugrpc_error_transport`, which is also
`zugrpc_error_unavailable`. The `zuhttp` condition is its `parent`. A
local timeout is `DEADLINE_EXCEEDED`, and an interrupt raises
`zugrpc_error_interrupt`. A response that is not gRPC, or breaks its
framing, raises `zugrpc_error_protocol`. See
[`grpc_status_codes()`](https://pedrobtz.github.io/zugrpc/reference/grpc_status_codes.md).

## Examples

``` r
# A test server, from zuhttp's mock transport: it answers every call with
# an empty message and status OK.
fake <- zuhttp::zu_mock_transport(function(req) {
  zuhttp::zu_response(
    200L,
    headers = c("content-type" = "application/grpc+proto"),
    body = as.raw(c(0, 0, 0, 0, 0)),
    trailers = c("grpc-status" = "0")
  )
})
ch <- grpc_channel(
  "http://localhost:50051",
  client = zuhttp::zu_client(transport = fake)
)
res <- grpc_call(ch, "/grpc.testing.TestService/EmptyCall", raw())
res$status
#> [1] "OK"
res$message
#> raw(0)
```
