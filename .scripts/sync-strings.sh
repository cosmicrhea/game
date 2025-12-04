#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/Library/Developer/Xcode/DerivedData/glass-dzbopunajrifkffhaviyfcmewtip/Build/Intermediates.noindex/Game.build"

scenes_files=()
ui_files=()

# collect all .stringsdata files and bucket them based on /Sources/Scenes/ in the JSON
while IFS= read -r -d '' file; do
  if grep -q '/Sources/Scenes/' "$file"; then
    scenes_files+=("$file")
  else
    ui_files+=("$file")
  fi
done < <(find "$BASE_DIR" -name '*.stringsdata' -print0)

# 1) files that *contain* /Sources/Scenes/ -> UI.xcstrings
if ((${#ui_files[@]})); then
  echo xcrun xcstringstool sync Assets/UI.xcstrings --stringsdata "${ui_files[@]}"
  xcrun xcstringstool sync Assets/UI.xcstrings --stringsdata "${ui_files[@]}"
else
  echo "no UI-related .stringsdata files found (with /Sources/Scenes/)"
fi

# 2) files that *do NOT contain* /Sources/Scenes/ -> Scenes.xcstrings
if ((${#scenes_files[@]})); then
  echo xcrun xcstringstool sync Assets/Scenes.xcstrings --stringsdata "${scenes_files[@]}"
  xcrun xcstringstool sync Assets/Scenes.xcstrings --stringsdata "${scenes_files[@]}"
else
  echo "no Scenes-related .stringsdata files found (without /Sources/Scenes/)"
fi
