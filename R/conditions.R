# Condition constructors. Every condition inherits from `zugrpc_error`
# (design §9). Stage 3 adds status details and the transport and interrupt
# wrappers; this file holds what the framing layer raises.

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
status_abort <- function(name, message = "", ..., call = NULL) {
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
      ...
    )
  )
  stop(cnd)
}
