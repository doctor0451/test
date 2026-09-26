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
# 3. 用自己的 autocore 覆盖源码中的 package/emortal/autocore
# ============================================================
if [ -d "$GITHUB_WORKSPACE/autocore" ]; then
    echo "使用自定义 autocore 覆盖 package/emortal/autocore..."
    rm -rf package/emortal/autocore
    cp -rf "$GITHUB_WORKSPACE/autocore" package/emortal/autocore
    echo "autocore 覆盖完成。"
else
    echo "警告：$GITHUB_WORKSPACE/autocore 不存在，跳过覆盖。"
fi

echo "diy-part1.sh done: luci-app-airoha-npu cloned, autocore overridden."
