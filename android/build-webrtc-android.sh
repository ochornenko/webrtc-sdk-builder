#!/bin/bash

# https://getstream.io/resources/projects/webrtc/library/android/

# ./build-webrtc-android.sh

set -e

# === Configuration ===
WEBRTC_ROOT="$HOME/webrtc-android"
NDK_PATH="/ndk"
BUILD_TYPE="release"  # or "debug"
WEBRTC_TAG="refs/branch-heads/7778"  # WebRTC m148
DEPOT_TOOLS="$WEBRTC_ROOT/depot_tools"

export ANDROID_NDK_ROOT="$NDK_PATH"
export ANDROID_NDK_HOME="$NDK_PATH"

ARCHS=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")
declare -A GN_ARCH_MAP=( ["armeabi-v7a"]="arm" ["arm64-v8a"]="arm64" ["x86"]="x86" ["x86_64"]="x64" )

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
  echo "🌐 Fetching WebRTC (first time)..."
  fetch --nohooks webrtc_android
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

# disable THIN archives
# 1. open /root/webrtc-android/src/build/config/compiler/BUILD.gn and in "thin_archive" to comment "arflags = [ "-T" ]"":
sed -i.bak '/^config("thin_archive") {/,/^}/s/^\([[:space:]]*\)arflags = \[ "-T" \]/\1# arflags = [ "-T" ]/' build/config/compiler/BUILD.gn

# OPTIONAL (just to make it clear to future readers): 
# 2. open /root/webrtc-android/src/build/config/BUILDCONFIG.gn and remove the line:
#  "//build/config/compiler:thin_archive",

# Fix _Unwind_Backtrace linker errors (https://issues.webrtc.org/issues/42223745#comment9)
# 1. Add //build/config:common_deps to libunwind visibility
python3 - <<'EOF'
import re
path = "buildtools/third_party/libunwind/BUILD.gn"
with open(path) as f:
    content = f.read()
if '"//build/config:common_deps"' not in content:
    content = re.sub(
        r'(source_set\("libunwind"\) \{.*?visibility = \[)([^\]]+?)(\s*\])',
        r'\1\2, "//build/config:common_deps"\3',
        content,
        count=1,
        flags=re.DOTALL
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ Patched buildtools/third_party/libunwind/BUILD.gn")
else:
    print("⏭️  buildtools/third_party/libunwind/BUILD.gn already patched")
EOF

# 2. Add libunwind to common_deps when use_custom_libcxx=false
python3 - <<'EOF'
import re
path = "build/config/BUILD.gn"
with open(path) as f:
    content = f.read()
if '//buildtools/third_party/libunwind' not in content:
    content = re.sub(
        r'(if \(use_custom_libcxx\) \{[^}]*public_deps \+= \[ "//buildtools/third_party/libc\+\+" \][^}]*\})',
        r'\1 else {\n    public_deps += [ "//buildtools/third_party/libunwind" ]\n  }',
        content,
        count=1
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ Patched build/config/BUILD.gn")
else:
    print("⏭️  build/config/BUILD.gn already patched")
EOF

# === Loop over architectures ===
for ARCH in "${ARCHS[@]}"; do
  GN_ARCH="${GN_ARCH_MAP[$ARCH]}"
  OUT_DIR="out_android_${ARCH}"

  echo "⚙️ Generating GN config for ${ARCH}..."

  IS_DEBUG=false
  if [ "${BUILD_TYPE,,}" == "debug" ]; then
    IS_DEBUG=true
  fi

  # Why we need use_custom_libcxx=false 
  # https://stackoverflow.com/questions/77872602/build-webrtc-on-linux-using-host-libc

  gn gen "$OUT_DIR" --args="
    target_os=\"android\"
    target_cpu=\"$GN_ARCH\"
    is_debug=$IS_DEBUG
    use_custom_libcxx=false
    rtc_include_tests=false
    use_rtti=true
    android_static_analysis=\"off\"
    dcheck_always_on=true
  "

  echo "🔨 Building WebRTC for $ARCH..."
  ninja -C "$OUT_DIR" webrtc

  echo "✅ Done building for $ARCH: output in $OUT_DIR"
done

# === Packaging SDK ===
echo ""
echo "📦 Packaging WebRTC static libs and headers..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/webrtc"

# Clean up previous webrtc folder
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy headers (.h and .inc files recursively)
echo "📂 Copying public headers..."
HEADER_DIRS=(
  "api"
  "audio"
  "call"
  "common_audio"
  "common_video"
  "logging"
  "media"
  "modules"
  "net"
  "p2p"
  "pc"
  "rtc_base"
  "sdk"
  "stats"
  "system_wrappers"
  "third_party/abseil-cpp/absl"
  "video"
)

RSYNC_SOURCES=()
for DIR in "${HEADER_DIRS[@]}"; do
    RSYNC_SOURCES+=("$WEBRTC_ROOT/src/$DIR")
done

rsync -a --include='*/' --include='*.h' --include='*.inc' --exclude='*' \
  "${RSYNC_SOURCES[@]}" \
  "$OUTPUT_DIR/"

# Copy static libraries
echo "📂 Copying static libraries..."
for ARCH in "${ARCHS[@]}"; do
    DEST_LIB="$OUTPUT_DIR/lib/$ARCH"
    mkdir -p "$DEST_LIB"
    echo "  Processing $ARCH..."
    cp "$WEBRTC_ROOT/src/out_android_${ARCH}/obj/libwebrtc.a" "$DEST_LIB/libwebrtc.a"
done

echo "🎉 All builds and copying complete!"
echo "✅ SDK copied to host at: $OUTPUT_DIR"
