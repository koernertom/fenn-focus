#!/bin/bash
# Builds Fenn Focus from this checkout, puts it into /Applications and opens it.
# Needs Xcode (not only the Command Line Tools). Another folder: INSTALL_DIR=~/Applications ./Scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Fenn Focus needs Xcode to build. Install it from the App Store, open it once, then run this again."
    echo "Already installed? Point the tools at it: sudo xcode-select -s /Applications/Xcode.app"
    exit 1
fi

python3 Scripts/generate_xcodeproj.py >/dev/null
echo "Building Fenn Focus – the first time takes a few minutes …"
xcodebuild -project FennFocus.xcodeproj -scheme FennFocus -configuration Release \
    -derivedDataPath build/Install -skipMacroValidation -skipPackagePluginValidation -quiet build

target="${INSTALL_DIR:-/Applications}"
rm -rf "${target:?}/FennFocus.app"
ditto build/Install/Build/Products/Release/FennFocus.app "$target/FennFocus.app"
echo "Installed to $target/FennFocus.app"
open "$target/FennFocus.app"
