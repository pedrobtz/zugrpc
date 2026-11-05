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
#' @param keepalive HTTP/2 keepalive from [grpc_keepalive()], or `NULL` for
#'   none. The default sends a PING on a connection idle for 60 seconds and
#'   replaces it if no answer comes within 20, as Spark Connect's Python
#'   client does.
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
  keepalive = grpc_keepalive(),
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
  if (!is.null(keepalive) && !inherits(keepalive, "zugrpc_keepalive")) {
    zugrpc_abort("argument", "`keepalive` must come from grpc_keepalive().")
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
  client <- with_keepalive(client, keepalive)

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

# Built once per session: packageVersion() takes about a millisecond, which
# is more than the rest of a unary call's own work (design §11).
user_agent <- function() {
  if (is.null(rpc_env$user_agent)) {
    rpc_env$user_agent <- sprintf(
      "zugrpc/%s zuhttp/%s",
      utils::packageVersion("zugrpc"),
      utils::packageVersion("zuhttp")
    )
  }
  rpc_env$user_agent
}

#' HTTP/2 keepalive settings
#'
#' A channel's connection can sit idle between calls, and a server or a
#' middlebox may drop it without saying so. With keepalive, a connection
#' idle for `time` seconds is sent an HTTP/2 PING before its next call, and
#' replaced by a new one if no answer comes within `timeout` seconds.
#'
#' @param time Seconds of idleness before a PING.
#' @param timeout Seconds to wait for the answer.
#'
#' @return A `zugrpc_keepalive`, for [grpc_channel()].
#' @export
#' @examples
#' grpc_keepalive()
#' grpc_keepalive(time = 30, timeout = 10)
grpc_keepalive <- function(time = 60, timeout = 20) {
  for (arg in list(list("time", time), list("timeout", timeout))) {
    v <- arg[[2L]]
    if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v <= 0) {
      zugrpc_abort(
        "argument",
        sprintf("`%s` must be one positive number of seconds.", arg[[1L]])
      )
    }
  }
  structure(
    list(time = as.numeric(time), timeout = as.numeric(timeout)),
    class = "zugrpc_keepalive"
  )
}

#' @export
print.zugrpc_keepalive <- function(x, ...) {
  cat(sprintf(
    "<zugrpc_keepalive> PING after %gs idle, answer within %gs\n",
    x$time,
    x$timeout
  ))
  invisible(x)
}

# Keepalive is a setting of zuhttp's pool (its §65.6). The client's other
# pool settings are kept; a client with no pool has no idle connection to
# keep alive.
with_keepalive <- function(client, keepalive) {
  pool <- client$pool
  if (is.null(pool)) {
    return(client)
  }
  zuhttp::zu_client_update(
    client,
    pool = zuhttp::zu_pool(
      max_idle = pool$max_idle,
      max_per_host = pool$max_per_host,
      idle_timeout = pool$idle_timeout_ms / 1000,
      keepalive_time = keepalive$time,
      keepalive_timeout = keepalive$timeout
    )
  )
}
