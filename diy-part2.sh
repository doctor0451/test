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
# 第6、7、8段共用：辅助函数 set_config
# 兼容三种情况：已存在、已注释、不存在
# 说明：原第6段内部定义，现移到此处供第6、7、8段共用
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
# 5.5 启用 plugin.txt 中的插件与主题（云编译时可选）
#     是否执行由 workflow_dispatch 的 enable_plugins 开关控制
#     对应环境变量：PLUGINS_ENABLED = true / false
# ============================================================
if [ "${PLUGINS_ENABLED:-false}" = "true" ]; then
    echo "插件与主题支持已启用，开始配置..."
    if [ -f "$GITHUB_WORKSPACE/plugin.txt" ]; then
        current_section=""
        # 逐行读取 plugin.txt
        while IFS= read -r line || [ -n "$line" ]; do
            # 去除回车符和首尾空格
            line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # 跳过空行
            [ -z "$line" ] && continue
            
            # 👈 修改：判断分类，支持 3 个类别
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
            
            # 跳过以 # 开头的注释行
            if [[ "$line" == "#"* ]]; then
                continue
            fi
            
            pkg_name="$line"
            
            # 根据分类处理
            if [ "$current_section" = "theme" ]; then
                # 特殊处理主题名称
                if [ "$pkg_name" = "Argon" ]; then
                    pkg_name="luci-theme-argon"
                elif [ "$pkg_name" = "Bootstrap" ]; then
                    pkg_name="luci-theme-bootstrap"
                fi
                echo "选中主题: $pkg_name"
                set_config "CONFIG_PACKAGE_${pkg_name}" y
            elif [ "$current_section" = "luci" ]; then
                # 👈 修改：如果是 luci 插件，自动判断并加上 luci-app- 前缀
                if [[ "$pkg_name" != luci-app-* ]]; then
                    echo "选中LuCI插件: luci-app-${pkg_name}"
                    set_config "CONFIG_PACKAGE_luci-app-${pkg_name}" y
                    set_config "CONFIG_PACKAGE_${pkg_name}" y # 顺便选上主程序，避免依赖丢失
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
        echo "未找到 plugin.txt，跳过。"
    fi
else
    echo "插件与主题支持未启用（PLUGINS_ENABLED=${PLUGINS_ENABLED:-false}），跳过。"
fi

# ============================================================
# 6. 启用 Docker 内核支持（云编译时可选）
#    是否执行由 workflow_dispatch 的 enable_docker_kernel 开关控制
#    对应环境变量：DOCKER_KERNEL_ENABLED = true / false
# ============================================================
if [ "${DOCKER_KERNEL_ENABLED:-false}" = "true" ]; then
    echo "Docker 内核支持已启用，开始配置..."

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
    set_config CONFIG_KERNEL_IPVLAN            y  # 👈 新增：增加 ipvlan 功能模块

    # 6.2 内核模块（kmod）
    #     必须编译时选上，后期在线安装 kmod 极易因内核版本不匹配而失败
    #     说明：
    #       - kmod-ipt-extra ：iptables-mod-extra 的依赖，被 Docker 网络相关包间接拉入
    #       - kmod-fs-btrfs  ：btrfs-progs 的依赖，部分存储相关包会用到
    #       - kmod-ipvlan    ：Docker macvlan/ipvlan 网络需要
    #     注意：续行列表里不能夹注释，否则会破坏续行符
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
    echo "Docker 内核支持未启用（DOCKER_KERNEL_ENABLED=${DOCKER_KERNEL_ENABLED:-false}），跳过第 6 段。"
fi

# ============================================================
# 7. 启用 Docker 用户态软件（云编译时可选）
#    是否执行由 workflow_dispatch 的 enable_docker_apps 开关控制
#    对应环境变量：DOCKER_APPS_ENABLED = true / false
# ============================================================
if [ "${DOCKER_APPS_ENABLED:-false}" = "true" ]; then
    echo "Docker 用户态软件已启用，开始配置..."

    # 7.1 Docker 用户态软件包
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
    echo "Docker 用户态软件未启用（DOCKER_APPS_ENABLED=${DOCKER_APPS_ENABLED:-false}），跳过第 7 段。"
fi

# ============================================================
# 8. U盘驱动 + 自动挂载 + Samba4（云编译时可开关，默认启用）
#    是否执行由 workflow_dispatch 的 enable_usb_storage 开关控制
#    对应环境变量：USB_STORAGE_ENABLED = true / false（默认 true）
#    与第6段若有重复项（如 kmod-fs-ext4），set_config 幂等设置 =y，
#    最终值一致，不影响编译，也不冲突。
# ============================================================
if [ "${USB_STORAGE_ENABLED:-true}" = "true" ]; then
    echo "U盘驱动与Samba4支持已启用，开始配置..."

    # 8.1 U盘常用文件系统驱动 + 中文文件名 NLS 编码
    #     说明：
    #       - kmod-fs-vfat/msdos/exfat/ext4/f2fs/ntfs3：覆盖U盘常见格式
    #       - kmod-fs-ntfs3：内核6.18推荐的内核态NTFS驱动
    #       - kmod-nls-cp437/cp936/iso8859-1/utf8：保证中文/英文文件名正常显示
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

    # 8.2 U盘存储与自动挂载
    #     说明：
    #       - usb-storage/uas/extras：USB存储设备识别（U盘、移动硬盘、读卡器）
    #       - block-mount/fstools：OpenWrt挂载框架
    #       - automount：热插拔自动挂载U盘到 /mnt 下
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

    # 8.3 Samba4 服务与 LuCI
    #     samba4-libs 是 samba4-server 的依赖，显式列出更稳妥
    set_config CONFIG_PACKAGE_samba4-server y
    set_config CONFIG_PACKAGE_samba4-libs y
    set_config CONFIG_PACKAGE_luci-app-samba4 y

    # 8.4 常用用户态工具
    #     说明：
    #       - e2fsprogs：ext2/3/4 格式化/修复
    #       - dosfstools：FAT/FAT32 格式化/修复
    #       - exfat-mkfs/exfat-fsck：exFAT 格式化/校验
    #       - ntfs3-mount：让 mount 命令识别 ntfs3 类型
    #       - usbutils：lsusb 等调试工具
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
    echo "U盘驱动与Samba4未启用（USB_STORAGE_ENABLED=${USB_STORAGE_ENABLED:-true}），跳过第 8 段。"
fi

echo "diy-part2.sh done: 仅保留 XG-040G-MD、HG5585F-CT和H3C HM2004-DU 仨个机型，选中 luci-app-airoha-npu，集成自定义 apk；插件/主题可选；Docker内核/用户态可选；U盘驱动+Samba4 默认启用。"
