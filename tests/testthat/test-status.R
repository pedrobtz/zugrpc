test_that("grpc_status_codes() lists the 17 codes from statuscodes.md", {
  codes <- grpc_status_codes()
  expect_s3_class(codes, "data.frame")
  expect_identical(nrow(codes), 17L)
  expect_identical(codes$code, 0:16)
  expect_identical(
    codes$name,
    c(
      "OK",
      "CANCELLED",
      "UNKNOWN",
      "INVALID_ARGUMENT",
      "DEADLINE_EXCEEDED",
      "NOT_FOUND",
      "ALREADY_EXISTS",
      "PERMISSION_DENIED",
      "RESOURCE_EXHAUSTED",
      "FAILED_PRECONDITION",
      "ABORTED",
      "OUT_OF_RANGE",
      "UNIMPLEMENTED",
      "INTERNAL",
      "UNAVAILABLE",
      "DATA_LOSS",
      "UNAUTHENTICATED"
    )
  )
  expect_type(codes$description, "character")
})

test_that("status_from_header() maps every code to its name", {
  codes <- grpc_status_codes()
  for (i in seq_len(nrow(codes))) {
    st <- status_from_header(as.character(codes$code[i]))
    expect_identical(st$name, codes$name[i])
    expect_identical(st$code, codes$code[i])
  }
})

test_that("status_from_header() treats missing, malformed and unknown codes", {
  expect_identical(status_from_header(NULL)$name, "INTERNAL")
  expect_identical(
    status_from_header(NULL)$message,
    "missing grpc-status in trailers"
  )
  expect_identical(status_from_header("abc")$name, "INTERNAL")
  expect_identical(status_from_header("")$name, "INTERNAL")
  expect_identical(status_from_header("17")$name, "UNKNOWN")
  expect_identical(status_from_header("17")$code, 2L)
})

test_that("status_from_http() follows the specification's fallback map", {
  map <- c(
    "400" = "INTERNAL",
    "401" = "UNAUTHENTICATED",
    "403" = "PERMISSION_DENIED",
    "404" = "UNIMPLEMENTED",
    "429" = "UNAVAILABLE",
    "502" = "UNAVAILABLE",
    "503" = "UNAVAILABLE",
    "504" = "UNAVAILABLE",
    "500" = "UNKNOWN",
    "418" = "UNKNOWN",
    "301" = "UNKNOWN"
  )
  for (http in names(map)) {
    expect_identical(
      status_from_http(as.integer(http)),
      map[[http]],
      info = http
    )
  }
})

test_that("grpc_message_decode() percent-decodes UTF-8", {
  expect_identical(grpc_message_decode("plain text"), "plain text")
  expect_identical(grpc_message_decode("50%25 off"), "50% off")
  expect_identical(grpc_message_decode("a%0Ab"), "a\nb")
  decoded <- grpc_message_decode("caf%C3%A9 %E2%9C%93")
  expect_identical(decoded, "café ✓")
  expect_identical(Encoding(decoded), "UTF-8")
})

test_that("grpc_message_decode() leaves malformed escapes alone", {
  expect_identical(grpc_message_decode("100%"), "100%")
  expect_identical(grpc_message_decode("%zz and %4"), "%zz and %4")
  # Bytes that are not UTF-8 after decoding: keep the text as received.
  expect_identical(grpc_message_decode("%FF%FE"), "%FF%FE")
  expect_identical(grpc_message_decode(NULL), "")
})

test_that("status errors carry the status name, code and classes", {
  cnd <- expect_error(
    status_abort("UNAVAILABLE", "connection reset"),
    class = "zugrpc_error_unavailable"
  )
  expect_s3_class(cnd, c("zugrpc_error_status", "zugrpc_error"))
  expect_identical(cnd$grpc_status, "UNAVAILABLE")
  expect_identical(cnd$grpc_code, 14L)
})

test_that("grpc_message_decode() never raises on what a server sends", {
  # A decoded NUL cannot be an R string: keep the text as received.
  expect_identical(grpc_message_decode("a%00b"), "a%00b")
  # A raw UTF-8 byte after `%`, from a server that does not encode it.
  value <- "50%é done"
  expect_identical(grpc_message_decode(value), value)
  # Lower-case escapes are hex too.
  expect_identical(grpc_message_decode("caf%c3%a9"), "café")
})

test_that("a grpc-message that does not decode keeps the status", {
  m <- mock_channel(grpc_response(
    trailers = c("grpc-status" = "13", "grpc-message" = "a%00b")
  ))
  cnd <- expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_internal"
  )
  expect_identical(cnd$grpc_message, "a%00b")
  expect_identical(cnd$method, "/a.B/C")
})
