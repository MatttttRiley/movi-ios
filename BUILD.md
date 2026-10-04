# Building the Movi IPA on a Mac

You need: a Mac with Xcode 16 or newer (free from the Mac App Store).

## Easiest way (Terminal, no signing headaches)

1. Unzip this folder and open Terminal in it.
2. Run:

```bash
xcodebuild \
  -project Movi.xcodeproj \
  -scheme Movi \
  -configuration Release \
  -derivedDataPath build \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build
```

3. Package the IPA:

```bash
APP_PATH="build/Build/Products/Release-iphoneos/Movi.app"
rm -rf Payload Movi-unsigned.ipa
mkdir Payload
cp -R "$APP_PATH" Payload/
zip -r -y Movi-unsigned.ipa Payload
```

4. Send `Movi-unsigned.ipa` back. It installs with Sideloadly, which
   re-signs it on the user's own computer with their Apple ID.

## What this app is

Native SwiftUI iOS app (iOS 16+, iPhone). No web views — native UI plus
Apple's AVPlayer. It talks to the Movi server's JSON API at
https://movi.byethost6.com for library data, and supports offline downloads.
