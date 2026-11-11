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
#'   when the call ends with a status other than `OK`. A stream that fails
#'   any other way, such as a lost connection, a passed deadline or a broken
#'   message, raises the same condition again on every later call. The
#'   complete messages that arrived before a broken one are returned first.
#' * `$trailers()` returns the trailing metadata once `$next_message()` has
#'   returned `NULL`, and `NULL` before.
#' * `$status()` returns the final status name once the stream has ended,
#'   and `NULL` before: `"OK"`, the server's status, or the status the stream
#'   failed with, such as `"CANCELLED"` or `"DEADLINE_EXCEEDED"`. A stream
#'   that failed without a status, on a protocol error, stays `NULL`.
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
  st$user_trailers <- NULL
  st$status <- NULL
  st$done <- FALSE
  st$cancelled <- FALSE
  # Whether any body byte has arrived: a status in the headers counts only
  # when none did (§6.2).
  st$body_seen <- FALSE
  # The condition a failed stream raised, raised again by every later read.
  st$error <- NULL
  # A non-OK status not yet raised, because a warning unwound the read that
  # found it. The next read raises it (#77).
  st$unraised <- NULL
  # Pieces of the body not yet split into messages, concatenated only once
  # the message they belong to is complete (§6.3).
  st$pending <- list()
  st$pending_len <- 0
  # The length of the message being read, prefix included, once known.
  st$need <- NULL
  # Messages split but not yet returned, from queue[[head]] on. Popping by
  # index rather than deleting the first element keeps a read of many small
  # messages linear (§11).
  st$queue <- list()
  st$head <- 1L
  st$channel <- channel
  # The finaliser goes on before the response is registered, so that no
  # interrupt can leave a registered response with nothing to abort it.
  # zuhttp's own finaliser does the same I/O, so aborting from GC is safe.
  st$id <- NULL
  reg.finalizer(st, function(e) stream_finish(e, abort = TRUE))
  st$id <- register_stream(channel, res)

  # A non-200 status or a body that is not gRPC is known from the headers.
  # A non-OK status in them is resolved when the stream ends (§6.2); an OK
  # one does not make a body that is not gRPC acceptable (#58).
  header_status <- field(st$headers, "grpc-status")
  if (is.null(header_status)) {
    if (st$http_status != 200L) {
      stream_finish(st, abort = TRUE)
      stop(http_status_error(
        st$http_status,
        method,
        st$user_headers,
        stats::setNames(list(), character())
      ))
    }
  }
  if (
    (is.null(header_status) ||
      status_from_header(header_status)$name == "OK") &&
      !is_grpc_type(st$headers)
  ) {
    # The condition keeps the start of the body, as a unary call's does.
    excerpt <- tryCatch(
      resp_read(res, 1024),
      zuhttp_error = function(cnd) raw()
    )
    stream_guard(st, check_content_type(st$headers, excerpt))
  }

  stream <- list(
    headers = function() st$user_headers,
    next_message = function() stream_next(st),
    trailers = function() st$user_trailers,
    status = function() {
      stream_sync(st)
      st$status
    },
    cancel = function() {
      stream_sync(st)
      if (!st$done) {
        stream_finish(st, abort = TRUE)
        stream_cancelled(st)
      }
      invisible(NULL)
    }
  )
  structure(stream, class = "zugrpc_stream", env = st)
}

#' @export
print.zugrpc_stream <- function(x, ...) {
  st <- attr(x, "env")
  stream_sync(st)
  state <- if (st$cancelled) {
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
    stream_sync(st)
    if (st$cancelled) {
      queue_clear(st)
    }
    if (st$head <= length(st$queue)) {
      msg <- st$queue[[st$head]]
      st$head <- st$head + 1L
      return(msg)
    }
    queue_clear(st)
    if (st$cancelled) {
      status_abort(
        "CANCELLED",
        "the stream was cancelled",
        method = st$method
      )
    }
    if (st$done) {
      if (!is.null(st$unraised)) {
        cnd <- st$unraised
        st$unraised <- NULL
        stop(cnd)
      }
      if (!is.null(st$error)) {
        stop(st$error)
      }
      return(NULL)
    }
    if (!is.null(st$deadline_at) && Sys.time() >= st$deadline_at) {
      stream_finish(st, abort = TRUE)
      stream_fail(
        st,
        status_error(
          "DEADLINE_EXCEEDED",
          "deadline exceeded",
          method = st$method
        )
      )
    }
    chunk <- stream_guard(st, resp_read(st$res, read_size(st)))
    if (length(chunk) == 0L) {
      stream_end(st)
    } else {
      stream_take(st, chunk)
    }
  }
}

queue_clear <- function(st) {
  st$queue <- list()
  st$head <- 1L
}

# Up to the rest of the message being read, so a large message arrives in
# few reads, and at least 64 KiB, so small ones arrive several at a time.
read_size <- function(st) {
  need <- if (is.null(st$need)) 0 else st$need
  max(65536, min(need - st$pending_len, 16 * 1024^2))
}

stream_take <- function(st, chunk) {
  st$body_seen <- TRUE
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
    st$need <- 5 + frame_length(head)
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
    frame_split(
      buf,
      max_message = st$max_message,
      encoding = st$encoding,
      partial = TRUE
    )
  )
  st$queue <- c(st$queue, framed$messages)
  st$pending <- list()
  st$pending_len <- 0
  st$need <- NULL
  if (!is.null(framed$error)) {
    # The complete messages before a bad prefix are delivered first, then
    # its error, on every later read (#76).
    stream_finish(st, abort = TRUE)
    stream_record(st, stamp_call(framed$error, st$method, st$http_status))
    return(invisible())
  }
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

# The body has ended. The status is resolved as for a unary call (§6.2):
# a status the server sent wins over a body that ends inside a message
# (#58). The stream is marked done only once its outcome is recorded, and
# warnings from decoding the trailers are held until then, so that one that
# unwinds cannot make a failed stream read as a clean end (#77).
stream_end <- function(st) {
  trailers <- stream_guard(
    st,
    lower_names(zuhttp::zu_resp_trailers(st$res))
  )
  warnings <- list()
  outcome <- withCallingHandlers(
    tryCatch(
      {
        st$user_trailers <- metadata_decode(user_metadata(trailers))
        resolve_status(
          st$http_status,
          st$headers,
          trailers,
          body_seen = st$body_seen,
          excerpt = raw(),
          method = st$method,
          user_headers = st$user_headers,
          user_trailers = st$user_trailers
        )
        if (st$pending_len > 0) {
          zugrpc_abort(
            "protocol",
            "The response body ends inside a gRPC message."
          )
        }
        NULL
      },
      zugrpc_error = function(cnd) stamp_call(cnd, st$method, st$http_status)
    ),
    warning = function(w) {
      warnings[[length(warnings) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  )

  stream_finish(st, abort = FALSE)
  if (is.null(outcome)) {
    st$status <- "OK"
  } else if (inherits(outcome, "zugrpc_error_status")) {
    # A status the server sent is raised once, then the stream reads as
    # ended (§6.6). Kept until it has been raised.
    st$status <- outcome$grpc_status
    st$unraised <- outcome
  } else {
    stream_record(st, outcome)
  }
  for (w in warnings) {
    warning(w)
  }
  if (!is.null(outcome)) {
    st$unraised <- NULL
    stop(outcome)
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
    abort_response(st$res)
  }
  unregister_stream(st$channel, st$id)
  invisible()
}

# Sends RST_STREAM for an unfinished response. zu_resp_abort() raises only
# when called from inside the response's own request body function, which
# zugrpc never streams, and then there is nothing left to undo.
abort_response <- function(res) {
  tryCatch(zuhttp::zu_resp_abort(res), zuhttp_error = function(e) NULL)
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
      stream_fail(st, transport_error(cnd, st$method))
    },
    zugrpc_error = function(cnd) {
      stream_finish(st, abort = TRUE)
      stream_fail(st, stamp_call(cnd, st$method, st$http_status))
    },
    error = function(cnd) {
      stream_finish(st, abort = TRUE)
      stream_fail(st, cnd)
    }
  )
}

# Raises `cnd` and keeps it, so that a failed stream never later reads as a
# clean end.
stream_fail <- function(st, cnd) {
  stream_record(st, cnd)
  stop(cnd)
}

# Keeps the condition a stream failed with, and its status when it has one,
# such as DEADLINE_EXCEEDED or UNAVAILABLE (#86). A protocol error has none.
stream_record <- function(st, cnd) {
  st$error <- cnd
  if (is.character(cnd$grpc_status)) {
    st$status <- cnd$grpc_status
  }
  invisible(cnd)
}

stream_cancelled <- function(st) {
  st$cancelled <- TRUE
  st$status <- "CANCELLED"
  invisible()
}

# A stream of a channel that grpc_close() has closed is cancelled: the
# response is already aborted, and the state says so at once (#86).
stream_sync <- function(st) {
  if (st$channel$closed && !st$done) {
    stream_finish(st, abort = FALSE)
    stream_cancelled(st)
  }
  invisible()
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
  if (!is.null(id) && exists(id, envir = channel$streams, inherits = FALSE)) {
    rm(list = id, envir = channel$streams)
  }
}
