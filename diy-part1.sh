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
# 3. 添加 iStore 官方 feed 源（只保留这一个）
#    注意：如果你的固件已经通过其他方式包含 quickstart，可跳过
# ============================================================
grep -q "src-git istore" feeds.conf.default || \
    echo "src-git istore https://github.com/linkease/istore.git;main" >> feeds.conf.default

echo "diy-part1.sh done: luci-app-airoha-npu cloned, istore feed added."
