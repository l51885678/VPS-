#!/usr/bin/env bash
set -euo pipefail

echo "开始安装..."

# 检测系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "你的系统是: $PRETTY_NAME"
else
    echo "无法识别系统"
    exit 1
fi

# 安装依赖
if command -v apt >/dev/null 2>&1; then
    apt update && apt install -y curl
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl
else
    echo "不支持的包管理器"
    exit 1
fi

echo "安装完成！"