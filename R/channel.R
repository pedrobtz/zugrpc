# Channels (design §4, §6.1). A channel is an environment so that
# grpc_close() can mark it closed for every copy a caller holds.

#' Open a gRPC channel
#'
#' A channel holds what every call to one server shares: the server's
#' address, the headers sent on every call, the message size limit, and the
#' `zuhttp` client whose connection pool carries the calls. An `http://` URL
#' speaks cleartext HTTP/2 with prior knowledge (h2c), for a local server.
#' An `https://` URL negotiates HTTP/2 over TLS. gRPC has no HTTP/1.1
#' fallback, so the channel's client always requires HTTP/2.
#'
#' @param url The server, as `http://host:port` or `https://host:port`. No
#'   path, query or user information.
#' @param headers Metadata sent on every call: a named character vector or a
#'   named list, as `metadata` in [grpc_call()]. A call's own metadata
#'   replaces a channel header of the same name.
#' @param tls Certificate trust settings from [zuhttp::zu_tls()], for an
#'   `https://` URL.
#' @param max_message The largest response message accepted, in bytes. The
#'   default, 128 MiB, is Spark Connect's. A larger message fails the call
#'   with `RESOURCE_EXHAUSTED`.
#' @param client A [zuhttp::zu_client()] to build on, so that proxies, TLS
#'   pins, middleware and test transports come from `zuhttp` unchanged. The
#'   channel derives its own client from it, with HTTP/2 required. `NULL`
#'   builds a fresh one.
#'
#' @return A `zugrpc_channel`.
#' @seealso [grpc_call()] to make a call, [grpc_close()] to close it.
#' @export
#' @examples
#' ch <- grpc_channel("http://localhost:50051")
#' ch
#' grpc_close(ch)
grpc_channel <- function(
  url,
  headers = NULL,
  tls = NULL,
  max_message = 128 * 1024^2,
  client = NULL
) {
  target <- parse_target(url)
  if (!is.null(tls) && !target$tls) {
    zugrpc_abort("argument", "`tls` applies only to an https:// URL.")
  }
  ok <- is.numeric(max_message) &&
    length(max_message) == 1L &&
    !is.na(max_message) &&
    max_message >= 0 &&
    max_message <= 4294967295
  if (!ok) {
    zugrpc_abort(
      "argument",
      "`max_message` must be one number of bytes between 0 and 4 GiB."
    )
  }
  if (!is.null(client) && !inherits(client, "zu_client")) {
    zugrpc_abort("argument", "`client` must be a zuhttp::zu_client().")
  }

  settings <- list(
    http2 = "required",
    check = FALSE,
    # A unary body is one message and its prefix; the default is 16 MiB.
    max_body = max_message + 5,
    user_agent = user_agent()
  )
  if (!is.null(tls)) {
    settings$tls <- tls
  }
  client <- if (is.null(client)) {
    do.call(zuhttp::zu_client, settings)
  } else {
    do.call(zuhttp::zu_client_update, c(list(client), settings))
  }

  ch <- new.env(parent = emptyenv())
  ch$origin <- target$origin
  ch$authority <- target$authority
  ch$tls <- target$tls
  ch$headers <- metadata_encode(headers)
  ch$max_message <- max_message
  ch$client <- client
  # Streams bound max_message per message, not the whole body (§6.3).
  ch$stream_client <- zuhttp::zu_client_update(client, max_body = Inf)
  ch$streams <- new.env(parent = emptyenv())
  ch$next_id <- 0
  ch$closed <- FALSE
  class(ch) <- "zugrpc_channel"
  ch
}

#' Close a gRPC channel
#'
#' Cancels the channel's open streams and closes its idle connections. A call
#' on a closed channel raises `zugrpc_error_argument`, and a cancelled stream
#' raises `zugrpc_error_cancelled` when it is next read. Closing a channel
#' twice does nothing.
#'
#' @param channel A channel from [grpc_channel()].
#'
#' @return `channel`, invisibly.
#' @export
#' @examples
#' ch <- grpc_channel("http://localhost:50051")
#' grpc_close(ch)
grpc_close <- function(channel) {
  check_channel(channel, open = FALSE)
  if (!channel$closed) {
    channel$closed <- TRUE
    for (id in ls(channel$streams)) {
      try(zuhttp::zu_resp_abort(channel$streams[[id]]), silent = TRUE)
    }
    rm(list = ls(channel$streams), envir = channel$streams)
    zuhttp::zu_pool_reset(channel$client)
  }
  invisible(channel)
}

#' @export
print.zugrpc_channel <- function(x, ...) {
  transport <- if (x$tls) "TLS, ALPN h2" else "cleartext HTTP/2 (h2c)"
  state <- if (x$closed) "closed" else "open"
  cat(sprintf("<zugrpc_channel> %s\n", x$authority))
  cat(sprintf("  transport: %s\n", transport))
  cat(sprintf("  state:     %s\n", state))
  cat(sprintf("  streams:   %d open\n", length(ls(x$streams))))
  invisible(x)
}

parse_target <- function(url) {
  ok <- is.character(url) && length(url) == 1L && !is.na(url)
  m <- if (ok) {
    regmatches(
      url,
      regexec("^(https?)://([^/?#@]+)/?$", url, ignore.case = TRUE)
    )[[1L]]
  } else {
    character()
  }
  if (length(m) != 3L) {
    zugrpc_abort(
      "argument",
      "A channel URL must be one string of the form http://host:port or https://host:port."
    )
  }
  scheme <- tolower(m[2L])
  list(
    origin = paste0(scheme, "://", m[3L]),
    authority = m[3L],
    tls = scheme == "https"
  )
}

check_channel <- function(channel, open = TRUE) {
  if (!inherits(channel, "zugrpc_channel")) {
    zugrpc_abort("argument", "`channel` must come from grpc_channel().")
  }
  if (open && channel$closed) {
    zugrpc_abort("argument", "The channel is closed.")
  }
  invisible(channel)
}

user_agent <- function() {
  sprintf(
    "zugrpc/%s zuhttp/%s",
    utils::packageVersion("zugrpc"),
    utils::packageVersion("zuhttp")
  )
}
