#!/usr/bin/env bash
# 生成正式 MantaPhotos.xcodeproj。
# 用法：在 MantaPhotos/ 目录执行  ./Xcode/generate-xcodeproj.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "未检测到 xcodegen。请先安装：brew install xcodegen"
  exit 1
fi

xcodegen generate --spec project.yml
echo "已生成 MantaPhotos.xcodeproj，可直接用 Xcode 打开。"
