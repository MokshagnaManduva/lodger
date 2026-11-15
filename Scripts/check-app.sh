#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# SwiftPM's classic and new build systems put library modules in different places.
if [ -f Engine/.build/debug/LodgerEngine.o ]; then
  modules=Engine/.build/debug
  objects=(Engine/.build/debug/LodgerEngine.o)
else
  modules=Engine/.build/debug/Modules
  objects=(Engine/.build/debug/LodgerEngine.build/*.o)
fi
mkdir -p build
swiftc -I "$modules" "${objects[@]}" \
  Engine/Sources/lodger/Preferences.swift Engine/Sources/lodger/AppController.swift \
  Engine/Sources/lodger/SettingsWindow.swift Engine/Sources/lodger/MenuBar.swift \
  Engine/Sources/lodger/UpdateChecker.swift Engine/Sources/lodger/UpdateFeed.swift \
  Engine/Sources/lodger/LoginItem.swift \
  Tests/AppChecks/main.swift -o build/app-checks
./build/app-checks "$PWD"
