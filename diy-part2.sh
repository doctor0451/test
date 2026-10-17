#!/bin/bash
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# 执行时机：workflow 中 "Load custom configuration" 步骤
# 当前工作目录：ponwrt/

# ============================================================
# 1. 修改默认后台管理 IP（ponwrt 默认预置 192.168.1.1）
# ============================================================
# sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# ============================================================
# 2. 修改固件主机名（默认为 OpenWrt）
# ============================================================
# sed -i 's/OpenWrt/XG-040G-MD/g' package/base-files/files/bin/config_generate

# ============================================================
# 3. 只保留 XG-040G-MD 和 HG5585F-CT 两个机型
# ============================================================
# 3.1 关闭所有 an7581 设备及其 PACKAGES
sed -i -E 's/^(CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_[^=]+)=y/# \1 is not set/' .config
sed -i -E 's/^(CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_[^=]+)=""/# \1 is not set/' .config

# 3.2 打开 XG-040G-MD（基础机型）
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y/' .config
sed -i 's/^# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi is not set/CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=""/' .config

# 3.3 打开 HG5585F-CT（基础机型）
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct=y/' .config
sed -i 's/^# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_fiberhome_hg5585f-ct is not set/CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_fiberhome_hg5585f-ct=""/' .config

# ============================================================
# 4. 选中 luci-app-airoha-npu
# ============================================================
sed -i 's/^# CONFIG_PACKAGE_luci-app-airoha-npu is not set/CONFIG_PACKAGE_luci-app-airoha-npu=y/' .config
grep -q "^CONFIG_PACKAGE_luci-app-airoha-npu=" .config || echo "CONFIG_PACKAGE_luci-app-airoha-npu=y" >> .config

# ============================================================
# 5. 集成自定义 apk 软件包
# ============================================================
if [ -d "$GITHUB_WORKSPACE/apk" ]; then
    echo "发现自定义 apk 目录，开始集成..."
    mkdir -p files/etc/apk/custom-packages
    mkdir -p files/etc/uci-defaults
    cp "$GITHUB_WORKSPACE"/apk/*.apk files/etc/apk/custom-packages/ 2>/dev/null

    cat > files/etc/uci-defaults/99-install-custom-apk <<'EOF'
#!/bin/sh
APK_DIR="/etc/apk/custom-packages"
LOG="/tmp/apk-install.log"
echo "=== Custom APK Installation Start ===" > "$LOG"
if [ -d "$APK_DIR" ]; then
    if [ -f /etc/apk/repositories ]; then
        mv /etc/apk/repositories /etc/apk/repositories.bak
    fi
    for apk in "$APK_DIR"/*.apk; do
        if [ -f "$apk" ]; then
            echo "Installing: $apk" >> "$LOG"
            apk add --allow-untrusted --no-network --force-broken-world "$apk" >> "$LOG" 2>&1
            echo "Exit code: $?" >> "$LOG"
        fi
    done
    if [ -f /etc/apk/repositories.bak ]; then
        mv /etc/apk/repositories.bak /etc/apk/repositories
    fi
fi
rm -rf "$APK_DIR"
exit 0
EOF
    chmod +x files/etc/uci-defaults/99-install-custom-apk
    echo "自定义 apk 集成完成，共 $(ls "$GITHUB_WORKSPACE"/apk/*.apk 2>/dev/null | wc -l) 个包。"
else
    echo "未发现 apk 目录，跳过自定义 apk 集成。"
fi

# ============================================================
# 6. 启用 Docker 支持（云编译时可选）
# ============================================================
if [ "${DOCKER_ENABLED:-false}" = "true" ]; then
    echo "Docker 支持已启用，开始配置..."
    set_config() {
        local key="$1"
        local value="$2"
        if grep -q "^${key}=" .config; then
            sed -i "s|^${key}=.*|${key}=${value}|" .config
        elif grep -q "^# ${key} is not set" .config; then
            sed -i "s|^# ${key} is not set|${key}=${value}|" .config
        else
            echo "${key}=${value}" >> .config
        fi
    }
    set_config CONFIG_KERNEL_CGROUPS y
    set_config CONFIG_KERNEL_NAMESPACES y
    set_config CONFIG_KERNEL_CGROUP_DEVICE y
    set_config CONFIG_KERNEL_MEMCG y
    set_config CONFIG_KERNEL_CGROUP_FREEZER y
    set_config CONFIG_KERNEL_CGROUP_PIDS y
    set_config CONFIG_KERNEL_VETH y
    set_config CONFIG_KERNEL_BRIDGE y
    set_config CONFIG_KERNEL_OVERLAY_FS y
    for kmod in \
        kmod-veth \
        kmod-ipt-nat \
        kmod-ipt-nat6 \
        kmod-ipt-physdev \
        kmod-ipt-extra \
        kmod-nf-ipvs \
        kmod-br-netfilter \
        kmod-nft-compat \
        kmod-dm \
        kmod-fs-ext4 \
        kmod-fs-btrfs \
    ; do
        set_config "CONFIG_PACKAGE_${kmod}" y
    done
    echo "Docker 支持配置完成。"
else
    echo "Docker 支持未启用（DOCKER_ENABLED=${DOCKER_ENABLED:-false}），跳过第 6 段。"
fi

# ============================================================
# 7. 新增：启用 NTFS 读写支持（用于挂载 NTFS 格式 U 盘）
#    内核 6.18 使用内核态 ntfs3 驱动，无需 ntfs-3g（用户态）
# ============================================================
echo "启用 NTFS 读写支持（kmod-fs-ntfs3）..."
if grep -q "^CONFIG_PACKAGE_kmod-fs-ntfs3=" .config; then
    sed -i 's/^CONFIG_PACKAGE_kmod-fs-ntfs3=.*/CONFIG_PACKAGE_kmod-fs-ntfs3=y/' .config
elif grep -q "^# CONFIG_PACKAGE_kmod-fs-ntfs3 is not set" .config; then
    sed -i 's/^# CONFIG_PACKAGE_kmod-fs-ntfs3 is not set/CONFIG_PACKAGE_kmod-fs-ntfs3=y/' .config
else
    echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
fi
echo "NTFS 支持配置完成。"

echo "diy-part2.sh done: 仅保留 nokia_xg-040g-md-ubi 和 fiberhome_hg5585f-ct，选中 luci-app-airoha-npu，集成自定义 apk，Docker 可选，已启用 NTFS 驱动。"
