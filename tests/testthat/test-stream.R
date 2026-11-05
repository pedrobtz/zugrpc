# Recorded and hand-built responses ---------------------------------------

stream_body <- function(...) do.call(c, lapply(list(...), wire_message))

test_that("a stream yields each message, then NULL, then the status", {
  msgs <- list(as.raw(1:3), raw(), as.raw(rep(7, 70000)))
  m <- mock_channel(grpc_response(
    body = do.call(c, lapply(msgs, wire_message)),
    trailers = c("grpc-status" = "0", "x-t" = "v")
  ))
  st <- grpc_stream(m$channel, "/a.B/C", raw())
  expect_s3_class(st, "zugrpc_stream")
  expect_null(st$trailers())
  expect_null(st$status())
  expect_identical(st$next_message(), msgs[[1]])
  expect_identical(st$next_message(), msgs[[2]])
  expect_identical(st$next_message(), msgs[[3]])
  expect_null(st$next_message())
  expect_null(st$next_message())
  expect_identical(st$status(), "OK")
  expect_identical(st$trailers(), list("x-t" = "v"))
  expect_length(ls(m$channel$streams), 0L)
})

test_that("a message split across reads at every offset reassembles", {
  msgs <- list(as.raw(1:9), as.raw(10:12))
  body <- do.call(c, lapply(msgs, wire_message))
  for (n in seq_along(body)) {
    local_mocked_bindings(
      resp_read = function(res, size) zuhttp::zu_resp_read(res, n)
    )
    m <- mock_channel(grpc_response(body = body))
    st <- grpc_stream(m$channel, "/a.B/C", raw())
    got <- list()
    while (!is.null(x <- st$next_message())) {
      got[[length(got) + 1L]] <- x
    }
    expect_identical(got, msgs)
  }
})

test_that("the request is the unary request, sent as a stream", {
  m <- mock_channel(grpc_response(body = raw()))
  st <- grpc_stream(
    m$channel,
    "/a.B/C",
    as.raw(1:2),
    metadata = c(k = "v"),
    deadline = 2
  )
  req <- m$seen$requests[[1L]]
  expect_identical(req$body, wire_message(as.raw(1:2)))
  expect_identical(sent_header(req, "k"), "v")
  expect_identical(sent_header(req, "grpc-timeout"), "2000000u")
  expect_true(req$stream)
})

test_that("Trailers-Only ends a stream with its status", {
  fx <- read_fixture("status-05")
  m <- replay_channel(fx)
  st <- grpc_stream(m$channel, fx$request$method, raw())
  cnd <- expect_error(st$next_message(), class = "zugrpc_error_not_found")
  expect_identical(cnd$grpc_message, "status 5")
  expect_identical(st$status(), "NOT_FOUND")
  expect_null(st$next_message())
})

test_that("a non-OK status after messages is raised after them", {
  fx <- read_fixture("spark", dir = "details")
  m <- mock_channel(grpc_response(
    body = stream_body(as.raw(1)),
    trailers = c(
      "grpc-status" = "13",
      "grpc-status-details-bin" = fx$response$headers[[
        "grpc-status-details-bin"
      ]]
    )
  ))
  st <- grpc_stream(m$channel, "/a.B/C", raw())
  expect_identical(st$next_message(), as.raw(1))
  cnd <- expect_error(st$next_message(), class = "zugrpc_error_internal")
  expect_identical(cnd$details$details$ErrorInfo$domain, "org.apache.spark")
})

test_that("headers() returns the initial metadata at once", {
  m <- mock_channel(grpc_response(
    body = raw(),
    headers = c("content-type" = "application/grpc", "x-h" = "1")
  ))
  st <- grpc_stream(m$channel, "/a.B/C", raw())
  expect_identical(st$headers(), list("x-h" = "1"))
})

# Hostile input ------------------------------------------------------------

test_that("a non-gRPC response fails when the stream opens", {
  m <- mock_channel(grpc_response(
    body = charToRaw("<html>"),
    trailers = NULL,
    headers = c("content-type" = "text/html")
  ))
  expect_error(
    grpc_stream(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_protocol"
  )
  expect_length(ls(m$channel$streams), 0L)

  m <- mock_channel(grpc_response(
    body = raw(),
    trailers = NULL,
    headers = c("content-type" = "text/plain"),
    status = 503L
  ))
  expect_error(
    grpc_stream(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_unavailable"
  )
})

test_that("a length above max_message aborts before the body is read", {
  reads <- 0L
  local_mocked_bindings(
    resp_read = function(res, n) {
      reads <<- reads + 1L
      zuhttp::zu_resp_read(res, 5)
    }
  )
  m <- mock_channel(
    grpc_response(body = wire_message(raw(100))),
    max_message = 10
  )
  st <- grpc_stream(m$channel, "/a.B/C", raw())
  expect_error(st$next_message(), class = "zugrpc_error_resource_exhausted")
  expect_identical(reads, 1L)
  expect_length(ls(m$channel$streams), 0L)
})

test_that("a compressed flag or a truncated body is a protocol error", {
  m <- mock_channel(grpc_response(body = wire_message(as.raw(1), flag = 1L)))
  st <- grpc_stream(m$channel, "/a.B/C", raw())
  expect_error(st$next_message(), class = "zugrpc_error_protocol")

  m <- mock_channel(grpc_response(body = wire_message(as.raw(1:9))[1:8]))
  st <- grpc_stream(m$channel, "/a.B/C", raw())
  expect_error(st$next_message(), class = "zugrpc_error_protocol")
})

test_that("a missing grpc-status at the end is INTERNAL", {
  m <- mock_channel(grpc_response(
    body = stream_body(as.raw(1)),
    trailers = c()
  ))
  st <- grpc_stream(m$channel, "/a.B/C", raw())
  expect_identical(st$next_message(), as.raw(1))
  expect_error(st$next_message(), class = "zugrpc_error_internal")
})

# Cancellation and lifetimes (design §6.6, §10) ---------------------------

test_that("cancel() stops the stream once, and reading after it is CANCELLED", {
  m <- mock_channel(grpc_response(body = stream_body(as.raw(1), as.raw(2))))
  st <- grpc_stream(m$channel, "/a.B/C", raw())
  expect_identical(st$next_message(), as.raw(1))
  expect_length(ls(m$channel$streams), 1L)
  expect_null(st$cancel())
  expect_null(st$cancel())
  expect_length(ls(m$channel$streams), 0L)
  expect_error(st$next_message(), class = "zugrpc_error_cancelled")
})

test_that("a deadline that has passed fails the next read", {
  m <- mock_channel(grpc_response(body = stream_body(as.raw(1))))
  st <- grpc_stream(m$channel, "/a.B/C", raw(), deadline = 0.05)
  Sys.sleep(0.1)
  expect_error(st$next_message(), class = "zugrpc_error_deadline_exceeded")
  expect_length(ls(m$channel$streams), 0L)
})

test_that("a deadline already passed fails before anything is sent", {
  m <- mock_channel(grpc_response())
  expect_error(
    grpc_stream(m$channel, "/a.B/C", raw(), deadline = 0),
    class = "zugrpc_error_deadline_exceeded"
  )
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw(), deadline = Sys.time() - 1),
    class = "zugrpc_error_deadline_exceeded"
  )
  expect_length(m$seen$requests, 0L)
})

test_that("grpc_close() cancels the channel's open streams", {
  m <- mock_channel(grpc_response(body = stream_body(as.raw(1), as.raw(2))))
  a <- grpc_stream(m$channel, "/a.B/C", raw())
  b <- grpc_stream(m$channel, "/a.B/C", raw())
  expect_identical(a$next_message(), as.raw(1))
  expect_length(ls(m$channel$streams), 2L)
  grpc_close(m$channel)
  expect_length(ls(m$channel$streams), 0L)
  expect_error(a$next_message(), class = "zugrpc_error_cancelled")
  expect_error(b$next_message(), class = "zugrpc_error_cancelled")
})

test_that("a dropped stream is cancelled by its finaliser", {
  m <- mock_channel(grpc_response(body = stream_body(as.raw(1), as.raw(2))))
  local({
    st <- grpc_stream(m$channel, "/a.B/C", raw())
    st$next_message()
  })
  expect_length(ls(m$channel$streams), 1L)
  gc()
  expect_length(ls(m$channel$streams), 0L)
})

test_that("an interrupt while reading leaves the channel usable", {
  m <- mock_channel(grpc_response(body = stream_body(as.raw(1))))
  st <- grpc_stream(m$channel, "/a.B/C", raw())
  local({
    local_mocked_bindings(
      resp_read = function(res, n) {
        stop(zuhttp::zu_condition("zu_interrupted_error", "interrupted"))
      }
    )
    expect_error(st$next_message(), class = "zugrpc_error_interrupt")
  })
  expect_length(ls(m$channel$streams), 0L)
  expect_identical(grpc_call(m$channel, "/a.B/C", raw())$status, "OK")
})

test_that("a channel read back with readRDS() makes calls", {
  # A handler that captures nothing, so the channel serialises cleanly.
  handler <- function(req) {
    zuhttp::zu_response(
      200L,
      headers = c("content-type" = "application/grpc"),
      body = as.raw(c(0, 0, 0, 0, 1, 4)),
      trailers = c("grpc-status" = "0")
    )
  }
  environment(handler) <- baseenv()
  ch <- grpc_channel(
    "http://localhost:50051",
    client = zuhttp::zu_client(transport = zuhttp::zu_mock_transport(handler))
  )
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(ch, path)
  ch <- readRDS(path)
  expect_identical(grpc_call(ch, "/a.B/C", raw())$message, as.raw(4))
  st <- grpc_stream(ch, "/a.B/C", raw())
  expect_identical(st$next_message(), as.raw(4))
})

test_that("a stream prints its method and state", {
  expect_snapshot({
    m <- mock_channel(grpc_response(body = stream_body(as.raw(1))))
    st <- grpc_stream(m$channel, "/a.B/C", raw())
    print(st)
    invisible(st$next_message())
    invisible(st$next_message())
    print(st)
    st2 <- grpc_stream(m$channel, "/a.B/C", raw())
    st2$cancel()
    print(st2)
  })
})
