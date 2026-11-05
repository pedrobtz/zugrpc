test_that("base64_encode() writes RFC 4648 base64 without padding", {
  expect_identical(base64_encode(raw()), "")
  expect_identical(base64_encode(charToRaw("f")), "Zg")
  expect_identical(base64_encode(charToRaw("fo")), "Zm8")
  expect_identical(base64_encode(charToRaw("foo")), "Zm9v")
  expect_identical(base64_encode(charToRaw("foobar")), "Zm9vYmFy")
  expect_identical(base64_encode(as.raw(c(0xfb, 0xff))), "+/8")
})

test_that("base64_decode() accepts padded and unpadded input", {
  for (s in c("Zg", "Zg==")) {
    expect_identical(base64_decode(s), charToRaw("f"))
  }
  for (s in c("Zm8", "Zm8=")) {
    expect_identical(base64_decode(s), charToRaw("fo"))
  }
  expect_identical(base64_decode("Zm9vYmFy"), charToRaw("foobar"))
  expect_identical(base64_decode(""), raw())
  expect_identical(base64_decode("+/8"), as.raw(c(0xfb, 0xff)))
})

test_that("base64 round-trips every byte value at every length mod 3", {
  bytes <- as.raw(0:255)
  for (n in 0:6) {
    x <- c(bytes, bytes[seq_len(n)])
    expect_identical(base64_decode(base64_encode(x)), x)
  }
})

test_that("base64_decode() rejects input that is not base64", {
  expect_error(base64_decode("Zm9v!"), class = "zugrpc_error_protocol")
  expect_error(base64_decode("Z"), class = "zugrpc_error_protocol")
  expect_error(base64_decode("Zg=a"), class = "zugrpc_error_protocol")
  expect_error(base64_decode("Zg==="), class = "zugrpc_error_protocol")
})

test_that("metadata_encode() lower-cases names and base64s -bin values", {
  md <- metadata_encode(list(
    "X-User-Agent" = "zuspark",
    "trace-bin" = as.raw(c(1, 2, 3))
  ))
  expect_identical(md, c("x-user-agent" = "zuspark", "trace-bin" = "AQID"))
})

test_that("metadata_encode() accepts a named character vector", {
  expect_identical(
    metadata_encode(c(authorization = "Bearer x")),
    c(authorization = "Bearer x")
  )
  expect_identical(
    metadata_encode(NULL),
    stats::setNames(character(), character())
  )
})

test_that("metadata_encode() refuses reserved and grpc- names", {
  for (nm in c("grpc-foo", "grpc-timeout", "te", "content-type", ":path")) {
    md <- stats::setNames(list("x"), nm)
    expect_error(metadata_encode(md), class = "zugrpc_error_argument")
  }
})

test_that("metadata_encode() refuses bad names and values", {
  expect_error(metadata_encode(list("x")), class = "zugrpc_error_argument")
  expect_error(
    metadata_encode(list("bad name" = "x")),
    class = "zugrpc_error_argument"
  )
  expect_error(
    metadata_encode(list("x-bin" = "not raw")),
    class = "zugrpc_error_argument"
  )
  expect_error(
    metadata_encode(list("x" = as.raw(1))),
    class = "zugrpc_error_argument"
  )
  expect_error(
    metadata_encode(list("x" = "line\nbreak")),
    class = "zugrpc_error_argument"
  )
  expect_error(
    metadata_encode(list("x" = c("a", "b"))),
    class = "zugrpc_error_argument"
  )
})

test_that("metadata_decode() turns -bin values back into raw vectors", {
  md <- metadata_decode(c("x-user-agent" = "zuspark", "trace-bin" = "AQID"))
  expect_identical(
    md,
    list("x-user-agent" = "zuspark", "trace-bin" = as.raw(1:3))
  )

  padded <- metadata_decode(c("trace-bin" = "AQI="))
  expect_identical(padded, list("trace-bin" = as.raw(1:2)))
})

test_that("metadata_decode() splits a comma-joined -bin value", {
  # A server may join repeated binary values with commas, as grpc-go reads.
  md <- metadata_decode(c("x-bin" = "AQ,Ag", "y" = "a,b"))
  expect_identical(
    md,
    list("x-bin" = as.raw(1), "x-bin" = as.raw(2), "y" = "a,b")
  )
})

test_that("metadata_decode() drops a -bin value that is not base64", {
  expect_warning(
    md <- metadata_decode(c("x-bin" = "!!!", "y" = "ok")),
    class = "zugrpc_warning_metadata"
  )
  expect_identical(md, list("y" = "ok"))
  cnd <- expect_warning(
    metadata_decode(c("x-bin" = "!!!")),
    class = "zugrpc_warning"
  )
  expect_identical(cnd$name, "x-bin")
  expect_identical(cnd$value, "!!!")
})

test_that("metadata_merge() lets call metadata override channel headers", {
  channel <- c(authorization = "a", "x-env" = "prod")
  call <- c("x-env" = "test", "x-req" = "1")
  expect_identical(
    metadata_merge(channel, call),
    c(authorization = "a", "x-env" = "test", "x-req" = "1")
  )
})

test_that("request_headers() puts the gRPC headers before the metadata", {
  h <- request_headers(
    metadata = c("x-user-agent" = "zuspark"),
    timeout = "30S",
    user_agent = "zugrpc/0.0.0.9000"
  )
  expect_identical(
    h,
    c(
      te = "trailers",
      "content-type" = "application/grpc+proto",
      "user-agent" = "zugrpc/0.0.0.9000",
      "grpc-timeout" = "30S",
      "grpc-accept-encoding" = "identity",
      "x-user-agent" = "zuspark"
    )
  )
  h <- request_headers(user_agent = "zugrpc/0.0.0.9000")
  expect_false("grpc-timeout" %in% names(h))
})

test_that("check_method() wants /service/method", {
  expect_identical(
    check_method("/spark.connect.SparkConnectService/ExecutePlan"),
    "/spark.connect.SparkConnectService/ExecutePlan"
  )
  for (m in c("ExecutePlan", "/a", "/a/b/c", "a/b", "", NA)) {
    expect_error(check_method(m), class = "zugrpc_error_argument")
  }
  expect_error(check_method(c("/a/b", "/c/d")), class = "zugrpc_error_argument")
})

test_that("metadata_encode() refuses HTTP/2 connection-specific headers", {
  # RFC 9113 §8.2.2 makes these malformed on HTTP/2; host is :authority.
  for (name in c(
    "connection",
    "keep-alive",
    "proxy-connection",
    "transfer-encoding",
    "upgrade",
    "host",
    "Host"
  )) {
    expect_error(
      metadata_encode(stats::setNames(list("x"), name)),
      class = "zugrpc_error_argument"
    )
  }
})

test_that("the reserved names are the same going out and coming in", {
  nms <- c(":path", "grpc-status", "te", "content-type", "connection", "x")
  expect_identical(is_reserved_name(nms), c(rep(TRUE, 5), FALSE))
  fields <- stats::setNames(as.character(seq_along(nms)), nms)
  expect_named(user_metadata(fields), "x")
})
