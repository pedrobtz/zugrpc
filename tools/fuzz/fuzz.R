# Generated-input fuzzing of zugrpc's parsers (#59), run by
# .github/workflows/fuzz.yaml. Each target compares what zugrpc returns
# against something that knows the answer, never only "it did not crash":
#
#   frame     frame_split() against messages encoded independently, cut at
#             random offsets, and a reference reader of random prefixes
#   base64    base64_decode() against jsonlite, on valid and random input
#   message   grpc_message_decode() as the inverse of a percent-encoder,
#             and never failing on random input
#   status    grpc-status and the HTTP fallback against statuscodes.md and
#             PROTOCOL-HTTP2.md, written out here
#   details   status_details_decode() on mutated recorded trailers: a
#             decoded Status or a warning and NULL, and through
#             grpc_call() the status always survives
#   metadata  metadata_decode() on random headers: every non-bin value
#             kept in place, and every dropped -bin value warned about
#
#   Rscript tools/fuzz/fuzz.R [seconds] [seed]
#
# or with FUZZ_SECONDS and FUZZ_SEED set, as tools/fuzz/reach.R runs it.
#
# It stops at the first disagreement, printing the seed and the input, so a
# failure is reproduced by running it again with that seed. Needs the
# package installed, and jsonlite.

args <- commandArgs(trailingOnly = TRUE)
budget <- if (length(args) >= 1L) {
  as.numeric(args[[1L]])
} else {
  as.numeric(Sys.getenv("FUZZ_SECONDS", "60"))
}
seed <- if (length(args) >= 2L) args[[2L]] else Sys.getenv("FUZZ_SEED", "")
# A CI run id is larger than an R integer, so the seed is taken modulo one.
seed <- if (nzchar(seed)) {
  as.integer(as.numeric(seed) %% .Machine$integer.max)
} else {
  sample.int(.Machine$integer.max, 1L)
}
fixtures <- Sys.getenv("FUZZ_FIXTURES", "tests/testthat/fixtures")

ns <- asNamespace("zugrpc")
frame_split <- get("frame_split", ns)
base64_decode <- get("base64_decode", ns)
base64_encode <- get("base64_encode", ns)
grpc_message_decode <- get("grpc_message_decode", ns)
status_details_decode <- get("status_details_decode", ns)
metadata_decode <- get("metadata_decode", ns)

fail <- function(target, what, input) {
  cat(sprintf("\nFAIL %s (seed %d): %s\n", target, seed, what))
  cat("input:\n")
  utils::str(input, vec.len = 200, nchar.max = 2000)
  quit(status = 1)
}

rand_bytes <- function(n) as.raw(sample.int(256L, n, replace = TRUE) - 1L)

# frame ---------------------------------------------------------------------

# An encoder written apart from zugrpc's: flag, then the length in four
# big-endian bytes.
encode_message <- function(bytes, flag = 0L) {
  n <- length(bytes)
  c(as.raw(c(flag, bitwAnd(bitwShiftR(n, c(24L, 16L, 8L, 0L)), 255L))), bytes)
}

# A reader written apart from zugrpc's: what frame_split() must return or
# raise for `buf`, given max_message.
reference_split <- function(buf, max_message, encoding = NULL) {
  pos <- 1L
  out <- list()
  n <- length(buf)
  while (n - pos + 1L >= 5L) {
    flag <- as.integer(buf[pos])
    len <- sum(as.numeric(buf[(pos + 1L):(pos + 4L)]) * 256^(3:0))
    if (flag != 0L) {
      # A compressed message needs a grpc-encoding, which v0.1.0 does not
      # support; any other flag is broken framing.
      unsupported <- flag == 1L && !is.null(encoding) && encoding != "identity"
      return(list(error = if (unsupported) "unimplemented" else "protocol"))
    }
    if (len > max_message) {
      return(list(error = "resource_exhausted"))
    }
    if (n - pos + 1L - 5L < len) {
      break
    }
    out[[length(out) + 1L]] <- if (len > 0) {
      buf[(pos + 5L):(pos + 4L + len)]
    } else {
      raw()
    }
    pos <- pos + 5L + len
  }
  list(messages = out, remainder = if (pos <= n) buf[pos:n] else raw())
}

fuzz_frame <- function() {
  # Whole messages, cut into random chunks as a stream reads them.
  count <- if (runif(1) < 0.2) sample(17:40, 1L) else sample.int(6L, 1L)
  msgs <- lapply(sample(0:300, count, replace = TRUE), rand_bytes)
  buf <- do.call(c, c(list(raw()), lapply(msgs, encode_message)))
  cuts <- sort(unique(sample.int(
    max(1L, length(buf)),
    sample(0:4, 1L),
    replace = TRUE
  )))
  got <- list()
  rest <- raw()
  for (piece in split(buf, findInterval(seq_along(buf), cuts + 1L))) {
    res <- frame_split(c(rest, piece), max_message = 1e6)
    got <- c(got, res$messages)
    rest <- res$remainder
  }
  if (!identical(got, msgs) || length(rest) != 0L) {
    fail(
      "frame",
      "chunked messages do not reassemble",
      list(msgs = msgs, cuts = cuts)
    )
  }

  # A good message, then random bytes: frame_split(partial = TRUE) must
  # agree with the reference reader on messages and on the error.
  max_message <- sample(c(0, 1, 10, 255, 1e6), 1L)
  encoding <- sample(list(NULL, "identity", "gzip"), 1L)[[1L]]
  buf <- c(
    encode_message(rand_bytes(sample(0:min(max_message, 20), 1L))),
    rand_bytes(sample(0:12, 1L))
  )
  if (runif(1) < 0.3) {
    buf[sample.int(length(buf), 1L)] <- rand_bytes(1L)
  }
  want <- reference_split(buf, max_message, encoding)
  got <- tryCatch(
    frame_split(
      buf,
      max_message = max_message,
      encoding = encoding,
      partial = TRUE
    ),
    error = function(cnd) {
      fail("frame", paste("partial split raised:", conditionMessage(cnd)), buf)
    }
  )
  if (is.null(want$error)) {
    if (
      !is.null(got$error) ||
        !identical(got$messages, want$messages) ||
        !identical(got$remainder, want$remainder)
    ) {
      fail(
        "frame",
        "split differs from the reference",
        list(buf = buf, max = max_message)
      )
    }
  } else {
    if (is.null(got$error)) {
      fail(
        "frame",
        paste("no error where the reference has", want$error),
        list(buf = buf, max = max_message)
      )
    }
    ok <- switch(
      want$error,
      protocol = inherits(got$error, "zugrpc_error_protocol"),
      unimplemented = inherits(got$error, "zugrpc_error_unimplemented"),
      resource_exhausted = inherits(
        got$error,
        "zugrpc_error_resource_exhausted"
      )
    )
    if (!ok) {
      fail(
        "frame",
        paste("wrong error class", class(got$error)[1L], "for", want$error),
        buf
      )
    }
    # Without partial, the same condition is raised.
    raised <- tryCatch(
      frame_split(buf, max_message = max_message, encoding = encoding),
      error = identity
    )
    if (!identical(class(raised), class(got$error))) {
      fail("frame", "partial and raising modes disagree", buf)
    }
    # The messages before the bad prefix are kept (#76).
    before <- reference_split(
      buf[seq_len(sum(lengths(got$messages)) + 5L * length(got$messages))],
      max_message,
      encoding
    )
    if (!identical(got$messages, before$messages)) {
      fail("frame", "messages before the bad prefix differ", buf)
    }
  }
}

# base64 --------------------------------------------------------------------

b64_chars <- c(LETTERS, letters, 0:9, "+", "/")

fuzz_base64 <- function() {
  # Valid: the bytes back, padded or not, against jsonlite's encoder.
  x <- rand_bytes(sample(0:200, 1L))
  # jsonlite wraps its output in lines; base64 in a header is one line.
  padded <- gsub("\\s", "", jsonlite::base64_enc(x))
  for (s in c(padded, sub("=+$", "", padded))) {
    got <- tryCatch(base64_decode(s), error = function(e) {
      fail("base64", "a valid encoding was refused", s)
    })
    if (!identical(got, x)) {
      fail("base64", "a valid encoding does not decode to its bytes", s)
    }
  }
  if (!identical(base64_encode(x), sub("=+$", "", padded))) {
    fail("base64", "the encoding differs from jsonlite's, unpadded", x)
  }

  # Random: accepted exactly when it is base64, and then as jsonlite reads it.
  s <- paste(
    sample(
      c(b64_chars, "=", "-", "_", " ", ","),
      sample(0:12, 1L),
      replace = TRUE
    ),
    collapse = ""
  )
  body <- sub("={1,2}$", "", s)
  valid <- grepl("^[A-Za-z0-9+/]*$", body) && nchar(body) %% 4L != 1L
  got <- tryCatch(base64_decode(s), error = identity)
  if (inherits(got, "condition")) {
    if (valid) {
      fail("base64", "valid input refused", s)
    }
    if (!inherits(got, "zugrpc_error_protocol")) {
      fail("base64", "refused without the protocol class", s)
    }
  } else {
    if (!valid) {
      fail("base64", "invalid input accepted", s)
    }
    pad <- strrep("=", (4L - nchar(body) %% 4L) %% 4L)
    if (!identical(got, jsonlite::base64_dec(paste0(body, pad)))) {
      fail("base64", "decodes differently from jsonlite", s)
    }
  }
}

# grpc-message ----------------------------------------------------------------

# Percent-encodes every byte that must be, and any other at random, in
# either case of hex digit.
percent_encode <- function(bytes) {
  paste(
    vapply(
      as.integer(bytes),
      function(b) {
        must <- b < 0x20 || b > 0x7e || b == 0x25
        if (must || runif(1) < 0.2) {
          sprintf(if (runif(1) < 0.5) "%%%02X" else "%%%02x", b)
        } else {
          rawToChar(as.raw(b))
        }
      },
      character(1)
    ),
    collapse = ""
  )
}

fuzz_message <- function() {
  # Valid UTF-8 without NUL round-trips.
  pool <- c(" ", "a", "%", "\n", "\t", "é", "☺", "\U0001f608", " ", "z")
  text <- enc2utf8(paste(
    sample(pool, sample(0:10, 1L), replace = TRUE),
    collapse = ""
  ))
  got <- grpc_message_decode(percent_encode(charToRaw(text)))
  if (!identical(got, text) && !(nchar(text) == 0L && identical(got, ""))) {
    fail(
      "message",
      "a percent-encoded message does not decode to its text",
      text
    )
  }

  # Random input never raises, and gives a string; with no `%` it is as
  # received.
  junk <- rawToChar(as.raw(sample(
    c(0x20:0x7e, 0x25, 0x25),
    sample(0:15, 1L),
    replace = TRUE
  )))
  got <- tryCatch(grpc_message_decode(junk), error = function(e) {
    fail("message", "raised", junk)
  })
  if (!is.character(got) || length(got) != 1L) {
    fail("message", "not one string", junk)
  }
  if (!grepl("%", junk, fixed = TRUE) && !identical(got, junk)) {
    fail("message", "text without % was changed", junk)
  }
}

# status ----------------------------------------------------------------------

status_from_header <- get("status_from_header", ns)
status_from_http <- get("status_from_http", ns)
# statuscodes.md, written out apart from the package's table.
spec_codes <- c(
  "OK",
  "CANCELLED",
  "UNKNOWN",
  "INVALID_ARGUMENT",
  "DEADLINE_EXCEEDED",
  "NOT_FOUND",
  "ALREADY_EXISTS",
  "PERMISSION_DENIED",
  "RESOURCE_EXHAUSTED",
  "FAILED_PRECONDITION",
  "ABORTED",
  "OUT_OF_RANGE",
  "UNIMPLEMENTED",
  "INTERNAL",
  "UNAVAILABLE",
  "DATA_LOSS",
  "UNAUTHENTICATED"
)
# PROTOCOL-HTTP2.md's map for a response with no grpc-status.
spec_http <- c(
  "400" = "INTERNAL",
  "401" = "UNAUTHENTICATED",
  "403" = "PERMISSION_DENIED",
  "404" = "UNIMPLEMENTED",
  "429" = "UNAVAILABLE",
  "502" = "UNAVAILABLE",
  "503" = "UNAVAILABLE",
  "504" = "UNAVAILABLE"
)

fuzz_status <- function() {
  # A decimal of one to nine ASCII digits is a code: its name, or UNKNOWN
  # outside the table. Anything else, or nothing, is INTERNAL.
  value <- if (runif(1) < 0.1) {
    NULL
  } else {
    paste(
      sample(
        c(0:9, 0:9, " ", "-", "+", "x", "\u0660"),
        sample(0:11, 1L),
        replace = TRUE
      ),
      collapse = ""
    )
  }
  chars <- if (is.null(value)) integer() else utf8ToInt(enc2utf8(value))
  digits <- length(chars) >= 1L &&
    length(chars) <= 9L &&
    all(chars >= 48L & chars <= 57L)
  want <- if (!digits) {
    "INTERNAL"
  } else {
    code <- sum((chars - 48L) * 10^(rev(seq_along(chars)) - 1L))
    if (code <= 16) spec_codes[code + 1L] else "UNKNOWN"
  }
  got <- status_from_header(value)$name
  if (!identical(got, want)) {
    fail("status", sprintf("grpc-status read as %s, not %s", got, want), value)
  }

  http <- sample(c(100:599, as.integer(names(spec_http))), 1L)
  want <- if (as.character(http) %in% names(spec_http)) {
    spec_http[[as.character(http)]]
  } else {
    "UNKNOWN"
  }
  if (!identical(status_from_http(http), want)) {
    fail("status", "HTTP status mapped against the specification's table", http)
  }
}

# details ---------------------------------------------------------------------

recorded <- local({
  read <- function(name) {
    fx <- dget(file.path(fixtures, "details", paste0(name, ".dput")))
    # Trailers-Only: the status and its details are in the headers.
    fields <- c(fx$response$headers, fx$response$trailers)
    fields[[match("grpc-status-details-bin", tolower(names(fields)))]]
  }
  c(read("every"), read("spark"))
})

fuzz_details <- function() {
  bytes <- base64_decode(sample(recorded, 1L))
  # Flip, drop or insert a few bytes.
  for (k in seq_len(sample(0:3, 1L))) {
    i <- sample.int(length(bytes), 1L)
    bytes <- switch(
      sample(3L, 1L),
      {
        bytes[i] <- rand_bytes(1L)
        bytes
      },
      bytes[-i],
      append(bytes, rand_bytes(sample(1:4, 1L)), after = i)
    )
  }
  value <- base64_encode(bytes)
  warned <- FALSE
  got <- withCallingHandlers(
    tryCatch(status_details_decode(value), error = function(e) {
      fail("details", paste("raised:", conditionMessage(e)), bytes)
    }),
    warning = function(w) {
      if (!inherits(w, "zugrpc_warning_details")) {
        fail("details", "an unclassed warning", bytes)
      }
      warned <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  if (is.null(got) && !warned) {
    fail("details", "NULL without a warning", bytes)
  }
  if (!is.null(got)) {
    # Each detail is named by its type: a packed one by the type in its own
    # type_url (empty when it has none), an unpacked one by a short
    # error_details.proto name.
    short <- c(
      "ErrorInfo",
      "RetryInfo",
      "DebugInfo",
      "QuotaFailure",
      "PreconditionFailure",
      "BadRequest",
      "RequestInfo",
      "ResourceInfo",
      "Help",
      "LocalizedMessage"
    )
    d <- got$details
    if (!is.list(d) || length(names(d)) != length(d)) {
      fail("details", "details not a named list", bytes)
    }
    for (i in seq_along(d)) {
      packed <- is.list(d[[i]]) &&
        identical(names(d[[i]]), c("type_url", "value"))
      want <- if (packed) sub("^.*/", "", d[[i]]$type_url) else short
      if (!names(d)[i] %in% want) {
        fail("details", sprintf("detail %d named '%s'", i, names(d)[i]), bytes)
      }
    }
  }

  # Through a call, the status survives whatever the trailer holds.
  fake <- zuhttp::zu_mock_transport(function(req) {
    zuhttp::zu_response(
      200L,
      headers = c("content-type" = "application/grpc"),
      body = raw(),
      trailers = c("grpc-status" = "13", "grpc-status-details-bin" = value)
    )
  })
  ch <- zugrpc::grpc_channel(
    "http://localhost:1",
    client = zuhttp::zu_client(transport = fake)
  )
  cnd <- suppressWarnings(tryCatch(
    zugrpc::grpc_call(ch, "/a.B/C", raw()),
    error = identity
  ))
  if (!inherits(cnd, "zugrpc_error_internal")) {
    fail("details", "the status was lost", bytes)
  }
}

# metadata ----------------------------------------------------------------------

fuzz_metadata <- function() {
  n <- sample(0:6, 1L)
  nms <- sample(c("a", "b", "x-bin", "y-bin", "a"), n, replace = TRUE)
  values <- vapply(
    nms,
    function(nm) {
      if (endsWith(nm, "-bin") && runif(1) < 0.7) {
        paste(
          vapply(
            seq_len(sample(1:3, 1L)),
            function(i) base64_encode(rand_bytes(sample(0:5, 1L))),
            ""
          ),
          collapse = ","
        )
      } else {
        paste(
          sample(c(b64_chars, ",", "=", "!"), sample(0:6, 1L), replace = TRUE),
          collapse = ""
        )
      }
    },
    character(1),
    USE.NAMES = FALSE
  )
  headers <- stats::setNames(values, nms)
  warnings <- 0L
  got <- withCallingHandlers(
    tryCatch(metadata_decode(headers), error = function(e) {
      fail("metadata", paste("raised:", conditionMessage(e)), headers)
    }),
    warning = function(w) {
      if (!inherits(w, "zugrpc_warning_metadata")) {
        fail("metadata", "an unclassed warning", headers)
      }
      warnings <<- warnings + 1L
      invokeRestart("muffleWarning")
    }
  )
  # The ASCII values, in order and unchanged.
  plain <- !endsWith(nms, "-bin")
  if (
    !identical(
      unname(unlist(got[!endsWith(names(got), "-bin")])) %||% character(),
      unname(values[plain])
    )
  ) {
    fail("metadata", "an ASCII value changed or moved", headers)
  }
  # Each -bin header gives its pieces, or nothing and one warning.
  bins <- which(!plain)
  expected <- 0L
  dropped <- 0L
  for (i in bins) {
    pieces <- strsplit(paste0(values[i], ","), ",", fixed = TRUE)[[1L]]
    if (!nzchar(values[i])) {
      pieces <- ""
    }
    ok <- all(vapply(
      pieces,
      function(p) {
        !inherits(
          tryCatch(base64_decode(trimws(p)), error = identity),
          "condition"
        )
      },
      TRUE
    ))
    if (ok) expected <- expected + length(pieces) else dropped <- dropped + 1L
  }
  if (sum(endsWith(names(got), "-bin")) != expected || warnings != dropped) {
    fail("metadata", "-bin entries or warnings miscounted", headers)
  }
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Run ---------------------------------------------------------------------------

set.seed(seed)
targets <- list(
  frame = fuzz_frame,
  base64 = fuzz_base64,
  message = fuzz_message,
  status = fuzz_status,
  details = fuzz_details,
  metadata = fuzz_metadata
)
runs <- stats::setNames(integer(length(targets)), names(targets))
start <- Sys.time()
while (as.numeric(Sys.time() - start, units = "secs") < budget) {
  for (name in names(targets)) {
    targets[[name]]()
    runs[[name]] <- runs[[name]] + 1L
  }
}
cat(sprintf("fuzz: seed %d, %.0f s, no disagreement\n", seed, budget))
print(runs)
