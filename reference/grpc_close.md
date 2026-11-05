# Close a gRPC channel

Cancels the channel's open streams and closes its idle connections. A
call on a closed channel raises `zugrpc_error_argument`, and a cancelled
stream raises `zugrpc_error_cancelled` when it is next read. Closing a
channel twice does nothing.

## Usage

``` r
grpc_close(channel)
```

## Arguments

- channel:

  A channel from
  [`grpc_channel()`](https://pedrobtz.github.io/zugrpc/reference/grpc_channel.md).

## Value

`channel`, invisibly.

## Examples

``` r
ch <- grpc_channel("http://localhost:50051")
grpc_close(ch)
```
