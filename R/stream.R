# Server-streaming calls (design §4 item 3, §6.3, §6.6) on zuhttp's pulled
# response body (§7.2 item 3, D6).

#' Make a server-streaming gRPC call
#'
#' Sends one request message and returns a stream that yields the response
#' messages one at a time, as they arrive. The server sends only as far ahead
#' as you read, so a stream you stop reading holds the server back rather
#' than filling memory.
#'
#' The stream is an object with five methods:
#'
#' * `$headers()` returns the initial metadata, a named list.
#' * `$next_message()` returns the next message as a raw vector, or `NULL`
#'   at the end of the stream. It raises a condition, as [grpc_call()] does,
#'   when the call ends with a status other than `OK`.
#' * `$trailers()` returns the trailing metadata once `$next_message()` has
#'   returned `NULL`, and `NULL` before.
#' * `$status()` returns the final status name, such as `"OK"`, once the
#'   stream has ended, and `NULL` before.
#' * `$cancel()` stops the call. The connection stays open for other calls.
#'   A second `$cancel()` does nothing. A later `$next_message()` raises
#'   `zugrpc_error_cancelled`.
#'
#' A stream that is no longer referenced is cancelled when it is
#' garbage-collected, and [grpc_close()] cancels every open stream of its
#' channel.
#'
#' @inheritParams grpc_call
#' @param deadline Seconds from now, or an absolute `POSIXct`, by which the
#'   whole stream must end. It is sent as `grpc-timeout`. Locally it is
#'   checked before each read, and each wait for more data is bounded by the
#'   time the deadline allowed when the call began, so a stall can overrun a
#'   deadline that is already partly used. `NULL` sets no deadline.
#'
#' @return A `zugrpc_stream`.
#' @export
#' @examples
#' # A test server, from zuhttp's mock transport: it streams two messages
#' # and ends with status OK.
#' fake <- zuhttp::zu_mock_transport(function(req) {
#'   zuhttp::zu_response(
#'     200L,
#'     headers = c("content-type" = "application/grpc+proto"),
#'     body = as.raw(c(0, 0, 0, 0, 1, 0x61, 0, 0, 0, 0, 1, 0x62)),
#'     trailers = c("grpc-status" = "0")
#'   )
#' })
#' ch <- grpc_channel(
#'   "http://localhost:50051",
#'   client = zuhttp::zu_client(transport = fake)
#' )
#' st <- grpc_stream(ch, "/grpc.testing.TestService/StreamingOutputCall", raw())
#' while (!is.null(m <- st$next_message())) print(rawToChar(m))
#' st$status()
grpc_stream <- function(
  channel,
  method,
  request,
  metadata = NULL,
  deadline = NULL
) {
  check_channel(channel)
  req <- build_request(channel, method, request, metadata, deadline)
  res <- tryCatch(
    zuhttp::zu_perform(
      req$request,
      client = channel$stream_client,
      stream = TRUE
    ),
    zuhttp_error = function(cnd) transport_abort(cnd, method)
  )
  new_stream(channel, res, method, req$deadline_at)
}

new_stream <- function(channel, res, method, deadline_at) {
  st <- new.env(parent = emptyenv())
  st$res <- res
  st$method <- method
  st$deadline_at <- deadline_at
  st$max_message <- channel$max_message
  st$http_status <- zuhttp::zu_resp_status(res)
  st$headers <- lower_names(zuhttp::zu_resp_headers(res))
  st$encoding <- field(st$headers, "grpc-encoding")
  st$user_headers <- metadata_decode(user_metadata(st$headers))
  st$trailers <- NULL
  st$user_trailers <- NULL
  st$status <- NULL
  st$done <- FALSE
  # Pieces of the body not yet split into messages, concatenated only once
  # the message they belong to is complete (§6.3).
  st$pending <- list()
  st$pending_len <- 0
  st$queue <- list()
  st$id <- register_stream(channel, res)
  st$channel <- channel

  # A non-200 status or a body that is not gRPC is known from the headers.
  if (is.null(field(st$headers, "grpc-status"))) {
    if (st$http_status != 200L) {
      stream_finish(st, abort = TRUE)
      status_abort(
        status_from_http(st$http_status),
        sprintf("HTTP status %d with no grpc-status", st$http_status),
        http_status = st$http_status,
        method = method,
        headers = st$user_headers,
        trailers = list()
      )
    }
    stream_guard(st, check_content_type(st$headers, raw()))
  }

  reg.finalizer(st, function(e) stream_finish(e, abort = TRUE))
  stream <- list(
    headers = function() st$user_headers,
    next_message = function() stream_next(st),
    trailers = function() st$user_trailers,
    status = function() st$status,
    cancel = function() {
      if (!st$done) {
        stream_finish(st, abort = TRUE)
        st$cancelled <- TRUE
      }
      invisible(NULL)
    }
  )
  structure(stream, class = "zugrpc_stream", env = st)
}

#' @export
print.zugrpc_stream <- function(x, ...) {
  st <- attr(x, "env")
  state <- if (isTRUE(st$cancelled)) {
    "cancelled"
  } else if (st$done) {
    paste0("ended, ", if (is.null(st$status)) "failed" else st$status)
  } else {
    "open"
  }
  cat(sprintf("<zugrpc_stream> %s\n", st$method))
  cat(sprintf("  state: %s\n", state))
  invisible(x)
}

# The next complete message, reading only when none is buffered.
stream_next <- function(st) {
  repeat {
    if (st$channel$closed && !st$done) {
      stream_finish(st, abort = TRUE)
      st$cancelled <- TRUE
    }
    if (isTRUE(st$cancelled)) {
      st$queue <- list()
    }
    if (length(st$queue) > 0L) {
      msg <- st$queue[[1L]]
      st$queue[[1L]] <- NULL
      return(msg)
    }
    if (isTRUE(st$cancelled)) {
      status_abort(
        "CANCELLED",
        "the stream was cancelled",
        method = st$method
      )
    }
    if (st$done) {
      return(NULL)
    }
    if (!is.null(st$deadline_at) && Sys.time() >= st$deadline_at) {
      stream_finish(st, abort = TRUE)
      status_abort("DEADLINE_EXCEEDED", "deadline exceeded", method = st$method)
    }
    chunk <- stream_guard(st, resp_read(st$res, read_size(st)))
    if (length(chunk) == 0L) {
      stream_end(st)
    } else {
      stream_take(st, chunk)
    }
  }
}

# Up to the rest of the message being read, so a large message arrives in
# few reads, and at least 64 KiB, so small ones arrive several at a time.
read_size <- function(st) {
  need <- st$need %||% 0
  max(65536, min(need - st$pending_len, 16 * 1024^2))
}

stream_take <- function(st, chunk) {
  st$pending[[length(st$pending) + 1L]] <- chunk
  st$pending_len <- st$pending_len + length(chunk)
  if (st$pending_len < 5) {
    return(invisible())
  }
  if (is.null(st$need)) {
    head <- stream_head(st)
    # Checks the flag and max_message from the prefix alone, before the
    # body of a message too large to accept is read.
    stream_guard(
      st,
      frame_split(head, max_message = st$max_message, encoding = st$encoding)
    )
    len <- sum(as.numeric(head[2:5]) * c(16777216, 65536, 256, 1))
    st$need <- 5 + len
  }
  if (st$pending_len < st$need) {
    return(invisible())
  }
  buf <- if (length(st$pending) == 1L) {
    st$pending[[1L]]
  } else {
    do.call(c, st$pending)
  }
  framed <- stream_guard(
    st,
    frame_split(buf, max_message = st$max_message, encoding = st$encoding)
  )
  st$queue <- c(st$queue, framed$messages)
  st$pending <- list()
  st$pending_len <- 0
  st$need <- NULL
  if (length(framed$remainder) > 0L) {
    stream_take(st, framed$remainder)
  }
  invisible()
}

# The first five bytes of the pending pieces, without joining them all.
stream_head <- function(st) {
  out <- raw()
  for (p in st$pending) {
    out <- c(out, p[seq_len(min(length(p), 5L - length(out)))])
    if (length(out) == 5L) break
  }
  out
}

# The body has ended: the status is in the trailers, or in the headers for
# Trailers-Only.
stream_end <- function(st) {
  trailers <- lower_names(zuhttp::zu_resp_trailers(st$res))
  stream_finish(st, abort = FALSE)
  st$trailers <- trailers
  st$user_trailers <- metadata_decode(user_metadata(trailers))
  if (st$pending_len > 0) {
    zugrpc_abort(
      "protocol",
      "The response body ends inside a gRPC message.",
      method = st$method
    )
  }
  status_fields <- trailers
  if (is.null(field(trailers, "grpc-status"))) {
    status_fields <- st$headers
  }
  status <- status_from_header(field(status_fields, "grpc-status"))
  st$status <- status$name
  if (status$name != "OK") {
    msg <- grpc_message_decode(field(status_fields, "grpc-message"))
    if (!nzchar(msg)) {
      msg <- status$message
    }
    status_abort(
      status$name,
      msg,
      details = status_details_decode(
        field(status_fields, "grpc-status-details-bin")
      ),
      http_status = st$http_status,
      method = st$method,
      headers = st$user_headers,
      trailers = st$user_trailers
    )
  }
  invisible()
}

# Ends the stream once: aborts the body when it was not read to its end, and
# removes it from the channel's open streams.
stream_finish <- function(st, abort) {
  if (st$done) {
    return(invisible())
  }
  st$done <- TRUE
  if (abort) {
    try(zuhttp::zu_resp_abort(st$res), silent = TRUE)
  }
  unregister_stream(st$channel, st$id)
  invisible()
}

# Runs `expr`; on any error the stream is finished first, with the body
# aborted so that the server stops sending, and a zuhttp condition is
# translated (§9).
stream_guard <- function(st, expr) {
  tryCatch(
    expr,
    zuhttp_error = function(cnd) {
      stream_finish(st, abort = TRUE)
      transport_abort(cnd, st$method)
    },
    error = function(cnd) {
      stream_finish(st, abort = TRUE)
      stop(cnd)
    }
  )
}

# A seam for tests, which cannot raise an interrupt inside zuhttp.
resp_read <- function(res, n) zuhttp::zu_resp_read(res, n)

# The channel keeps the open responses, not the streams, so a stream nobody
# references can still be collected and its finaliser run.
register_stream <- function(channel, res) {
  channel$next_id <- channel$next_id + 1
  id <- as.character(channel$next_id)
  assign(id, res, envir = channel$streams)
  id
}

unregister_stream <- function(channel, id) {
  if (exists(id, envir = channel$streams, inherits = FALSE)) {
    rm(list = id, envir = channel$streams)
  }
}

`%||%` <- function(x, y) if (is.null(x)) y else x
