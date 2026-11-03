# The gRPC wire format (design §4 item 1, §6.2 to §6.4): pure functions over
# raw vectors and character vectors. No I/O happens here.

default_max_message <- 128 * 1024^2

# One length-prefixed message: a compressed-flag byte (always 0 in v0.1.0),
# a four-byte big-endian length, then the bytes.
frame_encode <- function(message) {
  if (!is.raw(message)) {
    zugrpc_abort("argument", "A request message must be a raw vector.")
  }
  n <- length(message)
  if (n > 4294967295) {
    zugrpc_abort("argument", "A message cannot exceed 4 GiB.")
  }
  prefix <- as.raw(c(
    0,
    (n %/% 16777216) %% 256,
    (n %/% 65536) %% 256,
    (n %/% 256) %% 256,
    n %% 256
  ))
  c(prefix, message)
}

# Splits a buffer into its complete messages and the bytes of an incomplete
# one. Walks offsets rather than re-slicing the remainder, so many small
# messages cost one copy each and nothing quadratic. A declared length above
# `max_message` fails as soon as its prefix is complete, before the body is
# read (§6.3).
frame_split <- function(
  buf,
  max_message = default_max_message,
  encoding = NULL
) {
  n <- length(buf)
  messages <- vector("list", 16L)
  count <- 0L
  pos <- 1L
  while (n - pos + 1L >= 5L) {
    flag <- as.integer(buf[pos])
    len <- sum(
      as.numeric(buf[(pos + 1L):(pos + 4L)]) * c(16777216, 65536, 256, 1)
    )
    check_flag(flag, encoding)
    if (len > max_message) {
      status_abort(
        "RESOURCE_EXHAUSTED",
        sprintf(
          "received message larger than max (%.0f vs. %.0f)",
          len,
          max_message
        )
      )
    }
    if (n - pos + 1L - 5L < len) {
      break
    }
    start <- pos + 5L
    end <- pos + 4L + len
    count <- count + 1L
    if (count > length(messages)) {
      length(messages) <- 2L * length(messages)
    }
    messages[count] <- list(if (len > 0) buf[start:end] else raw())
    pos <- end + 1L
  }
  list(
    messages = messages[seq_len(count)],
    remainder = if (pos <= n) buf[pos:n] else raw()
  )
}

check_flag <- function(flag, encoding) {
  if (flag == 0L) {
    return(invisible())
  }
  if (flag != 1L) {
    zugrpc_abort(
      "protocol",
      sprintf("Invalid compressed-flag byte %d in a gRPC message.", flag)
    )
  }
  if (is.null(encoding) || identical(encoding, "identity")) {
    zugrpc_abort(
      "protocol",
      "A compressed message arrived without a grpc-encoding."
    )
  }
  status_abort(
    "UNIMPLEMENTED",
    sprintf("grpc-encoding '%s' is not supported", encoding)
  )
}

# The request headers of §6.2, in wire order, then the caller's metadata
# (already encoded by metadata_encode()).
request_headers <- function(
  metadata = NULL,
  timeout = NULL,
  user_agent
) {
  h <- c(
    te = "trailers",
    "content-type" = "application/grpc+proto",
    "user-agent" = user_agent
  )
  if (!is.null(timeout)) {
    h <- c(h, "grpc-timeout" = timeout)
  }
  h <- c(h, "grpc-accept-encoding" = "identity")
  c(h, metadata)
}

check_method <- function(method) {
  ok <- is.character(method) &&
    length(method) == 1L &&
    !is.na(method) &&
    grepl("^/[^/]+/[^/]+$", method)
  if (!ok) {
    zugrpc_abort(
      "argument",
      "A method must be one string of the form \"/package.Service/Method\"."
    )
  }
  method
}
