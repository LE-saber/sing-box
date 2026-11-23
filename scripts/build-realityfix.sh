#!/usr/bin/env bash
# Build sing-box 1.14.4 with the narrow MetaCubeX/utls PR #6 fix.
# The upstream source and its go.mod/go.sum are never modified in-place.
set -euo pipefail
umask 022

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"
BASE_SHA="c005f35300ce76427dc285481ec5695f5b179cd2"
if ! git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null ||
   ! git merge-base --is-ancestor "$BASE_SHA" HEAD; then
  echo "ERROR: build branch must descend from official sing-box v1.14.4 ($BASE_SHA)" >&2
  exit 1
fi
if ! grep -Eq '^[[:space:]]*github.com/metacubex/utls v1.8.7$' go.mod; then
  echo "ERROR: expected unchanged upstream metacubex/utls v1.8.7" >&2
  exit 1
fi

OUT="${OUTPUT_DIR:-$REPO/dist/realityfix}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SRC="$TMP/source"
UTLS="$TMP/utls"
mkdir -p "$SRC" "$UTLS"

# Use only committed source to make CI and local builds equivalent.
git archive --format=tar HEAD | tar -xf - -C "$SRC"
cd "$SRC"
export GOTOOLCHAIN=auto
export GOOS=linux
export GOARCH=amd64
export CGO_ENABLED=0

echo "== Download pinned upstream uTLS =="
go mod download github.com/metacubex/utls@v1.8.7
MODCACHE="$(go env GOMODCACHE)"
cp -a "$MODCACHE/github.com/metacubex/utls@v1.8.7/." "$UTLS/"
chmod -R u+w "$UTLS"

echo "== Apply original MetaCubeX PR #6 (no fuzz) =="
patch -d "$UTLS" -p1 --fuzz=0 < "$SRC/patches/0001-utls-reality-propagate-fallback-fin.patch"
grep -Fq 'cw.CloseWrite()' "$UTLS/reality.go"

echo "== Temporarily replace module only in isolated archive =="
go mod edit -replace "github.com/metacubex/utls=$UTLS"

echo "== REALITY fallback regression =="
cp "$SRC/tests/reality_fallback_close_patch_test.go" "$UTLS/reality_fallback_close_patch_test.go"
(
  cd "$UTLS"
  go test -count=1 -run '^TestRealityFallbackClosePropagated$' -timeout=90s .
)

TAGS="$(cat release/DEFAULT_BUILD_TAGS_OTHERS)"
echo "== Compile/test TLS and VLESS packages =="
go test -count=1 -tags "$TAGS" ./common/tls ./protocol/vless

if [[ "${RUN_UPSTREAM_REALITY_TEST:-0}" == 1 ]]; then
  echo "== Optional upstream REALITY integration (requires Internet to handshake destination) =="
  go test -count=1 -tags "$TAGS" -run '^TestReality$' -timeout=180s ./test
else
  echo "== Skipping upstream TestReality (uses public external host google.com); set RUN_UPSTREAM_REALITY_TEST=1 to enable =="
fi

echo "== Compile Linux amd64 binary =="
LDFLAGS_SHARED="$(cat release/LDFLAGS)"
VERSION="1.14.4-realityfix.1"
go build -trimpath -tags "$TAGS" \
  -ldflags "-X github.com/sagernet/sing-box/constant.Version=$VERSION $LDFLAGS_SHARED -s -w -buildid=" \
  -o "$OUT/sing-box" ./cmd/sing-box
"$OUT/sing-box" version
"$OUT/sing-box" version | grep -Fq "1.14.4-realityfix.1"
(cd "$OUT" && sha256sum sing-box > SHA256SUMS)
echo "DONE: $OUT/sing-box"
