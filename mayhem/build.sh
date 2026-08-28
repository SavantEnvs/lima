#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright The Lima Authors
# SPDX-License-Identifier: Apache-2.0
#
# mayhem/build.sh — build lima's LimaYAML config PARSER (pkg/limayaml.Unmarshal)
# as a sanitized libFuzzer binary (OSS-Fuzz Go path: go-118-fuzz-build -libfuzzer
# archive + clang++ ASan link), plus a dynamically-linked KAT oracle probe for
# mayhem/test.sh to run.
#
# Runs inside the commit image (GO mayhem/Dockerfile) as `mayhem` in /mayhem.
# GOROOT/GOPATH/GOMODCACHE are pinned by the Dockerfile ENV under /opt/toolchains
# (absolute, $HOME-independent — so the offline PATCH re-run finds the cache).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
#   - This FIRST build (online) fills $GOMODCACHE (go mod tidy + go get shim).
#   - GOPROXY points at the in-image module cache's file proxy FIRST, network
#     LAST, so the offline re-run resolves entirely from the cache; GOFLAGS=-mod=mod
#     + GOSUMDB=off keep go.sum verification local (no sum.golang.org round trip).
#
# HARNESS STAGING (netnew §6 Go): the upstream pkg/limayaml/ dir also holds a
# heavy defaults.go whose package-init calls Must(os.UserHomeDir()) /
# Must(user.Current()) and pulls a large transitive dep tree, plus a full test
# suite. We instead stage a MINIMAL, self-contained copy of the ONE upstream
# source that defines Unmarshal (marshal.go) + our harness + the KAT export into
# a fresh single-package dir under a leading-underscore path (skipped by
# `go build/test ./...` wildcards and by `go mod tidy`, still loadable by an
# explicit path) and point the builder there. marshal.go references no other
# in-package symbol, so this compiles standalone against the same upstream deps.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}"
: "${CXX:=clang++}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
export CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

# Sanitizers (§6.1): the OSS-Fuzz Go path is ASan-only for the libFuzzer link.
# Honor the knob — an explicit empty SANITIZER_FLAGS yields an un-sanitized build.
: "${SANITIZER_FLAGS=-fsanitize=address}"
export SANITIZER_FLAGS
GO_SAN="-fsanitize=address"
[ -n "${SANITIZER_FLAGS}" ] || GO_SAN=""

# Debug-info contract (§6.2 item 10): gc always emits DWARF4 with no knob, so we
# force the clang-compiled cgo C shims to DWARF3 (CGO_CFLAGS/CGO_CXXFLAGS) AND
# prepend a DWARF3 anchor.o at the final clang++ link so the FIRST .debug_info CU
# (what the gate reads) is DWARF < 4. $GO_DEBUG_FLAGS threads any base pins.
export GO_DEBUG_FLAGS="${GO_DEBUG_FLAGS:--gdwarf-3}"
export CGO_CFLAGS="${CGO_CFLAGS:-} ${GO_DEBUG_FLAGS}"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:-} ${GO_DEBUG_FLAGS}"

# Resolve modules offline-first from the in-image cache; network only as fallback.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOSUMDB="${GOSUMDB:-off}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"

cd "$SRC"
go version

TARGET="fuzz_limayaml"
STAGE="$SRC/_mayhem_harness/limayaml"

# ── Stage a minimal single-package copy: marshal.go (defines Unmarshal) + harness + KAT ──
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$SRC/pkg/limayaml/marshal.go"      "$STAGE/marshal.go"
cp "$SRC/mayhem/harness_limayaml.go.src" "$STAGE/harness_limayaml.go"
cp "$SRC/mayhem/kat_export.go.src"       "$STAGE/kat_export.go"

# ── Module graph: tidy FIRST, then add the go-118-fuzz-build /testing shim ─────
# (order matters — a trailing `go mod tidy` would prune the shim, netnew §6 Go).
# Reference the shim by the PSEUDO-VERSION the Dockerfile's `go install ...@<commit>`
# already resolved + cached (commit a70c2aa677fa43583571959478decabe02a96cd6). A raw
# commit hash forces a proxy.golang.org round trip to resolve it — fatal on the
# air-gapped PATCH re-run; the pseudo-version resolves straight from the file cache.
GO118_SHIM_VERSION="v0.0.0-20250520111509-a70c2aa677fa"
go mod tidy
go get "github.com/AdamKorcz/go-118-fuzz-build/testing@${GO118_SHIM_VERSION}"

# ── Build the libFuzzer archive from the staged single-package dir ─────────────
mkdir -p "$SRC/mayhem-build"
echo "=== go-118-fuzz-build $TARGET (func FuzzLimaYAML) ==="
go-118-fuzz-build -func FuzzLimaYAML -o "$SRC/mayhem-build/$TARGET.a" ./_mayhem_harness/limayaml

# ── DWARF3 anchor FIRST, then clang++ ASan+fuzzer link ─────────────────────────
printf 'int __mayhem_dwarf3_anchor;\n' > "$SRC/mayhem-build/anchor.c"
$CC $GO_DEBUG_FLAGS -c "$SRC/mayhem-build/anchor.c" -o "$SRC/mayhem-build/anchor.o"
$CXX $GO_SAN $LIB_FUZZING_ENGINE \
     "$SRC/mayhem-build/anchor.o" "$SRC/mayhem-build/$TARGET.a" -o "/mayhem/$TARGET"
echo "built /mayhem/$TARGET"

# ── KAT oracle probe: dynamically-linked (cgo) so the sabotage shim can neuter it ─
export CGO_ENABLED=1
go build -o /mayhem/lima_kat ./mayhem/kat
file /mayhem/lima_kat | grep -q 'dynamically linked' \
  || { echo "FATAL: /mayhem/lima_kat is not dynamically linked — oracle would be reward-hackable"; exit 1; }
echo "built /mayhem/lima_kat (dynamically linked)"

echo "build.sh complete"
