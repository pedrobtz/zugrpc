# The wording of every condition, in snapshots (portfolio rule: tests select
# conditions by class, and wording belongs here).

test_that("status conditions put the status name before the message", {
  expect_snapshot(error = TRUE, {
    status_abort("UNAVAILABLE", "connection reset")
    status_abort("UNKNOWN")
  })
})

test_that("a server's status and grpc-message reach the condition", {
  m <- mock_channel(grpc_response(
    trailers = c("grpc-status" = "14", "grpc-message" = "going%20away")
  ))
  expect_snapshot(error = TRUE, grpc_call(m$channel, "/a.B/C", raw()))

  m <- mock_channel(grpc_response(
    body = raw(),
    trailers = NULL,
    headers = c("content-type" = "text/plain"),
    status = 503L
  ))
  expect_snapshot(error = TRUE, grpc_call(m$channel, "/a.B/C", raw()))
})

test_that("transport conditions keep zuhttp's message", {
  for (class in c(
    "zu_connect_error",
    "zu_timeout_error",
    "zu_interrupted_error"
  )) {
    m <- failing_channel(class)
    expect_snapshot(error = TRUE, grpc_call(m$channel, "/a.B/C", raw()))
  }
})

test_that("protocol conditions say what broke", {
  m <- mock_channel(grpc_response(
    body = charToRaw("<html>"),
    trailers = NULL,
    headers = c("content-type" = "text/html")
  ))
  expect_snapshot(error = TRUE, grpc_call(m$channel, "/a.B/C", raw()))

  m <- mock_channel(grpc_response(body = wire_message(as.raw(1:9))[1:7]))
  expect_snapshot(error = TRUE, grpc_call(m$channel, "/a.B/C", raw()))

  m <- mock_channel(grpc_response(
    body = c(wire_message(as.raw(1)), wire_message(as.raw(2)))
  ))
  expect_snapshot(error = TRUE, grpc_call(m$channel, "/a.B/C", raw()))

  m <- mock_channel(grpc_response(body = wire_message(as.raw(1), flag = 1L)))
  expect_snapshot(error = TRUE, grpc_call(m$channel, "/a.B/C", raw()))

  m <- mock_channel(
    grpc_response(body = wire_message(raw(11))),
    max_message = 10
  )
  expect_snapshot(error = TRUE, grpc_call(m$channel, "/a.B/C", raw()))
})

test_that("warnings say what was dropped", {
  expect_snapshot(status_details_decode("!!"))
  expect_snapshot(metadata_decode(c("x-bin" = "!!")))
})

test_that("argument errors name what is wrong", {
  expect_snapshot(error = TRUE, {
    grpc_channel("localhost:1")
    grpc_channel("http://localhost:1", max_message = -1)
    grpc_keepalive(time = 0)
    grpc_call(grpc_channel("http://localhost:1"), "a.B/C", raw())
    grpc_call(grpc_channel("http://localhost:1"), "/a.B/C", "text")
    grpc_call(
      grpc_channel("http://localhost:1"),
      "/a.B/C",
      raw(),
      deadline = -1
    )
    metadata_encode(c(connection = "close"))
  })
})
