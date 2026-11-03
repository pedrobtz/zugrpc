test_that("frame_encode() writes flag, big-endian length and bytes", {
  expect_identical(frame_encode(raw()), as.raw(c(0, 0, 0, 0, 0)))
  expect_identical(frame_encode(as.raw(7)), as.raw(c(0, 0, 0, 0, 1, 7)))

  msg <- as.raw(rep(1:255, length.out = 65535))
  enc <- frame_encode(msg)
  expect_identical(enc[1:5], as.raw(c(0, 0, 0, 0xff, 0xff)))
  expect_identical(enc, wire_message(msg))

  msg <- raw(65536)
  expect_identical(frame_encode(msg)[1:5], as.raw(c(0, 0, 1, 0, 0)))
})

test_that("frame_encode() rejects anything but a raw vector", {
  expect_error(frame_encode("abc"), class = "zugrpc_error_argument")
  expect_error(frame_encode(1:3), class = "zugrpc_error_argument")
})

test_that("frame_split() returns complete messages of 0, 1 and 65535 bytes", {
  sizes <- c(0, 1, 65535)
  msgs <- lapply(sizes, function(n) as.raw(rep(0:255, length.out = n)))
  buf <- do.call(c, lapply(msgs, wire_message))

  res <- frame_split(buf)
  expect_identical(res$messages, msgs)
  expect_identical(res$remainder, raw())
})

test_that("frame_split() accepts a message of exactly max_message bytes", {
  msg <- as.raw(rep(1:9, length.out = 1000))
  res <- frame_split(wire_message(msg), max_message = 1000)
  expect_identical(res$messages, list(msg))
})

test_that("frame_split() fails RESOURCE_EXHAUSTED above max_message", {
  msg <- raw(1001)
  expect_error(
    frame_split(wire_message(msg), max_message = 1000),
    class = "zugrpc_error_resource_exhausted"
  )
  # The prefix alone is enough: the call fails before the body is read.
  cnd <- expect_error(
    frame_split(wire_message(msg)[1:5], max_message = 1000),
    class = "zugrpc_error_status"
  )
  expect_identical(cnd$grpc_status, "RESOURCE_EXHAUSTED")
  expect_identical(cnd$grpc_code, 8L)
})

test_that("frame_split() keeps an incomplete message as the remainder", {
  buf <- wire_message(as.raw(1:10))
  res <- frame_split(buf[1:3])
  expect_identical(res$messages, list())
  expect_identical(res$remainder, buf[1:3])

  res <- frame_split(buf[1:12])
  expect_identical(res$messages, list())
  expect_identical(res$remainder, buf[1:12])

  two <- c(buf, buf[1:7])
  res <- frame_split(two)
  expect_identical(res$messages, list(as.raw(1:10)))
  expect_identical(res$remainder, buf[1:7])
})

test_that("a message split at every offset reassembles byte for byte", {
  msgs <- list(as.raw(1:6), raw(), as.raw(250:255))
  buf <- do.call(c, lapply(msgs, wire_message))
  for (cut in 0:length(buf)) {
    res <- split_in_chunks(buf, cut)
    expect_identical(res$messages, msgs, info = paste("cut at", cut))
    expect_identical(res$remainder, raw(), info = paste("cut at", cut))
  }
  for (a in 1:(length(buf) - 1)) {
    for (b in (a + 1):length(buf)) {
      res <- split_in_chunks(buf, c(a, b))
      expect_identical(res$messages, msgs, info = paste("cuts", a, b))
    }
  }
})

test_that("a compressed flag without an encoding is a protocol error", {
  buf <- wire_message(as.raw(1:3), flag = 1L)
  expect_error(frame_split(buf), class = "zugrpc_error_protocol")
  expect_error(
    frame_split(buf, encoding = "identity"),
    class = "zugrpc_error_protocol"
  )
})

test_that("a compressed flag with an encoding is UNIMPLEMENTED for now", {
  buf <- wire_message(as.raw(1:3), flag = 1L)
  expect_error(
    frame_split(buf, encoding = "gzip"),
    class = "zugrpc_error_unimplemented"
  )
})

test_that("a flag other than 0 or 1 is a protocol error", {
  buf <- wire_message(as.raw(1:3), flag = 2L)
  expect_error(frame_split(buf), class = "zugrpc_error_protocol")
})

test_that("frame_split() handles many small messages in one buffer", {
  msgs <- lapply(1:2000, function(i) as.raw(i %% 256))
  buf <- do.call(c, lapply(msgs, wire_message))
  res <- frame_split(buf)
  expect_length(res$messages, 2000)
  expect_identical(res$messages, msgs)
})
