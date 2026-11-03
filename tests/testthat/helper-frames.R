# Builds one length-prefixed message by hand, independently of frame_encode(),
# so the tests check the encoder against the wire format rather than itself.
wire_message <- function(bytes, flag = 0L) {
  n <- length(bytes)
  prefix <- as.raw(c(
    flag,
    (n %/% 2^24) %% 256,
    (n %/% 2^16) %% 256,
    (n %/% 2^8) %% 256,
    n %% 256
  ))
  c(prefix, bytes)
}

# Feeds `bytes` to frame_split() in chunks ending at `cuts`, as a streaming
# reader would, and returns every message it produced plus the final remainder.
split_in_chunks <- function(bytes, cuts, ...) {
  starts <- c(1L, cuts + 1L)
  ends <- c(cuts, length(bytes))
  messages <- list()
  remainder <- raw()
  for (i in seq_along(starts)) {
    chunk <- if (starts[i] <= ends[i]) bytes[starts[i]:ends[i]] else raw()
    res <- frame_split(c(remainder, chunk), ...)
    messages <- c(messages, res$messages)
    remainder <- res$remainder
  }
  list(messages = messages, remainder = remainder)
}
