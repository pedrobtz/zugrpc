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
#' @param url The server, as `http://host:port` or `https://host:port`. The
#'   host is a name, an IPv4 address or a bracketed IPv6 address, and the
#'   port is from 1 to 65535. No path, query or user information.
#' @param headers Metadata sent on every call: a named character vector or a
#'   named list, as `metadata` in [grpc_call()], with the same reserved
#'   names. A call's own metadata replaces a channel header of the same
#'   name.
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
#'   channel derives its own client from it, with HTTP/2 required, no HTTP
#'   content coding and no query. Its headers may not use a name reserved
#'   for metadata (see `metadata` in [grpc_call()]). `NULL` builds a fresh
#'   one.
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
  # The same 128 MiB as default_max_message, written out for the usage.
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
  if (!is.null(client)) {
    # The client's own headers go on every request, so they keep the rules
    # metadata keeps (§6.4, #83).
    client_names <- tolower(names(client$headers))
    reserved <- is_reserved_name(client_names)
    if (any(reserved)) {
      zugrpc_abort(
        "argument",
        sprintf(
          "`client` sets header '%s', which is reserved for zugrpc.",
          client_names[reserved][1L]
        )
      )
    }
  }
  if (!is.null(keepalive) && !inherits(keepalive, "zugrpc_keepalive")) {
    zugrpc_abort("argument", "`keepalive` must come from grpc_keepalive().")
  }

  settings <- list(
    http2 = "required",
    check = FALSE,
    # gRPC uses no HTTP content coding: ask for none and decode none (#83).
    decode = FALSE,
    # A query would change the method's path, which check_method() guards.
    query = NULL,
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
  client <- own_pool(with_keepalive(client, keepalive))

  ch <- new.env(parent = emptyenv())
  ch$origin <- target$origin
  ch$authority <- target$authority
  ch$tls <- target$tls
  ch$headers <- metadata_encode(headers)
  ch$max_message <- max_message
  ch$client <- client
  # Streams bound max_message per message, not the whole body (§6.3). The
  # update keeps the pool, so both clients share the channel's connections
  # and grpc_close() releases them all.
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
      abort_response(channel$streams[[id]])
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

#' HTTP/2 keepalive settings
#'
#' A channel's connection can sit idle between calls, and a server or a
#' middlebox may drop it without saying so. With keepalive, a connection
#' idle for `time` seconds is sent an HTTP/2 PING before its next call, and
#' replaced by a new one if no answer comes within `timeout` seconds.
#'
#' @param time Seconds of idleness before a PING, from 0.001 (1 ms) to
#'   2147483.647 (about 24.8 days).
#' @param timeout Seconds to wait for the answer, in the same range.
#'
#' @return A `zugrpc_keepalive`, for [grpc_channel()].
#' @export
#' @examples
#' grpc_keepalive()
#' grpc_keepalive(time = 30, timeout = 10)
grpc_keepalive <- function(time = 60, timeout = 20) {
  check_keepalive_seconds(time, "time")
  check_keepalive_seconds(timeout, "timeout")
  structure(
    list(time = as.numeric(time), timeout = as.numeric(timeout)),
    class = "zugrpc_keepalive"
  )
}

#' @export
print.zugrpc_keepalive <- function(x, ...) {
  cat(sprintf(
    "<zugrpc_keepalive> PING after %ss idle, answer within %ss\n",
    format_seconds(x$time),
    format_seconds(x$timeout)
  ))
  invisible(x)
}

# A channel's connections are its own, so grpc_close() cannot clear those of
# the caller's client or of another channel built on it (§6.1, D8). zuhttp
# gives a client a fresh pool whenever its pool setting changes, and the
# setting is changed twice to get one when it would stay the same.
own_pool <- function(client) {
  pool <- client$pool
  if (is.null(pool)) {
    return(client)
  }
  client <- zuhttp::zu_client_update(client, pool = NULL)
  zuhttp::zu_client_update(client, pool = pool)
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

parse_target <- function(url) {
  ok <- is.character(url) && length(url) == 1L && !is.na(url)
  # A host name, IPv4 address or bracketed IPv6 address, and a port of 1 to
  # 65535 when there is one: what the transport cannot connect to is an
  # argument error here, not UNAVAILABLE on every call (#84).
  m <- if (ok) {
    regmatches(
      url,
      regexec(
        "^(https?)://((\\[[0-9A-Fa-f:.]+\\]|[A-Za-z0-9_.-]+)(:([0-9]{1,5}))?)/?$",
        url,
        ignore.case = TRUE
      )
    )[[1L]]
  } else {
    character()
  }
  port <- if (length(m) == 6L && nzchar(m[6L])) as.integer(m[6L])
  if (length(m) != 6L || (!is.null(port) && (port < 1L || port > 65535L))) {
    zugrpc_abort(
      "argument",
      "`url` must be one string, http://host:port or https://host:port."
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

# zuhttp keeps keepalive in whole milliseconds, from 1 to the largest C int,
# so a value outside that range is refused here rather than by zuhttp, or
# clamped without a word (#85).
check_keepalive_seconds <- function(x, arg) {
  ok <- is.numeric(x) &&
    length(x) == 1L &&
    is.finite(x) &&
    x >= 0.001 &&
    x <= 2147483.647
  if (!ok) {
    zugrpc_abort(
      "argument",
      sprintf(
        "`%s` must be one number of seconds from 0.001 to 2147483.647.",
        arg
      )
    )
  }
  invisible(x)
}

# Every digit, never scientific notation.
format_seconds <- function(x) {
  format(x, digits = 15, scientific = FALSE, trim = TRUE)
}
