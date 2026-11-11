source("common.R")
m <- mock(); grpc_call(m$ch, M, raw(), metadata = c("user-agent" = "")); cat(encodeString(sent(m)$headers[["user-agent"]], quote = '"'), "\n")
m <- mock(headers = c("user-agent" = "chan/1")); grpc_call(m$ch, M, raw(), metadata = c("user-agent" = "")); cat(encodeString(sent(m)$headers[["user-agent"]], quote = '"'), "\n")
# channel made with a mock client whose own user_agent is set: which wins
m <- mock(client_args = list(user_agent = "client/9")); grpc_call(m$ch, M, raw()); cat(sent(m)$headers[["user-agent"]], "| resolved:", sent(m)$resolved$user_agent, "\n")
# a channel does not change the caller's client
cl <- zuhttp::zu_client(max_body = 10, http2 = "never"); ch <- grpc_channel("http://h:1", client = cl); cat("caller's client untouched:", cl$max_body, cl$http2, "\n")
# metadata does not leak between calls or into the channel
m <- mock(headers = c(a = "1")); grpc_call(m$ch, M, raw(), metadata = c(b = "2")); grpc_call(m$ch, M, raw()); print(sent(m)$headers[-(1:4)]); print(m$ch$headers)
# next_id / registry with many streams
m <- mock(); sts <- lapply(1:12, function(i) grpc_stream(m$ch, M, raw())); print(m$ch); sts[[3]]$cancel(); sts[[3]]$cancel(); print(m$ch); rm(sts); invisible(gc()); print(m$ch); grpc_close(m$ch); print(m$ch)
