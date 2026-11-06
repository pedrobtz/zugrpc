# Records the unary and server-streaming responses that the tests replay.
#
# Run from the package root against grpc-go's interop server, built from the
# pinned tag, and the status-details server in tools/test-server, which
# uses the same grpc-go version:
#
#   go install google.golang.org/grpc/interop/server@v1.67.1
#   server --port 50051 &
#   (cd tools && go run ./test-server -grpc_port 50052) &
#   Rscript tools/record-fixtures.R localhost:50051 localhost:50052
#
# Each fixture is one `dput()` text file in tests/testthat/fixtures/unary/
# or tests/testthat/fixtures/stream/ (interop server), or
# tests/testthat/fixtures/details/ (status server):
# the request zugrpc should send (method and framed body) and the response
# exactly as zuhttp received it (HTTP status, headers, body and trailers).
# Streams are gzipped (`.dput.gz`), since their payloads are mostly zero
# bytes; R's file() reads them back unchanged.
# The requests are built by hand here, not by zugrpc, so the fixtures check
# zugrpc's encoding rather than repeat it.

library(zuhttp)

args <- commandArgs(trailingOnly = TRUE)
interop <- if (length(args) >= 1L) args[[1]] else "localhost:50051"
details <- if (length(args) >= 2L) args[[2]] else "localhost:50052"
fixtures <- file.path("tests", "testthat", "fixtures")

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

# grpc.testing.StreamingOutputCallRequest: response_parameters = 2
# (ResponseParameters: size = 1), response_status = 7.
streaming_request <- function(sizes, code = NULL, message = NULL) {
  params <- lapply(sizes, function(n) field_bytes(2, field_varint(1, n)))
  out <- do.call(c, c(list(raw()), params))
  if (!is.null(code)) {
    status <- c(
      field_varint(1, code),
      field_bytes(2, charToRaw(enc2utf8(message)))
    )
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

record <- function(
  name,
  method,
  message = raw(),
  metadata = NULL,
  authority = interop,
  dir = "unary",
  server = "grpc-go v1.67.1 interop server"
) {
  gz <- dir == "stream"
  out <- file.path(fixtures, dir)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
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
  path <- file.path(out, paste0(name, if (gz) ".dput.gz" else ".dput"))
  con <- if (gz) {
    gzfile(path, "w", encoding = "UTF-8")
  } else {
    file(path, "w", encoding = "UTF-8")
  }
  writeLines(
    c(
      sprintf("# Recorded from %s: %s", server, method),
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

# Server streaming. The body is recorded whole; the tests replay it through
# zuhttp's pulled reads. The sizes are those of grpc's server_streaming
# interop case, then one message larger than a 64 KiB read.
record(
  "sizes",
  paste0(svc, "StreamingOutputCall"),
  streaming_request(c(31415, 9, 2653, 58979)),
  dir = "stream"
)
record(
  "large",
  paste0(svc, "StreamingOutputCall"),
  streaming_request(c(70000, 1)),
  dir = "stream"
)
record(
  "empty",
  paste0(svc, "StreamingOutputCall"),
  streaming_request(integer()),
  dir = "stream"
)
# The interop server honours response_status on FullDuplexCall only.
record(
  "status-09",
  paste0(svc, "FullDuplexCall"),
  streaming_request(c(5, 5), code = 9, message = "stream end"),
  dir = "stream"
)

record(
  "fail",
  "/zugrpc.test.Status/StreamFail",
  authority = details,
  dir = "stream",
  server = "tools/test-server (grpc-go v1.67.1)"
)

for (name in c("Spark", "Every")) {
  record(
    tolower(name),
    paste0("/zugrpc.test.Status/", name),
    authority = details,
    dir = "details",
    server = "tools/test-server (grpc-go v1.67.1)"
  )
}
