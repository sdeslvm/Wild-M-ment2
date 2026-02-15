#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "=== Cleaning previous build ==="
rm -rf build 2>/dev/null || true

echo "=== Building project ==="
xcodebuild -scheme WildMoment \
    -configuration Browserstack \
    -sdk iphoneos \
    -derivedDataPath build \
    -project WildMoment.xcodeproj \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    ONLY_ACTIVE_ARCH=NO

echo "=== Creating IPA ==="
APP_PATH="build/Build/Products/Browserstack-iphoneos/WildMoment.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found"
    exit 1
fi

mkdir -p build/Payload
cp -r "$APP_PATH" build/Payload/
cd build
zip -r WildMoment.ipa Payload

echo "=== Done! ==="
echo "IPA: $PROJECT_DIR/build/WildMoment.ipa"
