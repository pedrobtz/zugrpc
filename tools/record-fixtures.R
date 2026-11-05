# Records the unary responses that tests/testthat/test-call.R replays.
#
# Run from the package root against grpc-go's interop server, built from the
# pinned tag:
#
#   go install google.golang.org/grpc/interop/server@v1.67.1
#   server --port 50051 &
#   Rscript tools/record-fixtures.R localhost:50051
#
# Each fixture is one `dput()` text file in tests/testthat/fixtures/unary/:
# the request zugrpc should send (method and framed body) and the response
# exactly as zuhttp received it (HTTP status, headers, body and trailers).
# The requests are built by hand here, not by zugrpc, so the fixtures check
# zugrpc's encoding rather than repeat it.

library(zuhttp)

args <- commandArgs(trailingOnly = TRUE)
authority <- if (length(args)) args[[1]] else "localhost:50051"
out <- file.path("tests", "testthat", "fixtures", "unary")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

client <- zu_client(http2 = "required", check = FALSE)

# Protobuf encoding of the few grpc.testing messages used, by hand.
varint <- function(x) {
  out <- raw()
  repeat {
    b <- x %% 128
    x <- x %/% 128
    if (x == 0) {
      return(c(out, as.raw(b)))
    }
    out <- c(out, as.raw(b + 128))
  }
}
field_bytes <- function(number, bytes) {
  c(varint(number * 8 + 2), varint(length(bytes)), bytes)
}
field_varint <- function(number, value) c(varint(number * 8), varint(value))

# grpc.testing.SimpleRequest: response_size = 2, response_status = 7
# (EchoStatus: code = 1, message = 2).
simple_request <- function(size = 0, code = NULL, message = NULL) {
  out <- if (size > 0) field_varint(2, size) else raw()
  if (!is.null(code)) {
    status <- field_varint(1, code)
    if (!is.null(message)) {
      status <- c(status, field_bytes(2, charToRaw(enc2utf8(message))))
    }
    out <- c(out, field_bytes(7, status))
  }
  out
}

frame <- function(bytes) {
  n <- length(bytes)
  c(
    as.raw(c(0, n %/% 2^24 %% 256, n %/% 2^16 %% 256, n %/% 2^8 %% 256)),
    as.raw(n %% 256),
    bytes
  )
}

record <- function(name, method, message = raw(), metadata = NULL) {
  body <- frame(message)
  req <- zu_request("POST", paste0("http://", authority, method))
  req <- do.call(
    zu_headers,
    c(list(req, te = "trailers"), as.list(metadata))
  )
  req <- zu_body_raw(req, body, type = "application/grpc+proto")
  res <- zu_perform(req, client = client)
  fixture <- list(
    request = list(method = method, body = body, metadata = metadata),
    response = list(
      status = zu_resp_status(res),
      headers = zu_resp_headers(res),
      body = zu_resp_raw(res),
      trailers = zu_resp_trailers(res)
    )
  )
  path <- file.path(out, paste0(name, ".dput"))
  con <- file(path, "w", encoding = "UTF-8")
  writeLines(
    c(
      sprintf("# Recorded from grpc-go v1.67.1 interop server: %s", method),
      "# Regenerate with tools/record-fixtures.R; do not edit by hand."
    ),
    con
  )
  dput(fixture, con)
  close(con)
  message("wrote ", path)
}

svc <- "/grpc.testing.TestService/"

record("empty", paste0(svc, "EmptyCall"))
record("ok", paste0(svc, "UnaryCall"), simple_request(size = 10))
record(
  "metadata",
  paste0(svc, "UnaryCall"),
  simple_request(size = 1),
  metadata = c(
    "x-grpc-test-echo-initial" = "test_initial_metadata_value",
    "x-grpc-test-echo-trailing-bin" = "q6ur"
  )
)
for (code in 1:16) {
  record(
    sprintf("status-%02d", code),
    paste0(svc, "UnaryCall"),
    simple_request(code = code, message = sprintf("status %d", code))
  )
}
record(
  "special-message",
  paste0(svc, "UnaryCall"),
  simple_request(
    code = 2,
    message = "\t\ntest with whitespace\r\nand Unicode BMP ☺ and non-BMP \U0001f608\t\n"
  )
)
record("unimplemented-method", paste0(svc, "UnimplementedCall"))
record(
  "unimplemented-service",
  "/grpc.testing.UnimplementedService/UnimplementedCall"
)
