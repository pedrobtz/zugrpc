# Condition constructors. Every condition inherits from `zugrpc_error`
# (design §9).

zugrpc_abort <- function(kind, message, ..., call = NULL) {
  cnd <- structure(
    class = c(
      paste0("zugrpc_error_", kind),
      "zugrpc_error",
      "error",
      "condition"
    ),
    list(message = message, call = call, ...)
  )
  stop(cnd)
}

# A non-OK gRPC status. The class vector carries the code as
# `zugrpc_error_<name>` so callers can select one status (D10).
status_abort <- function(name, message = "", ..., details = NULL, call = NULL) {
  code <- status_code(name)
  full <- if (nzchar(message)) paste0(name, ": ", message) else name
  cnd <- structure(
    class = c(
      paste0("zugrpc_error_", tolower(name)),
      "zugrpc_error_status",
      "zugrpc_error",
      "error",
      "condition"
    ),
    list(
      message = full,
      call = call,
      grpc_status = name,
      grpc_code = code,
      grpc_message = message,
      details = details,
      ...
    )
  )
  stop(cnd)
}

# A zuhttp condition raised while performing a call, translated (§6.6, §9).
# The zuhttp condition is kept as `parent`.
transport_abort <- function(cnd, method) {
  if (inherits(cnd, "zu_interrupted_error")) {
    stop(structure(
      class = c("zugrpc_error_interrupt", "zugrpc_error", "error", "condition"),
      list(
        message = "The call was interrupted.",
        call = NULL,
        grpc_status = "CANCELLED",
        grpc_code = 1L,
        method = method,
        parent = cnd
      )
    ))
  }
  if (inherits(cnd, "zu_timeout_error")) {
    status_abort(
      "DEADLINE_EXCEEDED",
      "deadline exceeded",
      method = method,
      parent = cnd
    )
  }
  if (inherits(cnd, "zu_cancelled_error")) {
    status_abort(
      "CANCELLED",
      "the call was cancelled",
      method = method,
      parent = cnd
    )
  }
  if (inherits(cnd, "zu_body_limit_error")) {
    status_abort(
      "RESOURCE_EXHAUSTED",
      "the response is larger than max_message",
      method = method,
      parent = cnd
    )
  }
  # Also `zugrpc_error_unavailable`, so a handler for that status catches a
  # failure of either layer.
  stop(structure(
    class = c(
      "zugrpc_error_transport",
      "zugrpc_error_unavailable",
      "zugrpc_error",
      "error",
      "condition"
    ),
    list(
      message = paste0("UNAVAILABLE: ", conditionMessage(cnd)),
      call = NULL,
      grpc_status = "UNAVAILABLE",
      grpc_code = 14L,
      method = method,
      parent = cnd
    )
  ))
}
