# zugrpc

## Overview

[gRPC](https://grpc.io) is how many services talk to each other, Spark
Connect among them. It runs only over HTTP/2 and puts each call’s status
in HTTP trailers, which the usual R HTTP clients do not expose. Until
now, calling a gRPC service from R meant installing the gRPC C++
libraries or going through Python.

zugrpc is a gRPC client written in R. It speaks the gRPC wire protocol
over the HTTP/2 requests that
[zuhttp](https://github.com/pedrobtz/zuhttp) makes, so it needs no gRPC,
protobuf or libcurl installed on the system. You encode and decode
messages yourself, typically with
[zuproto](https://github.com/pedrobtz/zuproto).

- **Unary and server-streaming calls.**
  [`grpc_call()`](https://pedrobtz.github.io/zugrpc/reference/grpc_call.md)
  returns one message;
  [`grpc_stream()`](https://pedrobtz.github.io/zugrpc/reference/grpc_stream.md)
  returns them one at a time as they arrive, and the server sends only
  as fast as you read.
- **Errors you can select by class.** Every status code is a condition
  class, such as `zugrpc_error_unavailable`, and the `google.rpc.Status`
  details, Spark’s `ErrorInfo` among them, are decoded for you.
- **Deadlines and cancellation.** A deadline goes to the server as
  `grpc-timeout` and also bounds the call locally. Cancelling a stream
  resets it with `RST_STREAM` and keeps the connection for other calls.
- **zuhttp’s transport.** Cleartext HTTP/2 for local servers, TLS with
  the platform’s own TLS stack and trust store, a connection pool and
  HTTP/2 keepalive.

## Installation

zugrpc is not on CRAN yet. Install the development version from GitHub:

``` r

# install.packages("pak")
pak::pak("pedrobtz/zugrpc")
```

## Usage

``` r

library(zugrpc)
```

These examples talk to a fake server, built from zuhttp’s mock
transport, with plain-text messages instead of protobuf. Against a real
server, leave out `client = fake`.

A channel holds what every call to one server shares.

``` r

ch <- grpc_channel("http://localhost:50051", client = fake)
```

A unary call sends one request message and returns one response.

``` r

res <- grpc_call(ch, "/demo.Greeter/SayHello", charToRaw("world"), deadline = 5)
rawToChar(res$message)
#> [1] "hello, world"
```

A server-streaming call yields its messages one at a time, then `NULL`.

``` r

st <- grpc_stream(ch, "/demo.Greeter/Count", raw())
while (!is.null(m <- st$next_message())) print(rawToChar(m))
#> [1] "one"
#> [1] "two"
#> [1] "three"
st$status()
#> [1] "OK"
```

A failed call raises a condition whose class names its status.

``` r

tryCatch(
  grpc_call(ch, "/demo.Greeter/SayGoodbye", raw()),
  zugrpc_error_not_found = function(cnd) cnd$grpc_message
)
#> [1] "no such greeting"
```

Every function starts with `grpc_`, except
[`zugrpc_info()`](https://pedrobtz.github.io/zugrpc/reference/zugrpc_info.md),
and a failed call’s condition class is `zugrpc_error_` followed by its
status code in lower case.

## Learn more

- [Get started](https://pedrobtz.github.io/zugrpc/articles/zugrpc.html)
  walks through channels, calls, streams, errors and cancellation.
- [Performance](https://pedrobtz.github.io/zugrpc/articles/performance.html)
  reports what zugrpc adds to a call, measured.
- The [function reference](https://pedrobtz.github.io/zugrpc/reference/)
  documents every function.

## Related work

zugrpc follows gRPC’s [HTTP/2
protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md)
and [status
codes](https://github.com/grpc/grpc/blob/master/doc/statuscodes.md). It
is tested against [grpc-go](https://github.com/grpc/grpc-go)’s interop
server and against [Spark
Connect](https://spark.apache.org/spark-connect/). It bundles the
`google/rpc` protocol definitions from
[googleapis](https://github.com/googleapis/googleapis) to decode error
details. [rgrpc](https://CRAN.R-project.org/package=rgrpc) is a client
and server built on the gRPC C++ libraries.
