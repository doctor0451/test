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
# 3. 只保留 XG-040G-MD 和 HG5585F-CT 两个机型，关闭其余 an7581 设备
#    执行时机：make defconfig 之前，.config 为原始格式，sed 可精确匹配
# ============================================================
for dev in \
    fiberhome_hg5382a \
    fiberhome_hg5585f-cu \
    gemtek_xg2010g \
    nokia_xg-040g-tf-ubi \
    unionman_ung00a \
    znxt_zn504xg-d \
    znxt_zn515xg-d
do
    sed -i "s/^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_${dev}=y/# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_${dev} is not set/g" .config
    sed -i "s/^CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_${dev}=\"\"/# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_${dev} is not set/g" .config
done

# 确保两个目标机型保持开启
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y/' .config
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct=y/' .config

# ============================================================
# 4. 选中 luci-app-airoha-npu
#    如果 .config 中已有对应行，则改成 =y；没有则追加
# ============================================================
sed -i 's/^# CONFIG_PACKAGE_luci-app-airoha-npu is not set/CONFIG_PACKAGE_luci-app-airoha-npu=y/' .config
grep -q "^CONFIG_PACKAGE_luci-app-airoha-npu=" .config || echo "CONFIG_PACKAGE_luci-app-airoha-npu=y" >> .config

echo "diy-part2.sh done: 仅保留 nokia_xg-040g-md-ubi 和 fiberhome_hg5585f-ct，并选中 luci-app-airoha-npu."


# ============================================================
# 选中 iStore 商店及首页 (quickstart)
# ============================================================
# iStore 软件中心（商店本体）
sed -i 's/^# CONFIG_PACKAGE_luci-app-store is not set/CONFIG_PACKAGE_luci-app-store=y/' .config
grep -q "^CONFIG_PACKAGE_luci-app-store=" .config || echo "CONFIG_PACKAGE_luci-app-store=y" >> .config

# iStore 首页 / 网络向导（quickstart）
sed -i 's/^# CONFIG_PACKAGE_luci-app-quickstart is not set/CONFIG_PACKAGE_luci-app-quickstart=y/' .config
grep -q "^CONFIG_PACKAGE_luci-app-quickstart=" .config || echo "CONFIG_PACKAGE_luci-app-quickstart=y" >> .config

# iStore 首页中文语言包
sed -i 's/^# CONFIG_PACKAGE_luci-i18n-quickstart-zh-cn is not set/CONFIG_PACKAGE_luci-i18n-quickstart-zh-cn=y/' .config
grep -q "^CONFIG_PACKAGE_luci-i18n-quickstart-zh-cn=" .config || echo "CONFIG_PACKAGE_luci-i18n-quickstart-zh-cn=y" >> .config

# 依赖：luci-compat（21及以上版本固件需要）[citation:5]
sed -i 's/^# CONFIG_PACKAGE_luci-compat is not set/CONFIG_PACKAGE_luci-compat=y/' .config
grep -q "^CONFIG_PACKAGE_luci-compat=" .config || echo "CONFIG_PACKAGE_luci-compat=y" >> .config

# 可选：如果使用第三方源，可能需要 istorex 相关包
# sed -i 's/^# CONFIG_PACKAGE_luci-app-istorex is not set/CONFIG_PACKAGE_luci-app-istorex=y/' .config

echo "diy-part2.sh done: iStore + quickstart 已选中。"
