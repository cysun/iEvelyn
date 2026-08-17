#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/iEvelyn.xcodeproj"
SCHEME="iEvelyn"
EXPECTED_VERSION="1.1"
EXPECTED_BUILD="2"

: "\${IEVELYN_DEVELOPMENT_TEAM:?Set IEVELYN_DEVELOPMENT_TEAM to the Apple Developer Team ID.}"
: "\${IEVELYN_NOTARY_PROFILE:?Set IEVELYN_NOTARY_PROFILE to a validated notarytool Keychain profile.}"

DEVELOPER_DIR="\${DEVELOPER_DIR:-/Volumes/galfrey/Applications/Xcode.app/Contents/Developer}"
SOURCE_PACKAGES_DIR="\${IEVELYN_SOURCE_PACKAGES_DIR:-/Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step3-SourcePackages}"
DERIVED_DATA_DIR="\${IEVELYN_RELEASE_DERIVED_DATA:-/Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step16-Release}"
RELEASE_ROOT="\${IEVELYN_RELEASE_ROOT:-/Volumes/galfrey/Xcode/Release/iEvelyn-1.1-2}"
ARCHIVE_PATH="$RELEASE_ROOT/iEvelyn.xcarchive"
SUBMISSION_ZIP="$RELEASE_ROOT/iEvelyn-notarization.zip"
FINAL_ZIP="$RELEASE_ROOT/iEvelyn-1.1-2-macOS.zip"
SIGNED_ENTITLEMENTS="$RELEASE_ROOT/iEvelyn-signed-entitlements.plist"

export DEVELOPER_DIR

if [[ -e "$RELEASE_ROOT" ]]; then
    print -u2 "Release output already exists: $RELEASE_ROOT"
    print -u2 "Choose a new IEVELYN_RELEASE_ROOT so a prior candidate is never overwritten."
    exit 1
fi

if ! security find-identity -v -p codesigning |
    /usr/bin/grep -F "Developer ID Application" >/dev/null; then
    print -u2 "No valid Developer ID Application identity is available in the login Keychain."
    exit 1
fi

mkdir -p "$RELEASE_ROOT"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$IEVELYN_DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/iEvelyn.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
ACTUAL_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
ACTUAL_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")

if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" || "$ACTUAL_BUILD" != "$EXPECTED_BUILD" ]]; then
    print -u2 "Archive identity is Version $ACTUAL_VERSION ($ACTUAL_BUILD), expected Version $EXPECTED_VERSION ($EXPECTED_BUILD)."
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNING_DETAILS=$(codesign --display --verbose=4 "$APP_PATH" 2>&1)
print "$SIGNING_DETAILS"
if [[ "$SIGNING_DETAILS" != *"Authority=Developer ID Application:"* ||
      "$SIGNING_DETAILS" != *"TeamIdentifier=$IEVELYN_DEVELOPMENT_TEAM"* ||
      "$SIGNING_DETAILS" != *"runtime"* ||
      "$SIGNING_DETAILS" != *"Timestamp="* ]]; then
    print -u2 "Archive is missing the expected Developer ID identity, team, Hardened Runtime, or secure timestamp."
    exit 1
fi

codesign --display --entitlements :- "$APP_PATH" > "$SIGNED_ENTITLEMENTS"
plutil -p "$SIGNED_ENTITLEMENTS"
if /usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" \
    "$SIGNED_ENTITLEMENTS" >/dev/null 2>&1; then
    print -u2 "Release entitlements must not contain com.apple.security.get-task-allow."
    exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ZIP"
xcrun notarytool submit "$SUBMISSION_ZIP" \
    --keychain-profile "$IEVELYN_NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ZIP"
shasum -a 256 "$FINAL_ZIP"

print "Notarized direct-download candidate: $FINAL_ZIP"
