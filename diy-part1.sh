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

# 👈 克隆 luci-theme-carbon 主题
if [ ! -d "package/luci-theme-carbon" ]; then
    git clone --depth=1 https://github.com/mrjoechen/luci-theme-carbon.git package/luci-theme-carbon
else
    echo "package/luci-theme-carbon already exists, skip clone."
fi

# ============================================================
# 3. 添加 kenzok8/small-package 源（包含 iStore 商店和首页）
# ============================================================
sed -i '/src-git istore/d' feeds.conf.default
grep -q "src-git small" feeds.conf.default || \
    echo "src-git small https://github.com/kenzok8/small-package" >> feeds.conf.default

# ============================================================
# 4. 检查并拉取最新的 apk 软件包
# ============================================================
echo "检查并下载最新的自定义 apk 软件包..."

APK_DIR="$GITHUB_WORKSPACE/apk"
mkdir -p "$APK_DIR"
UPDATE_APK=false

# 封装通用的 API 获取和下载逻辑
fetch_latest_apks() {
    local target_repo="$1"
    local filter_pattern="$2"
    
    echo "--> 处理仓库: $target_repo"
    
    # 获取 API JSON
    local latest_release_json=$(curl -s "https://api.github.com/repos/$target_repo/releases/latest")
    if [[ -z "$latest_release_json" ]] || [[ "$(echo "$latest_release_json" | jq -r '.message')" == "Not Found" ]]; then
        latest_release_json=$(curl -s "https://api.github.com/repos/$target_repo/releases" | jq '.[0]')
    fi

    local latest_tag=$(echo "$latest_release_json" | jq -r '.tag_name')
    local remote_published_at=$(echo "$latest_release_json" | jq -r '.published_at')

    if [ -n "$latest_tag" ] && [ "$latest_tag" != "null" ]; then
        local remote_ts=$(date -d "$remote_published_at" +%s)
        
        # 使用子 shell 避免 while 循环内部变量丢失
        while read -r asset_name; do
            # 过滤出需要的 apk 文件
            if [[ "$asset_name" == $filter_pattern ]]; then
                local pkg_prefix=$(echo "$asset_name" | grep -oE '^[a-zA-Z0-9-]+' | sed 's/-[0-9].*//')
                local need_download=false
                local local_files=$(ls "$APK_DIR"/${pkg_prefix}*.apk 2>/dev/null || true)
                
                if [ -n "$local_files" ]; then
                    local first_local_file=$(echo "$local_files" | head -n 1)
                    local local_ts=$(git -C "$GITHUB_WORKSPACE" log -1 --format=%ct -- "apk/$(basename "$first_local_file")" 2>/dev/null)
                    if [ -n "$local_ts" ] && [ "$remote_ts" -le "$local_ts" ]; then
                        echo "本地已存在更新的 $asset_name，跳过下载"
                    else
                        need_download=true
                    fi
                else
                    need_download=true
                fi
                
                if [ "$need_download" = true ]; then
                    local tmp_dir=$(mktemp -d)
                    echo "下载 $asset_name 到临时目录..."
                    local download_url="https://github.com/$target_repo/releases/download/$latest_tag/$asset_name"
                    if curl -sL -o "$tmp_dir/$asset_name" "$download_url"; then
                        rm -f "$APK_DIR"/${pkg_prefix}*.apk
                        mv "$tmp_dir"/"$asset_name" "$APK_DIR"/
                        echo "替换成功: $asset_name"
                        UPDATE_APK=true
                    else
                        echo "警告：$asset_name 下载失败，保留本地旧版本。"
                    fi
                    rm -rf "$tmp_dir"
                fi
            fi
        done < <(echo "$latest_release_json" | jq -r '.assets[].name')
    else
        echo "警告：无法获取 $target_repo 的最新 Release。"
    fi
}

# 拉取 qwe-qaq/luci-app 的 natmode 和 pon-status 包
fetch_latest_apks "qwe-qaq/luci-app" "luci-app-natmode*.apk|luci-app-pon-status*.apk"

# 👈 新增：拉取 shb110119/luci-app-traffic 的包
fetch_latest_apks "shb110119/luci-app-traffic" "*.apk"

# 👈 如果下载了新的 APK，把它推送到你的 GitHub 仓库
if [ "$UPDATE_APK" = true ]; then
    echo "正在将最新的 APK 推送到仓库..."
    cd "$GITHUB_WORKSPACE"
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add -A apk/
    git commit -m "Auto-update custom APK files [skip ci]" || true
    git push origin HEAD:$GITHUB_REF_NAME || true
    echo "推送完成。"
    cd ponwrt
fi

# ============================================================
# 5. autocore 覆盖逻辑（按 Git 提交时间比较）
# ============================================================
USER_AUTOCORE="$GITHUB_WORKSPACE/autocore/Makefile"
SRC_AUTOCORE="package/emortal/autocore/Makefile"

if [ -f "$USER_AUTOCORE" ] && [ -f "$SRC_AUTOCORE" ]; then
    SRC_TS=$(git log -1 --format=%ct "$SRC_AUTOCORE" 2>/dev/null)
    USER_TS=$(git -C "$GITHUB_WORKSPACE" log -1 --format=%ct "autocore/Makefile" 2>/dev/null)

    if [ -z "$SRC_TS" ] || [ -z "$USER_TS" ]; then
        SRC_TS=$(date -r "$SRC_AUTOCORE" +%s 2>/dev/null)
        USER_TS=$(date -r "$USER_AUTOCORE" +%s 2>/dev/null)
    fi

    if [ -n "$USER_TS" ] && [ -n "$SRC_TS" ] && [ "$USER_TS" -gt "$SRC_TS" ]; then
        echo "用户 autocore 提交更新，执行覆盖..."
        rm -rf package/emortal/autocore
        cp -rf "$GITHUB_WORKSPACE/autocore" package/emortal/autocore
        echo "autocore 覆盖完成。"
    else
        echo "源码 autocore 更新或相同，跳过覆盖。"
    fi
else
    echo "警告：autocore/Makefile 或源码 autocore/Makefile 不存在，跳过覆盖。"
fi

echo "diy-part1.sh done: luci-app-airoha-npu cloned, luci-theme-carbon cloned, small feed added, apk downloaded, autocore checked."
