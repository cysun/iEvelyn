# Direct-download release

iEvelyn 1.2 build 3 is intended for direct download outside the Mac App Store.
The release candidate must be signed with a **Developer ID Application**
certificate, use Hardened Runtime, be accepted by Apple's notary service, and
carry a stapled notarization ticket. The app remains sandboxed.

The repository never stores signing certificates, private keys, Apple account
credentials, app-specific passwords, or App Store Connect API keys.

## One-time setup

1. Join the Apple Developer Program and install a valid **Developer ID
   Application** certificate and its private key in the login Keychain.
2. Record the ten-character Apple Developer Team ID.
3. Save notarization credentials to a named Keychain profile. This interactive
   form prompts securely for the app-specific password:

       DEVELOPER_DIR=/Volumes/galfrey/Applications/Xcode.app/Contents/Developer \
       xcrun notarytool store-credentials iEvelyn-notary \
         --apple-id YOUR-APPLE-ID \
         --team-id YOUR-TEAM-ID

   An App Store Connect API key may be used instead; run
   xcrun notarytool store-credentials --help for the installed Xcode syntax.
4. Confirm the prerequisites without exposing key material:

       security find-identity -v -p codesigning
       DEVELOPER_DIR=/Volumes/galfrey/Applications/Xcode.app/Contents/Developer \
         xcrun notarytool history --keychain-profile iEvelyn-notary

Apple's current requirements and rationale are documented in
[Developer ID](https://developer.apple.com/support/developer-id/),
[Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
and
[Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime/).

## Produce a release candidate

Use a new output directory for every candidate:

    IEVELYN_DEVELOPMENT_TEAM=YOUR-TEAM-ID \
    IEVELYN_NOTARY_PROFILE=iEvelyn-notary \
    IEVELYN_RELEASE_ROOT=/Volumes/galfrey/Xcode/Release/iEvelyn-1.2-3-candidate-1 \
    scripts/release-direct-download.sh

The script:

1. refuses to overwrite a previous candidate;
2. requires a valid Developer ID Application identity;
3. archives Release with Hardened Runtime and a secure timestamp;
4. verifies that the packaged identity is version 1.2 build 3;
5. verifies the Developer ID identity, team, Hardened Runtime, secure
   timestamp, and signed entitlements, and rejects `get-task-allow`;
6. submits a ZIP to notarytool and waits for acceptance;
7. staples and validates the ticket;
8. asks Gatekeeper to assess the app; and
9. creates the final iEvelyn-1.2-3-macOS.zip plus its SHA-256 digest.

If notarization fails, use the submission identifier printed by notarytool:

    xcrun notarytool log SUBMISSION-ID \
      --keychain-profile iEvelyn-notary

Do not distribute a candidate whose notarization, stapler, signature, or
Gatekeeper check failed.

## Final release checks

- Download the final ZIP through the actual hosting path so it receives the
  normal quarantine attribute.
- On a clean compatible Mac, expand it, move iEvelyn to Applications, launch
  it, and confirm Gatekeeper identifies Chengyu Sun's signed, notarized app.
- Exercise first launch, file import/export, backup/restore, WebKit reading,
  multiple windows, and relaunch state restoration.
- Compare the published SHA-256 value with shasum -a 256.
- Retain the archive, notarization submission identifier and log, final ZIP,
  checksum, source commit, and manual-test record for the release.
