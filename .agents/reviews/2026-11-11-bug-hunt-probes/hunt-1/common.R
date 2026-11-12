.libPaths(c("<W>/lib", .libPaths())); suppressMessages(library(zugrpc))
mock <- function(..., respond = NULL, client_args = list()) {
  seen <- new.env(); seen$requests <- list()
  fake <- zuhttp::zu_mock_transport(function(req) {
    seen$requests <- c(seen$requests, list(req))
    if (!is.null(respond)) return(respond(req))
    zuhttp::zu_response(200L, headers = c("content-type" = "application/grpc+proto"),
      body = as.raw(c(0,0,0,0,0)), trailers = c("grpc-status" = "0"))
  })
  ch <- grpc_channel("http://localhost:50051", client = do.call(zuhttp::zu_client, c(list(transport = fake), client_args)), ...)
  list(ch = ch, seen = seen)
}
M <- "/a.B/C"
try_ <- function(expr) tryCatch(expr, condition = function(e) structure(list(cls = class(e), msg = conditionMessage(e)), class = "caught"))
print.caught <- function(x, ...) cat("  <", paste(head(x$cls, 3), collapse = "/"), "> ", x$msg, "\n", sep = "")
sent <- function(m) { r <- m$seen$requests; r[[length(r)]] }
