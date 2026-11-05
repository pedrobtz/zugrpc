# a channel prints its authority, transport and state

    Code
      ch <- grpc_channel("http://localhost:50051")
      print(ch)
    Output
      <zugrpc_channel> localhost:50051
        transport: cleartext HTTP/2 (h2c)
        state:     open
        streams:   0 open
    Code
      grpc_close(ch)
      print(ch)
    Output
      <zugrpc_channel> localhost:50051
        transport: cleartext HTTP/2 (h2c)
        state:     closed
        streams:   0 open
    Code
      print(grpc_channel("https://spark.example.org:443"))
    Output
      <zugrpc_channel> spark.example.org:443
        transport: TLS, ALPN h2
        state:     open
        streams:   0 open

