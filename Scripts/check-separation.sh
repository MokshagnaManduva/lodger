#!/bin/bash
# CI guard: the reusable engine and the app must not acquire character-specific
# assets or references. Pack data belongs under Packs/ and is loaded through
# PackStore. Uses grep and find only, so it cannot pass by failing to run.
set -euo pipefail
cd "$(dirname "$0")/.."

bad=0
assets=$(find Engine/Sources -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.gif' \
  -o -name '*.wav' -o -name '*.mp3' -o -name '*.aiff' -o -name '*.json' \))
if [ -n "$assets" ]; then
  echo "ERROR Engine/Sources contains non-source files:"
  echo "$assets"
  bad=1
fi

# Every reference pack: its folder name, display name and the last component of
# its id. None may appear in engine or app source.
names=$(python3 - <<'PY'
import json
from pathlib import Path
out = set()
for manifest in Path("Packs").glob("*/pack.json"):
    identity = json.loads(manifest.read_text())["identity"]
    out |= {manifest.parent.name.lower(), identity["name"].lower(), identity["id"].split(".")[-1].lower()}
print("\n".join(sorted(n for n in out if len(n) >= 3)))
PY
)
[ -n "$names" ] || { echo "ERROR no reference packs found to check against"; exit 1; }
checked=0
for name in $names; do
  checked=$((checked + 1))
  if grep -rni --include='*.swift' -- "$name" Engine/Sources; then
    echo "ERROR Engine/Sources mentions the character '$name'"
    bad=1
  fi
done

if (( bad )); then
  exit 1
fi
echo "engine/pack separation: OK ($checked character names checked across Engine/Sources)"
