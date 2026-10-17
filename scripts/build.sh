#!/usr/bin/env bash
#
# 在 macOS 上本地编译 SplashAdKiller。
#
# 用法：
#   ./scripts/build.sh rootless   # Dopamine / palera1n rootless 等
#   ./scripts/build.sh rootful    # unc0ver / Taurine / checkra1n 等
#
set -euo pipefail

SCHEME="${1:-rootless}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -z "${THEOS:-}" ]; then
    echo "请先设置 THEOS，例如：export THEOS=\$HOME/theos" >&2
    exit 1
fi

if [ ! -d "$THEOS/makefiles" ]; then
    echo "找不到 $THEOS/makefiles，THEOS 路径不正确。" >&2
    exit 1
fi

cp control control.bak
restore() { mv -f control.bak control; }
trap restore EXIT

case "$SCHEME" in
    rootful)
        sed -i '' 's/^Architecture:.*/Architecture: iphoneos-arm/' control
        ;;
    rootless)
        export THEOS_PACKAGE_SCHEME=rootless
        sed -i '' 's/^Architecture:.*/Architecture: iphoneos-arm64/' control
        ;;
    *)
        echo "用法：$0 [rootful|rootless]" >&2
        exit 1
        ;;
esac

make clean package

echo
echo "编译完成，产物："
ls -1 packages/*.deb
