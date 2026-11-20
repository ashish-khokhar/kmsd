#!/usr/bin/env bash
#
# Build the kmsd (vlmcsd) Docker image for multiple CPU architectures using
# Docker Buildx, mirroring the GitHub Actions workflow (.github/workflows/build-images.yaml).
#
# By default it builds linux/amd64 and linux/arm64. Because a single local Docker
# image can only hold one architecture, a multi-arch build is either:
#   * pushed to a registry as a multi-arch manifest  (--push), or
#   * built to the cache only, to validate every arch (default, no output).
# Use --load to load a single-arch image into your local Docker for testing.
#
# Usage:
#   ./build-all-arch.sh [options]
#
# Options:
#   -i, --image NAME       Image repository       (default: $IMAGE or ashishkhokhar/kmsd)
#   -t, --tag  TAG         Image tag              (default: $TAG   or latest)
#   -r, --registry REG     Registry prefix        (default: $REGISTRY or docker.io)
#   -p, --platform LIST    Comma-separated arches  (default: $PLATFORMS or linux/amd64,linux/arm64)
#       --push             Push the multi-arch manifest to the registry
#       --load             Load the image into local Docker (forces one platform)
#       --qemu             Register QEMU/binfmt emulators first (needed for cross-arch on Linux)
#       --no-cache         Build without the layer cache
#   -h, --help             Show this help and exit
#
# Examples:
#   ./build-all-arch.sh                       # build all arches (validate only)
#   ./build-all-arch.sh --push                # build + push multi-arch :latest
#   ./build-all-arch.sh --load                # load a local single-arch image to test
#   ./build-all-arch.sh --qemu --push -t v1   # install emulators, then build + push :v1

set -euo pipefail

# Always run from the repository root (where the Dockerfile and build context live).
cd "$(dirname "$(readlink -f "$0")")"

IMAGE="${IMAGE:-ashishkhokhar/kmsd}"
TAG="${TAG:-latest}"
REGISTRY="${REGISTRY:-docker.io}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="kmsd-multiarch"

PUSH=0
LOAD=0
SETUP_QEMU=0
NO_CACHE=0

die() { echo "Error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--image)    IMAGE="${2?missing value for $1}"; shift 2;;
    -t|--tag)      TAG="${2?missing value for $1}"; shift 2;;
    -r|--registry) REGISTRY="${2?missing value for $1}"; shift 2;;
    -p|--platform) PLATFORMS="${2?missing value for $1}"; shift 2;;
    --push)        PUSH=1; shift;;
    --load)        LOAD=1; shift;;
    --qemu)        SETUP_QEMU=1; shift;;
    --no-cache)    NO_CACHE=1; shift;;
    -h|--help)     awk 'NR>=2{ if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0;;
    *)             die "unknown argument: $1 (use --help)";;
  esac
done

[[ $PUSH -eq 1 && $LOAD -eq 1 ]] && die "--push and --load are mutually exclusive."

command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH."
docker buildx version >/dev/null 2>&1 || die "docker buildx is not available (needs Docker 19.03+ with Buildx)."

# Compose the fully-qualified image reference.
REF="${REGISTRY:+$REGISTRY/}${IMAGE}:${TAG}"

# Optionally register QEMU emulators so the host can build foreign architectures.
if [[ $SETUP_QEMU -eq 1 ]]; then
  echo ">> Registering QEMU/binfmt emulators ..."
  docker run --privileged --rm tonistiigi/binfmt:latest --install all
fi

# Ensure a Buildx builder with the docker-container driver exists (required for
# multi-platform builds; the default 'docker' driver cannot build >1 platform).
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  echo ">> Creating Buildx builder '$BUILDER' ..."
  docker buildx create --name "$BUILDER" --driver docker-container --use >/dev/null
else
  docker buildx use "$BUILDER"
fi
docker buildx inspect --bootstrap >/dev/null

# Decide the output mode.
OUTPUT_ARGS=()
if [[ $PUSH -eq 1 ]]; then
  OUTPUT_ARGS+=(--push)
elif [[ $LOAD -eq 1 ]]; then
  # --load can only import a single platform into the local Docker image store.
  if [[ "$PLATFORMS" == *,* ]]; then
    PLATFORMS="linux/$(docker version -f '{{.Server.Arch}}' 2>/dev/null || uname -m)"
    echo ">> --load supports one platform; building for host platform: $PLATFORMS"
  fi
  OUTPUT_ARGS+=(--load)
else
  echo ">> No --push/--load given: building all platforms to cache (validation only)."
  echo "   Re-run with --push to publish the multi-arch manifest, or --load to test locally."
fi

[[ $NO_CACHE -eq 1 ]] && OUTPUT_ARGS+=(--no-cache)

echo ">> Building $REF for: $PLATFORMS"
set -x
docker buildx build \
  --platform "$PLATFORMS" \
  --tag "$REF" \
  --file Dockerfile \
  "${OUTPUT_ARGS[@]}" \
  .
set +x

echo ">> Done: $REF ($PLATFORMS)"
