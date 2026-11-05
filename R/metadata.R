# gRPC metadata (design §6.4). A caller passes a named list or a named
# character vector; a name ending in `-bin` carries a raw vector, which goes
# on the wire as unpadded base64.

metadata_encode <- function(metadata) {
  if (is.null(metadata) || length(metadata) == 0L) {
    return(stats::setNames(character(), character()))
  }
  nms <- names(metadata)
  if (is.null(nms) || anyNA(nms) || any(!nzchar(nms))) {
    zugrpc_abort("argument", "Every metadata entry must be named.")
  }
  nms <- tolower(nms)
  bad <- !grepl("^[0-9a-z_.-]+$", nms) & !startsWith(nms, ":")
  if (any(bad)) {
    zugrpc_abort(
      "argument",
      sprintf("Invalid metadata name '%s'.", nms[bad][1L])
    )
  }
  reserved <- is_reserved_name(nms)
  if (any(reserved)) {
    zugrpc_abort(
      "argument",
      sprintf("Metadata name '%s' is reserved for zugrpc.", nms[reserved][1L])
    )
  }
  values <- vapply(
    seq_along(nms),
    function(i) metadata_value(nms[i], metadata[[i]]),
    character(1)
  )
  stats::setNames(values, nms)
}

# Names that belong to the protocol, not to metadata (§6.2, §6.4): HTTP/2
# pseudo-headers, the grpc- prefix, te and content-type, and the
# connection-specific headers HTTP/2 forbids (RFC 9113 §8.2.2), with host,
# which :authority replaces. The same rule filters received metadata.
reserved_names <- c(
  "te",
  "content-type",
  "connection",
  "keep-alive",
  "proxy-connection",
  "transfer-encoding",
  "upgrade",
  "host"
)

is_reserved_name <- function(nms) {
  startsWith(nms, ":") | startsWith(nms, "grpc-") | nms %in% reserved_names
}

metadata_value <- function(name, value) {
  if (endsWith(name, "-bin")) {
    if (!is.raw(value)) {
      zugrpc_abort(
        "argument",
        sprintf("Metadata '%s' ends in -bin, so its value must be raw.", name)
      )
    }
    return(base64_encode(value))
  }
  ok <- is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    grepl("^[ -~]*$", value)
  if (!ok) {
    zugrpc_abort(
      "argument",
      sprintf(
        "Metadata '%s' must be one string of printable ASCII; use a -bin name for bytes.",
        name
      )
    )
  }
  value
}

# Received metadata, as a named character vector from the wire, into a named
# list: `-bin` values become raw vectors, others stay strings. A `-bin` value
# may join several with commas; each becomes an entry of the same name, as a
# repeated header does. One that is not base64 is dropped with a warning:
# metadata never decides the outcome of a call (§9).
metadata_decode <- function(headers) {
  nms <- names(headers)
  bin <- endsWith(nms, "-bin")
  if (!any(bin)) {
    return(as.list(headers))
  }
  out <- lapply(seq_along(headers), function(i) {
    if (bin[i]) bin_values(nms[i], headers[[i]]) else list(headers[[i]])
  })
  times <- lengths(out)
  stats::setNames(unlist(out, recursive = FALSE), rep(nms, times))
}

bin_values <- function(name, value) {
  pieces <- if (nzchar(value)) strsplit(value, ",", fixed = TRUE)[[1L]] else ""
  tryCatch(
    lapply(trimws(pieces), base64_decode),
    zugrpc_error_protocol = function(e) {
      metadata_warning(name, value)
      list()
    }
  )
}

# Channel headers go on every call; call metadata replaces a channel header
# of the same name.
metadata_merge <- function(channel, call) {
  c(channel[!names(channel) %in% names(call)], call)
}

# Base64 (RFC 4648 §4) in base R (D9). Encoding writes no padding; decoding
# accepts padded or unpadded input, as the gRPC specification requires.
b64_alphabet <- c(LETTERS, letters, 0:9, "+", "/")

base64_encode <- function(x) {
  n <- length(x)
  if (n == 0L) {
    return("")
  }
  b <- as.integer(x)
  pad <- (3L - n %% 3L) %% 3L
  b <- c(b, integer(pad))
  i <- seq.int(1L, length(b), by = 3L)
  v <- b[i] * 65536L + b[i + 1L] * 256L + b[i + 2L]
  idx <- rbind(
    bitwShiftR(v, 18L),
    bitwAnd(bitwShiftR(v, 12L), 63L),
    bitwAnd(bitwShiftR(v, 6L), 63L),
    bitwAnd(v, 63L)
  )
  chars <- b64_alphabet[as.vector(idx) + 1L]
  paste(chars[seq_len(length(chars) - pad)], collapse = "")
}

base64_decode <- function(s) {
  if (!is.character(s) || length(s) != 1L || is.na(s)) {
    zugrpc_abort("protocol", "Base64 input must be one string.")
  }
  s <- sub("={1,2}$", "", s)
  chars <- strsplit(s, "", fixed = TRUE)[[1L]]
  v <- match(chars, b64_alphabet) - 1L
  if (anyNA(v) || length(v) %% 4L == 1L) {
    zugrpc_abort("protocol", "Invalid base64 in gRPC metadata.")
  }
  if (length(v) == 0L) {
    return(raw())
  }
  rem <- length(v) %% 4L
  pad <- (4L - rem) %% 4L
  v <- c(v, integer(pad))
  i <- seq.int(1L, length(v), by = 4L)
  w <- bitwShiftL(v[i], 18L) +
    bitwShiftL(v[i + 1L], 12L) +
    bitwShiftL(v[i + 2L], 6L) +
    v[i + 3L]
  bytes <- rbind(
    bitwShiftR(w, 16L),
    bitwAnd(bitwShiftR(w, 8L), 255L),
    bitwAnd(w, 255L)
  )
  out <- as.raw(as.vector(bytes))
  drop <- pad
  out[seq_len(length(out) - drop)]
}
