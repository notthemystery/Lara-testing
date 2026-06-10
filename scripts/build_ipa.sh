#!/bin/bash
set -euo pipefail

rm -rf build/
mkdir -p build

echo "Build Started!"
echo

xcodebuild \
  -project lara1.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64e \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="Config/lara.entitlements" \
  archive \
  -archivePath "$PWD/build/lara.xcarchive"

# -----------------------------------
# FIND APP FROM XCODE OUTPUT
# -----------------------------------

APP_PATH=$(find "$PWD/build/lara.xcarchive/Products/Applications" -name "*.app" -type d | head -n 1)

if [ ! -d "$APP_PATH" ]; then
  echo "Missing .app in archive"
  exit 1
fi

echo "Found app: $APP_PATH"

# -----------------------------------
# COPY TO PROJECT ROOT (NEW BEHAVIOR)
# -----------------------------------

APP_ROOT="$PWD/lara.app"

rm -rf "$APP_ROOT"
cp -R "$APP_PATH" "$APP_ROOT"

echo "Copied app to project root: $APP_ROOT"

# -----------------------------------
# MODIFY INFO.PLIST
# -----------------------------------

plutil -replace UIFileSharingEnabled -bool YES "$APP_ROOT/Info.plist"

# -----------------------------------
# DETECT EXECUTABLE NAME
# -----------------------------------

EXEC_NAME=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$APP_ROOT/Info.plist")

if [ -z "$EXEC_NAME" ]; then
  echo "Failed to read CFBundleExecutable"
  exit 1
fi

echo "Executable: $EXEC_NAME"

# -----------------------------------
# SIGN (ldid)
# -----------------------------------

if ! command -v ldid >/dev/null 2>&1; then
  echo "ERROR: ldid not installed. Install with: brew install ldid" >&2
  exit 1
fi

ldid -SConfig/lara.entitlements "$APP_ROOT/$EXEC_NAME"
#cd "$APP_ROOT"
#mkdir Frameworks
#mv libgrabkernel2.dylib Frameworks/
#mv libxpf.dylib Frameworks/

# -----------------------------------
# BUILD IPA
# -----------------------------------

rm -rf Payload
mkdir -p Payload
cp -R "$APP_ROOT" Payload/

(cd "$PWD" && /usr/bin/zip -qry lara.ipa Payload)

echo
echo "build successful!"
echo "ipa at: $PWD/lara.ipa"
exit 0
