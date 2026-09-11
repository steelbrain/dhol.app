#!/bin/zsh
set -euo pipefail

# Dhol.xcodeproj is generated, not committed. Run this after changing
# project.yml, and before opening the project in Xcode for the first time.

repo_root=${0:A:h:h}
project="$repo_root/Dhol.xcodeproj"
pins="$repo_root/Package.resolved"
project_pins="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if ! command -v xcodegen >/dev/null; then
    echo "xcodegen is not installed: brew install xcodegen" >&2
    exit 1
fi

cd "$repo_root"
xcodegen generate --spec project.yml --project .

# The generated project is ignored by git, so the dependency pins live at the
# repo root and are copied in and back out around resolution.
mkdir -p "${project_pins:h}"
if [[ -f "$pins" ]]; then
    cp "$pins" "$project_pins"
fi
xcodebuild -project "$project" -scheme Dhol -resolvePackageDependencies -skipPackagePluginValidation -quiet
cp "$project_pins" "$pins"
