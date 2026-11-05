#!/usr/bin/env bash
# Starts the live test servers, then runs the test suite against them with
# the installed package. CI's live.yaml calls it from the package root, on
# Linux, macOS and Windows (Git Bash); it also works on a developer machine.
# The servers are started in the same step as the tests because a Windows
# runner does not keep background processes between steps.
#
#   tools/ci-live.sh <work dir>
set -euo pipefail

work=${1:-${RUNNER_TEMP:-$(mktemp -d)}/zugrpc-live}
mkdir -p "$work"
exe=""
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) exe=".exe" ;; esac

GOBIN="$work/bin" go install google.golang.org/grpc/interop/server@v1.67.1
(cd tools && go build -o "$work/bin/test-server$exe" ./test-server)
"$work/bin/test-server$exe" -cert_dir "$work/certs"

start() {
  local log=$1
  shift
  "$@" >"$work/$log.log" 2>&1 &
}
start interop "$work/bin/server$exe" -port 10000
start interop-tls "$work/bin/server$exe" -port 10001 -use_tls \
  -tls_cert_file "$work/certs/cert.pem" -tls_key_file "$work/certs/key.pem"
start test-server "$work/bin/test-server$exe" -grpc_port 10002 \
  -h1_tls_port 10003 -h2_port 10004 \
  -tls_cert_file "$work/certs/cert.pem" -tls_key_file "$work/certs/key.pem"
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

# curl exits 7 while nothing listens; any other answer means the port is up.
for port in 10000 10001 10002 10003 10004; do
  up=""
  for _ in $(seq 1 60); do
    rc=0
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$port/" || rc=$?
    if [ "$rc" -ne 7 ]; then
      up=yes
      break
    fi
    sleep 1
  done
  if [ -z "$up" ]; then
    echo "port $port did not come up" >&2
    cat "$work"/*.log >&2
    exit 1
  fi
done

export ZU_GRPC_TEST_SERVER=http://127.0.0.1:10000
export ZU_GRPC_TEST_TLS=https://localhost:10001
export ZU_GRPC_TEST_CA="$work/certs/ca.pem"
export ZU_GRPC_TEST_STATUS=http://127.0.0.1:10002
export ZU_GRPC_TEST_H1_TLS=https://localhost:10003
export ZU_H2_TEST_SERVER=http://127.0.0.1:10004
export NOT_CRAN=true

Rscript tools/ci-live-tests.R
