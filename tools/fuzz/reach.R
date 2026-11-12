# What the fuzz corpus reaches (#60): runs tools/fuzz/fuzz.R under covr and
# lists the lines of the parsers it never executes, file by file. Fails when
# any file's reach falls below its floor, so a fuzz target that stops
# reaching its parser is noticed. The floors were set from the first runs
# (2026-11-11), a little under what 30 s reached; raise them as the targets
# grow.
#
#   Rscript tools/fuzz/reach.R [seconds] [seed]

args <- commandArgs(trailingOnly = TRUE)
budget <- if (length(args) >= 1L) args[[1L]] else "60"
seed <- if (length(args) >= 2L) args[[2L]] else Sys.getenv("FUZZ_SEED", "1")

# Whole files, so the encoders and argument checks the decode targets never
# call count as unreached: metadata.R is mostly metadata_encode().
floors <- c(
  "R/frame.R" = 88,
  "R/metadata.R" = 50,
  "R/status.R" = 95,
  "R/details.R" = 95
)

root <- normalizePath(".")
code <- sprintf(
  paste0(
    'Sys.setenv(FUZZ_SECONDS = "%s", FUZZ_SEED = "%s", FUZZ_FIXTURES = "%s"); ',
    'source("%s")'
  ),
  budget,
  seed,
  file.path(root, "tests", "testthat", "fixtures"),
  file.path(root, "tools", "fuzz", "fuzz.R")
)
cov <- covr::package_coverage(root, type = "none", code = code, quiet = TRUE)
lines <- covr::tally_coverage(cov, by = "line")
lines <- lines[lines$filename %in% names(floors), ]

failed <- FALSE
for (file in names(floors)) {
  x <- lines[lines$filename == file, ]
  reach <- 100 * mean(x$value > 0)
  missed <- sort(x$line[x$value == 0])
  status <- if (reach >= floors[[file]]) "ok" else "BELOW FLOOR"
  cat(sprintf(
    "%-14s %5.1f%% reached (floor %d%%) %s\n",
    file,
    reach,
    floors[[file]],
    status
  ))
  if (length(missed)) {
    cat("  never reached: lines", paste(missed, collapse = ", "), "\n")
  }
  failed <- failed || reach < floors[[file]]
}
if (failed) {
  quit(status = 1)
}
