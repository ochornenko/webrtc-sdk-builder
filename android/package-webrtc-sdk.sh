#!/usr/bin/env bash
set -e

# This script packages the copied webrtc folder on the host into a release zip.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEBRTC_DIR="$SCRIPT_DIR/webrtc"
ZIP_NAME="libwebrtc-android-m148.zip"

if [ ! -d "$WEBRTC_DIR" ]; then
    echo "❌ Error: '$WEBRTC_DIR' directory not found!"
    echo "Please run build-webrtc-android.sh first to build and copy the SDK to the host."
    exit 1
fi

echo "🗜️ Creating release zip..."
cd "$SCRIPT_DIR"
# Remove old zip if it exists
rm -f "$ZIP_NAME"
zip -r "$ZIP_NAME" webrtc/
cd - > /dev/null

echo "🎉 Packaging complete!"
echo "✅ Release zip created at: $SCRIPT_DIR/$ZIP_NAME"
