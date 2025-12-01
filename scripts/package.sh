#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CHART_DIR="composio"
MANIFESTS_DIR="$REPO_ROOT/manifests"

if [ ! -f "$CHART_DIR/Chart.yaml" ]; then
  echo "Error: Chart not found at $CHART_DIR/Chart.yaml" >&2
  exit 1
fi

mkdir -p "$MANIFESTS_DIR"

echo "Packaging Helm chart from $CHART_DIR ..."
helm package -u "$CHART_DIR"

# Identify the most recently created composio package in repo root
PKG_FILE="$(ls -t "$REPO_ROOT"/composio-*.tgz | head -n1 || true)"

if [ -z "${PKG_FILE:-}" ] || [ ! -f "$PKG_FILE" ]; then
  echo "Error: Could not find packaged .tgz after helm package" >&2
  exit 1
fi

echo "Moving $(basename "$PKG_FILE") to $MANIFESTS_DIR ..."
mv -f "$PKG_FILE" "$MANIFESTS_DIR"/

echo "Package ready: $MANIFESTS_DIR/$(basename "$PKG_FILE")"


