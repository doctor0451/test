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
# 3. 添加 kenzok8/small-package 源（包含 iStore 商店和首页）
# ============================================================
sed -i '/src-git istore/d' feeds.conf.default
grep -q "src-git small" feeds.conf.default || \
    echo "src-git small https://github.com/kenzok8/small-package" >> feeds.conf.default

# ============================================================
# 4. 检查并拉取 qwe-qaq/luci-app 最新的 natmode 和 pon-status apk
# ============================================================
echo "检查并下载最新的 luci-app-natmode 和 luci-app-pon-status apk..."

TARGET_REPO="qwe-qaq/luci-app"
APK_DIR="$GITHUB_WORKSPACE/apk"
mkdir -p "$APK_DIR"

UPDATE_APK=false

# 获取 API JSON
LATEST_RELEASE_JSON=$(curl -s "https://api.github.com/repos/$TARGET_REPO/releases/latest")
if [[ -z "$LATEST_RELEASE_JSON" ]] || [[ "$(echo "$LATEST_RELEASE_JSON" | jq -r '.message')" == "Not Found" ]]; then
    LATEST_RELEASE_JSON=$(curl -s "https://api.github.com/repos/$TARGET_REPO/releases" | jq '.[0]')
fi

LATEST_TAG=$(echo "$LATEST_RELEASE_JSON" | jq -r '.tag_name')
REMOTE_PUBLISHED_AT=$(echo "$LATEST_RELEASE_JSON" | jq -r '.published_at')

if [ -n "$LATEST_TAG" ] && [ "$LATEST_TAG" != "null" ]; then
    REMOTE_TS=$(date -d "$REMOTE_PUBLISHED_AT" +%s)
    
    # 👈 修复点：这里使用 < <(...) 代替管道，避免变量丢失
    while read -r asset_name; do
        if [[ "$asset_name" == luci-app-natmode*.apk || "$asset_name" == luci-app-pon-status*.apk ]]; then
            NEED_DOWNLOAD=false
            LOCAL_FILES=$(ls "$APK_DIR"/${asset_name%%_*}*.apk 2>/dev/null || true)
            
            if [ -n "$LOCAL_FILES" ]; then
                FIRST_LOCAL_FILE=$(echo "$LOCAL_FILES" | head -n 1)
                LOCAL_TS=$(git -C "$GITHUB_WORKSPACE" log -1 --format=%ct -- "apk/$(basename "$FIRST_LOCAL_FILE")" 2>/dev/null)
                
                if [ -n "$LOCAL_TS" ] && [ "$REMOTE_TS" -le "$LOCAL_TS" ]; then
                    echo "本地已存在更新的 $asset_name，跳过下载"
                else
                    NEED_DOWNLOAD=true
                fi
            else
                NEED_DOWNLOAD=true
            fi
            
            if [ "$NEED_DOWNLOAD" = true ]; then
                TMP_DIR=$(mktemp -d)
                echo "下载 $asset_name 到临时目录..."
                
                DOWNLOAD_URL="https://github.com/$TARGET_REPO/releases/download/$LATEST_TAG/$asset_name"
                if curl -sL -o "$TMP_DIR/$asset_name" "$DOWNLOAD_URL"; then
                    rm -f "$APK_DIR"/${asset_name%%_*}*.apk
                    mv "$TMP_DIR"/"$asset_name" "$APK_DIR"/
                    echo "替换成功: $asset_name"
                    UPDATE_APK=true
                else
                    echo "警告：$asset_name 下载失败，保留本地旧版本。"
                fi
                rm -rf "$TMP_DIR"
            fi
        fi
    done < <(echo "$LATEST_RELEASE_JSON" | jq -r '.assets[].name')
else
    echo "警告：无法获取 $TARGET_REPO 的最新 Release，将使用仓库内原有 apk 文件。"
fi

# 👈 如果下载了新的 APK，把它推送到你的 GitHub 仓库，这样网页就能看到了
if [ "$UPDATE_APK" = true ]; then
    echo "正在将最新的 APK 推送到仓库..."
    cd "$GITHUB_WORKSPACE"
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add apk/
    git commit -m "Auto-update APK files from qwe-qaq/luci-app [skip ci]" || true
    # 👈 确保推到当前分支，并忽略报错防止流水线中断
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

echo "diy-part1.sh done: luci-app-airoha-npu cloned, small feed added, apk downloaded, autocore checked."
