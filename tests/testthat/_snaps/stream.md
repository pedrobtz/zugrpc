# a stream prints its method and state

    Code
      m <- mock_channel(grpc_response(body = stream_body(as.raw(1))))
      st <- grpc_stream(m$channel, "/a.B/C", raw())
      print(st)
    Output
      <zugrpc_stream> /a.B/C
        state: open
    Code
      invisible(st$next_message())
      invisible(st$next_message())
      print(st)
    Output
      <zugrpc_stream> /a.B/C
        state: ended, OK
    Code
      st2 <- grpc_stream(m$channel, "/a.B/C", raw())
      st2$cancel()
      print(st2)
    Output
      <zugrpc_stream> /a.B/C
        state: cancelled

