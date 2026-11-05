# Condition constructors (design §9). Every error inherits from
# `zugrpc_error` and every warning from `zugrpc_warning`. The class vectors
# are API: callers select on them (D10).

new_zugrpc_condition <- function(classes, message, ..., call = NULL) {
  structure(
    class = c(classes, "condition"),
    list(message = message, call = call, ...)
  )
}

zugrpc_error <- function(kind, message, ...) {
  new_zugrpc_condition(
    c(paste0("zugrpc_error_", kind), "zugrpc_error", "error"),
    message,
    ...
  )
}

zugrpc_abort <- function(kind, message, ...) {
  stop(zugrpc_error(kind, message, ...))
}

zugrpc_warning <- function(kind, message, ...) {
  new_zugrpc_condition(
    c(paste0("zugrpc_warning_", kind), "zugrpc_warning", "warning"),
    message,
    ...
  )
}

# A non-OK gRPC status. The class vector carries the code as
# `zugrpc_error_<name>` so callers can select one status (D10).
status_error <- function(name, message = "", ..., details = NULL) {
  new_zugrpc_condition(
    c(
      paste0("zugrpc_error_", tolower(name)),
      "zugrpc_error_status",
      "zugrpc_error",
      "error"
    ),
    if (nzchar(message)) paste0(name, ": ", message) else name,
    grpc_status = name,
    grpc_code = status_code(name),
    grpc_message = message,
    details = details,
    ...
  )
}

status_abort <- function(name, message = "", ...) {
  stop(status_error(name, message, ...))
}

# Received `-bin` metadata that is not base64. The entry is dropped.
metadata_warning <- function(name, value) {
  warning(zugrpc_warning(
    "metadata",
    sprintf("Received metadata '%s' is not base64 and was dropped.", name),
    name = name,
    value = value
  ))
}

# A zuhttp condition raised while performing a call, translated (§6.6, §9).
# The zuhttp condition is kept as `parent`.
transport_error <- function(cnd, method) {
  if (inherits(cnd, "zu_interrupted_error")) {
    message <- "The call was interrupted."
    return(new_zugrpc_condition(
      c("zugrpc_error_interrupt", "zugrpc_error", "error"),
      message,
      grpc_status = "CANCELLED",
      grpc_code = status_code("CANCELLED"),
      grpc_message = message,
      method = method,
      parent = cnd
    ))
  }
  status <- if (inherits(cnd, "zu_timeout_error")) {
    c("DEADLINE_EXCEEDED", "deadline exceeded")
  } else if (inherits(cnd, "zu_cancelled_error")) {
    c("CANCELLED", "the call was cancelled")
  } else if (inherits(cnd, "zu_body_limit_error")) {
    c("RESOURCE_EXHAUSTED", "the response is larger than max_message")
  }
  if (!is.null(status)) {
    return(status_error(status[1L], status[2L], method = method, parent = cnd))
  }
  # Also `zugrpc_error_unavailable`, so a handler for that status catches a
  # failure of either layer.
  new_zugrpc_condition(
    c(
      "zugrpc_error_transport",
      "zugrpc_error_unavailable",
      "zugrpc_error",
      "error"
    ),
    paste0("UNAVAILABLE: ", conditionMessage(cnd)),
    grpc_status = "UNAVAILABLE",
    grpc_code = status_code("UNAVAILABLE"),
    grpc_message = conditionMessage(cnd),
    method = method,
    parent = cnd
  )
}

transport_abort <- function(cnd, method) {
  stop(transport_error(cnd, method))
}

# Every condition of a call carries its method, and its HTTP status once the
# response has one (§9). The wire-format helpers raise without them; this
# stamps them on, keeping any already set.
with_call_context <- function(expr, method, http_status = NULL) {
  tryCatch(
    expr,
    zugrpc_error = function(cnd) {
      stop(stamp_call(cnd, method, http_status))
    }
  )
}

stamp_call <- function(cnd, method, http_status = NULL) {
  if (is.null(cnd$method)) {
    cnd$method <- method
  }
  if (is.null(cnd$http_status) && !is.null(http_status)) {
    cnd$http_status <- http_status
  }
  cnd
}
