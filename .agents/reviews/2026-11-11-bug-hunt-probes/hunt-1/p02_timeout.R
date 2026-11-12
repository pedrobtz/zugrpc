source("common.R")
gt <- zugrpc:::grpc_timeout
vals <- c(0, 1e-16, 1e-10, 1e-9, 1.5e-9, 0.001, 0.0999999999, 0.1, 0.3, 1, 1.1, 30, 99.999999, 99.9999991, 100, 600, 99999.999, 99999.9991, 123456.789, 99999999, 99999999.5, 1e8, 5999999940, 5999999941, 359999996400, 359999996401, 2^31, 2^53, 9007199.254740993, 1e17, 1e300)
for (v in vals) cat(format(v, digits = 17), "->", gt(v), "\n")
# server never sees shorter deadline: decoded >= seconds
dec <- function(s) { u <- substring(s, nchar(s)); as.numeric(substr(s, 1, nchar(s) - 1)) * zugrpc:::timeout_units[[u]] / 1e9 }
set.seed(1); x <- c(runif(20000, 0, 2), 10^runif(20000, -9, 12), sample(1e6, 5000) / 1000)
out <- vapply(x, gt, ""); d <- vapply(out, dec, 0)
cat("shorter than asked:", sum(d < x & d < 99999999 * 3600), " bad format:", sum(!grepl("^[0-9]{1,8}[numSMH]$", out)), "\n")
print(head(cbind(x = format(x[d < x], digits = 17), out = out[d < x]), 10))
# overshoot: more than 1 unit over?
cat("== hostile options\n")
options(OutDec = ",", scipen = -5, digits = 3)
for (v in c(0.1, 1, 30, 99999.999, 123456.789, 1e8, 1e17)) cat(v, "->", gt(v), "\n")
out2 <- vapply(x, gt, ""); cat("changed under options:", sum(out2 != out), "\n")
options(OutDec = ".", scipen = 0, digits = 7)
cat("== deadline_seconds\n")
ds <- zugrpc:::deadline_seconds
now <- as.POSIXct("2026-01-01 00:00:00", tz = "UTC")
cases <- list(NULL, 5, 5L, 0, -1, NA, NA_real_, NA_integer_, Inf, c(1, 2), numeric(), "5", TRUE, factor(5), c(a = 5), 2^31, 2^53 + 2,
  now + 10, now - 10, as.POSIXct(NA), c(now, now), as.POSIXlt(now + 10), Sys.Date(), as.difftime(5, units = "secs"), as.difftime(5, units = "mins"), list(5), 1e-300,
  as.POSIXct("2026-01-01 01:00:00", tz = "Asia/Tokyo"), structure(1767225610, class = c("POSIXct", "POSIXt")))
for (cs in cases) { cat(deparse(cs)[1], " => "); r <- try_(ds(cs, now = now)); if (inherits(r, "caught")) print(r) else cat(format(r, digits = 17), "\n") }
cat("== build_request with deadlines: header and policy timeout\n")
for (d in list(NULL, 30, 0.0004, 1e-12, 1e-16, 0, 1e10, 1e300, 2.5, Sys.time() + 30, Sys.time() - 1, Sys.time() + 1e12)) {
  m <- mock(); r <- try_(grpc_call(m$ch, M, raw(), deadline = d))
  cat(deparse(d)[1], ": "); if (inherits(r, "caught")) print(r)
  if (length(m$seen$requests)) { q <- sent(m); cat(" grpc-timeout=", q$headers[["grpc-timeout"]] %||% "<none>", " policy=", format(q$policy$timeout), "\n") } else cat(" nothing sent\n")
}
Sys.setenv(TZ = "Pacific/Auckland"); m <- mock(); grpc_call(m$ch, M, raw(), deadline = Sys.time() + 30); cat("TZ Auckland:", sent(m)$headers[["grpc-timeout"]], "\n")
m <- mock(); grpc_call(m$ch, M, raw(), deadline = as.POSIXct(format(Sys.time() + 30, tz = "UTC"), tz = "UTC")); cat("UTC-built:", sent(m)$headers[["grpc-timeout"]], "\n")
