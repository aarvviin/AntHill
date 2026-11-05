#!/bin/zsh
# Builds the app and zips it for a GitHub release.
set -e
cd "$(dirname "$0")/.."
./scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
mkdir -p dist
rm -f dist/AntHill-$VERSION.zip
ditto -c -k --norsrc --keepParent build/AntHill.app dist/AntHill-$VERSION.zip
echo "packaged dist/AntHill-$VERSION.zip"
