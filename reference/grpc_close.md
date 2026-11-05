# Close a gRPC channel

Closes the channel's idle connections. A call on a closed channel raises
`zugrpc_error_argument`. Closing a channel twice does nothing.

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
