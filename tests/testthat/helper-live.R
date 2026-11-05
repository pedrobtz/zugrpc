# Live tests run only where CI (.github/workflows/live.yaml) or a developer
# has started the servers and set these variables:
#
#   ZU_GRPC_TEST_SERVER  grpc-go's interop server over h2c
#   ZU_GRPC_TEST_TLS     the same server over TLS, as https://localhost:<port>
#   ZU_GRPC_TEST_CA      the CA that signed its certificate
#   ZU_GRPC_TEST_STATUS  tools/test-server's gRPC port (h2c)
#   ZU_GRPC_TEST_H1_TLS  tools/test-server's TLS port that offers http/1.1 only
#   ZU_H2_TEST_SERVER    a plain HTTP/2 server (h2c) that is not gRPC
#   ZU_SPARK_TEST_SERVER a Spark Connect server (h2c), in test-spark.R
live_server <- function(var) {
  skip_on_cran()
  value <- Sys.getenv(var)
  skip_if(!nzchar(value), paste(var, "is not set"))
  value
}

# Trust for the local TLS servers. Where the backend cannot take a private CA
# (Schannel, zuhttp#5), verification is off: the tests are of ALPN h2, and
# certificate checking is zuhttp's to test.
live_tls_client <- function() {
  ca <- Sys.getenv("ZU_GRPC_TEST_CA")
  if (nzchar(ca) && "ca_file" %in% zuhttp::zu_info()$tls_capabilities) {
    zuhttp::zu_client(tls = zuhttp::zu_tls(ca_file = ca))
  } else {
    zuhttp::zu_client(verify = FALSE)
  }
}

# grpc.testing messages, encoded by hand (protobuf varint and length-
# delimited fields only).
pb_varint <- function(x) {
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
pb_bytes <- function(number, bytes) {
  c(pb_varint(number * 8 + 2), pb_varint(length(bytes)), bytes)
}
pb_int <- function(number, value) c(pb_varint(number * 8), pb_varint(value))

echo_status <- function(code, message = "") {
  pb_bytes(7, c(pb_int(1, code), pb_bytes(2, charToRaw(enc2utf8(message)))))
}

# SimpleRequest: response_size = 2, response_status = 7.
simple_request <- function(size = 0, code = NULL, message = "") {
  c(
    if (size > 0) pb_int(2, size),
    if (!is.null(code)) echo_status(code, message)
  )
}

# StreamingOutputCallRequest: response_parameters = 2 (size = 1,
# interval_us = 2), response_status = 7.
streaming_request <- function(sizes, interval_us = 0, code = NULL) {
  params <- lapply(sizes, function(n) {
    pb_bytes(2, c(pb_int(1, n), if (interval_us > 0) pb_int(2, interval_us)))
  })
  c(do.call(c, params), if (!is.null(code)) echo_status(code, "stream end"))
}

# The payload length of a SimpleResponse or StreamingOutputCallResponse,
# field 1 (Payload), whose body is field 2. Payloads here are under 128
# bytes or a whole multiple, so reading the varints is enough.
payload_size <- function(msg) {
  if (length(msg) == 0L) {
    return(0)
  }
  read_varint <- function(pos) {
    v <- 0
    k <- 0
    repeat {
      b <- as.integer(msg[pos])
      v <- v + (b %% 128) * 128^k
      pos <- pos + 1L
      k <- k + 1L
      if (b < 128) {
        return(c(v, pos))
      }
    }
  }
  outer <- read_varint(2L)
  if (outer[1] == 0) {
    return(0)
  }
  inner <- read_varint(outer[2] + 1L)
  inner[1]
}
