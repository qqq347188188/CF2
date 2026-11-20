#!/bin/bash
# 222.ipa (CFM 1.0.590) 作弊版打包脚本
# 用法: bash build_and_package.sh /path/to/222.ipa
# 环境: macOS + Theos (export THEOS=~/theos) + insert_dylib + ldid

set -euo pipefail

IPA="${1:-222.ipa}"
WORK="$(pwd)/build_cf"
OUT="$(pwd)/222-cheat.ipa"
APP_NAME="cf"

echo "[*] 清理工作目录"
rm -rf "$WORK"; mkdir -p "$WORK"

echo "[*] 1/5 解压 IPA"
unzip -q "$IPA" -d "$WORK"

echo "[*] 2/5 用 Theos 编译 CFCheatHook.dylib"
make -C "$(dirname "$0")" clean
make -C "$(dirname "$0")" -j2
DYLIB="$(find "$(dirname "$0")" -name 'CFCheatHook.dylib' 2>/dev/null | head -n1)"
if [ -z "$DYLIB" ]; then
    echo "[-] 找不到编译产物 CFCheatHook.dylib"; exit 1
fi

echo "[*] 3/5 注入 dylib 到主程序 Mach-O"
cp "$DYLIB" "$WORK/Payload/${APP_NAME}.app/Frameworks/CFCheatHook.dylib"
insert_dylib --strip-codesig --all-yes \
    "@executable_path/Frameworks/CFCheatHook.dylib" \
    "$WORK/Payload/${APP_NAME}.app/${APP_NAME}" \
    "$WORK/Payload/${APP_NAME}.app/${APP_NAME}_patched" >/dev/null
mv "$WORK/Payload/${APP_NAME}.app/${APP_NAME}_patched" "$WORK/Payload/${APP_NAME}.app/${APP_NAME}"
chmod +x "$WORK/Payload/${APP_NAME}.app/${APP_NAME}"

echo "[*] 4/5 ad-hoc 重签（dylib + app）"
if command -v ldid >/dev/null 2>&1; then
    ldid -S "$WORK/Payload/${APP_NAME}.app/Frameworks/CFCheatHook.dylib"
    find "$WORK/Payload/${APP_NAME}.app/Frameworks" -maxdepth 2 -type f -perm -u+x -exec ldid -S {} \;
    ldid -S "$WORK/Payload/${APP_NAME}.app/${APP_NAME}"
else
    codesign --force --deep --sign - "$WORK/Payload/${APP_NAME}.app"
fi

echo "[*] 5/5 打包成品 IPA"
(cd "$WORK" && zip -qry "$OUT" Payload)

echo "[+] 完成: $OUT"
echo "[+] 用 TrollStore 安装即可"
