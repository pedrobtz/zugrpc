test_that("grpc_channel() accepts http:// and https:// origins", {
  ch <- grpc_channel("http://localhost:50051")
  expect_s3_class(ch, "zugrpc_channel")
  expect_identical(ch$origin, "http://localhost:50051")
  expect_false(ch$tls)

  ch <- grpc_channel("HTTPS://spark.example.org:443/")
  expect_identical(ch$origin, "https://spark.example.org:443")
  expect_identical(ch$authority, "spark.example.org:443")
  expect_true(ch$tls)
})

test_that("grpc_channel() rejects URLs that are not a bare origin", {
  bad <- list(
    "localhost:50051",
    "ftp://localhost:21",
    "http://localhost:50051/grpc.testing.TestService",
    "http://user:pw@localhost:50051",
    "http://localhost:50051?x=1",
    c("http://a", "http://b"),
    NA_character_,
    1
  )
  for (url in bad) {
    expect_error(grpc_channel(url), class = "zugrpc_error_argument")
  }
})

test_that("grpc_channel() validates its other arguments", {
  expect_error(
    grpc_channel("http://localhost:1", tls = zuhttp::zu_tls()),
    class = "zugrpc_error_argument"
  )
  expect_error(
    grpc_channel("http://localhost:1", max_message = -1),
    class = "zugrpc_error_argument"
  )
  expect_error(
    grpc_channel("http://localhost:1", max_message = "big"),
    class = "zugrpc_error_argument"
  )
  expect_error(
    grpc_channel("http://localhost:1", client = list()),
    class = "zugrpc_error_argument"
  )
  expect_error(
    grpc_channel("http://localhost:1", headers = c("grpc-x" = "1")),
    class = "zugrpc_error_argument"
  )
})

test_that("the channel's client requires HTTP/2, also when one is supplied", {
  ch <- grpc_channel("http://localhost:1")
  expect_identical(client_setting(ch$client, "http2"), "required")
  expect_false(client_setting(ch$client, "check"))
  expect_identical(client_setting(ch$client, "max_body"), 128 * 1024^2 + 5)

  base <- zuhttp::zu_client(http2 = "off", timeout = 7)
  ch <- grpc_channel("http://localhost:1", client = base, max_message = 10)
  expect_identical(client_setting(ch$client, "http2"), "required")
  expect_identical(client_setting(ch$client, "timeout"), 7)
  expect_identical(client_setting(ch$client, "max_body"), 15)
  expect_identical(client_setting(base, "http2"), "off")
})

test_that("grpc_close() closes once, and a closed channel refuses calls", {
  m <- mock_channel(grpc_response())
  expect_invisible(grpc_close(m$channel))
  expect_true(m$channel$closed)
  expect_no_error(grpc_close(m$channel))
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_argument"
  )
  expect_length(m$seen$requests, 0L)
  expect_error(grpc_close(list()), class = "zugrpc_error_argument")
})

test_that("a channel prints its authority, transport and state", {
  expect_snapshot({
    ch <- grpc_channel("http://localhost:50051")
    print(ch)
    grpc_close(ch)
    print(ch)
    print(grpc_channel("https://spark.example.org:443"))
  })
})

test_that("keepalive defaults to Spark's 60 and 20 seconds, in the pool", {
  ch <- grpc_channel("http://localhost:1")
  expect_identical(pool_setting(ch$client, "keepalive_time_ms"), 60000L)
  expect_identical(pool_setting(ch$client, "keepalive_timeout_ms"), 20000L)
  expect_identical(pool_setting(ch$stream_client, "keepalive_time_ms"), 60000L)

  base <- zuhttp::zu_client(pool = zuhttp::zu_pool(max_idle = 3L))
  ch <- grpc_channel(
    "http://localhost:1",
    keepalive = grpc_keepalive(time = 5, timeout = 2),
    client = base
  )
  expect_identical(pool_setting(ch$client, "max_idle"), 3L)
  expect_identical(pool_setting(ch$client, "keepalive_time_ms"), 5000L)
  expect_identical(pool_setting(ch$client, "keepalive_timeout_ms"), 2000L)

  ch <- grpc_channel("http://localhost:1", keepalive = NULL)
  expect_identical(pool_setting(ch$client, "keepalive_time_ms"), 0L)

  ch <- grpc_channel(
    "http://localhost:1",
    client = zuhttp::zu_client(pool = NULL)
  )
  expect_null(client_setting(ch$client, "pool"))
})

test_that("grpc_keepalive() validates and prints", {
  expect_error(grpc_keepalive(time = 0), class = "zugrpc_error_argument")
  expect_error(grpc_keepalive(timeout = NA), class = "zugrpc_error_argument")
  expect_error(
    grpc_channel("http://localhost:1", keepalive = list(time = 1)),
    class = "zugrpc_error_argument"
  )
  expect_snapshot(print(grpc_keepalive(time = 30, timeout = 10)))
})

test_that("a channel never shares its pool with the client it builds on", {
  base <- zuhttp::zu_client()
  a <- grpc_channel("http://localhost:1", client = base, keepalive = NULL)
  b <- grpc_channel("http://localhost:1", client = base, keepalive = NULL)
  expect_false(identical(pool_state(a$client), pool_state(base)))
  expect_false(identical(pool_state(a$client), pool_state(b$client)))

  # The default keepalive changes the pool settings, and still gets its own.
  c <- grpc_channel("http://localhost:1", client = a$client)
  expect_false(identical(pool_state(c$client), pool_state(a$client)))
})

test_that("unary calls and streams share the channel's one pool", {
  # So that grpc_close() releases the idle connections of both.
  ch <- grpc_channel("http://localhost:1")
  expect_true(identical(pool_state(ch$stream_client), pool_state(ch$client)))
})

test_that("tls reaches both of the channel's clients", {
  tls <- zuhttp::zu_tls()
  ch <- grpc_channel("https://localhost:443", tls = tls)
  expect_identical(client_setting(ch$client, "tls"), tls)
  expect_identical(client_setting(ch$stream_client, "tls"), tls)

  base <- zuhttp::zu_client()
  ch <- grpc_channel("https://localhost:443", tls = tls, client = base)
  expect_identical(client_setting(ch$client, "tls"), tls)
})

test_that("a stream's body is unbounded; each message is bounded instead", {
  ch <- grpc_channel("http://localhost:1", max_message = 10)
  expect_identical(client_setting(ch$client, "max_body"), 15)
  expect_identical(client_setting(ch$stream_client, "max_body"), Inf)
})
