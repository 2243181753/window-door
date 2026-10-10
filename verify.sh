#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./test.sh
./dev-build.sh
binary_dir=$(swift build -c debug --show-bin-path)
export HOVERPORTAL_UI_REPORT_DIR="$PWD"
"$binary_dir/HoverPortal" --ui-smoke-test
result=$(/usr/bin/plutil -extract result raw -o - menu-verification.json)
[[ "$result" == passed ]]
print "PASS: source build, 16 geometry groups, 48 enhanced checks, 9 remembered-window checks, 64 gesture learning checks, 13 activation/gesture opt-in checks 16 capture lifecycle checks, 32 viewing-angle checks 41 status reason checks 10 resource-demand checks and menu UI."
