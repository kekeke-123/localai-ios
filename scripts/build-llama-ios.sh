#!/usr/bin/env bash
# 在 macOS 上编译 llama.cpp 的 iOS XCFramework，供 App 链接。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LLAMA_REPO="${LLAMA_REPO:-https://github.com/ggml-org/llama.cpp.git}"
LLAMA_REF="${LLAMA_REF:-master}"

if [ ! -d .llama.cpp/.git ]; then
  echo "==> 克隆 llama.cpp ($LLAMA_REF)"
  rm -rf .llama.cpp
  git clone --depth 1 --branch "$LLAMA_REF" "$LLAMA_REPO" .llama.cpp
fi

echo "==> 编译 iOS 版（真机 + 模拟器）"
cd .llama.cpp
chmod +x build-xcframework.sh
./build-xcframework.sh ios-sim ios-device
cd ..

echo "==> 拷贝 XCFramework 与头文件"
rm -rf ThirdParty
mkdir -p ThirdParty/include
cp -R .llama.cpp/build-apple/llama.xcframework ThirdParty/llama.xcframework
cp .llama.cpp/include/llama.h ThirdParty/include/
cp .llama.cpp/ggml/include/*.h ThirdParty/include/
cp .llama.cpp/tools/mtmd/mtmd.h ThirdParty/include/
cp .llama.cpp/tools/mtmd/mtmd-helper.h ThirdParty/include/

echo "==> 完成："
ls -1 ThirdParty
du -sh ThirdParty/llama.xcframework
