#!/bin/bash
# CI guard: the reusable engine must not acquire character-specific assets or
# references. Pack data belongs under Packs/ and is loaded through PackStore.
set -euo pipefail
cd "$(dirname "$0")/.."

bad=0
while IFS= read -r file; do
  case "$file" in
    Engine/*)
      echo "ERROR engine contains non-engine file: $file"
      bad=1
      ;;
  esac
done < <(rg --files Engine | rg '\.(png|jpg|jpeg|gif|wav|mp3|aiff|json)$' || true)

if rg -n -i --glob '*.swift' --glob '*.md' 'klien' Engine/Sources/LodgerEngine; then
  echo "ERROR reusable engine contains pack-specific vocabulary"
  bad=1
fi

if (( bad )); then
  exit 1
fi
echo "engine/pack separation: OK"
