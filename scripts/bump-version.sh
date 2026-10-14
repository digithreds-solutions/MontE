#!/usr/bin/env bash
# ==============================================================================
# scripts/bump-version.sh
# Bumps semantic versions for Mont-E
# Usage:
#   ./scripts/bump-version.sh major     # 2.0.0 -> 3.0.0
#   ./scripts/bump-version.sh minor     # 2.0.0 -> 2.1.0
#   ./scripts/bump-version.sh patch     # 2.0.0 -> 2.0.1
#   ./scripts/bump-version.sh 2.5.0     # Explicit version set
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION_FILE="$ROOT_DIR/VERSION"
CURRENT_VERSION="2.0.0"
if [[ -f "$VERSION_FILE" ]]; then
  CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
fi

BUMP_TYPE="${1:-patch}"

# Parse semver parts
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR="${MAJOR:-2}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

# Strip any pre-release suffix from PATCH if present
PATCH="${PATCH%%-*}"

case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
    ;;
  patch)
    PATCH=$((PATCH + 1))
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
    ;;
  *)
    # Custom version passed directly
    if [[ "$BUMP_TYPE" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
      NEW_VERSION="$BUMP_TYPE"
    else
      echo "Error: Invalid bump type or version '$BUMP_TYPE'. Use 'major', 'minor', 'patch', or a valid semver like '2.1.0'." >&2
      exit 1
    fi
    ;;
esac

echo "==> Bumping version: $CURRENT_VERSION -> $NEW_VERSION"

# 1. Write root VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"

# Helper to update Info.plist files
update_plist_version() {
  local plist_path="$1"
  if [[ -f "$plist_path" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$plist_path" 2>/dev/null || \
      sed -i '' -E "s/<key>CFBundleShortVersionString<\/key>[[:space:]]*<string>[^<]+<\/string>/<key>CFBundleShortVersionString<\/key>\n    <string>$NEW_VERSION<\/string>/" "$plist_path"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$plist_path" 2>/dev/null || \
      sed -i '' -E "s/<key>CFBundleVersion<\/key>[[:space:]]*<string>[^<]+<\/string>/<key>CFBundleVersion<\/key>\n    <string>$NEW_VERSION<\/string>/" "$plist_path"
  fi
}

# 2. Update Plist files
update_plist_version "$ROOT_DIR/Info.plist"
update_plist_version "$ROOT_DIR/Sources/Monte/Resources/Info.plist"

# 3. Update Packages/README.md
if [[ -f "$ROOT_DIR/Packages/README.md" ]]; then
  cat <<EOF > "$ROOT_DIR/Packages/README.md"
# Mont-E Distribution Packages (v$NEW_VERSION)

This directory holds local compiled installer DMGs for Mont-E.
Official release binaries are hosted on [GitHub Releases](https://github.com/digithreds-solutions/MontE/releases).

### Built Artifacts:
- **\`Monte-${NEW_VERSION}.dmg\`**: Mont-E — Developer Hardware, Battery & SSD Swap Optimizer for Apple Silicon & Intel macOS.
EOF
fi

echo "==> Successfully upgraded Mont-E to version $NEW_VERSION"
echo "$NEW_VERSION"
