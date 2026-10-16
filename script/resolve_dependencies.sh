#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
mkdir -p .build/logs
xcodegen generate >.build/logs/release-project.log
xcodebuild -resolvePackageDependencies -project Commander4Mac.xcodeproj -scheme Commander4Mac -derivedDataPath .build/xcode -clonedSourcePackagesDirPath .build/xcode/SourcePackages -onlyUsePackageVersionsFromResolvedFile >.build/logs/release-resolve.log 2>&1
git -C .build/xcode/SourcePackages/checkouts/AMSMB2 submodule update --init --recursive >>.build/logs/release-resolve.log 2>&1
echo 'Resolved locked dependencies and initialized pinned submodules.'
