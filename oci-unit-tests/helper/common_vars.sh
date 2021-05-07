# shellcheck shell=dash
# shellcheck disable=SC2034

readonly DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
readonly DOCKER_NAMESPACE="${DOCKER_NAMESPACE:-ubuntu}"
readonly DOCKER_PACKAGE="${DOCKER_PACKAGE:-$(basename "$0" | sed 's@\(.*\)_test\.sh@\1@')}"
readonly DOCKER_TAG="${DOCKER_TAG:-edge}"
readonly DOCKER_IMAGE="${DOCKER_IMAGE:-${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_PACKAGE}:${DOCKER_TAG}}"

readonly DOCKER_PREFIX="${DOCKER_PREFIX:-oci_${DOCKER_PACKAGE}_test}"
readonly DOCKER_NETWORK="${DOCKER_NETWORK:-${DOCKER_PREFIX}_net}"

# List of all supported architectures for the images.
readonly SUPPORTED_ARCHITECTURES="amd64 arm64 ppc64el s390x"
# List of all supported registries.
readonly SUPPORTED_REGISTRIES="aws docker"
# List of all supported namespaces.
readonly SUPPORTED_NAMESPACES="ubuntu lts"
