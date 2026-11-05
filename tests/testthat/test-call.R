# Recorded responses from grpc-go's interop server ------------------------

test_that("an EmptyCall sends the recorded request and returns OK", {
  fx <- read_fixture("empty")
  m <- replay_channel(fx)
  res <- grpc_call(m$channel, fx$request$method, raw())

  expect_identical(res$message, raw())
  expect_identical(res$status, "OK")
  expect_length(res$headers, 0L)

  req <- m$seen$requests[[1L]]
  expect_identical(req$method, "POST")
  expect_identical(req$url, paste0("http://localhost:50051", fx$request$method))
  expect_identical(req$body, fx$request$body)
  expect_identical(sent_header(req, "te"), "trailers")
  expect_identical(sent_header(req, "content-type"), "application/grpc+proto")
  expect_identical(sent_header(req, "grpc-accept-encoding"), "identity")
  expect_match(sent_header(req, "user-agent"), "^zugrpc/[0-9.]+ zuhttp/")
  expect_length(sent_header(req, "grpc-timeout"), 0L)
})

test_that("a UnaryCall returns the one response message", {
  fx <- read_fixture("ok")
  m <- replay_channel(fx)
  request <- fx$request$body[-(1:5)]
  res <- grpc_call(m$channel, fx$request$method, request)

  expect_identical(m$seen$requests[[1L]]$body, fx$request$body)
  expect_identical(res$message, fx$response$body[-(1:5)])
  expect_identical(res$status, "OK")
  # endpoint-load-metrics-bin is metadata; grpc-status is not.
  expect_named(res$trailers, "endpoint-load-metrics-bin")
})

test_that("metadata goes out encoded and comes back decoded", {
  fx <- read_fixture("metadata")
  m <- replay_channel(fx)
  res <- grpc_call(
    m$channel,
    fx$request$method,
    fx$request$body[-(1:5)],
    metadata = list(
      "X-Grpc-Test-Echo-Initial" = "test_initial_metadata_value",
      "x-grpc-test-echo-trailing-bin" = as.raw(c(0xab, 0xab, 0xab))
    )
  )

  req <- m$seen$requests[[1L]]
  expect_identical(
    sent_header(req, "x-grpc-test-echo-initial"),
    "test_initial_metadata_value"
  )
  expect_identical(sent_header(req, "x-grpc-test-echo-trailing-bin"), "q6ur")

  expect_identical(
    res$headers,
    list("x-grpc-test-echo-initial" = "test_initial_metadata_value")
  )
  expect_identical(
    res$trailers[["x-grpc-test-echo-trailing-bin"]],
    as.raw(c(0xab, 0xab, 0xab))
  )
})

test_that("every non-OK status raises its own class, from Trailers-Only", {
  codes <- grpc_status_codes()
  for (code in 1:16) {
    fx <- read_fixture(sprintf("status-%02d", code))
    m <- replay_channel(fx)
    name <- codes$name[codes$code == code]
    cnd <- expect_error(
      grpc_call(m$channel, fx$request$method, fx$request$body[-(1:5)]),
      class = paste0("zugrpc_error_", tolower(name))
    )
    expect_s3_class(cnd, "zugrpc_error_status")
    expect_s3_class(cnd, "zugrpc_error")
    expect_identical(cnd$grpc_status, name)
    expect_identical(cnd$grpc_code, code)
    expect_identical(cnd$grpc_message, sprintf("status %d", code))
    expect_identical(cnd$http_status, 200L)
    expect_identical(cnd$method, fx$request$method)
  }
})

test_that("grpc-message is percent-decoded as UTF-8", {
  fx <- read_fixture("special-message")
  m <- replay_channel(fx)
  cnd <- expect_error(
    grpc_call(m$channel, fx$request$method, fx$request$body[-(1:5)]),
    class = "zugrpc_error_unknown"
  )
  expect_identical(
    cnd$grpc_message,
    "\t\ntest with whitespace\r\nand Unicode BMP ☺ and non-BMP \U0001f608\t\n"
  )
})

test_that("an unknown method or service is UNIMPLEMENTED", {
  for (name in c("unimplemented-method", "unimplemented-service")) {
    fx <- read_fixture(name)
    m <- replay_channel(fx)
    expect_error(
      grpc_call(m$channel, fx$request$method, raw()),
      class = "zugrpc_error_unimplemented"
    )
  }
})

# Request building ---------------------------------------------------------

test_that("a deadline becomes grpc-timeout and the request's timeout", {
  m <- mock_channel(grpc_response())
  grpc_call(m$channel, "/a.B/C", raw(), deadline = 1.5)
  req <- m$seen$requests[[1L]]
  expect_identical(sent_header(req, "grpc-timeout"), "1500000u")
  expect_identical(req$policy$timeout, 1.5)

  expect_error(
    grpc_call(m$channel, "/a.B/C", raw(), deadline = -1),
    class = "zugrpc_error_argument"
  )
})

test_that("call metadata replaces a channel header of the same name", {
  m <- mock_channel(
    grpc_response(),
    headers = c(authorization = "Bearer a", "x-team" = "r")
  )
  grpc_call(
    m$channel,
    "/a.B/C",
    raw(),
    metadata = c(authorization = "Bearer b")
  )
  req <- m$seen$requests[[1L]]
  expect_identical(sent_header(req, "authorization"), "Bearer b")
  expect_identical(sent_header(req, "x-team"), "r")
})

test_that("bad arguments fail before anything is sent", {
  m <- mock_channel(grpc_response())
  expect_error(
    grpc_call(m$channel, "a.B/C", raw()),
    class = "zugrpc_error_argument"
  )
  expect_error(
    grpc_call(m$channel, "/a.B/C", "text"),
    class = "zugrpc_error_argument"
  )
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw(), metadata = c(te = "x")),
    class = "zugrpc_error_argument"
  )
  expect_error(
    grpc_call(list(), "/a.B/C", raw()),
    class = "zugrpc_error_argument"
  )
  expect_length(m$seen$requests, 0L)
})

# Status without a well-behaved server -------------------------------------

test_that("a status in trailers after a message wins over the message", {
  m <- mock_channel(grpc_response(
    body = wire_message(as.raw(1:3)),
    trailers = c("grpc-status" = "14", "grpc-message" = "going%20away")
  ))
  cnd <- expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_unavailable"
  )
  expect_identical(cnd$grpc_message, "going away")
})

test_that("a non-200 HTTP status with no grpc-status maps to a gRPC status", {
  cases <- c(
    "400" = "internal",
    "401" = "unauthenticated",
    "403" = "permission_denied",
    "404" = "unimplemented",
    "429" = "unavailable",
    "502" = "unavailable",
    "503" = "unavailable",
    "504" = "unavailable",
    "500" = "unknown"
  )
  for (http in names(cases)) {
    m <- mock_channel(grpc_response(
      body = charToRaw("nope"),
      trailers = NULL,
      headers = c("content-type" = "text/plain"),
      status = as.integer(http)
    ))
    cnd <- expect_error(
      grpc_call(m$channel, "/a.B/C", raw()),
      class = paste0("zugrpc_error_", cases[[http]])
    )
    expect_identical(cnd$http_status, as.integer(http))
  }
})

test_that("a grpc-status beats the HTTP status", {
  m <- mock_channel(grpc_response(
    body = raw(),
    trailers = NULL,
    headers = c("content-type" = "application/grpc", "grpc-status" = "5"),
    status = 503L
  ))
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_not_found"
  )
})

test_that("a completed response with no grpc-status is INTERNAL", {
  m <- mock_channel(grpc_response(trailers = NULL))
  cnd <- expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_internal"
  )
  expect_identical(cnd$grpc_message, "missing grpc-status in trailers")
})

# Hostile input (design §10) ----------------------------------------------

test_that("two messages on a unary call are a protocol error", {
  m <- mock_channel(grpc_response(
    body = c(wire_message(as.raw(1)), wire_message(as.raw(2)))
  ))
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_protocol"
  )
})

test_that("no message, or a truncated one, is a protocol error", {
  for (body in list(raw(), wire_message(as.raw(1:9))[1:7])) {
    m <- mock_channel(grpc_response(body = body))
    expect_error(
      grpc_call(m$channel, "/a.B/C", raw()),
      class = "zugrpc_error_protocol"
    )
  }
})

test_that("a declared length above max_message is RESOURCE_EXHAUSTED", {
  m <- mock_channel(
    grpc_response(body = wire_message(raw(11))),
    max_message = 10
  )
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_resource_exhausted"
  )
})

test_that("a compressed flag with no grpc-encoding is a protocol error", {
  m <- mock_channel(grpc_response(body = wire_message(as.raw(1), flag = 1L)))
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_protocol"
  )

  m <- mock_channel(grpc_response(
    body = wire_message(as.raw(1), flag = 1L),
    headers = c("content-type" = "application/grpc", "grpc-encoding" = "gzip")
  ))
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_unimplemented"
  )
})

test_that("text/html with status 200 is a protocol error with the body", {
  page <- charToRaw(strrep("<html>", 400))
  m <- mock_channel(grpc_response(
    body = page,
    trailers = NULL,
    headers = c("Content-Type" = "text/html; charset=utf-8")
  ))
  cnd <- expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_protocol"
  )
  expect_identical(cnd$content_type, "text/html; charset=utf-8")
  expect_identical(cnd$body, page[1:1024])
})
