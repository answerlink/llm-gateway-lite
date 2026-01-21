#!/bin/bash
# LLM Gateway Docker 日志轮转脚本
# 用途：手动触发容器内的日志轮转（不依赖宿主机 cron）
# 使用：./scripts/rotate-logs-docker.sh

set -e

CONTAINER_NAME="llm-gateway-lite-llm-gateway-1"

echo "=== Docker 容器日志轮转 ==="
echo "容器名称: $CONTAINER_NAME"
echo "时间: $(date)"
echo ""

# 检查容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ 错误: 容器 $CONTAINER_NAME 未运行"
    echo ""
    echo "可用的容器："
    docker ps --format "  - {{.Names}}"
    exit 1
fi

echo "1. 执行日志轮转..."
docker exec "$CONTAINER_NAME" /usr/sbin/logrotate -f /etc/logrotate.d/llm-gateway.conf

echo ""
echo "2. 当前日志文件状态:"
docker exec "$CONTAINER_NAME" ls -lh /var/log/llm-gateway/

echo ""
echo "3. 轮转后的日志文件:"
docker exec "$CONTAINER_NAME" sh -c "ls -lht /var/log/llm-gateway/*.gz 2>/dev/null | head -5 || echo '  无压缩日志文件'"

echo ""
echo "✅ 日志轮转完成！"
