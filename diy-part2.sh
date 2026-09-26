#!/bin/bash
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# 执行时机：workflow 中 "Load custom configuration" 步骤
# 当前工作目录：ponwrt/

# ============================================================
# 1. 修改默认后台管理 IP（ponwrt 默认预置 192.168.1.1）
#    如需修改，取消下面一行注释并改成你要的 IP
# ============================================================
# sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# ============================================================
# 2. 修改固件主机名（默认为 OpenWrt）
#    取消注释并改成你的设备名称
# ============================================================
# sed -i 's/OpenWrt/XG-040G-MD/g' package/base-files/files/bin/config_generate

# ============================================================
# 3. 只保留 XG-040G-MD 和 HG5585F-CT 两个机型，关闭其余所有 an7581 设备
#    采用白名单方式：先关闭全部，再打开指定机型，避免源仓库新增机型被误编译
#    执行时机：make defconfig 之前，.config 为原始格式，sed 可精确匹配
# ============================================================

# 3.1 关闭所有 an7581 设备及其 PACKAGES
sed -i -E 's/^(CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_[^=]+)=y/# \1 is not set/' .config
sed -i -E 's/^(CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_[^=]+)=""/# \1 is not set/' .config

# 3.2 打开 XG-040G-MD
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y/' .config
sed -i 's/^# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi is not set/CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=""/' .config

# 3.3 打开 HG5585F-CT
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct=y/' .config
sed -i 's/^# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_fiberhome_hg5585f-ct is not set/CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_fiberhome_hg5585f-ct=""/' .config

# ============================================================
# 4. 选中 luci-app-airoha-npu
#    如果 .config 中已有对应行，则改成 =y；没有则追加
# ============================================================
sed -i 's/^# CONFIG_PACKAGE_luci-app-airoha-npu is not set/CONFIG_PACKAGE_luci-app-airoha-npu=y/' .config
grep -q "^CONFIG_PACKAGE_luci-app-airoha-npu=" .config || echo "CONFIG_PACKAGE_luci-app-airoha-npu=y" >> .config

echo "diy-part2.sh done: 仅保留 nokia_xg-040g-md-ubi 和 fiberhome_hg5585f-ct，并选中 luci-app-airoha-npu."
