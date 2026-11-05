#!/bin/sh
# Builds inst/descriptors/google-rpc.binpb, the descriptor set zugrpc decodes
# grpc-status-details-bin with (design §6.5, §12). Run from the package root:
#
#   sh tools/gen-descriptors.sh
#
# It needs curl and protoc. The googleapis commit is pinned, so the output
# changes only when the pin or protoc's serialisation does; the SHA-256 of
# the result is committed beside it and checked by the tests.
set -eu

GOOGLEAPIS_COMMIT=02362883cd16428e5f57fa60ca8d8f60dafcdba7
FILES="google/rpc/status.proto google/rpc/error_details.proto google/rpc/code.proto"
OUT=inst/descriptors/google-rpc.binpb

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for f in $FILES; do
  mkdir -p "$tmp/$(dirname "$f")"
  curl -fsSL -o "$tmp/$f" \
    "https://raw.githubusercontent.com/googleapis/googleapis/$GOOGLEAPIS_COMMIT/$f"
done

mkdir -p "$(dirname "$OUT")"
# No --include_imports: the imports are well-known types, which every
# zuproto pool already holds.
protoc --proto_path="$tmp" --descriptor_set_out="$OUT" $FILES

if command -v sha256sum >/dev/null 2>&1; then
  sum=$(sha256sum "$OUT" | cut -d' ' -f1)
else
  sum=$(shasum -a 256 "$OUT" | cut -d' ' -f1)
fi
echo "$sum  google-rpc.binpb" > "$OUT.sha256"
echo "wrote $OUT ($sum) with $(protoc --version), googleapis $GOOGLEAPIS_COMMIT"
