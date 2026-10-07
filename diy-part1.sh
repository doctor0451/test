#!/bin/bash
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# 执行时机：workflow 中 "Load custom feeds" 步骤
# 当前工作目录：ponwrt/

# ============================================================
# 1. 移除不需要的 feed（可选）
# ============================================================
# sed -i '/helloworld/d' feeds.conf.default

# ============================================================
# 2. 直接克隆 luci-app-airoha-npu 到 package 目录
# ============================================================
if [ ! -d "package/luci-app-airoha-npu" ]; then
    git clone --depth=1 https://github.com/luanmuc/luci-app-airoha-npu.git package/luci-app-airoha-npu
else
    echo "package/luci-app-airoha-npu already exists, skip clone."
fi

# ============================================================
# 3. 添加 kenzok8/small-package 源（包含 iStore 商店和首页）
#    注意：不要同时添加 istore 官方源，以免同名包冲突导致编译失败
# ============================================================
# 先移除可能存在的 istore 源，防止冲突
sed -i '/src-git istore/d' feeds.conf.default

# 添加 small-package 源
grep -q "src-git small" feeds.conf.default || \
    echo "src-git small https://github.com/kenzok8/small-package" >> feeds.conf.default

# ============================================================
# 4. autocore 覆盖逻辑（按 Git 提交时间比较）
#    比较：
#      - 用户仓库：$GITHUB_WORKSPACE/autocore/Makefile
#      - 源码仓库：package/emortal/autocore/Makefile
#    规则：
#      - 若源码仓库 Makefile 提交时间更新或相同 → 不覆盖
#      - 若用户仓库 Makefile 提交时间更新        → 覆盖
#    说明：使用 git log 获取真实提交时间，而非文件 mtime
# ============================================================
USER_AUTOCORE="$GITHUB_WORKSPACE/autocore/Makefile"
SRC_AUTOCORE="package/emortal/autocore/Makefile"

if [ -f "$USER_AUTOCORE" ] && [ -f "$SRC_AUTOCORE" ]; then
    # 获取源码仓库该文件的最后提交时间戳
    SRC_TS=$(git log -1 --format=%ct "$SRC_AUTOCORE" 2>/dev/null)
    # 获取用户仓库该文件的最后提交时间戳
    USER_TS=$(git -C "$GITHUB_WORKSPACE" log -1 --format=%ct "autocore/Makefile" 2>/dev/null)

    echo "源码 autocore 提交时间戳: $SRC_TS"
    echo "用户 autocore 提交时间戳: $USER_TS"

    # 如果无法获取 Git 提交时间（如浅克隆），回退到文件 mtime 比较
    if [ -z "$SRC_TS" ] || [ -z "$USER_TS" ]; then
        echo "无法获取 Git 提交时间，回退到文件 mtime 比较..."
        SRC_TS=$(date -r "$SRC_AUTOCORE" +%s 2>/dev/null)
        USER_TS=$(date -r "$USER_AUTOCORE" +%s 2>/dev/null)
    fi

    if [ -n "$USER_TS" ] && [ -n "$SRC_TS" ] && [ "$USER_TS" -gt "$SRC_TS" ]; then
        echo "用户 autocore 提交更新，执行覆盖..."
        rm -rf package/emortal/autocore
        cp -rf "$GITHUB_WORKSPACE/autocore" package/emortal/autocore
        echo "autocore 覆盖完成。"
    else
        echo "源码 autocore 更新或相同，跳过覆盖。"
    fi
else
    echo "警告：autocore/Makefile 或源码 autocore/Makefile 不存在，跳过覆盖。"
fi

echo "diy-part1.sh done: luci-app-airoha-npu cloned, small feed added, autocore checked."
