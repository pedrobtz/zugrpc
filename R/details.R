# Status details (design §6.5): `grpc-status-details-bin` is base64 of a
# serialised google.rpc.Status. zuproto decodes it against the descriptor set
# in inst/descriptors/, built by tools/gen-descriptors.sh (D4). Nothing else
# is ever decoded with it.

rpc_env <- new.env(parent = emptyenv())

rpc_pool <- function() {
  if (is.null(rpc_env$pool)) {
    path <- system.file("descriptors", "google-rpc.binpb", package = "zugrpc")
    rpc_env$pool <- zuproto::proto_pool(path)
  }
  rpc_env$pool
}

# The ten messages of google/rpc/error_details.proto.
error_detail_types <- paste0(
  "google.rpc.",
  c(
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
)

# Decodes the trailer into list(code, message, details). Each detail of an
# error_details.proto type is unpacked and named by its short type name, such
# as `ErrorInfo`; any other is left as list(type_url, value) and named by its
# full type name. A trailer that does not decode is a warning and NULL, never
# an error, so that the status is not lost behind a parser (§9).
status_details_decode <- function(value) {
  if (is.null(value)) {
    return(NULL)
  }
  tryCatch(
    {
      status <- zuproto::proto_decode(
        base64_decode(value),
        "google.rpc.Status",
        rpc_pool(),
        enums = "character"
      )
      status$details <- unpack_details(status$details)
      status
    },
    error = function(e) {
      warning(zugrpc_warning(
        "details",
        paste0(
          "grpc-status-details-bin could not be decoded; `details` is NULL. ",
          conditionMessage(e)
        ),
        parent = e
      ))
      NULL
    }
  )
}

unpack_details <- function(details) {
  if (length(details) == 0L) {
    return(list())
  }
  types <- vapply(
    details,
    function(any) sub("^.*/", "", any$type_url),
    character(1)
  )
  out <- lapply(seq_along(details), function(i) {
    if (types[i] %in% error_detail_types) {
      zuproto::proto_unpack_any(details[[i]], rpc_pool(), enums = "character")
    } else {
      details[[i]]
    }
  })
  known <- types %in% error_detail_types
  names(out) <- ifelse(known, sub("^google\\.rpc\\.", "", types), types)
  out
}
