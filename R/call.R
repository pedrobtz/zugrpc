# Unary calls (design §4 item 3, §6.2 to §6.5).

#' Make a unary gRPC call
#'
#' Sends one request message to a method and returns the one response
#' message, with the server's initial and trailing metadata. The request is
#' already encoded, for example by `zuproto::proto_encode()`; zugrpc only
#' frames it. A call that ends with a status other than `OK` raises a
#' condition instead of returning.
#'
#' @param channel A channel from [grpc_channel()].
#' @param method The full method name, `"/package.Service/Method"`.
#' @param request The encoded request message, a raw vector.
#' @param metadata Request metadata: a named character vector, or a named
#'   list whose `-bin` entries are raw vectors. Names are lower-cased. Names
#'   starting with `grpc-` or `:` are reserved, and so are `te`,
#'   `content-type`, `content-length`, `accept-encoding`, `host` and the
#'   connection headers HTTP/2 forbids, such as `connection`. A name given
#'   more than once is sent once, its values joined by commas. A
#'   `user-agent` is sent before zugrpc's own.
#' @param deadline Seconds from now, or an absolute `POSIXct`, by which the
#'   call must finish. It is sent to the server as `grpc-timeout` and also
#'   bounds the request locally. `NULL` sets no deadline.
#'
#' @return A list with elements `message` (raw, the response message),
#'   `headers` and `trailers` (named lists of the initial and trailing
#'   metadata, with `-bin` values as raw vectors) and `status` (`"OK"`). A
#'   `-bin` value holding several, joined by commas, gives one entry each. One
#'   that is not base64 is dropped with a `zugrpc_warning_metadata` warning.
#'
#' @section Errors:
#' A non-`OK` status raises `zugrpc_error_status`, whose class also carries
#' the status as `zugrpc_error_<name>`, for example
#' `zugrpc_error_unavailable`. Its fields are `grpc_status`, `grpc_code`,
#' `grpc_message`, `details`, `http_status`, `method`, `headers` and
#' `trailers`. `details` is the decoded `google.rpc.Status` from the
#' `grpc-status-details-bin` trailer, or `NULL` when there is none: a list of
#' `code`, `message` and `details`. Its `details` are the decoded error
#' details, named by type, such as `ErrorInfo` with its `reason`, `domain`
#' and `metadata`. Two details of one type share its name, so
#' `d[names(d) == "BadRequest"]` selects them all. A trailer that does not
#' decode gives a `zugrpc_warning_details` warning, and `details` is `NULL`.
#'
#' A failure below gRPC, such as a refused connection or a TLS error,
#' raises `zugrpc_error_transport`, which is also `zugrpc_error_unavailable`.
#' The `zuhttp` condition is its `parent`. A local timeout is
#' `DEADLINE_EXCEEDED`, and an interrupt raises `zugrpc_error_interrupt`.
#' A response that is not gRPC, or breaks its framing, raises
#' `zugrpc_error_protocol`. See [grpc_status_codes()].
#'
#' @export
#' @examples
#' # A test server, from zuhttp's mock transport: it answers every call with
#' # an empty message and status OK.
#' fake <- zuhttp::zu_mock_transport(function(req) {
#'   zuhttp::zu_response(
#'     200L,
#'     headers = c("content-type" = "application/grpc+proto"),
#'     body = as.raw(c(0, 0, 0, 0, 0)),
#'     trailers = c("grpc-status" = "0")
#'   )
#' })
#' ch <- grpc_channel(
#'   "http://localhost:50051",
#'   client = zuhttp::zu_client(transport = fake)
#' )
#' res <- grpc_call(ch, "/grpc.testing.TestService/EmptyCall", raw())
#' res$status
#' res$message
grpc_call <- function(
  channel,
  method,
  request,
  metadata = NULL,
  deadline = NULL
) {
  check_channel(channel)
  req <- build_request(channel, method, request, metadata, deadline)
  # Pulled, so that the status and headers are known before the body: when
  # the body passes max_body they still decide the outcome (§6.2, #79).
  res <- tryCatch(
    zuhttp::zu_perform(req$request, client = channel$client, stream = TRUE),
    zuhttp_error = function(cnd) transport_abort(cnd, method)
  )
  finished <- FALSE
  on.exit(if (!finished) abort_response(res))

  http_status <- zuhttp::zu_resp_status(res)
  headers <- zuhttp::zu_resp_headers(res)
  body <- with_call_context(
    unary_body(res, http_status, headers, req$deadline_at, channel, method),
    method = method,
    http_status = http_status
  )
  trailers <- zuhttp::zu_resp_trailers(res)
  finished <- TRUE

  unary_result(
    http_status = http_status,
    headers = headers,
    body = body,
    trailers = trailers,
    method = method,
    max_message = channel$max_message
  )
}

# Reads a unary response body to its end. Each read is bounded by what is
# left of the deadline, so a stall cannot overrun it. The channel's client
# stops the body at max_message plus the prefix.
unary_body <- function(
  res,
  http_status,
  headers,
  deadline_at,
  channel,
  method
) {
  pieces <- list()
  repeat {
    chunk <- tryCatch(
      zuhttp::zu_resp_read(res, 1024^2, timeout = read_timeout(deadline_at)),
      zuhttp_error = function(cnd) {
        body <- do.call(c, c(list(raw()), pieces))
        unary_read_failed(cnd, http_status, headers, body, channel, method)
      }
    )
    if (length(chunk) == 0L) {
      break
    }
    pieces[[length(pieces) + 1L]] <- chunk
  }
  if (length(pieces) == 1L) pieces[[1L]] else do.call(c, c(list(raw()), pieces))
}

# Seconds left before `deadline_at`, for one read; NULL with no deadline.
# At least 1 ms, as for the request (§6.6): bytes already there are still
# read, and zuhttp times out a read that would wait.
read_timeout <- function(deadline_at) {
  if (is.null(deadline_at)) {
    return(NULL)
  }
  max(as.numeric(deadline_at) - as.numeric(Sys.time()), 0.001)
}

# A unary body that failed while being read. Past max_body, what is already
# known decides first: a non-200 HTTP status, a body that is not gRPC, or a
# message whose prefix declares more than max_message (§6.2, §6.3).
unary_read_failed <- function(
  cnd,
  http_status,
  headers,
  body,
  channel,
  method
) {
  if (inherits(cnd, "zu_body_limit_error")) {
    headers <- lower_names(headers)
    with_call_context(
      {
        if (is.null(field(headers, "grpc-status"))) {
          if (http_status != 200L) {
            stop(http_status_error(
              http_status,
              method,
              metadata_decode(user_metadata(headers)),
              list()
            ))
          }
          check_content_type(headers, body)
        }
        if (length(body) >= 5L) {
          frame_split(
            body[1:5],
            max_message = channel$max_message,
            encoding = field(headers, "grpc-encoding")
          )
        }
      },
      method = method,
      http_status = http_status
    )
  }
  stop(stamp_call(transport_error(cnd, method), method, http_status))
}

# The POST of §6.2: headers, metadata, deadline and the framed message.
build_request <- function(channel, method, request, metadata, deadline) {
  check_method(method)
  body <- frame_encode(request)
  seconds <- deadline_seconds(deadline)
  if (!is.null(seconds) && seconds <= 0) {
    # Nothing is sent: the server could only answer the same.
    status_abort("DEADLINE_EXCEEDED", "deadline exceeded", method = method)
  }
  timeout <- if (!is.null(seconds)) grpc_timeout(seconds)
  metadata <- metadata_merge(channel$headers, metadata_encode(metadata))
  # A caller's user-agent goes before zugrpc's, as other gRPC clients do.
  agent <- user_agent()
  if ("user-agent" %in% names(metadata)) {
    # One entry: metadata_encode() joins a repeated name. An empty one adds
    # nothing, rather than a leading space (#82).
    caller <- trimws(metadata[["user-agent"]])
    if (nzchar(caller)) {
      agent <- paste(caller, agent)
    }
    metadata <- metadata[names(metadata) != "user-agent"]
  }
  headers <- request_headers(
    metadata = metadata,
    timeout = timeout,
    user_agent = agent
  )
  req <- zuhttp::zu_request("POST", paste0(channel$origin, method))
  # One named vector, never spliced into `...`, where a header named `req`
  # or a prefix of it would bind to zu_headers()'s own argument (#81).
  req <- zuhttp::zu_headers(req, headers)
  req <- zuhttp::zu_body_raw(req, body, type = "application/grpc+proto")
  # Without a deadline the request must not keep zuhttp's default timeout,
  # and zuhttp reads a bound that rounds to 0 ms as "its default" too.
  local_bound <- if (is.null(seconds)) Inf else max(seconds, 0.001)
  req <- zuhttp::zu_req_timeout(req, total = local_bound)
  list(
    request = req,
    deadline_at = if (!is.null(seconds)) Sys.time() + seconds
  )
}

# Turns one completed HTTP response into a unary result or a condition. The
# order follows §6.2: a grpc-status wins wherever it is; without one, a
# non-200 HTTP status maps to a gRPC status, and a 200 that is not gRPC is a
# protocol error.
unary_result <- function(
  http_status,
  headers,
  body,
  trailers,
  method,
  max_message
) {
  with_call_context(
    unary_outcome(http_status, headers, body, trailers, method, max_message),
    method = method,
    http_status = http_status
  )
}

unary_outcome <- function(
  http_status,
  headers,
  body,
  trailers,
  method,
  max_message
) {
  headers <- lower_names(headers)
  trailers <- lower_names(trailers)
  # Decoded once, so that a bad -bin value warns once.
  user_headers <- metadata_decode(user_metadata(headers))
  user_trailers <- metadata_decode(user_metadata(trailers))
  resolve_status(
    http_status,
    headers,
    trailers,
    body_seen = length(body) > 0L,
    excerpt = body,
    method = method,
    user_headers = user_headers,
    user_trailers = user_trailers
  )

  framed <- frame_split(
    body,
    max_message = max_message,
    encoding = field(headers, "grpc-encoding")
  )
  if (length(framed$remainder) > 0L) {
    zugrpc_abort(
      "protocol",
      "The response body ends inside a gRPC message.",
      method = method
    )
  }
  if (length(framed$messages) != 1L) {
    zugrpc_abort(
      "protocol",
      sprintf(
        "A unary call must return exactly one message, not %d.",
        length(framed$messages)
      ),
      method = method
    )
  }

  list(
    message = framed$messages[[1L]],
    headers = user_headers,
    trailers = user_trailers,
    status = "OK"
  )
}

# The status of a response that has ended, in the order of §6.2, for unary
# calls and streams alike (#58): a grpc-status in the trailers; else, when no
# body arrived, one in the headers (Trailers-Only); else a non-200 HTTP
# status maps to a status; else a content-type that is not gRPC is the
# protocol error; else the status is the missing-status INTERNAL. Raises the
# condition for anything but OK, and returns the OK status invisibly.
# `excerpt` is the start of the body, kept by the protocol error.
resolve_status <- function(
  http_status,
  headers,
  trailers,
  body_seen,
  excerpt,
  method,
  user_headers,
  user_trailers
) {
  status_fields <- trailers
  if (is.null(field(trailers, "grpc-status")) && !body_seen) {
    status_fields <- headers
  }
  status_value <- field(status_fields, "grpc-status")

  if (is.null(status_value)) {
    if (http_status != 200L) {
      stop(http_status_error(http_status, method, user_headers, user_trailers))
    }
    check_content_type(headers, excerpt)
  }

  status <- status_from_header(status_value)
  if (status$name != "OK") {
    stop(grpc_status_error(
      status,
      status_fields,
      http_status,
      method,
      user_headers,
      user_trailers
    ))
  }
  check_content_type(headers, excerpt)
  invisible(status)
}

# The condition for a non-OK status, from the fields that carried it: the
# trailers, or the headers of a Trailers-Only response (§6.2, §6.5). An
# empty grpc-message falls back to what status_from_header() found, such as
# a missing grpc-status.
grpc_status_error <- function(
  status,
  fields,
  http_status,
  method,
  headers,
  trailers
) {
  message <- grpc_message_decode(field(fields, "grpc-message"))
  if (!nzchar(message)) {
    message <- status$message
  }
  status_error(
    status$name,
    message,
    details = status_details_decode(field(fields, "grpc-status-details-bin")),
    http_status = http_status,
    method = method,
    headers = headers,
    trailers = trailers
  )
}

# The condition for a non-200 response with no grpc-status (§6.2).
http_status_error <- function(http_status, method, headers, trailers) {
  status_error(
    status_from_http(http_status),
    sprintf("HTTP status %d with no grpc-status", http_status),
    http_status = http_status,
    method = method,
    headers = headers,
    trailers = trailers
  )
}

# A `content-type` not starting with application/grpc is the usual sign of
# a plain HTTP server; the condition keeps the first 1 KiB of the body.
check_content_type <- function(headers, body) {
  if (!is_grpc_type(headers)) {
    type <- field(headers, "content-type")
    zugrpc_abort(
      "protocol",
      sprintf(
        "The response is not gRPC: content-type is %s.",
        if (is.null(type)) "missing" else sprintf("'%s'", type)
      ),
      content_type = type,
      body = body[seq_len(min(length(body), 1024L))]
    )
  }
  invisible(headers)
}

is_grpc_type <- function(headers) {
  type <- field(headers, "content-type")
  !is.null(type) && startsWith(tolower(type), "application/grpc")
}

# The first value of a header, or NULL when it is absent.
field <- function(fields, name) {
  if (is.null(fields)) {
    return(NULL)
  }
  i <- match(name, names(fields))
  if (is.na(i)) NULL else fields[[i]]
}

lower_names <- function(fields) {
  if (is.null(fields) || length(fields) == 0L) {
    return(stats::setNames(character(), character()))
  }
  stats::setNames(fields, tolower(names(fields)))
}

# Metadata as the caller sees it: the reserved fields of the protocol are
# not metadata (§6.2, §6.4).
user_metadata <- function(fields) {
  fields[!is_reserved_name(names(fields))]
}
