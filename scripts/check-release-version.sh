#!/bin/sh
# Release version consistency: VERSION file == package.json == backend
# app-version == CHANGELOG head section, and (when releasing) the tag
# too. Mirrors the release.yml validate logic so the contract runs on
# every push/PR instead of only at tag time. An annotated tag v<version>
# is the only release trigger.
set -eu

cd "$(dirname "$0")/.."

TAG="${1:-}"

# VERSION file: bare semver on a single line, newline-terminated.
grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' VERSION || {
  echo "VERSION must be bare semver (x.y.z)" >&2; exit 1; }
[ "$(tail -c 1 VERSION | wc -l)" -eq 1 ] || {
  echo "VERSION must end with a newline" >&2; exit 1; }
FILE_VERSION=$(cat VERSION)

ROOT_VERSION=$(node -p "require('./package.json').version")
BACKEND_VERSION=$(sed -n 's/.*(define app-version "\([^"]*\)").*/\1/p' backend/main.rkt)

echo "VERSION=$FILE_VERSION package.json=$ROOT_VERSION backend=$BACKEND_VERSION tag=${TAG:-none}"

[ -n "$BACKEND_VERSION" ] || { echo "backend/main.rkt has no app-version" >&2; exit 1; }
[ "$FILE_VERSION" = "$ROOT_VERSION" ] || { echo "VERSION != package.json version" >&2; exit 1; }
[ "$ROOT_VERSION" = "$BACKEND_VERSION" ] || { echo "package.json != backend app-version" >&2; exit 1; }

if [ -n "$TAG" ]; then
  case "$TAG" in
    v"$FILE_VERSION") ;;
    *) echo "tag $TAG != v$FILE_VERSION" >&2; exit 1 ;;
  esac
fi
echo "version consistency OK"
