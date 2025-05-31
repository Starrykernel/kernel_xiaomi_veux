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
KERNEL_NAME="Paimon"      # Kernel name
KERNEL_DEFCONFIG="${DEVICE_CODENAME}_defconfig"
ANYKERNEL3_DIR=$PWD/AnyKernel3/
FINAL_KERNEL_ZIP="${KERNEL_NAME}-[KSU]-Kernel-${DEVICE_CODENAME}-$(date '+%Y%m%d').zip"
BUILD_STATUS="STABLE"

BUILD_HOSTNAME=$(hostname)
COMPILER_PATH="$HOME/clang-r547379/bin"

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
export KBUILD_BUILD_HOST=$BUILD_HOSTNAME
export KBUILD_BUILD_USER="GoogleFucksYou"
export KBUILD_COMPILER_STRING="$COMPILER_NAME"

# Telegram Bot Config
BOT_TOKEN="put telegram bot token"
CHAT_ID="put telegram channel/chat id"

# Function to send Telegram message
send_message() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
         -d "chat_id=${CHAT_ID}" \
         -d "parse_mode=MarkdownV2" \
         -d "text=$1"
}

# Clone Clang if missing
if ! [ -d "$HOME/clang-r547379" ]; then
    send_message "$(escape_markdown "⚙️ Clang not found! Cloning...")"
    if ! git clone -q https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git -b 15.0 --depth=1 --single-branch ~/clang-r547379; then
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

# Upload to Telegram
send_message "$(escape_markdown "📤 Uploading ${KERNEL_NAME} Kernel zip...")"
curl -F chat_id="$CHAT_ID" \
     -F document=@"../$FINAL_KERNEL_ZIP" \
     -F parse_mode="MarkdownV2" \
     -F caption="✅ *$(escape_markdown "$KERNEL_NAME") Kernel for $(escape_markdown "$DEVICE_CODENAME") $(escape_markdown "$DEVICE_NAME")*
🖥️ *Built on:* \`$(escape_markdown "$BUILD_HOSTNAME")\`
⚙️ *Compiler:* \`$(escape_markdown "$COMPILER_NAME")\`
🔰 *Build Status:* \`$(escape_markdown "$BUILD_STATUS")\`" \
     "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"

# Finish
BUILD_END=$(date +"%s")
BUILD_TIME=$((BUILD_END - BUILD_START))

send_message "$(escape_markdown "🚀 ${KERNEL_NAME} Kernel build completed in $((BUILD_TIME / 60)) min $((BUILD_TIME % 60)) sec")"

# Clean up
rm -rf out/
rm -rf $ANYKERNEL3_DIR/Image $ANYKERNEL3_DIR/dtbo.img $ANYKERNEL3_DIR/dtb

exit 0