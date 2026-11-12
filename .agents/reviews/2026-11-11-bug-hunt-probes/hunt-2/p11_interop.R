source("<W>/hunt-2/common.R")
c1 <- grpc_channel("http://127.0.0.1:47212")
show(grpc_call(c1, "/grpc.testing.TestService/EmptyCall", raw()))
show(grpc_call(c1, "/grpc.testing.TestService/UnimplementedCall", raw()))
show(grpc_call(c1, "/grpc.testing.TestService/NoSuch", raw()))
show(grpc_call(c1, "/grpc.testing.TestService/EmptyCall", as.raw(c(0xff, 0xff))))
# SimpleRequest: response_size=2 (field 2 varint), echo metadata
r <- show(grpc_call(c1, "/grpc.testing.TestService/UnaryCall", as.raw(c(0x10, 0x05)), metadata = list("x-grpc-test-echo-initial" = "iv", "x-grpc-test-echo-trailing-bin" = as.raw(c(0xab, 0xab, 0xab)))))
# status echo: response_status field 7 {code=1:2, message=2:"bad msg é"}
msg <- charToRaw("bad é %\n"); st <- c(as.raw(c(0x08, 0x02, 0x12, length(msg))), msg)
e <- show(grpc_call(c1, "/grpc.testing.TestService/UnaryCall", c(as.raw(c(0x3a, length(st))), st)))
cat(hx(charToRaw(e$err$grpc_message)), "\n")
# streaming: response_parameters (field 2) {size=1: n}
rp <- function(n) { v <- if (n < 128) as.raw(n) else as.raw(c(bitwOr(bitwAnd(n, 127), 128), bitwShiftR(n, 7) %% 128 + if (n >= 16384) 128 else 0, if (n >= 16384) bitwShiftR(n, 14))); b <- c(as.raw(0x08), v); c(as.raw(c(0x12, length(b))), b) }
st <- grpc_stream(c1, "/grpc.testing.TestService/StreamingOutputCall", c(rp(1), rp(100), rp(70000), rp(0)))
l <- drain(st); cat("stream lens", lengths(l), "status", st$status(), "\n")
# deadline vs server: tiny deadline
show(grpc_call(c1, "/grpc.testing.TestService/UnaryCall", as.raw(c(0x10, 0x05)), deadline = 1e-6))
grpc_close(c1)
# mock: invalid UTF-8 in grpc-message and upper-case names
fake <- zuhttp::zu_mock_transport(function(req) zuhttp::zu_response(200L, headers = c("Content-Type" = "application/grpc", "X-Up" = "1"), body = raw(), trailers = c("Grpc-Status" = "5", "GRPC-MESSAGE" = "bad\xff%20x", "X-T-BIN" = "QQ")))
c2 <- grpc_channel("http://localhost:1", client = zuhttp::zu_client(transport = fake))
e <- tryCatch(grpc_call(c2, "/s.S/M", raw()), error = function(e) e); cat(class(e)[1], hx(charToRaw(e$grpc_message)), names(e$headers), names(e$trailers), "\n")
