# Make a unary gRPC call

Sends one request message to a method and returns the one response
message, with the server's initial and trailing metadata. The request is
already encoded, for example by `zuproto::proto_encode()`; zugrpc only
frames it. A call that ends with a status other than `OK` raises a
condition instead of returning.

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
  with `grpc-`, `te` and `content-type` are reserved.

- deadline:

  Seconds from now, or an absolute `POSIXct`, by which the call must
  finish. It is sent to the server as `grpc-timeout` and also bounds the
  request locally. `NULL` sets no deadline.

## Value

A list with elements `message` (raw, the response message), `headers`
and `trailers` (named lists of the initial and trailing metadata, with
`-bin` values as raw vectors) and `status` (`"OK"`).

## Errors

A non-`OK` status raises `zugrpc_error_status`, whose class also carries
the status as `zugrpc_error_<name>`, for example
`zugrpc_error_unavailable`. Its fields are `grpc_status`, `grpc_code`,
`grpc_message`, `http_status`, `method`, `headers` and `trailers`. A
response that is not gRPC, or breaks its framing, raises
`zugrpc_error_protocol`. See
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
