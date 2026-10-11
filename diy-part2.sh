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

# 3.2 打开 XG-040G-MD（基础机型，不含 -usb-sfp 变体）
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y/' .config
sed -i 's/^# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi is not set/CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=""/' .config

# 3.3 打开 HG5585F-CT（基础机型，不含 -usb-sfp 变体）
sed -i 's/^# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct is not set/CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct=y/' .config
sed -i 's/^# CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_fiberhome_hg5585f-ct is not set/CONFIG_TARGET_DEVICE_PACKAGES_airoha_an7581_DEVICE_fiberhome_hg5585f-ct=""/' .config

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

    # 复制所有 apk 文件
    cp "$GITHUB_WORKSPACE"/apk/*.apk files/etc/apk/custom-packages/ 2>/dev/null

    # 创建开机自动安装脚本
    cat > files/etc/uci-defaults/99-install-custom-apk <<'EOF'
#!/bin/sh
# 首次启动时自动安装固件内置的 apk 包
# --allow-untrusted：跳过签名验证（解决 UNTRUSTED signature）
# --no-network     ：不尝试下载依赖（解决 wget error 8）
APK_DIR="/etc/apk/custom-packages"
LOG="/tmp/apk-install.log"

echo "=== Custom APK Installation Start ===" > "$LOG"

if [ -d "$APK_DIR" ]; then
    # 临时禁用软件源，避免 apk add 时尝试联网
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

    # 恢复软件源
    if [ -f /etc/apk/repositories.bak ]; then
        mv /etc/apk/repositories.bak /etc/apk/repositories
    fi
fi

# 安装完成后删除内置 apk 文件，释放空间
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
#    是否执行由 workflow_dispatch 的 enable_docker 开关控制
#    对应环境变量：DOCKER_ENABLED = true / false
# ============================================================
if [ "${DOCKER_ENABLED:-false}" = "true" ]; then
    echo "Docker 支持已启用，开始配置..."

    # 辅助函数：设置 .config 中某项为指定值
    # 兼容三种情况：已存在、已注释、不存在
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

    # 6.1 内核功能开关
    #     只保留最核心的选项，其他依赖由 6.2 里的 kmod 包自动拉入
    set_config CONFIG_KERNEL_CGROUPS           y
    set_config CONFIG_KERNEL_NAMESPACES        y
    set_config CONFIG_KERNEL_CGROUP_DEVICE     y
    set_config CONFIG_KERNEL_MEMCG             y
    set_config CONFIG_KERNEL_CGROUP_FREEZER    y
    set_config CONFIG_KERNEL_CGROUP_PIDS       y
    set_config CONFIG_KERNEL_VETH              y
    set_config CONFIG_KERNEL_BRIDGE            y
    set_config CONFIG_KERNEL_OVERLAY_FS        y

    # 6.2 内核模块（kmod）
    #     必须编译时选上，后期在线安装 kmod 极易因内核版本不匹配而失败
    #     注意：续行列表里不能夹注释，否则会破坏续行符
    for kmod in \
        kmod-veth \
        kmod-ipt-nat \
        kmod-ipt-nat6 \
        kmod-ipt-physdev \
        kmod-nf-ipvs \
        kmod-br-netfilter \
        kmod-nft-compat \
        kmod-dm \
        kmod-fs-ext4 \
    ; do
        set_config "CONFIG_PACKAGE_${kmod}" y
    done

    # 6.3 Docker 用户态软件包
    #     这些是纯用户态程序，后期可以在线安装：
    #       apk add docker dockerd docker-compose luci-app-dockerman luci-i18n-dockerman-zh-cn
    #     如需在固件里预装，取消下面这段的注释
    #
    # for pkg in \
    #     docker \
    #     dockerd \
    #     docker-compose \
    #     luci-app-dockerman \
    #     luci-i18n-dockerman-zh-cn \
    # ; do
    #     set_config "CONFIG_PACKAGE_${pkg}" y
    # done

    echo "Docker 支持配置完成（6.3 用户态软件未预装，可后期在线安装）。"
else
    echo "Docker 支持未启用（DOCKER_ENABLED=${DOCKER_ENABLED:-false}），跳过第 6 段。"
fi

echo "diy-part2.sh done: 仅保留 nokia_xg-040g-md-ubi 和 fiberhome_hg5585f-ct，选中 luci-app-airoha-npu，集成自定义 apk，Docker 可选。"
