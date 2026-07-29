Build WebRTC libs for Android (in Docker) and iOS (natively on macOS)

---

## Table of Contents

- [Android](#android)
  - [Prerequisites](#prerequisites)
  - [1. Start the container](#1-start-the-container)
  - [2. Install dependencies (first time only)](#2-install-dependencies-first-time-only)
  - [3. Set git identity (required by depot_tools)](#3-set-git-identity-required-by-depot_tools)
  - [4. Build WebRTC](#4-build-webrtc)
  - [5. Package the SDK (Zip)](#5-package-the-sdk-zip)
  - [Notes](#notes)
- [iOS](#ios)
  - [Prerequisites](#prerequisites-1)
  - [1. Set git identity (required by depot_tools)](#1-set-git-identity-required-by-depot_tools-1)
  - [2. Build WebRTC](#2-build-webrtc-1)
  - [3. Package the SDK](#3-package-the-sdk-1)

---

## Android

Builds WebRTC M148 (`refs/branch-heads/7778`) as `libwebrtc.a` for `armeabi-v7a`, `arm64-v8a`, `x86`, and `x86_64`.

### Prerequisites

- Docker Desktop
- Android NDK **21.4.7075529** installed via Android Studio (located at `~/Library/Android/sdk/ndk/21.4.7075529`)

### 1. Start the container

```sh
cd android/
docker compose up -d
docker exec -it webrtc-android-builder /bin/bash
```

### 2. Install dependencies (first time only)

Inside the container:

```sh
apt update && apt install -y \
  git python3 curl pkg-config unzip zip gnupg flex bison \
  gperf build-essential libnss3-tools python3-setuptools python3-venv \
  openjdk-11-jdk ninja-build clang nodejs npm rsync file
```

### 3. Set git identity (required by depot_tools)

```sh
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
```

### 4. Build WebRTC

```sh
chmod +x /workspace/build-webrtc-android.sh
/workspace/build-webrtc-android.sh
```

This will:
- Clone `depot_tools`
- Fetch the WebRTC source (~20 GB, first run only)
- Check out M148 and run `gclient sync`
- Apply required patches (thin archive, libunwind linker fix)
- Build `libwebrtc.a` for all 4 architectures
- Copy public headers and static libraries into `android/webrtc/` on the host

Source and build output are stored in a named Docker volume (`webrtc-root-volume`) and persist across container restarts.

### 5. Package the SDK (Zip)

```sh
chmod +x /workspace/package-webrtc-sdk.sh
/workspace/package-webrtc-sdk.sh
```

This will package the copied `webrtc` folder on the host into a release zip file:

```
android/
  webrtc/          ← public headers and libraries
    api/           ← public headers (e.g. api/, rtc_base/, etc.)
    media/
    pc/
    ...
    lib/
      armeabi-v7a/libwebrtc.a
      arm64-v8a/libwebrtc.a
      x86/libwebrtc.a
      x86_64/libwebrtc.a
  libwebrtc-android-m148.zip  ← Release package
```

### Notes

- The NDK is mounted read-only from the Mac host at `/ndk` inside the container
- Only the `android/` directory is mounted as `/workspace` — the host filesystem is otherwise not accessible
- `libwebrtc.a` is more than 100 MB per architecture — use [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository) to distribute binaries rather than committing them to the repository

---

## iOS

Builds WebRTC M148 (`refs/branch-heads/7778`) as `WebRTC.xcframework` for physical devices (`arm64`) and simulators (`arm64`, `x64`).

### Prerequisites

- macOS host machine
- Xcode and Xcode Command Line Tools installed (`xcode-select --install`)

### 1. Set git identity (required by depot_tools)

If you haven't already configured Git globally:

```sh
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
```

### 2. Build WebRTC

Run the build script natively on your macOS host:

```sh
cd ios/
chmod +x build-webrtc-ios.sh
./build-webrtc-ios.sh
```

This will:
- Clone `depot_tools` to `ios/webrtc-ios/depot_tools`
- Fetch the WebRTC iOS source (~20 GB, first run only) to `ios/webrtc-ios/src`
- Check out M148 and run `gclient sync`
- Build the `framework_objc` target for physical devices (`device:arm64`) and simulators (`simulator:arm64`, `simulator:x64`)
- Combine the compiled slices into a unified `WebRTC.xcframework` using `lipo` and `xcodebuild` in the `ios/` directory

### 3. Package the SDK (Zip)

```sh
chmod +x package-webrtc-sdk.sh
./package-webrtc-sdk.sh
```

This will package the `WebRTC.xcframework` into a release zip file `WebRTC-ios-m148.xcframework.zip` in the `ios/` directory.

```
ios/
  WebRTC.xcframework/                  ← Unified framework for device and simulator
  WebRTC-ios-m148.xcframework.zip      ← Release package
```
