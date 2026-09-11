#!/usr/bin/env bash
# 在 macOS 上构建 iOS 测试版 IPA。
#
#   ./tool/build_ipa.sh            # 不签名 IPA（交给 Sideloadly 签名，最省事）
#   ./tool/build_ipa.sh --signed   # 用本机 Xcode 证书导出已签名 IPA（需配置团队）
#
# 产物：build/ApexScrolling-unsigned.ipa 或 build/ios/ipa/*.ipa
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "未找到 flutter，请先安装 Flutter 3.35.x 并加入 PATH" >&2
  exit 1
fi

if [ "$(uname -s)" != "Darwin" ]; then
  echo "iOS 构建必须在 macOS 上进行（当前系统：$(uname -s)）" >&2
  exit 1
fi

flutter pub get

if [ "${1:-}" = "--signed" ]; then
  flutter build ipa --release
  echo "已签名 IPA：build/ios/ipa/"
  ls -lh build/ios/ipa/ || true
  exit 0
fi

flutter build ios --release --no-codesign

APP_PATH="build/ios/iphoneos/Runner.app"
if [ ! -d "$APP_PATH" ]; then
  echo "找不到构建产物：$APP_PATH" >&2
  exit 1
fi

rm -rf build/ipa_payload
mkdir -p build/ipa_payload/Payload
cp -R "$APP_PATH" build/ipa_payload/Payload/
(cd build/ipa_payload && zip -qry ../ApexScrolling-unsigned.ipa Payload)

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
echo "版本：$VERSION"
echo "IPA ：build/ApexScrolling-unsigned.ipa"
shasum -a 256 build/ApexScrolling-unsigned.ipa | tee build/ApexScrolling-unsigned.ipa.sha256
