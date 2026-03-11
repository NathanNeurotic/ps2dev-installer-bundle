#!/usr/bin/env bash
set -Eeuo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$BUNDLE_DIR/install.sh" "$@"
