W <- "<W>/hunt-3"
.libPaths(c(file.path(dirname(W), "lib"), .libPaths()))
suppressPackageStartupMessages(library(zugrpc))
PORT <- as.integer(Sys.getenv("H3_PORT", "47330"))
URL <- paste0("http://127.0.0.1:", PORT)
LOG <- Sys.getenv("H3_LOG")
M <- "/t.S/M"
slog <- function(pat = NULL, wait = 0.25) {
  Sys.sleep(wait); l <- readLines(LOG)
  if (!is.null(pat)) l <- grep(pat, l, value = TRUE)
  cat(paste0("   SRV| ", l), sep = "\n"); invisible(l)
}
mark <- 0L
snew <- function(wait = 0.25) { # server log lines since last call
  Sys.sleep(wait); l <- readLines(LOG); out <- l[seq_along(l) > mark]; mark <<- length(l)
  cat(paste0("   SRV| ", out), sep = "\n"); invisible(out)
}
show <- function(label, expr) {
  r <- tryCatch(list(ok = expr), error = function(e) list(err = e), interrupt = function(e) list(int = e))
  cat(label, ": ", sep = "")
  if (!is.null(r$err)) cat("ERR <", paste(head(class(r$err), 3), collapse = ","), "> ", conditionMessage(r$err), "\n", sep = "")
  else if (!is.null(r$int)) cat("RAW INTERRUPT\n")
  else if (is.null(r$ok)) cat("NULL\n") else if (is.raw(r$ok)) cat("raw[", length(r$ok), "] ", paste(head(as.integer(r$ok), 8), collapse = " "), "\n", sep = "")
  else cat(paste(format(r$ok), collapse = " "), "\n")
  invisible(r)
}
st_env <- function(s) attr(s, "env")
state <- function(s) { e <- st_env(s); cat(sprintf("   state: done=%s cancelled=%s error=%s status=%s queue=%d head=%d pending=%g need=%s registry=%d | ",
  e$done, e$cancelled, if (is.null(e$error)) "NULL" else class(e$error)[1], if (is.null(e$status)) "NULL" else e$status,
  length(e$queue), e$head, e$pending_len, if (is.null(e$need)) "NULL" else e$need, length(ls(e$channel$streams)))); print(s) }
scn <- function(ch, s, ...) grpc_stream(ch, M, raw(), metadata = c("x-scn" = s), ...)
