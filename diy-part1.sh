#!/bin/bash
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# 执行时机：workflow 中 "Load custom feeds" 步骤
# 当前工作目录：ponwrt/

# ============================================================
# 1. 移除不需要的 feed（可选）
#    例如删除 helloworld feed，避免污染
# ============================================================
# sed -i '/helloworld/d' feeds.conf.default

# ============================================================
# 2. 添加第三方 feed（可选，按需取消注释）
# ============================================================
# echo "src-git airoha_npu https://github.com/luanmuc/luci-app-airoha-npu.git" >> feeds.conf.default

# ============================================================
# 3. 直接克隆 luci-app-airoha-npu 到 package 目录
#    方案二：不使用 feed 机制，直接把源码放到 package/ 下
# ============================================================
if [ ! -d "package/luci-app-airoha-npu" ]; then
    git clone --depth=1 https://github.com/luanmuc/luci-app-airoha-npu.git package/luci-app-airoha-npu
else
    echo "package/luci-app-airoha-npu already exists, skip clone."
fi

echo "diy-part1.sh done: luci-app-airoha-npu cloned into package/."
