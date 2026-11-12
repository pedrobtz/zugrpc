source(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE))), "common.R"))
pool <- function(ch) unlist(unclass(ch$client$pool))
cat("## A: numbers on grpc_keepalive -> what zuhttp pool gets\n")
for (v in list(c(60, 20), c(1e-4, 1), c(4e-4, 1), c(5e-4, 1), c(0.001, 1e-4), c(0.0015, 0.0004), c(2147483, 1), c(2147484, 1), c(1e10, 1), c(1, 1e10), c(.Machine$integer.max + 1, 1), c(1e300, 1e300), c(0, 1), c(-1, 1), c(NA, 1), c(Inf, 1), c(1, Inf), c(NaN, 1))) {
  cat(sprintf("time=%-12g timeout=%-8g : ", v[1], v[2]))
  r <- tryCatch({ k <- grpc_keepalive(v[1], v[2]); ch <- grpc_channel(URL, keepalive = k); p <- pool(ch); paste("ka_time_ms", p[["keepalive_time_ms"]], "ka_timeout_ms", p[["keepalive_timeout_ms"]]) },
                error = function(e) paste("ERR", class(e)[1], conditionMessage(e)), warning = function(w) paste("WARN", conditionMessage(w)))
  cat(r, "\n")
}
show("int time", unclass(grpc_keepalive(1L, 2L))); show("lgl", grpc_keepalive(TRUE)); show("chr", grpc_keepalive("1")); show("len2", grpc_keepalive(c(1, 2)))
cat("## B: keepalive NULL; caller's pool settings kept?\n")
cl <- zuhttp::zu_client(pool = zuhttp::zu_pool(max_idle = 3L, max_per_host = 2L, idle_timeout = 7, keepalive_time = 5, keepalive_timeout = 2))
print(pool(grpc_channel(URL, client = cl, keepalive = NULL))); print(pool(grpc_channel(URL, client = cl))); print(pool(grpc_channel(URL, keepalive = NULL)))
cat("## C: client with no pool\n")
cln <- show("zu_client(pool = NULL)", zuhttp::zu_client(pool = NULL))$ok
if (!is.null(cln)) { cat("pool is NULL:", is.null(cln$pool), "\n"); c0 <- grpc_channel(URL, client = cln); show("call", grpc_call(c0, M, raw())$message); show("call", grpc_call(c0, M, raw())$message)
  s <- scn(c0, "h,m1,w"); show("next", s$next_message()); show("close", class(grpc_close(c0))); show("next", s$next_message()); snew() }
cat("## D: keepalive on the wire: time 0.5, timeout 0.5; idle 0.3 (no ping), idle 0.8 (ping)\n")
ch <- grpc_channel(URL, keepalive = grpc_keepalive(0.5, 0.5)); invisible(grpc_call(ch, M, raw())); Sys.sleep(0.3); invisible(grpc_call(ch, M, raw())); Sys.sleep(0.8); show("call", grpc_call(ch, M, raw())$message); snew()
cat("## E: open stream idle 1.2s with keepalive 0.5 (reads later): any ping, stream survives?\n")
s <- scn(ch, "h,m1,s1200,m1,t0"); for (i in 1:3) show("next", s$next_message()); snew()
cat("## F: idle_timeout of pool: stream open longer than idle_timeout 1s and unread: survives?\n")
c2 <- grpc_channel(URL, client = zuhttp::zu_client(pool = zuhttp::zu_pool(idle_timeout = 1)), keepalive = NULL)
s <- scn(c2, "h,m1,s300,m1,t0"); Sys.sleep(1.6); invisible(grpc_call(c2, M, raw())); for (i in 1:3) show("next", s$next_message()); snew()
