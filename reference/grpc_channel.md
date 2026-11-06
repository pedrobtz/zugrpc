# Open a gRPC channel

A channel holds what every call to one server shares: the server's
address, the headers sent on every call, the message size limit, and the
`zuhttp` client whose connection pool carries the calls. An `http://`
URL speaks cleartext HTTP/2 with prior knowledge (h2c), for a local
server. An `https://` URL negotiates HTTP/2 over TLS. gRPC has no
HTTP/1.1 fallback, so the channel's client always requires HTTP/2.

## Usage

``` r
grpc_channel(
  url,
  headers = NULL,
  tls = NULL,
  keepalive = grpc_keepalive(),
  max_message = 128 * 1024^2,
  client = NULL
)
```

## Arguments

- url:

  The server, as `http://host:port` or `https://host:port`. No path,
  query or user information.

- headers:

  Metadata sent on every call: a named character vector or a named list,
  as `metadata` in
  [`grpc_call()`](https://pedrobtz.github.io/zugrpc/reference/grpc_call.md),
  with the same reserved names. A call's own metadata replaces a channel
  header of the same name.

- tls:

  Certificate trust settings from
  [`zuhttp::zu_tls()`](https://pedrobtz.github.io/zuhttp/reference/zu_tls.html),
  for an `https://` URL.

- keepalive:

  HTTP/2 keepalive from
  [`grpc_keepalive()`](https://pedrobtz.github.io/zugrpc/reference/grpc_keepalive.md),
  or `NULL` for none. The default sends a PING on a connection idle for
  60 seconds and replaces it if no answer comes within 20, as Spark
  Connect's Python client does.

- max_message:

  The largest response message accepted, in bytes. The default, 128 MiB,
  is Spark Connect's. A larger message fails the call with
  `RESOURCE_EXHAUSTED`.

- client:

  A
  [`zuhttp::zu_client()`](https://pedrobtz.github.io/zuhttp/reference/zu_client.html)
  to build on, so that proxies, TLS pins, middleware and test transports
  come from `zuhttp` unchanged. The channel derives its own client from
  it, with HTTP/2 required. `NULL` builds a fresh one.

## Value

A `zugrpc_channel`.

## See also

[`grpc_call()`](https://pedrobtz.github.io/zugrpc/reference/grpc_call.md)
to make a call,
[`grpc_close()`](https://pedrobtz.github.io/zugrpc/reference/grpc_close.md)
to close it.

## Examples

``` r
ch <- grpc_channel("http://localhost:50051")
ch
#> <zugrpc_channel> localhost:50051
#>   transport: cleartext HTTP/2 (h2c)
#>   state:     open
#>   streams:   0 open
grpc_close(ch)
```
