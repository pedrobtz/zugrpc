# HTTP/2 keepalive settings

A channel's connection can sit idle between calls, and a server or a
middlebox may drop it without saying so. With keepalive, a connection
idle for `time` seconds is sent an HTTP/2 PING before its next call, and
replaced by a new one if no answer comes within `timeout` seconds.

## Usage

``` r
grpc_keepalive(time = 60, timeout = 20)
```

## Arguments

- time:

  Seconds of idleness before a PING.

- timeout:

  Seconds to wait for the answer.

## Value

A `zugrpc_keepalive`, for
[`grpc_channel()`](https://pedrobtz.github.io/zugrpc/reference/grpc_channel.md).

## Examples

``` r
grpc_keepalive()
#> <zugrpc_keepalive> PING after 60s idle, answer within 20s
grpc_keepalive(time = 30, timeout = 10)
#> <zugrpc_keepalive> PING after 30s idle, answer within 10s
```
