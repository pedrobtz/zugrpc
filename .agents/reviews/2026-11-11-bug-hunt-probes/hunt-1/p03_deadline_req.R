source("common.R")
hd <- function(q, n) { h <- q$headers; if (n %in% names(h)) h[[n]] else "<none>" }
for (d in list(NULL, 30, 30L, 0.0004, 0.00149, 1e-12, 1e-16, 0, 1e10, 1e300, 2.5, Sys.time() + 30, Sys.time() - 1, Sys.time() + 1e12)) {
  for (f in c("call", "stream")) {
  m <- mock(); r <- try_(if (f == "call") grpc_call(m$ch, M, raw(), deadline = d) else grpc_stream(m$ch, M, raw(), deadline = d))
  cat(f, deparse(d)[1], ": "); if (inherits(r, "caught")) print(r)
  if (length(m$seen$requests)) { q <- sent(m); cat(" grpc-timeout=", hd(q, "grpc-timeout"), " policy=", format(q$policy$timeout, digits = 15), "\n") } else cat(" nothing sent\n")
  }
}
Sys.setenv(TZ = "Pacific/Auckland"); m <- mock(); grpc_call(m$ch, M, raw(), deadline = Sys.time() + 30); cat("TZ Auckland:", hd(sent(m), "grpc-timeout"), "\n")
m <- mock(); grpc_call(m$ch, M, raw(), deadline = as.POSIXct(format(Sys.time() + 30, tz = "UTC", usetz = FALSE), tz = "UTC")); cat("UTC-built:", hd(sent(m), "grpc-timeout"), "\n")
m <- mock(); grpc_call(m$ch, M, raw(), deadline = as.POSIXlt(Sys.time() + 30) |> as.POSIXct()); cat("lt->ct:", hd(sent(m), "grpc-timeout"), "\n")
options(OutDec = ",", scipen = -5, digits = 3, warn = 2)
m <- mock(); print(try_(grpc_call(m$ch, M, raw(), deadline = 123456.789)$status)); cat("hostile:", hd(sent(m), "grpc-timeout"), format(sent(m)$policy$timeout, digits=15), "\n")
cat("== url / body of request\n"); str(sent(m)[c("method", "url")]); print(sent(m)$body)
