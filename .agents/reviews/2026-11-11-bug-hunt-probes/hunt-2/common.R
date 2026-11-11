W <- "<W>/hunt-2"
.libPaths(c(file.path(dirname(W), "lib"), .libPaths()))
suppressPackageStartupMessages(library(zugrpc))
PORT <- 47211
URL <- paste0("http://127.0.0.1:", PORT)
hx <- function(x) paste(sprintf("%02x", as.integer(x)), collapse = "")
frame <- function(x, flag = 0) hx(c(as.raw(flag), zugrpc:::frame_encode(as.raw(x))[-1]))
frs <- function(s) frame(charToRaw(s))
H0 <- list(c(":status", "200"), c("content-type", "application/grpc"))
TOK <- list(c("grpc-status", "0"))
# scen: named list of step lists
set_scen <- function(...) {
  writeLines(enc2utf8(as.character(jsonlite::toJSON(list(...), auto_unbox = TRUE, null = "null"))), file.path(W, "scen.json"), useBytes = TRUE)
}
h <- function(kv, end = FALSE) list(h = kv, end = end)
d <- function(hex, end = FALSE, chunk = NULL, gap = NULL) { s <- list(d = hex, end = end); if (!is.null(chunk)) s$chunk <- chunk; if (!is.null(gap)) s$gap <- gap; s }
last_req <- function() { l <- readLines(file.path(W, "req.log")); l <- l[grepl('"headers"', l)]; jsonlite::fromJSON(l[length(l)], simplifyVector = FALSE) }
log_events <- function() { l <- readLines(file.path(W, "req.log")); l[grepl('"event"', l)] }
show <- function(expr) {
  ws <- list()
  r <- withCallingHandlers(
    tryCatch(list(ok = expr), error = function(e) list(err = e)),
    warning = function(w) { ws[[length(ws) + 1]] <<- w; invokeRestart("muffleWarning") })
  if (!is.null(r$err)) {
    e <- r$err
    cat("  ERR <", paste(head(class(e), 3), collapse = ","), "> ", conditionMessage(e), "\n", sep = "")
  } else { cat("  OK: "); str(r$ok, give.attr = FALSE, vec.len = 8) }
  for (w in ws) cat("  WARN <", class(w)[1], "> ", conditionMessage(w), "\n", sep = "")
  invisible(r)
}
ch <- function(...) grpc_channel(URL, ...)
drain <- function(st, max = 100) { out <- list(); repeat { m <- st$next_message(); if (is.null(m)) break; out[[length(out) + 1]] <- m; if (length(out) >= max) break }; out }
# stream run: collect messages then outcome
srun <- function(c, m, ...) {
  got <- list()
  r <- tryCatch({ st <- grpc_stream(c, m, raw(), ...); repeat { x <- st$next_message(); if (is.null(x)) break; got[[length(got) + 1]] <- x }; paste0("END status=", st$status()) },
    error = function(e) paste0("ERR <", paste(head(class(e), 2), collapse = ","), "> ", conditionMessage(e)))
  cat("  stream: msgs=[", paste(vapply(got, function(x) if (length(x) > 16) paste0("<", length(x), "b>") else rawToChar(x), ""), collapse = "|"), "] ", r, "\n", sep = "")
  invisible(list(got = got, r = r))
}
urun <- function(c, m, ...) {
  r <- tryCatch({ x <- grpc_call(c, m, raw(), ...); paste0("OK msg=", if (length(x$message) > 16) paste0("<", length(x$message), "b>") else rawToChar(x$message)) },
    error = function(e) paste0("ERR <", paste(head(class(e), 2), collapse = ","), "> ", conditionMessage(e)))
  cat("  unary:  ", r, "\n", sep = "")
  invisible(r)
}
both <- function(name, steps) {
  cat(name, "\n"); do.call(set_scen, stats::setNames(list(steps), "M"))
  c1 <- ch(); on.exit(grpc_close(c1))
  urun(c1, "/s.S/M"); srun(c1, "/s.S/M")
}
