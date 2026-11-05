# gRPC status codes (design §6.5), from grpc/grpc doc/statuscodes.md.

status_table <- data.frame(
  code = 0:16,
  name = c(
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
  ),
  description = c(
    "Not an error; returned on success.",
    "The operation was cancelled, typically by the caller.",
    "Unknown error.",
    "The client specified an invalid argument.",
    "The deadline expired before the operation could complete.",
    "Some requested entity was not found.",
    "The entity that a client attempted to create already exists.",
    "The caller does not have permission to execute the operation.",
    "Some resource has been exhausted.",
    "The system is not in a state required for the operation.",
    "The operation was aborted.",
    "The operation was attempted past the valid range.",
    "The operation is not implemented or not supported.",
    "Internal error.",
    "The service is currently unavailable.",
    "Unrecoverable data loss or corruption.",
    "The request does not have valid authentication credentials."
  ),
  stringsAsFactors = FALSE
)

#' gRPC status codes
#'
#' The 17 status codes a gRPC call can end with, as the gRPC specification
#' defines them. A failed call raises a condition of class
#' `zugrpc_error_<name>` in lower case, for example `zugrpc_error_unavailable`.
#'
#' @return A data frame with one row per code and columns `code` (integer),
#'   `name` and `description` (character).
#' @export
#' @examples
#' grpc_status_codes()
grpc_status_codes <- function() {
  status_table
}

status_code <- function(name) {
  status_table$code[match(name, status_table$name)]
}

# `grpc-status` as received. Missing or malformed is INTERNAL; an integer
# outside the table is UNKNOWN, as the specification says.
status_from_header <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[1L])) {
    return(list(
      name = "INTERNAL",
      code = 13L,
      message = "missing grpc-status in trailers"
    ))
  }
  value <- value[1L]
  if (!grepl("^[0-9]{1,9}$", value)) {
    return(list(
      name = "INTERNAL",
      code = 13L,
      message = sprintf("malformed grpc-status '%s'", value)
    ))
  }
  code <- as.integer(value)
  i <- match(code, status_table$code)
  if (is.na(i)) {
    return(list(name = "UNKNOWN", code = 2L, message = ""))
  }
  list(name = status_table$name[i], code = code, message = "")
}

# The status for an HTTP response with no grpc-status.
status_from_http <- function(http_status) {
  switch(
    as.character(http_status),
    "400" = "INTERNAL",
    "401" = "UNAUTHENTICATED",
    "403" = "PERMISSION_DENIED",
    "404" = "UNIMPLEMENTED",
    "429" = ,
    "502" = ,
    "503" = ,
    "504" = "UNAVAILABLE",
    "UNKNOWN"
  )
}

# `grpc-message` is percent-encoded UTF-8. Malformed escapes stay as they
# are, and a result that is a NUL or not valid UTF-8 falls back to the text
# as received, so a decoding problem never hides the status (§6.5).
grpc_message_decode <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[1L])) {
    return("")
  }
  value <- value[1L]
  if (!grepl("%", value, fixed = TRUE, useBytes = TRUE)) {
    return(value)
  }
  tryCatch(percent_decode(value), error = function(e) value)
}

hex_digits <- as.raw(c(0x30:0x39, 0x41:0x46, 0x61:0x66))

percent_decode <- function(value) {
  bytes <- charToRaw(value)
  out <- raw(length(bytes))
  is_hex <- function(b) b %in% hex_digits
  n <- length(bytes)
  i <- 1L
  j <- 0L
  while (i <= n) {
    b <- bytes[i]
    if (
      b == as.raw(0x25) &&
        i + 2L <= n &&
        is_hex(bytes[i + 1L]) &&
        is_hex(bytes[i + 2L])
    ) {
      j <- j + 1L
      out[j] <- as.raw(strtoi(rawToChar(bytes[(i + 1L):(i + 2L)]), 16L))
      i <- i + 3L
    } else {
      j <- j + 1L
      out[j] <- b
      i <- i + 1L
    }
  }
  out <- out[seq_len(j)]
  if (any(out == as.raw(0))) {
    return(value)
  }
  decoded <- rawToChar(out)
  if (!validUTF8(decoded)) {
    return(value)
  }
  Encoding(decoded) <- "UTF-8"
  decoded
}
