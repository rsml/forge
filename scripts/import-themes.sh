#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CATALOG="$SCRIPT_DIR/curated-themes.txt"
DEST_DIR="$REPO_ROOT/Resources/themes"

REPO_URL="https://github.com/mbadolato/iTerm2-Color-Schemes"
PINNED_SHA="267128889e574c224b56084f06d648eb1970ce9c"

# Workspace cleanup
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Cloning mbadolato/iTerm2-Color-Schemes (sparse, pinned to $PINNED_SHA)..."

# Clone without depth so we can checkout an arbitrary commit, sparse to avoid
# downloading the full tree.
git clone --filter=blob:none --no-checkout "$REPO_URL" "$WORKDIR/repo" 2>&1

# Fetch the exact pinned commit and check it out.
git -C "$WORKDIR/repo" fetch --depth=1 origin "$PINNED_SHA"
git -C "$WORKDIR/repo" sparse-checkout init --cone
git -C "$WORKDIR/repo" sparse-checkout set ghostty
git -C "$WORKDIR/repo" checkout FETCH_HEAD

GHOSTTY_DIR="$WORKDIR/repo/ghostty"

# Prepare destination directory.
mkdir -p "$DEST_DIR"
find "$DEST_DIR" -maxdepth 1 -name '*.conf' -delete

# Read catalog and import themes.
missing=()

while IFS= read -r line; do
    # Skip blank lines and comment lines.
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    name="$line"
    src="$GHOSTTY_DIR/$name"
    dst="$DEST_DIR/$name.conf"

    if [[ ! -f "$src" ]]; then
        missing+=("$name")
        continue
    fi

    {
        printf "# Theme: %s\n" "$name"
        printf "# Source: %s\n" "$REPO_URL"
        printf "# Pinned commit: %s\n" "$PINNED_SHA"
        printf "# Imported by scripts/import-themes.sh — do not edit by hand.\n"
        printf "\n"
        cat "$src"
    } > "$dst"

done < "$CATALOG"

# Report any missing themes.
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: the following themes were not found in the upstream ghostty/ directory:" >&2
    for m in "${missing[@]}"; do
        echo "  $m" >&2
    done
    exit 1
fi

count="$(find "$DEST_DIR" -maxdepth 1 -name '*.conf' | wc -l | tr -d ' ')"
echo "Successfully imported $count themes to $DEST_DIR"
