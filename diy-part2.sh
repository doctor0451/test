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
# 3. 只保留 XG-040G-MD、HG5585F-CT和H3C HM2004-DU 仨个机型，关闭其余所有 an7581 设备
#    采用白名单方式：先关闭全部，再打开指定机型，避免源仓库新增机型被误编译
#    执行时机：make defconfig 之前，.config 为原始格式，sed 可精确匹配
# ============================================================

# 3.1 关闭所有 an7581 设备及其 PACKAGES
sed -i -E 's/^(CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_[^=]+)=y/# \1 is not set/' .config
sed -i -E 's/^(CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_[^=]+)=""/# \1 is not set/' .config

# 3.2 打开 XG-040G-MD（基础机型，不含 -usb-sfp 变体）
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y/' .config
sed -i 's/^# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi is not set/CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=""/' .config

# 3.3 打开 HG5585F-CT（基础机型，不含 -usb-sfp 变体）
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct=y/' .config
sed -i 's/^# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_fiberhome_hg5585f-ct is not set/CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_fiberhome_hg5585f-ct=""/' .config

# 👇 3.4 新增：打开 H3C HM2004-DU
# 增加 grep -q || echo 兜底，防止原始 config 缺失该项导致 sed 失效
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_h3c_hm2004-du is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_h3c_hm2004-du=y/' .config
grep -q "^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_h3c_hm2004-du=" .config || echo "CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_h3c_hm2004-du=y" >> .config

sed -i 's/^# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_h3c_hm2004-du is not set/CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_h3c_hm2004-du=""/' .config
grep -q "^CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_h3c_hm2004-du=" .config || echo 'CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_h3c_hm2004-du=""' >> .config

# ============================================================
# 4. 选中 luci-app-airoha-npu
#    如果 .config 中已有对应行，则改成 =y；没有则追加
# ============================================================
sed -i 's/^# CONFIG_PACKAGE_luci-app-airoha-npu is not set/CONFIG_PACKAGE_luci-app-airoha-npu=y/' .config
grep -q "^CONFIG_PACKAGE_luci-app-airoha-npu=" .config || echo "CONFIG_PACKAGE_luci-app-airoha-npu=y" >> .config

# ============================================================
# 5. 集成自定义 apk 软件包
#    把 apk 放到 files/etc/apk/custom-packages/
#    通过 uci-defaults 脚本在开机时用 --allow-untrusted 安装
#    （绕过签名校验 + 禁用网络请求，解决：
#       - wget: exited with error 8
#       - UNTRUSTED signature）
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
            apk add \
                --allow-untrusted \
                --no-network \
                --force-broken-world \
                "$apk" >> "$LOG" 2>&1
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
# 第6、7、8、9、10、11段共用：辅助函数 set_config
# 兼容三种情况：已存在、已注释、不存在
# 说明：原第6段内部定义，现移到此处供后续各段共用
# ============================================================
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

# ============================================================
# 6. 启用 iStore 商店（云编译时可选，默认关闭）
# ============================================================
if [ "${ISTORE_ENABLED:-false}" = "true" ]; then
    echo "iStore 商店已启用，开始配置..."
    set_config CONFIG_PACKAGE_luci-app-store y
    set_config CONFIG_PACKAGE_luci-i18n-store-zh-cn y
    echo "iStore 商店配置完成。"
else
    echo "iStore 商店未启用（ISTORE_ENABLED=${ISTORE_ENABLED:-false}），跳过第 6 段。"
fi

# ============================================================
# 7. 启用 plugin.txt 中的插件与主题（云编译时可选）
# ============================================================
if [ "${PLUGINS_ENABLED:-false}" = "true" ]; then
    echo "插件与主题支持已启用，开始配置..."
    if [ -f "$GITHUB_WORKSPACE/plugin.txt" ]; then
        current_section=""
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$line" ] && continue
            if [[ "$line" == *"luci插件："* ]]; then
                current_section="luci"
                continue
            elif [[ "$line" == *"插件："* ]]; then
                current_section="pkg"
                continue
            elif [[ "$line" == *"主题："* ]]; then
                current_section="theme"
                continue
            fi
            if [[ "$line" == "#"* ]]; then
                continue
            fi
            pkg_name="$line"
            if [ "$current_section" = "theme" ]; then
                if [ "$pkg_name" = "Argon" ]; then pkg_name="luci-theme-argon"; fi
                if [ "$pkg_name" = "Bootstrap" ]; then pkg_name="luci-theme-bootstrap"; fi
                echo "选中主题: $pkg_name"
                set_config "CONFIG_PACKAGE_${pkg_name}" y
            elif [ "$current_section" = "luci" ]; then
                if [[ "$pkg_name" != luci-app-* ]]; then
                    echo "选中LuCI插件: luci-app-${pkg_name}"
                    set_config "CONFIG_PACKAGE_luci-app-${pkg_name}" y
                    set_config "CONFIG_PACKAGE_${pkg_name}" y
                else
                    echo "选中LuCI插件: $pkg_name"
                    set_config "CONFIG_PACKAGE_${pkg_name}" y
                fi
            elif [ "$current_section" = "pkg" ]; then
                echo "选中插件: $pkg_name"
                set_config "CONFIG_PACKAGE_${pkg_name}" y
            fi
        done < "$GITHUB_WORKSPACE/plugin.txt"
        echo "插件与主题配置完成。"
    else
        echo "未找到 plugin.txt，跳过第 7 段。"
    fi
else
    echo "插件与主题支持未启用（PLUGINS_ENABLED=${PLUGINS_ENABLED:-false}），跳过第 7 段。"
fi

# ============================================================
# 8. 启用 Docker 内核支持（云编译时可选）
# ============================================================
if [ "${DOCKER_KERNEL_ENABLED:-false}" = "true" ]; then
    echo "Docker 内核支持已启用，开始配置..."
    set_config CONFIG_KERNEL_CGROUPS           y
    set_config CONFIG_KERNEL_NAMESPACES        y
    set_config CONFIG_KERNEL_CGROUP_DEVICE     y
    set_config CONFIG_KERNEL_MEMCG             y
    set_config CONFIG_KERNEL_CGROUP_FREEZER    y
    set_config CONFIG_KERNEL_CGROUP_PIDS       y
    set_config CONFIG_KERNEL_VETH              y
    set_config CONFIG_KERNEL_BRIDGE            y
    set_config CONFIG_KERNEL_OVERLAY_FS        y
    set_config CONFIG_KERNEL_IPVLAN            y

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
        kmod-ipvlan \
    ; do
        set_config "CONFIG_PACKAGE_${kmod}" y
    done
    echo "Docker 内核支持配置完成。"
else
    echo "Docker 内核支持未启用（DOCKER_KERNEL_ENABLED=${DOCKER_KERNEL_ENABLED:-false}），跳过第 8 段。"
fi

# ============================================================
# 9. 启用 Docker 用户态软件（云编译时可选）
# ============================================================
if [ "${DOCKER_APPS_ENABLED:-false}" = "true" ]; then
    echo "Docker 用户态软件已启用，开始配置..."
    for pkg in \
        docker \
        dockerd \
        docker-compose \
        luci-app-dockerman \
        luci-i18n-dockerman-zh-cn \
    ; do
        set_config "CONFIG_PACKAGE_${pkg}" y
    done
    echo "Docker 用户态软件配置完成。"
else
    echo "Docker 用户态软件未启用（DOCKER_APPS_ENABLED=${DOCKER_APPS_ENABLED:-false}），跳过第 9 段。"
fi

# ============================================================
# 10. U盘驱动 + 自动挂载 + Samba4（云编译时可开关，默认启用）
# ============================================================
if [ "${USB_STORAGE_ENABLED:-true}" = "true" ]; then
    echo "U盘驱动与Samba4支持已启用，开始配置..."
    for kopt in \
        kmod-fs-vfat \
        kmod-fs-msdos \
        kmod-fs-exfat \
        kmod-fs-ext4 \
        kmod-fs-f2fs \
        kmod-fs-ntfs3 \
        kmod-nls-cp437 \
        kmod-nls-cp936 \
        kmod-nls-iso8859-1 \
        kmod-nls-utf8 \
    ; do
        set_config "CONFIG_PACKAGE_${kopt}" y
    done

    for pkg in \
        kmod-usb-storage \
        kmod-usb-storage-uas \
        kmod-usb-storage-extras \
        block-mount \
        fstools \
        automount \
    ; do
        set_config "CONFIG_PACKAGE_${pkg}" y
    done

    set_config CONFIG_PACKAGE_samba4-server y
    set_config CONFIG_PACKAGE_samba4-libs y
    set_config CONFIG_PACKAGE_luci-app-samba4 y

    for tool in \
        e2fsprogs \
        dosfstools \
        exfat-mkfs \
        exfat-fsck \
        ntfs3-mount \
        usbutils \
    ; do
        set_config "CONFIG_PACKAGE_${tool}" y
    done
    echo "U盘驱动与Samba4配置完成。"
else
    echo "U盘驱动与Samba4未启用（USB_STORAGE_ENABLED=${USB_STORAGE_ENABLED:-true}），跳过第 10 段。"
fi

# ============================================================
# 11. 启用 luci-theme-carbon 主题（云编译时可选，默认关闭）
#     是否执行由 workflow_dispatch 的 enable_carbon_theme 开关控制
#     对应环境变量：CARBON_THEME_ENABLED = true / false
# ============================================================
if [ "${CARBON_THEME_ENABLED:-false}" = "true" ]; then
    echo "luci-theme-carbon 主题已启用，开始配置..."
    set_config CONFIG_PACKAGE_luci-theme-carbon y
    echo "luci-theme-carbon 配置完成。"
else
    echo "luci-theme-carbon 未启用（CARBON_THEME_ENABLED=${CARBON_THEME_ENABLED:-false}），跳过第 11 段。"
fi

echo "diy-part2.sh done: 仅保留 XG-040G-MD、HG5585F-CT和H3C HM2004-DU 仨个机型，选中 luci-app-airoha-npu，集成自定义 apk；插件/主题可选；iStore 可选；Docker内核/用户态可选；U盘驱动+Samba4 默认启用；Carbon主题可选。"
