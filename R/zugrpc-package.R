#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL

# Built once per session and shared by the package: the descriptor pool of
# R/details.R and the user agent of R/channel.R.
rpc_env <- new.env(parent = emptyenv())
