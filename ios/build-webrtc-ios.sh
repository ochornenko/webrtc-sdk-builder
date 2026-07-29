#!/bin/bash

# Build WebRTC m148 framework_objc per (environment, arch) slice for iOS.
# Mirrors the official tools_webrtc/ios/build_ios_libs.py flow.
# Runs natively on macOS (Xcode + command-line tools required).
#
#   ./build-webrtc-ios.sh

set -e

# === Configuration ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEBRTC_ROOT="$SCRIPT_DIR/webrtc-ios"
BUILD_TYPE="release"                # release | debug
WEBRTC_TAG="refs/branch-heads/7778" # WebRTC m148
DEPOT_TOOLS="$WEBRTC_ROOT/depot_tools"
IOS_DEPLOYMENT_TARGET="17.0"

# (environment, arch) slices to build.
SLICES=("device:arm64" "simulator:arm64" "simulator:x64")

# === Sanity checks ===
if ! xcode-select -p >/dev/null 2>&1; then
  echo "❌ Xcode command line tools not found. Run: xcode-select --install"
  exit 1
fi

# === Clone depot tools ===
if [ ! -d "$DEPOT_TOOLS" ]; then
  echo "📦 Cloning depot_tools..."
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi

export PATH="$DEPOT_TOOLS:$PATH"

# === Fetch WebRTC source ===
mkdir -p "$WEBRTC_ROOT"
cd "$WEBRTC_ROOT"

if [ ! -d "src" ]; then
  echo "🌐 Fetching WebRTC iOS (first time)..."
  fetch --nohooks webrtc_ios
fi

cd src

# === Checkout specific version (M148) ===
echo "🔁 Checking out WebRTC m148..."
WEBRTC_REF="${WEBRTC_TAG#refs/}"  # e.g. branch-heads/7778
git fetch origin "${WEBRTC_TAG}:refs/remotes/${WEBRTC_REF}"
git checkout -B build "refs/remotes/${WEBRTC_REF}"

# --reset    discards local changes in all managed sub-repos (buildtools, build, third_party/*)
# --force    overrides "nothing to do" caching
# -D         removes stale sub-repos when switching milestones
# --with_branch_heads  required for release branches (deps pinned on branch-heads/*)
gclient sync -D --force --reset --with_branch_heads

echo "🔁 gclient sync done"

IS_DEBUG=false
if [ "$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')" = "debug" ]; then
  IS_DEBUG=true
fi

# === Loop over slices ===
for SLICE in "${SLICES[@]}"; do
  ENV="${SLICE%%:*}"
  ARCH="${SLICE##*:}"
  OUT_DIR="out_${ENV}_${ARCH}"

  echo "⚙️ Generating GN config for env=${ENV} arch=${ARCH}..."

  gn gen "$OUT_DIR" --args="
    target_os=\"ios\"
    target_environment=\"$ENV\"
    target_cpu=\"$ARCH\"
    is_debug=$IS_DEBUG
    is_component_build=false
    rtc_include_tests=false
    ios_enable_code_signing=false
    ios_deployment_target=\"$IOS_DEPLOYMENT_TARGET\"
    rtc_libvpx_build_vp9=false
    rtc_enable_objc_symbol_export=true
    use_lld=true
    enable_dsyms=true
    enable_stripping=true
  "

  echo "🔨 Building //sdk:framework_objc for $ENV/$ARCH..."
  ninja -C "$OUT_DIR" framework_objc

  echo "✅ Done building $ENV/$ARCH → $OUT_DIR"
done

# === Packaging SDK ===
echo ""
echo "📦 Packaging WebRTC into XCFramework..."
STAGING="$WEBRTC_ROOT/src/xcf-staging"
XCF_DIR="$SCRIPT_DIR/WebRTC.xcframework"

rm -rf "$STAGING" "$XCF_DIR"
mkdir -p "$STAGING"

ENVIRONMENTS=("device" "simulator")
archs_for_env() {
  case "$1" in
    device)    echo "arm64" ;;
    simulator) echo "arm64 x64" ;;
  esac
}

XCF_ARGS=()

for ENV in "${ENVIRONMENTS[@]}"; do
  ENV_DIR="$STAGING/$ENV"
  mkdir -p "$ENV_DIR"

  ARCHS=($(archs_for_env "$ENV"))
  FIRST_ARCH="${ARCHS[0]}"
  FIRST_BUILD="$WEBRTC_ROOT/src/out_${ENV}_${FIRST_ARCH}"
  FIRST_FW="$FIRST_BUILD/WebRTC.framework"
  FIRST_DSYM="$FIRST_BUILD/WebRTC.dSYM"

  if [ ! -d "$FIRST_FW" ]; then
    echo "❌ Missing $FIRST_FW — build failed."
    exit 1
  fi

  echo "📦 [$ENV] Copying framework template from $FIRST_ARCH..."
  cp -R "$FIRST_FW" "$ENV_DIR/WebRTC.framework"

  # Lipo all arch dylibs into the framework's WebRTC binary.
  DYLIB_REL="WebRTC.framework/WebRTC"
  OUT_DYLIB="$ENV_DIR/$DYLIB_REL"
  if [ -L "$OUT_DYLIB" ]; then
    # Resolve symlink (macOS-style frameworks use Versions/A/WebRTC).
    LINK_TARGET="$(readlink "$OUT_DYLIB")"
    OUT_DYLIB="$(dirname "$OUT_DYLIB")/$LINK_TARGET"
  fi
  rm -f "$OUT_DYLIB"

  DYLIBS=()
  for ARCH in "${ARCHS[@]}"; do
    DYLIBS+=("$WEBRTC_ROOT/src/out_${ENV}_${ARCH}/$DYLIB_REL")
  done
  echo "🔗 [$ENV] lipo dylibs → $OUT_DYLIB"
  lipo -create "${DYLIBS[@]}" -output "$OUT_DYLIB"

  # Lipo dSYMs if present.
  if [ -d "$FIRST_DSYM" ]; then
    cp -R "$FIRST_DSYM" "$ENV_DIR/WebRTC.dSYM"
    DSYM_REL="WebRTC.dSYM/Contents/Resources/DWARF/WebRTC"
    OUT_DSYM="$ENV_DIR/$DSYM_REL"
    rm -f "$OUT_DSYM"
    DSYMS=()
    for ARCH in "${ARCHS[@]}"; do
      DSYMS+=("$WEBRTC_ROOT/src/out_${ENV}_${ARCH}/$DSYM_REL")
    done
    echo "🔗 [$ENV] lipo dSYM slices..."
    lipo -create "${DSYMS[@]}" -output "$OUT_DSYM"
    XCF_ARGS+=(-framework "$ENV_DIR/WebRTC.framework" -debug-symbols "$ENV_DIR/WebRTC.dSYM")
  else
    XCF_ARGS+=(-framework "$ENV_DIR/WebRTC.framework")
  fi
done

echo "🧱 Creating $XCF_DIR..."
xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "$XCF_DIR"

rm -rf "$STAGING"

echo "🎉 All builds and packaging complete!"
echo "✅ XCFramework created at: $XCF_DIR"
