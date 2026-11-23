<!--
SPDX-FileCopyrightText: 2019-Present Christian Kußowski
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# FluffyChat

A cross-platform client built with [Flutter](https://flutter.dev).

## Prerequisites

- [Flutter](https://flutter.dev) SDK
- [Rust](https://www.rust-lang.org/tools/install) toolchain

## Getting started

1. Clone the repository and enter the project directory:
   ```sh
   git clone <repository-url>
   cd fluffychat
   ```

2. Fetch dependencies:
   ```sh
   flutter pub get
   ```

3. Run in debug mode:
   ```sh
   flutter run
   ```

## Building

### Android

```sh
flutter build apk
```

### iOS / iPadOS

Requires a Mac with Xcode installed and configured for Xcode-managed app signing.

Set the optional environment variables as needed, then run the build script:

- `FLUFFYCHAT_NEW_TEAM`: Apple Developer team ID used for signing
- `FLUFFYCHAT_NEW_GROUP`: App ID group prefix (e.g. `com.example.app`)
- `FLUFFYCHAT_INSTALL_IPA`: set to `1` to install the resulting IPA on connected devices

```sh
./scripts/build-ios.sh
```

### Web

```sh
./scripts/prepare-web.sh   # installs Vodozemac
flutter build web --release
```

A `config.json` can be served at the same path as the built web app for runtime
configuration. An example is available at `config.sample.json`; only set the
values you actually need.

### Desktop (Linux, Windows, macOS)

Enable Flutter desktop support first: <https://flutter.dev/desktop>

Linux additional dependencies:

```sh
sudo apt install libjsoncpp1 libsecret-1-dev libsecret-1-0 librhash0 libwebkit2gtk-4.0-dev lld
```

Build with one of:

```sh
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

## Firebase Cloud Messaging (optional)

```sh
./scripts/add-firebase-messaging.sh
```

## Configuration and MDM

Configuration is supported via MDM on Android & iOS and via a `config.json`
file on web. The Android MDM configuration is declared in
`/android/app/src/main/res/xml/app_restrictions.xml`. See `config.sample.json`
for an example.

## Integration tests

Requires Docker. Prepare the test environment before each run:

```sh
./scripts/prepare_integration_test.sh
flutter test integration_test/mobile_test.dart
```
