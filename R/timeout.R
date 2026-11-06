# Deadlines (design §6.6). A deadline is seconds from now or an absolute
# POSIXct; on the wire it is `grpc-timeout`, at most eight digits and a unit.

timeout_units <- c(n = 1, u = 1e3, m = 1e6, S = 1e9, M = 60e9, H = 3600e9)

# The finest unit whose value fits in eight digits, rounded up so the
# server never sees a shorter deadline than the caller set.
grpc_timeout <- function(seconds) {
  ns <- max(0, ceiling(seconds * 1e9 - 1e-6))
  for (unit in names(timeout_units)) {
    k <- timeout_units[[unit]]
    value <- if (ns < 2^53) ns %/% k + (ns %% k > 0) else ceiling(ns / k)
    if (value <= 99999999) {
      return(paste0(format(value, scientific = FALSE), unit))
    }
  }
  "99999999H"
}

deadline_seconds <- function(deadline, now = Sys.time()) {
  if (is.null(deadline)) {
    return(NULL)
  }
  if (
    inherits(deadline, "POSIXct") && length(deadline) == 1L && !is.na(deadline)
  ) {
    return(max(0, as.numeric(deadline) - as.numeric(now)))
  }
  ok <- is.numeric(deadline) &&
    length(deadline) == 1L &&
    is.finite(deadline) &&
    deadline >= 0
  if (!ok) {
    zugrpc_abort(
      "argument",
      paste0(
        "`deadline` must be a non-negative number of seconds or one POSIXct ",
        "time."
      )
    )
  }
  as.numeric(deadline)
}
