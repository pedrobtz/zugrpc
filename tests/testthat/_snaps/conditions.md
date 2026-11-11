# argument errors name what is wrong

    Code
      grpc_channel("localhost:1")
    Condition
      Error:
      ! `url` must be one string, http://host:port or https://host:port.
    Code
      grpc_channel("http://localhost:1", max_message = -1)
    Condition
      Error:
      ! `max_message` must be one number of bytes between 0 and 4 GiB.
    Code
      grpc_keepalive(time = 0)
    Condition
      Error:
      ! `time` must be one number of seconds from 0.001 to 2147483.647.
    Code
      grpc_call(grpc_channel("http://localhost:1"), "a.B/C", raw())
    Condition
      Error:
      ! `method` must be one string of the form "/package.Service/Method".
    Code
      grpc_call(grpc_channel("http://localhost:1"), "/a.B/C", "text")
    Condition
      Error:
      ! `request` must be a raw vector.
    Code
      grpc_call(grpc_channel("http://localhost:1"), "/a.B/C", raw(), deadline = -1)
    Condition
      Error:
      ! `deadline` must be a non-negative number of seconds or one POSIXct time.
    Code
      metadata_encode(c(connection = "close"))
    Condition
      Error:
      ! Metadata name 'connection' is reserved for zugrpc.

# transport conditions keep zuhttp's message

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! UNAVAILABLE: boom

---

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! DEADLINE_EXCEEDED: deadline exceeded

---

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! The call was interrupted.

# protocol conditions say what broke

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! The response is not gRPC: content-type is 'text/html'.

---

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! The response body ends inside a gRPC message.

---

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! A unary call must return exactly one message, not 2.

---

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! A compressed message arrived without a grpc-encoding.

---

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! RESOURCE_EXHAUSTED: received message larger than max (11 vs. 10)

# status conditions put the status name before the message

    Code
      status_abort("UNAVAILABLE", "connection reset")
    Condition
      Error:
      ! UNAVAILABLE: connection reset
    Code
      status_abort("UNKNOWN")
    Condition
      Error:
      ! UNKNOWN

# a server's status and grpc-message reach the condition

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! UNAVAILABLE: going away

---

    Code
      grpc_call(m$channel, "/a.B/C", raw())
    Condition
      Error:
      ! UNAVAILABLE: HTTP status 503 with no grpc-status

# warnings say what was dropped

    Code
      status_details_decode("!!")
    Condition
      Warning:
      grpc-status-details-bin could not be decoded; `details` is NULL. Invalid base64 in gRPC metadata.
      Caused by error:
      ! Invalid base64 in gRPC metadata.
    Output
      NULL

---

    Code
      metadata_decode(c(`x-bin` = "!!"))
    Condition
      Warning:
      Received metadata 'x-bin' is not base64 and was dropped.
    Output
      named list()

