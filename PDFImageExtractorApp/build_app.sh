#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Figra.app"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$ROOT_DIR/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$BUILD_DIR"

if [[ -f "$ROOT_DIR/../logo.png" && -f "$ROOT_DIR/Resources/generate_app_icon.swift" ]]; then
  (cd "$ROOT_DIR/Resources" && swift generate_app_icon.swift && iconutil -c icns AppIcon.iconset -o AppIcon.icns)
fi

swiftc "$ROOT_DIR/Sources"/*.swift \
  -target arm64-apple-macosx13.0 \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  -framework PDFKit \
  -framework UniformTypeIdentifiers \
  -o "$MACOS/Figra"

cp "$ROOT_DIR/Info.plist" "$CONTENTS/Info.plist"
if [[ -f "$ROOT_DIR/Resources/pdffigures2.jar" ]]; then
  cp "$ROOT_DIR/Resources/pdffigures2.jar" "$RESOURCES/pdffigures2.jar"
fi
if [[ -d "$ROOT_DIR/Resources/jre" ]]; then
  ditto "$ROOT_DIR/Resources/jre" "$RESOURCES/jre"
fi
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi
if [[ -f "$ROOT_DIR/Resources/AppIcon.ico" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.ico" "$RESOURCES/AppIcon.ico"
fi
if [[ -f "$ROOT_DIR/Resources/logo.png" ]]; then
  cp "$ROOT_DIR/Resources/logo.png" "$RESOURCES/logo.png"
fi
chmod +x "$MACOS/Figra"
if [[ -f "$RESOURCES/jre/bin/java" ]]; then
  chmod +x "$RESOURCES/jre/bin/java"
fi

echo "$APP_DIR"
