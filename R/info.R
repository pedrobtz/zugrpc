#' What this installation of zugrpc can do
#'
#' Reports the `zuhttp` that carries zugrpc's calls: its version, whether it
#' speaks HTTP/2, which gRPC requires, and its TLS backend.
#'
#' @return A list with elements `version` (zugrpc's, a string), `zuhttp`
#'   (its version, a string), `http2` (logical), `tls_backend` (a string)
#'   and `tls_capabilities` (character), printed as a short report.
#' @seealso [zuhttp::zu_info()] for the full transport report.
#' @export
#' @examples
#' zugrpc_info()
zugrpc_info <- function() {
  zu <- zuhttp::zu_info()
  structure(
    list(
      version = as.character(utils::packageVersion("zugrpc")),
      zuhttp = as.character(utils::packageVersion("zuhttp")),
      http2 = "HTTP/2" %in% zu$http,
      tls_backend = zu$tls_backend,
      tls_capabilities = zu$tls_capabilities
    ),
    class = "zugrpc_info"
  )
}

#' @export
print.zugrpc_info <- function(x, ...) {
  cat(sprintf("zugrpc %s on zuhttp %s\n", x$version, x$zuhttp))
  cat(sprintf("  HTTP/2:      %s\n", if (x$http2) "yes" else "no"))
  cat(sprintf("  TLS backend: %s\n", x$tls_backend))
  invisible(x)
}
