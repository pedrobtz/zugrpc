# Status details from tools/status-server ---------------------------------

test_that("a Spark-style Status yields ErrorInfo in the condition's details", {
  fx <- read_fixture("spark", dir = "details")
  m <- replay_channel(fx)
  cnd <- expect_error(
    grpc_call(m$channel, fx$request$method, raw()),
    class = "zugrpc_error_internal"
  )
  expect_s3_class(cnd, "zugrpc_error_status")
  expect_identical(cnd$details$code, 13L)
  expect_identical(cnd$details$message, cnd$grpc_message)
  expect_named(cnd$details$details, "ErrorInfo")

  info <- cnd$details$details$ErrorInfo
  expect_identical(
    info$reason,
    "org.apache.spark.sql.catalyst.ExtendedAnalysisException"
  )
  expect_identical(info$domain, "org.apache.spark")
  expect_identical(info$metadata[["sqlState"]], "42P01")
  expect_identical(info$metadata[["errorClass"]], "TABLE_OR_VIEW_NOT_FOUND")
  expect_setequal(
    names(info$metadata),
    c("classes", "sqlState", "errorClass", "messageParameters", "errorId")
  )
})

test_that("each error_details.proto type is unpacked, and others are kept", {
  fx <- read_fixture("every", dir = "details")
  m <- replay_channel(fx)
  cnd <- expect_error(
    grpc_call(m$channel, fx$request$method, raw()),
    class = "zugrpc_error_unavailable"
  )
  d <- cnd$details$details
  expect_named(
    d,
    c(
      "RetryInfo",
      "DebugInfo",
      "QuotaFailure",
      "PreconditionFailure",
      "BadRequest",
      "RequestInfo",
      "ResourceInfo",
      "Help",
      "LocalizedMessage",
      "google.protobuf.Duration"
    )
  )
  expect_equal(as.numeric(d$RetryInfo$retry_delay), 1.5)
  expect_identical(d$DebugInfo$stack_entries, c("a", "b"))
  expect_identical(d$QuotaFailure$violations[[1]]$subject, "s")
  expect_identical(d$PreconditionFailure$violations[[1]]$type, "TOS")
  expect_identical(d$BadRequest$field_violations[[1]]$field, "f")
  expect_identical(d$RequestInfo$request_id, "r1")
  expect_identical(d$ResourceInfo$resource_type, "table")
  expect_identical(d$Help$links[[1]]$url, "https://example.org")
  expect_identical(d$LocalizedMessage$locale, "en-GB")
  # Not an error_details.proto type, so left packed.
  other <- d[["google.protobuf.Duration"]]
  expect_identical(
    other$type_url,
    "type.googleapis.com/google.protobuf.Duration"
  )
  expect_type(other$value, "raw")
})

test_that("a status without a details trailer has NULL details", {
  fx <- read_fixture("status-05")
  m <- replay_channel(fx)
  cnd <- expect_error(
    grpc_call(m$channel, fx$request$method, raw()),
    class = "zugrpc_error_not_found"
  )
  expect_null(cnd$details)
  expect_true("details" %in% names(cnd))
})

# Hostile details (design §9, §10) ----------------------------------------

test_that("a details trailer that is not base64 warns and keeps the status", {
  m <- mock_channel(grpc_response(
    trailers = c(
      "grpc-status" = "3",
      "grpc-message" = "bad",
      "grpc-status-details-bin" = "%%%not base64"
    )
  ))
  cnd <- NULL
  expect_warning(
    cnd <- tryCatch(
      grpc_call(m$channel, "/a.B/C", raw()),
      zugrpc_error = identity
    ),
    class = "zugrpc_warning_details"
  )
  expect_s3_class(cnd, "zugrpc_error_invalid_argument")
  expect_identical(cnd$grpc_message, "bad")
  expect_null(cnd$details)
})

test_that("a details trailer that is not a Status warns and keeps the status", {
  # A length-delimited field 3 that declares 5 bytes and carries 1.
  not_status <- base64_encode(as.raw(c(0x1a, 0x05, 0x01)))
  m <- mock_channel(grpc_response(
    trailers = c("grpc-status" = "9", "grpc-status-details-bin" = not_status)
  ))
  cnd <- NULL
  expect_warning(
    cnd <- tryCatch(
      grpc_call(m$channel, "/a.B/C", raw()),
      zugrpc_error = identity
    ),
    class = "zugrpc_warning_details"
  )
  expect_s3_class(cnd, "zugrpc_error_failed_precondition")
  expect_null(cnd$details)
})

test_that("the bundled descriptor set matches its recorded SHA-256", {
  skip_if_not(exists("sha256sum", envir = asNamespace("tools")))
  dir <- system.file("descriptors", package = "zugrpc")
  recorded <- strsplit(
    readLines(file.path(dir, "google-rpc.binpb.sha256")),
    " "
  )
  sha256sum <- get("sha256sum", envir = asNamespace("tools"))
  actual <- unname(sha256sum(file.path(dir, "google-rpc.binpb")))
  expect_identical(actual, recorded[[1]][1])
})

# Conditions from below gRPC (design §9) -----------------------------------

test_that("a zuhttp failure is a transport error that is also UNAVAILABLE", {
  m <- failing_channel("zu_connect_error")
  cnd <- expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_transport"
  )
  expect_s3_class(cnd, "zugrpc_error_unavailable")
  expect_s3_class(cnd, "zugrpc_error")
  expect_false(inherits(cnd, "zugrpc_error_status"))
  expect_identical(cnd$grpc_status, "UNAVAILABLE")
  expect_identical(cnd$grpc_code, 14L)
  expect_identical(cnd$method, "/a.B/C")
  expect_s3_class(cnd$parent, "zu_connect_error")

  m <- failing_channel("zu_tls_handshake_error")
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_transport"
  )
})

test_that("an interrupt in zuhttp raises zugrpc_error_interrupt", {
  m <- failing_channel("zu_interrupted_error")
  cnd <- expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_interrupt"
  )
  expect_s3_class(cnd, "zugrpc_error")
  expect_identical(cnd$grpc_status, "CANCELLED")
  expect_s3_class(cnd$parent, "zu_interrupted_error")
})

test_that("zuhttp's timeout, cancel and body limit map to their statuses", {
  cases <- c(
    zu_timeout_error = "zugrpc_error_deadline_exceeded",
    zu_cancelled_error = "zugrpc_error_cancelled",
    zu_body_limit_error = "zugrpc_error_resource_exhausted"
  )
  for (from in names(cases)) {
    m <- failing_channel(from)
    cnd <- expect_error(
      grpc_call(m$channel, "/a.B/C", raw()),
      class = cases[[from]]
    )
    expect_s3_class(cnd, "zugrpc_error_status")
    expect_s3_class(cnd$parent, from)
  }
})

test_that("every class of the design's condition table is raised", {
  # zugrpc_error_status, _transport and _interrupt are raised above;
  # _protocol and _argument here.
  m <- mock_channel(grpc_response(
    body = raw(),
    trailers = c("grpc-status" = "0")
  ))
  expect_error(
    grpc_call(m$channel, "/a.B/C", raw()),
    class = "zugrpc_error_protocol"
  )
  expect_error(grpc_channel("nope"), class = "zugrpc_error_argument")
})

test_that("a Status with no details decodes to an empty list", {
  # google.rpc.Status: code = 1 (5), message = 2 ("x"); no field 3.
  status <- as.raw(c(0x08, 0x05, 0x12, 0x01, 0x78))
  got <- status_details_decode(base64_encode(status))
  expect_identical(got$code, 5L)
  expect_identical(got$message, "x")
  expect_identical(got$details, list())
})

test_that("a details warning is also a zugrpc_warning", {
  expect_warning(status_details_decode("!!"), class = "zugrpc_warning")
})
