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

test_that("live: a stall after part of the deadline overruns it (zuhttp#173)", {
  # Pins the known overrun of design §6.6: each wait is bounded by the whole
  # deadline afresh, so a stall that starts 0.6 s into a 1 s deadline fails
  # at about 1.6 s. When zuhttp#173 makes the bound exact this fails at about
  # 1 s; then tighten it and update §6.6.
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_STATUS"))
  withr::defer(grpc_close(ch))
  t0 <- Sys.time()
  st <- grpc_stream(ch, "/zugrpc.test.Status/SlowStall", raw(), deadline = 1)
  expect_identical(st$next_message(), as.raw(c(0x0a, 0x01, 0x01)))
  expect_error(st$next_message(), class = "zugrpc_error_deadline_exceeded")
  elapsed <- as.numeric(Sys.time() - t0, units = "secs")
  expect_gt(elapsed, 1.4)
  expect_lt(elapsed, 3)
})

test_that("live: a stream reset partway through its body is a transport error", {
  ch <- grpc_channel(live_server("ZU_H2_TEST_SERVER"))
  withr::defer(grpc_close(ch))
  st <- grpc_stream(ch, "/zugrpc.test.Reset/Mid", raw(), deadline = 10)
  expect_identical(st$next_message(), as.raw(7))
  cnd <- expect_error(st$next_message(), class = "zugrpc_error_transport")
  expect_identical(cnd$method, "/zugrpc.test.Reset/Mid")
  expect_error(st$next_message(), class = "zugrpc_error_transport")
  expect_length(ls(ch$streams), 0L)
})

test_that("live: a stream's whole body may exceed max_message", {
  # Each message is under the limit; together they are far over it.
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_SERVER"), max_message = 1000)
  withr::defer(grpc_close(ch))
  st <- grpc_stream(
    ch,
    paste0(interop, "StreamingOutputCall"),
    streaming_request(rep(900, 20)),
    deadline = 10
  )
  got <- c()
  while (!is.null(m <- st$next_message())) {
    got <- c(got, payload_size(m))
  }
  expect_identical(got, rep(900, 20))
})

test_that("live: tls = zu_tls(ca_file =) trusts a private CA", {
  url <- live_server("ZU_GRPC_TEST_TLS")
  ca <- Sys.getenv("ZU_GRPC_TEST_CA")
  skip_if_not(
    "ca_file" %in% zuhttp::zu_info()$tls_capabilities,
    "this TLS backend cannot take a private CA (zuhttp#5)"
  )
  ch <- grpc_channel(url, tls = zuhttp::zu_tls(ca_file = ca))
  withr::defer(grpc_close(ch))
  res <- grpc_call(ch, paste0(interop, "EmptyCall"), raw(), deadline = 10)
  expect_identical(res$status, "OK")
})

test_that("live: grpc-go reads grpc-timeout as the deadline that was set", {
  # The other side of the header (#61): tools/test-server answers with the
  # time left on the call's deadline, as grpc-go decoded it. Each unit
  # rounds up, by at most one of its steps.
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_STATUS"))
  withr::defer(grpc_close(ch))
  left <- function(deadline) {
    m <- grpc_call(
      ch,
      "/zugrpc.test.Status/Deadline",
      raw(),
      deadline = deadline
    )
    rawToChar(m$message[-(1:2)])
  }
  expect_identical(left(NULL), "none")
  step <- c(n = 1e-9, u = 1e-6, m = 1e-3, S = 1, M = 60, H = 3600)
  for (d in c(0.05, 5, 500, 2e5, 1e9, 7e9)) {
    unit <- substring(grpc_timeout(d), nchar(grpc_timeout(d)))
    seconds <- as.numeric(left(d)) / 1e9
    expect_lte(seconds, d + step[[unit]])
    expect_gt(seconds, d - 1)
  }
})

test_that("live: max_message is straddled on unary calls and streams", {
  # Through zuhttp's own max_body on a real socket, not the mock (#67).
  url <- live_server("ZU_GRPC_TEST_SERVER")
  ch <- grpc_channel(url)
  size <- length(
    grpc_call(
      ch,
      paste0(interop, "UnaryCall"),
      simple_request(size = 1000),
      deadline = 10
    )$message
  )
  stream_size <- length(grpc_stream(
    ch,
    paste0(interop, "StreamingOutputCall"),
    streaming_request(1000),
    deadline = 10
  )$next_message())
  grpc_close(ch)

  for (limit in size + c(-1, 0, 1)) {
    ch <- grpc_channel(url, max_message = limit)
    call <- function() {
      grpc_call(
        ch,
        paste0(interop, "UnaryCall"),
        simple_request(size = 1000),
        deadline = 10
      )
    }
    if (limit >= size) {
      expect_length(call()$message, size)
    } else {
      cnd <- expect_error(call(), class = "zugrpc_error_resource_exhausted")
      expect_identical(cnd$http_status, 200L)
    }
    grpc_close(ch)
  }
  for (limit in stream_size + c(-1, 0, 1)) {
    ch <- grpc_channel(url, max_message = limit)
    st <- grpc_stream(
      ch,
      paste0(interop, "StreamingOutputCall"),
      streaming_request(1000),
      deadline = 10
    )
    if (limit >= stream_size) {
      expect_length(st$next_message(), stream_size)
      expect_null(st$next_message())
    } else {
      expect_error(st$next_message(), class = "zugrpc_error_resource_exhausted")
    }
    grpc_close(ch)
  }

  # max_message = 0 takes an empty message and nothing more.
  ch <- grpc_channel(url, max_message = 0)
  withr::defer(grpc_close(ch))
  expect_identical(
    grpc_call(ch, paste0(interop, "EmptyCall"), raw(), deadline = 10)$message,
    raw()
  )
  expect_error(
    grpc_call(
      ch,
      paste0(interop, "UnaryCall"),
      simple_request(size = 1),
      deadline = 10
    ),
    class = "zugrpc_error_resource_exhausted"
  )
})

test_that("live: a forked child leaves the parent's channel and stream alone", {
  # A child of fork() shares the parent's sockets (#65). zuhttp's PID guard
  # gives it connections of its own; the parent's stream and its next call
  # must be untouched by anything the child does.
  skip_on_os("windows")
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_SERVER"))
  withr::defer(grpc_close(ch))
  expect_identical(
    grpc_call(ch, paste0(interop, "EmptyCall"), raw(), deadline = 10)$status,
    "OK"
  )
  st <- grpc_stream(
    ch,
    paste0(interop, "StreamingOutputCall"),
    streaming_request(c(1, 2, 3), interval_us = 200000),
    deadline = 30
  )
  expect_identical(payload_size(st$next_message()), 1)

  child <- parallel::mcparallel({
    call <- grpc_call(
      ch,
      paste0(interop, "EmptyCall"),
      raw(),
      deadline = 10
    )$status
    # Reading the parent's stream must fail, never yield its next message.
    read <- tryCatch(
      {
        m <- st$next_message()
        if (is.null(m)) "end" else paste("message", payload_size(m))
      },
      zugrpc_error = function(cnd) "error"
    )
    st$cancel()
    grpc_close(ch)
    list(call = call, read = read)
  })
  out <- parallel::mccollect(child, wait = TRUE)[[1L]]
  expect_identical(out$call, "OK")
  expect_identical(out$read, "error")

  expect_identical(payload_size(st$next_message()), 2)
  expect_identical(payload_size(st$next_message()), 3)
  expect_null(st$next_message())
  expect_identical(st$status(), "OK")
  expect_identical(
    grpc_call(ch, paste0(interop, "EmptyCall"), raw(), deadline = 10)$status,
    "OK"
  )
})

test_that("live: a stream read back with readRDS() fails, and keeps failing", {
  # The copy's response did not survive serialisation (#66). It must raise
  # a zugrpc error, the same on every read, while the original reads on.
  ch <- grpc_channel(live_server("ZU_GRPC_TEST_SERVER"))
  withr::defer(grpc_close(ch))
  st <- grpc_stream(
    ch,
    paste0(interop, "StreamingOutputCall"),
    streaming_request(c(1, 2, 3), interval_us = 200000),
    deadline = 30
  )
  expect_identical(payload_size(st$next_message()), 1)

  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(st, path)
  copy <- readRDS(path)
  first <- expect_error(copy$next_message(), class = "zugrpc_error")
  again <- expect_error(copy$next_message(), class = "zugrpc_error")
  expect_identical(class(again), class(first))

  expect_identical(payload_size(st$next_message()), 2)
  expect_identical(payload_size(st$next_message()), 3)
  expect_null(st$next_message())
})
