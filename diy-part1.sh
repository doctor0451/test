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
#    注意：不要同时添加 istore 官方源，以免同名包冲突导致编译失败
# ============================================================
# 先移除可能存在的 istore 源，防止冲突
sed -i '/src-git istore/d' feeds.conf.default

# 添加 small-package 源
grep -q "src-git small" feeds.conf.default || \
    echo "src-git small https://github.com/kenzok8/small-package" >> feeds.conf.default

# ============================================================
# 4. 检查并拉取 qwe-qaq/luci-app 最新的 natmode 和 pon-status apk
#    说明：提前配置 GH_TOKEN，否则 gh 命令会因缺少认证而失败
# ============================================================
echo "检查并下载最新的 luci-app-natmode 和 luci-app-pon-status apk..."

TARGET_REPO="qwe-qaq/luci-app"
APK_DIR="$GITHUB_WORKSPACE/apk"
mkdir -p "$APK_DIR"

# 获取远程最新 Release 的 Tag 和发布时间
REMOTE_DATA=$(gh release view -R "$TARGET_REPO" --json tagName,publishedAt -q '.tagName + " " + .publishedAt' 2>/dev/null)
if [ -n "$REMOTE_DATA" ]; then
    LATEST_TAG=$(echo "$REMOTE_DATA" | cut -d' ' -f1)
    REMOTE_PUBLISHED_AT=$(echo "$REMOTE_DATA" | cut -d' ' -f2)
    REMOTE_TS=$(date -d "$REMOTE_PUBLISHED_AT" +%s)
    
    # 列出最新 Release 中的 Asset
    gh release view "$LATEST_TAG" -R "$TARGET_REPO" --json assets -q '.assets[].name' | while read -r asset_name; do
        # 匹配需要的 apk 名称
        if [[ "$asset_name" == luci-app-natmode*.apk || "$asset_name" == luci-app-pon-status*.apk ]]; then
            NEED_DOWNLOAD=false
            
            # 检查本地是否有同名或同类型的文件
            LOCAL_FILES=$(ls "$APK_DIR"/${asset_name%%_*}*.apk 2>/dev/null || true)
            
            if [ -n "$LOCAL_FILES" ]; then
                # 获取本地文件在 Git 中的最后一次提交时间（最精确）
                FIRST_LOCAL_FILE=$(echo "$LOCAL_FILES" | head -n 1)
                LOCAL_TS=$(git -C "$GITHUB_WORKSPACE" log -1 --format=%ct -- "apk/$(basename "$FIRST_LOCAL_FILE")" 2>/dev/null)
                
                if [ -n "$LOCAL_TS" ]; then
                    if [ "$REMOTE_TS" -gt "$LOCAL_TS" ]; then
                        echo "远程文件 $asset_name 比本地新 (Remote: $REMOTE_TS > Local: $LOCAL_TS)，将替换"
                        NEED_DOWNLOAD=true
                    else
                        echo "本地已存在更新的 $asset_name (Remote: $REMOTE_TS <= Local: $LOCAL_TS)，跳过下载"
                    fi
                else
                    echo "本地文件 $FIRST_LOCAL_FILE 缺少 Git 记录，默认下载覆盖"
                    NEED_DOWNLOAD=true
                fi
            else
                echo "本地不存在 $asset_name，准备下载"
                NEED_DOWNLOAD=true
            fi
            
            # 👈 优化：执行替换（先下载到临时目录，成功后再删除旧包，防止网络问题导致丢包）
            if [ "$NEED_DOWNLOAD" = true ]; then
                TMP_DIR=$(mktemp -d)
                echo "下载 $asset_name 到临时目录..."
                if gh release download "$LATEST_TAG" -R "$TARGET_REPO" -p "$asset_name" -D "$TMP_DIR" --clobber; then
                    # 下载成功，删除本地同名的旧包，并移入新包
                    rm -f "$APK_DIR"/${asset_name%%_*}*.apk
                    mv "$TMP_DIR"/"$asset_name" "$APK_DIR"/
                    echo "替换成功: $asset_name"
                else
                    echo "警告：$asset_name 下载失败，保留本地旧版本。"
                fi
                rm -rf "$TMP_DIR"
            fi
        fi
    done
else
    echo "警告：无法获取 $TARGET_REPO 的最新 Release，将使用仓库内原有 apk 文件。"
fi

# ============================================================
# 5. autocore 覆盖逻辑（按 Git 提交时间比较）
#    比较：
#      - 用户仓库：$GITHUB_WORKSPACE/autocore/Makefile
#      - 源码仓库：package/emortal/autocore/Makefile
#    规则：
#      - 若源码仓库 Makefile 提交时间更新或相同 → 不覆盖
#      - 若用户仓库 Makefile 提交时间更新        → 覆盖
#    说明：使用 git log 获取真实提交时间，而非文件 mtime
# ============================================================
USER_AUTOCORE="$GITHUB_WORKSPACE/autocore/Makefile"
SRC_AUTOCORE="package/emortal/autocore/Makefile"

if [ -f "$USER_AUTOCORE" ] && [ -f "$SRC_AUTOCORE" ]; then
    # 获取源码仓库该文件的最后提交时间戳
    SRC_TS=$(git log -1 --format=%ct "$SRC_AUTOCORE" 2>/dev/null)
    # 获取用户仓库该文件的最后提交时间戳
    USER_TS=$(git -C "$GITHUB_WORKSPACE" log -1 --format=%ct "autocore/Makefile" 2>/dev/null)

    echo "源码 autocore 提交时间戳: $SRC_TS"
    echo "用户 autocore 提交时间戳: $USER_TS"

    # 如果无法获取 Git 提交时间（如浅克隆），回退到文件 mtime 比较
    if [ -z "$SRC_TS" ] || [ -z "$USER_TS" ]; then
        echo "无法获取 Git 提交时间，回退到文件 mtime 比较..."
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
