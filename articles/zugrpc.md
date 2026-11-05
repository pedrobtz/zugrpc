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

## Open a channel

A channel holds the connection to one server. An `http://` URL is
cleartext HTTP/2, for a local server. An `https://` URL negotiates
HTTP/2 over TLS.

``` r

ch <- grpc_channel("http://localhost:15002")

ch <- grpc_channel(
  "https://spark.example.org:443",
  tls = zuhttp::zu_tls(ca_file = NULL),
  headers = c(authorization = "Bearer ..."),
  keepalive = grpc_keepalive(time = 60, timeout = 20),
  max_message = 128 * 1024^2
)
```

## Make a unary call

A unary call sends one request message and returns one response message.
The request is a raw vector, typically from
[`zuproto::proto_encode()`](https://pedrobtz.github.io/zuproto/reference/proto_encode.html).
The deadline is in seconds, or an absolute `POSIXct`.

``` r

res <- grpc_call(
  ch, "/spark.connect.SparkConnectService/AnalyzePlan",
  request = req_bytes,
  metadata = c("x-user-agent" = "zuspark"),
  deadline = 30
)
res$message
res$headers
res$trailers
res$status
```

## Stream the responses

A server-streaming call returns a stream. Each `$next_message()` returns
one response message, and `NULL` at the end. The server only sends more
as you read.

``` r

st <- grpc_stream(
  ch, "/spark.connect.SparkConnectService/ExecutePlan",
  request = req_bytes, deadline = 600
)
st$headers()
# Open: should $next_message() take a timeout of its own, or is the call
# deadline enough?
while (!is.null(m <- st$next_message())) {
  zuproto::proto_decode(m, type, pool)
}
st$trailers()
st$status()
```

Cancel a stream you no longer need. A second cancel does nothing.

``` r

st$cancel()
```

## Handle errors

A call that ends with a non-OK status raises a `zugrpc_error_status`
condition. Its class also carries the status, so you can catch one code.
The `details` field holds the decoded `google.rpc.Status`.

``` r

tryCatch(
  grpc_call(ch, "/spark.connect.SparkConnectService/AnalyzePlan",
            request = req_bytes),
  zugrpc_error_unavailable = function(cnd) {
    cnd$message
  },
  zugrpc_error_status = function(cnd) {
    cnd$details
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

Closing a channel cancels its open streams. `zugrpc_info()` reports the
zuhttp version, whether it offers HTTP/2 and its TLS backend.

``` r

grpc_close(ch)
zugrpc_info()
```

## Next

See the [function
reference](https://pedrobtz.github.io/zugrpc/reference/index.md) for
every function. Stage 5 of the design adds an article on performance,
measured against its targets.
