# A recorded response from tests/testthat/fixtures/<dir>/, written by
# tools/record-fixtures.R against grpc-go's interop server.
read_fixture <- function(name, dir = "unary") {
  dget(test_path("fixtures", dir, paste0(name, ".dput")))
}

# A channel whose zuhttp client answers every request with `respond(req)`,
# a function returning a zu_response(). The requests it saw are kept in
# `$seen`, newest last.
mock_channel <- function(respond, ...) {
  seen <- new.env(parent = emptyenv())
  seen$requests <- list()
  fake <- zuhttp::zu_mock_transport(function(req) {
    seen$requests <- c(seen$requests, list(req))
    respond(req)
  })
  ch <- grpc_channel(
    "http://localhost:50051",
    client = zuhttp::zu_client(transport = fake),
    ...
  )
  list(channel = ch, seen = seen)
}

# A channel that replays one recorded response.
replay_channel <- function(fixture, ...) {
  r <- fixture$response
  mock_channel(
    function(req) {
      zuhttp::zu_response(
        r$status,
        headers = r$headers,
        body = r$body,
        trailers = r$trailers
      )
    },
    ...
  )
}

# A hand-built gRPC response, for the hostile inputs no real server sends.
grpc_response <- function(
  body = wire_message(raw()),
  trailers = c("grpc-status" = "0"),
  headers = c("content-type" = "application/grpc+proto"),
  status = 200L
) {
  force(body)
  function(req) {
    zuhttp::zu_response(
      status,
      headers = headers,
      body = body,
      trailers = trailers
    )
  }
}

# The value of a header a request carried, matched case-insensitively.
sent_header <- function(req, name) {
  h <- req$headers
  unname(h[tolower(names(h)) == name])
}

# A channel whose zuhttp transport fails with the zuhttp condition `class`.
failing_channel <- function(class) {
  mock_channel(function(req) stop(zuhttp::zu_condition(class, "boom")))
}
