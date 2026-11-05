# Against real servers (design §10); see helper-live.R for the variables.

test_that("live: unary calls over h2c, with metadata both ways", {
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_SERVER"))
  withr::defer(grpc_close(ch))

  res <- grpc_call(ch, paste0(interop, "EmptyCall"), raw(), deadline = 10)
  expect_identical(res$status, "OK")
  expect_identical(res$message, raw())

  res <- grpc_call(
    ch,
    paste0(interop, "UnaryCall"),
    simple_request(size = 1000),
    metadata = list(
      "x-grpc-test-echo-initial" = "hello",
      "x-grpc-test-echo-trailing-bin" = as.raw(c(0xab, 0xcd, 0xef))
    ),
    deadline = 10
  )
  expect_identical(payload_size(res$message), 1000)
  expect_identical(res$headers[["x-grpc-test-echo-initial"]], "hello")
  expect_identical(
    res$trailers[["x-grpc-test-echo-trailing-bin"]],
    as.raw(c(0xab, 0xcd, 0xef))
  )
})

test_that("live: every status code and a percent-encoded message", {
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_SERVER"))
  withr::defer(grpc_close(ch))
  codes <- grpc_status_codes()
  for (code in 1:16) {
    name <- codes$name[codes$code == code]
    cnd <- expect_error(
      grpc_call(
        ch,
        paste0(interop, "UnaryCall"),
        simple_request(code = code, message = "café 100%"),
        deadline = 10
      ),
      class = paste0("zugrpc_error_", tolower(name))
    )
    expect_identical(cnd$grpc_message, "café 100%")
  }
  expect_error(
    grpc_call(ch, paste0(interop, "UnimplementedCall"), raw()),
    class = "zugrpc_error_unimplemented"
  )
})

test_that("live: a server stream arrives message by message", {
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_SERVER"))
  withr::defer(grpc_close(ch))
  sizes <- c(10, 70000, 0, 2^20)
  st <- grpc_stream(
    ch,
    paste0(interop, "StreamingOutputCall"),
    streaming_request(sizes),
    deadline = 30
  )
  got <- c()
  while (!is.null(m <- st$next_message())) {
    got <- c(got, payload_size(m))
  }
  expect_identical(got, sizes)
  expect_identical(st$status(), "OK")
  expect_type(st$trailers(), "list")

  # 300 ms between messages: the first is in hand long before the last is
  # sent, so the iterator is not waiting for the whole body.
  # grpc-go sends its headers with the first message, so the clock starts
  # before the call.
  t0 <- Sys.time()
  st <- grpc_stream(
    ch,
    paste0(interop, "StreamingOutputCall"),
    streaming_request(c(1, 1, 1), interval_us = 300000),
    deadline = 30
  )
  expect_identical(payload_size(st$next_message()), 1)
  first <- as.numeric(Sys.time() - t0, units = "secs")
  while (!is.null(st$next_message())) {}
  all <- as.numeric(Sys.time() - t0, units = "secs")
  expect_lt(first, 0.6)
  expect_gt(all, 0.8)
})

test_that("live: a stream that ends with an error status raises it", {
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_SERVER"))
  withr::defer(grpc_close(ch))
  # The interop server honours response_status on FullDuplexCall, not on
  # StreamingOutputCall; one request, then the end of the request stream.
  st <- grpc_stream(
    ch,
    paste0(interop, "FullDuplexCall"),
    streaming_request(c(5, 5), code = 9),
    deadline = 10
  )
  cnd <- tryCatch(
    {
      while (!is.null(st$next_message())) {}
      NULL
    },
    zugrpc_error = identity
  )
  expect_s3_class(cnd, "zugrpc_error_failed_precondition")
})

test_that("live: Spark-style details decode from a real server", {
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_STATUS"))
  withr::defer(grpc_close(ch))
  cnd <- expect_error(
    grpc_call(ch, "/zugrpc.test.Status/Spark", raw(), deadline = 10),
    class = "zugrpc_error_internal"
  )
  expect_identical(
    cnd$details$details$ErrorInfo$metadata[["errorClass"]],
    "TABLE_OR_VIEW_NOT_FOUND"
  )
})

test_that("live: a server that stalls after its headers hits the deadline", {
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_STATUS"))
  withr::defer(grpc_close(ch))

  t0 <- Sys.time()
  st <- grpc_stream(ch, "/zugrpc.test.Status/Stall", raw(), deadline = 1)
  expect_identical(st$headers()[["x-stall"]], "1")
  expect_error(st$next_message(), class = "zugrpc_error_deadline_exceeded")
  elapsed <- as.numeric(Sys.time() - t0, units = "secs")
  expect_gt(elapsed, 0.9)
  expect_lt(elapsed, 2)

  t0 <- Sys.time()
  expect_error(
    grpc_call(ch, "/zugrpc.test.Status/Stall", raw(), deadline = 1),
    class = "zugrpc_error_deadline_exceeded"
  )
  elapsed <- as.numeric(Sys.time() - t0, units = "secs")
  expect_gt(elapsed, 0.9)
  expect_lt(elapsed, 2)

  # The channel is still good.
  expect_error(
    grpc_call(ch, "/zugrpc.test.Status/Spark", raw(), deadline = 10),
    class = "zugrpc_error_internal"
  )
})

test_that("live: cancel() returns within 100 ms and keeps the channel", {
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_STATUS"))
  withr::defer(grpc_close(ch))
  st <- grpc_stream(ch, "/zugrpc.test.Status/Stall", raw(), deadline = 30)
  t0 <- Sys.time()
  st$cancel()
  expect_lt(as.numeric(Sys.time() - t0, units = "secs"), 0.1)
  st$cancel()
  expect_error(st$next_message(), class = "zugrpc_error_cancelled")
  expect_error(
    grpc_call(ch, "/zugrpc.test.Status/Spark", raw(), deadline = 10),
    class = "zugrpc_error_internal"
  )
})

test_that("live: dropped streams, grpc_close() and readRDS()", {
  url <- live_server("ZU_GRPC_TEST_STATUS")
  ch <- grpc_channel(url)
  local({
    st <- grpc_stream(ch, "/zugrpc.test.Status/Stall", raw(), deadline = 30)
  })
  gc()
  expect_length(ls(ch$streams), 0L)

  a <- grpc_stream(ch, "/zugrpc.test.Status/Stall", raw(), deadline = 30)
  b <- grpc_stream(ch, "/zugrpc.test.Status/Stall", raw(), deadline = 30)
  expect_length(ls(ch$streams), 2L)
  grpc_close(ch)
  expect_error(a$next_message(), class = "zugrpc_error_cancelled")
  expect_error(b$next_message(), class = "zugrpc_error_cancelled")

  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(grpc_channel(url), path)
  ch <- readRDS(path)
  withr::defer(grpc_close(ch))
  expect_error(
    grpc_call(ch, "/zugrpc.test.Status/Spark", raw(), deadline = 10),
    class = "zugrpc_error_internal"
  )
})

test_that("live: TLS negotiates ALPN h2", {
  url <- live_server("ZU_GRPC_TEST_TLS")
  ch <- grpc_channel(url, client = live_tls_client())
  withr::defer(grpc_close(ch))
  res <- grpc_call(ch, paste0(interop, "EmptyCall"), raw(), deadline = 10)
  expect_identical(res$status, "OK")
  st <- grpc_stream(
    ch,
    paste0(interop, "StreamingOutputCall"),
    streaming_request(c(3, 4)),
    deadline = 10
  )
  expect_identical(payload_size(st$next_message()), 3)
  expect_identical(payload_size(st$next_message()), 4)
  expect_null(st$next_message())
})

test_that("live: a TLS server offering only http/1.1 is a transport error", {
  url <- live_server("ZU_GRPC_TEST_H1_TLS")
  ch <- grpc_channel(url, client = live_tls_client())
  withr::defer(grpc_close(ch))
  cnd <- expect_error(
    grpc_call(ch, "/a.B/C", raw(), deadline = 10),
    class = "zugrpc_error_transport"
  )
  expect_s3_class(cnd$parent, "zu_connect_error")
})

test_that("live: a plain HTTP/2 server is a protocol error", {
  ch <- grpc_channel(live_server("ZU_H2_TEST_SERVER"))
  withr::defer(grpc_close(ch))
  expect_error(
    grpc_call(ch, "/a.B/C", raw(), deadline = 10),
    class = "zugrpc_error_protocol"
  )
  expect_error(
    grpc_stream(ch, "/a.B/C", raw(), deadline = 10),
    class = "zugrpc_error_protocol"
  )
})
