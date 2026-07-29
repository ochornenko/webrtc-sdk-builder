#!/bin/bash

# Package the WebRTC.xcframework into a zip file.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XCF_DIR="$SCRIPT_DIR/WebRTC.xcframework"
XCF_ZIP="$SCRIPT_DIR/WebRTC-ios-m148.xcframework.zip"

if [ ! -d "$XCF_DIR" ]; then
  echo "❌ Missing $XCF_DIR — run build-webrtc-ios.sh first."
  exit 1
fi

echo "📦 Packaging WebRTC.xcframework into a zip file..."
rm -f "$XCF_ZIP"

cd "$SCRIPT_DIR"
zip -qr "$XCF_ZIP" "$(basename "$XCF_DIR")"
cd - > /dev/null

echo "✅ XCFramework zip created at: $XCF_ZIP"
