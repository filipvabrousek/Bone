#!/bin/zsh
#
# Every check Bone has, in one go:
#   1. unit tests on macOS (swift test) and on an iOS simulator
#   2. the package built for iOS, macOS, watchOS and visionOS – Debug, and Release
#      (where every library file compiles to nothing)
#   3. the demo apps (Bone-27 on iOS, Bone-vision on visionOS), Debug and Release
#
#   Tests/run.sh                 # all of it
#   SIM="iPhone 17 Pro" Tests/run.sh
#
# xcodebuild picks Bone-27.xcodeproj over Package.swift in the same folder, so
# the package is built through a folder that holds only links to it.

ROOT=${0:A:h:h}
SIM=${SIM:-iPhone 17 Pro}
WORK=$(mktemp -d)
trap 'rm -rf $WORK' EXIT
PKG=$WORK/pkg
mkdir -p $PKG && ln -s $ROOT/Package.swift $PKG/ && ln -s $ROOT/Bone-27 $PKG/ && ln -s $ROOT/Tests $PKG/
failures=0

check() {
    local name=$1; shift
    local out
    out=$("$@" 2>&1)
    if [[ $? -eq 0 ]] && ! echo "$out" | grep -q "BUILD FAILED\|TEST FAILED\|error: "; then
        echo "✓ $name"
    else
        echo "✗ $name"
        echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error:|issue at|failed" | sort -u | head -15
        failures=$((failures + 1))
    fi
}

cd $ROOT
check "unit tests · macOS" swift test --scratch-path $WORK/spm
check "unit tests · iOS ($SIM)" sh -c "cd $PKG && xcodebuild test -scheme Bone -destination 'platform=iOS Simulator,name=$SIM' -derivedDataPath $WORK/dd"

for config in Debug Release; do
    for platform in "iOS Simulator" "macOS" "watchOS Simulator" "visionOS Simulator"; do
        check "package · $platform · $config" sh -c "cd $PKG && xcodebuild build -scheme Bone -configuration $config -destination 'generic/platform=$platform' -derivedDataPath $WORK/dd"
    done
    check "demo · iOS · $config" xcodebuild build -project Bone-27.xcodeproj -scheme Bone-27 -configuration $config \
        -destination "generic/platform=iOS Simulator" -derivedDataPath $WORK/dd-demo
    check "demo · visionOS · $config" xcodebuild build -project Bone-27.xcodeproj -scheme Bone-vision -configuration $config \
        -destination "generic/platform=visionOS Simulator" -derivedDataPath $WORK/dd-demo
done

echo
[[ $failures -eq 0 ]] && echo "all checks passed" || echo "$failures check(s) failed"
exit $failures
