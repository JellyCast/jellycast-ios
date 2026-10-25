#!/bin/zsh
# Renders JellyCast/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png from BrandMark.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -parse-as-library -O \
    scripts/render-app-icon.swift \
    JellyCast/Core/DesignSystem/BrandMark.swift \
    JellyCast/Core/DesignSystem/JellyCastColors.swift \
    -o "$build_dir/render-app-icon"
"$build_dir/render-app-icon" JellyCast/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
