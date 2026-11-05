#!/bin/zsh
# Builds a universal AntHill.app with just the Command Line Tools.
set -e
cd "$(dirname "$0")/.."
APP=build/AntHill.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 \
    -framework AppKit -framework SwiftUI \
    Sources/*.swift -o build/AntHill-$arch
done
lipo -create build/AntHill-arm64 build/AntHill-x86_64 -output $APP/Contents/MacOS/AntHill
rm build/AntHill-arm64 build/AntHill-x86_64
cp Resources/Info.plist $APP/Contents/Info.plist
codesign --force --sign - $APP
echo "built $APP"
