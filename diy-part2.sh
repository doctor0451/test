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

echo "diy-part2.sh done: 仅保留 nokia_xg-040g-md-ubi 和 fiberhome_hg5585f-ct，选中 luci-app-airoha-npu，集成自定义 apk。"
