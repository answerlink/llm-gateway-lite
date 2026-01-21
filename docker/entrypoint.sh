#!/bin/sh
set -e

CONFIG_DIR=${GATEWAY_CONFIG_DIR:-/etc/llm-gateway/conf.d}

# 创建日志目录
mkdir -p /var/log/llm-gateway
# 预创建 upstream.log，避免 worker 无权限创建新文件
touch /var/log/llm-gateway/upstream.log
chmod 666 /var/log/llm-gateway/upstream.log
# 创建 /app/logs 目录以避免 OpenResty 默认路径检查的警告
mkdir -p /app/logs

if [ ! -d "$CONFIG_DIR" ]; then
  echo "Config dir not found: $CONFIG_DIR" >&2
fi

# 将环境变量写入文件供 Lua 读取（解决 OpenResty 环境变量访问问题）
mkdir -p /tmp/gateway
echo "${GATEWAY_AUTH_ENABLED:-true}" > /tmp/gateway/auth_enabled

# 启动 crond 守护进程（用于定期日志轮转）
crond -b -l 2

# 验证 logrotate 配置（使用 verbose 模式，不使用 debug 模式）
if logrotate -v /etc/logrotate.d/llm-gateway.conf > /dev/null 2>&1; then
  echo "✅ 日志轮转已配置: 每天凌晨2点自动轮转，保留30天"
else
  echo "⚠️  警告: logrotate 配置可能有问题，但服务继续启动"
fi

exec openresty -g 'daemon off;' -p /app -c /app/nginx/nginx.conf
