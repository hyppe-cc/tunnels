#!/bin/zsh
# Publishes a new version: scripts/release.sh 1.1.0
# Creates and pushes the tag; the GitHub Action builds, creates the release and updates Homebrew.
set -euo pipefail
cd "${0:A:h}/.."

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: scripts/release.sh X.Y.Z   (latest: $(git describe --tags --abbrev=0 2>/dev/null || echo none))" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "There are uncommitted changes. Commit them before releasing." >&2
  exit 1
fi

git push origin main
git tag "v$VERSION"
git push origin "v$VERSION"

echo "Releasing v$VERSION… follow progress with:  gh run watch"
