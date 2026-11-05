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

# The contract with zuhttp's object layout ---------------------------------
# zuhttp has no accessors for a request's timeout or a client's settings, so
# these read its fields. They are the only place the tests do, so a zuhttp
# refactor is fixed here.

# The total timeout a request was sent with, in seconds.
request_timeout <- function(req) req$policy$timeout

# A setting of a zu_client(), such as "http2", "max_body" or "tls".
client_setting <- function(client, name) client[[name]]

# A setting of the client's pool, such as "keepalive_time_ms".
pool_setting <- function(client, name) client$pool[[name]]

# The environment holding the client's pool; two clients that share one
# share their connections.
pool_state <- function(client) attr(client, "pool_state")

# A channel whose zuhttp transport fails with the zuhttp condition `class`.
failing_channel <- function(class) {
  mock_channel(function(req) stop(zuhttp::zu_condition(class, "boom")))
}

# A response body of whole messages, one per argument.
stream_body <- function(...) do.call(c, lapply(list(...), wire_message))

# Counts the calls zugrpc makes to zuhttp's zu_resp_abort(), which sends
# RST_STREAM, and zu_pool_reset(), which closes connections, while still
# making them. Cancellation must abort exactly once and never reset (D8).
local_zuhttp_spy <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv())
  calls$abort <- 0L
  calls$reset <- 0L
  abort <- zuhttp::zu_resp_abort
  reset <- zuhttp::zu_pool_reset
  testthat::local_mocked_bindings(
    zu_resp_abort = function(resp) {
      calls$abort <- calls$abort + 1L
      abort(resp)
    },
    zu_pool_reset = function(client) {
      calls$reset <- calls$reset + 1L
      reset(client)
    },
    .package = "zuhttp",
    .env = env
  )
  calls
}
