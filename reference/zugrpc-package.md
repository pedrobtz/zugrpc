# zugrpc: Client for 'gRPC' Remote Procedure Calls over 'HTTP/2'

A client for 'gRPC' remote procedure calls, written in 'R' on top of the
'HTTP/2' requests that 'zuhttp' makes. Implements the 'gRPC' wire
protocol: length-prefixed messages, request headers and metadata,
deadlines, cancellation, and the call status carried in 'HTTP' trailers,
with error details decoded into structured conditions. Supports unary
and server-streaming calls, with streamed responses read one message at
a time. Messages are encoded and decoded by the caller, for example with
'zuproto'.

## See also

Useful links:

- <https://github.com/pedrobtz/zugrpc>

- <https://pedrobtz.github.io/zugrpc/>

- Report bugs at <https://github.com/pedrobtz/zugrpc/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]
