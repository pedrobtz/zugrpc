# Get started with zugrpc

``` r

library(zugrpc)
```

gRPC is how many services talk to each other, Spark Connect among them.
It runs only over HTTP/2 and carries its status in HTTP trailers, which
the usual R HTTP clients do not expose. zugrpc speaks the gRPC wire
protocol on top of zuhttp’s HTTP/2. You bring the request message,
encoded with zuproto, and get back the response message, its metadata
and its status. Calls can be unary or server-streaming.

This article talks to a fake server, built in a hidden chunk with
zuhttp’s mock transport, so that it runs anywhere. Its messages are
plain text rather than protobuf, to keep the output readable. Against a
real server, leave out `client = fake`.

## Open a channel

A channel holds what every call to one server shares. An `http://` URL
is cleartext HTTP/2, for a local server. An `https://` URL negotiates
HTTP/2 over TLS, with trust settings from
[`zuhttp::zu_tls()`](https://pedrobtz.github.io/zuhttp/reference/zu_tls.html).

``` r

ch <- grpc_channel("http://localhost:50051", client = fake)
ch
#> <zugrpc_channel> localhost:50051
#>   transport: cleartext HTTP/2 (h2c)
#>   state:     open
#>   streams:   0 open
```

`headers` go on every call, `keepalive` keeps an idle connection
checked, and `max_message` limits the size of a response message.

``` r

grpc_channel(
  "https://spark.example.org:443",
  headers = c(authorization = "Bearer ..."),
  keepalive = grpc_keepalive(time = 60, timeout = 20),
  max_message = 128 * 1024^2
)
```

## Make a unary call

A unary call sends one request message and returns one response message.
The request is a raw vector, usually from
[`zuproto::proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.html).
The deadline is in seconds, or an absolute `POSIXct`.

``` r

res <- grpc_call(
  ch, "/demo.Greeter/SayHello",
  request = charToRaw("world"),
  metadata = c("x-request-id" = "42"),
  deadline = 30
)
rawToChar(res$message)
#> [1] "hello, world"
res$headers
#> $`x-served-by`
#> [1] "fake"
res$status
#> [1] "OK"
```

## Stream the responses

A server-streaming call returns a stream. Each `$next_message()` returns
one response message, and `NULL` at the end. The server only sends as
far ahead as you read.

``` r

st <- grpc_stream(ch, "/demo.Greeter/Count", request = raw(), deadline = 600)
while (!is.null(m <- st$next_message())) {
  print(rawToChar(m))
}
#> [1] "one"
#> [1] "two"
#> [1] "three"
st$status()
#> [1] "OK"
```

Cancel a stream you no longer need. The connection stays open for other
calls, and a second cancel does nothing.

``` r

st <- grpc_stream(ch, "/demo.Greeter/Count", request = raw())
rawToChar(st$next_message())
#> [1] "one"
st$cancel()
```

## Handle errors

A call that ends with a status other than `OK` raises a
`zugrpc_error_status` condition. Its class also carries the status, so
you can catch one code.

``` r

tryCatch(
  grpc_call(ch, "/demo.Greeter/SayGoodbye", request = raw()),
  zugrpc_error_not_found = function(cnd) {
    cnd$grpc_message
  }
)
#> [1] "no such greeting"
```

The condition’s `details` field holds the decoded `google.rpc.Status`,
with error details such as `ErrorInfo` unpacked. Spark Connect puts its
error class and SQL state there:

``` r

tryCatch(
  grpc_stream(spark, "/spark.connect.SparkConnectService/ExecutePlan",
              request = bad_plan)$next_message(),
  zugrpc_error_status = function(cnd) {
    cnd$details$details$ErrorInfo$metadata[["errorClass"]]
  }
)
```

[`grpc_status_codes()`](https://pedrobtz.github.io/zugrpc/reference/grpc_status_codes.md)
lists the codes a call can end with.

``` r

grpc_status_codes()
#>    code                name
#> 1     0                  OK
#> 2     1           CANCELLED
#> 3     2             UNKNOWN
#> 4     3    INVALID_ARGUMENT
#> 5     4   DEADLINE_EXCEEDED
#> 6     5           NOT_FOUND
#> 7     6      ALREADY_EXISTS
#> 8     7   PERMISSION_DENIED
#> 9     8  RESOURCE_EXHAUSTED
#> 10    9 FAILED_PRECONDITION
#> 11   10             ABORTED
#> 12   11        OUT_OF_RANGE
#> 13   12       UNIMPLEMENTED
#> 14   13            INTERNAL
#> 15   14         UNAVAILABLE
#> 16   15           DATA_LOSS
#> 17   16     UNAUTHENTICATED
#>                                                      description
#> 1                             Not an error; returned on success.
#> 2          The operation was cancelled, typically by the caller.
#> 3                                                 Unknown error.
#> 4                      The client specified an invalid argument.
#> 5      The deadline expired before the operation could complete.
#> 6                           Some requested entity was not found.
#> 7   The entity that a client attempted to create already exists.
#> 8  The caller does not have permission to execute the operation.
#> 9                              Some resource has been exhausted.
#> 10      The system is not in a state required for the operation.
#> 11                                    The operation was aborted.
#> 12             The operation was attempted past the valid range.
#> 13            The operation is not implemented or not supported.
#> 14                                               Internal error.
#> 15                         The service is currently unavailable.
#> 16                        Unrecoverable data loss or corruption.
#> 17   The request does not have valid authentication credentials.
```

## Close and inspect

Closing a channel cancels its open streams.

``` r

grpc_close(ch)
```

[`zugrpc_info()`](https://pedrobtz.github.io/zugrpc/reference/zugrpc_info.md)
reports the zuhttp version, whether it speaks HTTP/2 and its TLS
backend.

``` r

zugrpc_info()
#> zugrpc 0.0.0.9000 on zuhttp 0.1.0
#>   HTTP/2:      yes
#>   TLS backend: openssl
```

## Next

See the [function
reference](https://pedrobtz.github.io/zugrpc/reference/index.md) for
every function, and the [performance
article](https://pedrobtz.github.io/zugrpc/articles/performance.md) for
what a call costs.
