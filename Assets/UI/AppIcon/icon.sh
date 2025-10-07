#!/usr/bin/env bash

set -euo pipefail

# Resolve script directory so outputs land in Assets/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <icon-image>" >&2
  exit 1
fi

input_icon_path="$1"

# Ensure input exists
if [ ! -f "$input_icon_path" ]; then
  echo "Error: input file not found: $input_icon_path" >&2
  exit 1
fi

# Resolve absolute path for the input
if [[ "$input_icon_path" != /* ]]; then
  input_icon_abs="$(cd "$(dirname "$input_icon_path")" && pwd)/$(basename "$input_icon_path")"
else
  input_icon_abs="$input_icon_path"
fi

# Dependency checks
if ! command -v iconsur >/dev/null 2>&1; then
  echo "Error: iconsur is not installed or not in PATH" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "Error: ImageMagick 'magick' is not installed or not in PATH" >&2
  exit 1
fi

# Work in the Assets directory for consistent outputs
cd "$SCRIPT_DIR"

# 1) Copy to icon.png
cp "$input_icon_abs" "icon.png"

# 2) Generate masked icon using iconsur
iconsur -l -i "$input_icon_abs" -o "icon~masked.png" set /Applications/Safari.app >/dev/null

# 3) Convert main icon to webp
magick "$input_icon_abs" "icon.webp"

# 4) Convert masked icon to webp
magick "icon~masked.png" "icon~masked.webp"

echo "Done: icon.png, icon~masked.png, icon.webp, icon~masked.webp"


