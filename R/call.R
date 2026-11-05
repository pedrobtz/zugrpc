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
#'   starting with `grpc-`, `te` and `content-type` are reserved.
#' @param deadline Seconds from now, or an absolute `POSIXct`, by which the
#'   call must finish. It is sent to the server as `grpc-timeout` and also
#'   bounds the request locally. `NULL` sets no deadline.
#'
#' @return A list with elements `message` (raw, the response message),
#'   `headers` and `trailers` (named lists of the initial and trailing
#'   metadata, with `-bin` values as raw vectors) and `status` (`"OK"`).
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
#' and `metadata`. A trailer that does not decode gives a
#' `zugrpc_warning_details` warning, and `details` is `NULL`.
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
  check_method(method)
  body <- frame_encode(request)
  seconds <- deadline_seconds(deadline)
  timeout <- if (!is.null(seconds)) grpc_timeout(seconds)
  headers <- request_headers(
    metadata = metadata_merge(channel$headers, metadata_encode(metadata)),
    timeout = timeout,
    user_agent = user_agent()
  )

  req <- zuhttp::zu_request("POST", paste0(channel$origin, method))
  req <- do.call(zuhttp::zu_headers, c(list(req), as.list(headers)))
  req <- zuhttp::zu_body_raw(req, body, type = "application/grpc+proto")
  if (!is.null(seconds)) {
    req <- zuhttp::zu_req_timeout(req, total = seconds)
  }
  res <- tryCatch(
    zuhttp::zu_perform(req, client = channel$client),
    zuhttp_error = function(cnd) transport_abort(cnd, method)
  )

  unary_result(
    http_status = zuhttp::zu_resp_status(res),
    headers = zuhttp::zu_resp_headers(res),
    body = zuhttp::zu_resp_raw(res),
    trailers = zuhttp::zu_resp_trailers(res),
    method = method,
    max_message = channel$max_message
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
  headers <- lower_names(headers)
  trailers <- lower_names(trailers)
  # Trailers-Only: the status arrives in the one HEADERS block.
  status_fields <- trailers
  if (is.null(field(trailers, "grpc-status")) && length(body) == 0L) {
    status_fields <- headers
  }
  status_value <- field(status_fields, "grpc-status")
  message_value <- field(status_fields, "grpc-message")

  if (is.null(status_value)) {
    if (http_status != 200L) {
      status_abort(
        status_from_http(http_status),
        sprintf("HTTP status %d with no grpc-status", http_status),
        http_status = http_status,
        method = method,
        headers = metadata_decode(user_metadata(headers)),
        trailers = metadata_decode(user_metadata(trailers))
      )
    }
    check_content_type(headers, body)
  }

  status <- status_from_header(status_value)
  if (status$name != "OK") {
    msg <- grpc_message_decode(message_value)
    if (!nzchar(msg)) {
      msg <- status$message
    }
    status_abort(
      status$name,
      msg,
      details = status_details_decode(
        field(status_fields, "grpc-status-details-bin")
      ),
      http_status = http_status,
      method = method,
      headers = metadata_decode(user_metadata(headers)),
      trailers = metadata_decode(user_metadata(trailers))
    )
  }
  check_content_type(headers, body)

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
    headers = metadata_decode(user_metadata(headers)),
    trailers = metadata_decode(user_metadata(trailers)),
    status = "OK"
  )
}

# A `content-type` not starting with application/grpc is the usual sign of
# a plain HTTP server; the condition keeps the first 1 KiB of the body.
check_content_type <- function(headers, body) {
  type <- field(headers, "content-type")
  if (is.null(type) || !startsWith(tolower(type), "application/grpc")) {
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
  invisible()
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
  nms <- names(fields)
  keep <- !(startsWith(nms, ":") |
    startsWith(nms, "grpc-") |
    nms %in% c("content-type", "te"))
  fields[keep]
}
