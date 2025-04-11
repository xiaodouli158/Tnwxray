#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 切换到Nginx目录
cd "$SCRIPT_DIR"

# 启动Nginx，使用相对路径
./nginx-static -c nginx.conf "$@"
