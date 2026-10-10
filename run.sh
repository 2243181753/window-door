#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
# Camera access requires a bundle with NSCameraUsageDescription.
./build.sh
exec "$PWD/视窗之门.app/Contents/MacOS/HoverPortal" "$@"
