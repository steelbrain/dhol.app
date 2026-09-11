#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
configuration=${CONFIGURATION:-release}
output_dir="$repo_root/build"
app_dir="$output_dir/Dhol.app"
derived_data="$output_dir/XcodeDerivedData"

case "${configuration:l}" in
    debug) xcode_configuration="Debug" ;;
    release) xcode_configuration="Release" ;;
    *) echo "CONFIGURATION must be debug or release" >&2; exit 2 ;;
esac

"$repo_root/Scripts/generate-project.sh"

# Built with xcodebuild rather than SwiftPM because MLX's Metal shaders need a
# full Xcode toolchain to compile. The project assembles, signs and verifies the
# bundle itself, so all that is left here is to copy the result out.
cd "$repo_root"
xcodebuild \
    -project Dhol.xcodeproj \
    -scheme Dhol \
    -destination "platform=macOS,arch=arm64" \
    -configuration "$xcode_configuration" \
    -derivedDataPath "$derived_data" \
    -skipPackagePluginValidation \
    -quiet \
    build

mkdir -p "$output_dir"
rm -rf "$app_dir"
cp -R "$derived_data/Build/Products/$xcode_configuration/Dhol.app" "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "Built $app_dir"
