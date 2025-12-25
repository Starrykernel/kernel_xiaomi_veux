#!/bin/bash

#
# This Bash script automates the process of building a custom kernel for any device using Clang.
# It packages the compiled kernel with AnyKernel3 and sends real-time updates via Telegram.
# USAGE : ./build.sh or bash build.sh
#
# Copyright (C) 2025 Amrita Das <bhabanidas431@gmail.com>
# Licensed under the GNU General Public License v2.0
#

# Set Kernel Build Variables
DEVICE_CODENAME="veux"  # Device codename (e.g., veux, garnet, etc.)
DEVICE_NAME="Redmi Note 11E Pro/Redmi Note 11 Pro 5G/POCO X4 Pro 5G"      # Device Market name (e.g., POCO X4 PRO 5G)
KERNEL_NAME="Starry"      # Kernel name
KERNEL_DEFCONFIG="vendor/${DEVICE_CODENAME}-qgki_defconfig"

# SourceForge Upload Config
SF_USER="takixamru"
SF_PROJECT="roms"        # lowercase
SF_FOLDER="veux"              # folder inside SF project

# Changelog Repo Config
CHANGELOG_REPO="$HOME/changelogs"     # local clone of your GitHub changelogs repo
CHANGELOG_DEVICE_DIR="${CHANGELOG_REPO}/${DEVICE_CODENAME}"

# AnyKernel3 Config
ANYKERNEL3_DIR="$PWD/AnyKernel3"

BUILD_HOSTNAME=$(hostname)
COMPILER_PATH="$HOME/clang/bin"

echo ""
echo "=============================="
echo "   SELECT YOUR BUILD TYPE"
echo "=============================="
echo ""

PS3="Choose option (1-5): "

select opt in "STABLE" "BETA" "ALPHA" "TEST" "CUSTOM"; do
    case $opt in
        "STABLE")
            BUILD_STATUS="STABLE"
            break
            ;;
        "BETA")
            BUILD_STATUS="BETA"
            break
            ;;
        "ALPHA")
            BUILD_STATUS="ALPHA"
            break
            ;;
        "TEST")
            BUILD_STATUS="TEST"
            break
            ;;
        "CUSTOM")
            read -rp "Enter custom tag: " CUSTOM_TAG
            BUILD_STATUS="$CUSTOM_TAG"
            break
            ;;
        *)
            echo "Invalid choice. Try again."
            ;;
    esac
done
echo ""
echo ">>> Selected Build Type: $BUILD_STATUS"
echo ""

FINAL_KERNEL_ZIP="${KERNEL_NAME}-${BUILD_STATUS}-Kernel-${DEVICE_CODENAME}-$(date '+%Y%m%d').zip"

# MarkdownV2 escape function for Telegram
escape_markdown() {
    echo "$1" | sed -e 's/[][()_.~`>#+=|{}!\\-]/\\&/g'
}

# Detect Compiler
if [ -d "$COMPILER_PATH" ]; then
    export PATH="$COMPILER_PATH:$PATH"
    COMPILER_NAME="$($COMPILER_PATH/clang --version | head -n 1 | sed -E 's/\(.*\)//' | awk '{$1=$1;print}')"
else
    COMPILER_NAME="Unknown Compiler"
fi

export ARCH=arm64
export KBUILD_BUILD_HOST="アムリトクン"
export KBUILD_BUILD_USER="私は彼女を愛している"
export KBUILD_COMPILER_STRING="$COMPILER_NAME"

# Telegram Bot Config
BOT_TOKEN=""
CHAT_ID=""

# Function to send Telegram message
send_message() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
         -d "chat_id=${CHAT_ID}" \
         -d "parse_mode=MarkdownV2" \
         -d "text=$1"
}

# Upload to SF
upload_to_sourceforge() {
    local ZIP_FILE="$1"
    local REMOTE_PATH="/home/frs/project/${SF_PROJECT:0:1}/${SF_PROJECT:0:1}${SF_PROJECT:1:1}/${SF_PROJECT}/${SF_FOLDER}/"

    echo "Uploading $ZIP_FILE to SourceForge..."

    rsync -avP --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
        "$ZIP_FILE" \
        "${SF_USER}@frs.sourceforge.net:${REMOTE_PATH}"

    if [ $? -ne 0 ]; then
        send_message "$(escape_markdown "❌ SourceForge upload failed!")"
    else
        send_message "$(escape_markdown "📤 Uploaded to SourceForge successfully")"
    fi
}
# Push changelogs
push_changelog() {
    local DATE_TAG
    DATE_TAG="$(date '+%Y-%m-%d_%H-%M')"
    local FILE="${CHANGELOG_DEVICE_DIR}/${DATE_TAG}.txt"

    mkdir -p "${CHANGELOG_DEVICE_DIR}"

    {
        echo "Kernel: ${KERNEL_NAME}"
        echo "Device: ${DEVICE_NAME} (${DEVICE_CODENAME})"
        echo "Build Type: ${BUILD_STATUS}"
        echo "Compiler: ${COMPILER_NAME}"
        echo "Date: ${DATE_TAG}"
        echo ""
        echo "==== Latest Commits ===="
        git log --oneline -100
    } > "${FILE}"

    cd "${CHANGELOG_REPO}" || exit 1
    git pull --rebase
    git add "${FILE}"
    git commit -m "changelog(${DEVICE_CODENAME}): ${KERNEL_NAME} ${BUILD_STATUS} ${DATE_TAG}"
    git push
}


# Clone Clang if missing
if ! [ -d "$HOME/clang" ]; then
    send_message "$(escape_markdown "⚙️ Clang not found! Cloning...")"
    if ! git clone -q https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git -b 15.0 --depth=1 --single-branch ~/clang; then
        send_message "$(escape_markdown "❌ Cloning failed! Aborting...")"
        exit 1
    fi
fi

# Start build
BUILD_START=$(date +"%s")

send_message "*$(escape_markdown "$KERNEL_NAME") Kernel Build Started\!*
📱 *Device:* \`$(escape_markdown "$DEVICE_NAME") \($(escape_markdown "$DEVICE_CODENAME")\)\`
🖥 *Building on:* \`$(escape_markdown "$BUILD_HOSTNAME")\`
⚙️ *Compiler:* \`$(escape_markdown "$COMPILER_NAME")\`
🔰 *Build Status:* \`$(escape_markdown "$BUILD_STATUS")\`"

# Clean and defconfig
make O=out clean
make mrproper
make $KERNEL_DEFCONFIG O=out

# Compile Kernel
make -j$(nproc) O=out \
    ARCH=arm64 \
    CC=clang \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LD=ld.lld \
    LLVM=1 \
    LLVM_IAS=1

# Check build success
if [ ! -f "$PWD/out/arch/arm64/boot/Image" ]; then
    send_message "$(escape_markdown "❌ Build failed! Image not found.")"
    exit 1
fi

send_message "$(escape_markdown "✅ ${KERNEL_NAME} Kernel built successfully\! Zipping files...")"

# Package kernel
rm -rf $ANYKERNEL3_DIR/Image $ANYKERNEL3_DIR/dtbo.img $ANYKERNEL3_DIR/dtb
cp $PWD/out/arch/arm64/boot/Image $ANYKERNEL3_DIR/
cp $PWD/out/arch/arm64/boot/dtbo.img $ANYKERNEL3_DIR/
cp $PWD/out/arch/arm64/boot/dts/vendor/xiaomi/peux.dtb $ANYKERNEL3_DIR/dtb

cd $ANYKERNEL3_DIR/
zip -r9 "../$FINAL_KERNEL_ZIP" * -x README $FINAL_KERNEL_ZIP
cd ..

# Upload ONLY release/stable builds to SourceForge
if [ "$BUILD_STATUS" = "STABLE" ] || [ "$BUILD_STATUS" = "RELEASE" ]; then
    upload_to_sourceforge "$PWD/$FINAL_KERNEL_ZIP"
else
    echo "Skipping SourceForge upload (non-release build)"
fi

# Push changelog only for release/stable builds
if [ "$BUILD_STATUS" = "STABLE" ] || [ "$BUILD_STATUS" = "RELEASE" ]; then
    echo "Pushing changelog..."
    push_changelog
else
    echo "Skipping changelog push (non-release build)"
fi

# Upload only if NOT a release/STABLE build
if [ "$BUILD_STATUS" != "STABLE" ] && [ "$BUILD_STATUS" != "RELEASE" ]; then
    send_message "$(escape_markdown "📤 Uploading ${KERNEL_NAME} Kernel zip...")"

    curl -F chat_id="$CHAT_ID" \
         -F document=@"../$FINAL_KERNEL_ZIP" \
         -F parse_mode="MarkdownV2" \
         -F caption="✅ *$(escape_markdown "$KERNEL_NAME") Kernel for $(escape_markdown "$DEVICE_CODENAME") $(escape_markdown "$DEVICE_NAME")*
🖥️ *Built on:* \`$(escape_markdown "$BUILD_HOSTNAME")\`
⚙️ *Compiler:* \`$(escape_markdown "$COMPILER_NAME")\`
🔰 *Build Status:* \`$(escape_markdown "$BUILD_STATUS")\`" \
     "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
fi

# Finish
BUILD_END=$(date +"%s")
BUILD_TIME=$((BUILD_END - BUILD_START))

send_message "$(escape_markdown "🚀 ${KERNEL_NAME} Kernel build completed in $((BUILD_TIME / 60)) min $((BUILD_TIME % 60)) sec")"

# Clean up
rm -rf out/
rm -rf $ANYKERNEL3_DIR/Image $ANYKERNEL3_DIR/dtbo.img $ANYKERNEL3_DIR/dtb

exit 0

