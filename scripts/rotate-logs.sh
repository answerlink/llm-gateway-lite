#!/bin/bash
# LLM Gateway 日志轮转脚本
# 用途：手动或通过 cron 定期轮转日志
# 使用：sudo ./scripts/rotate-logs.sh

set -e

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误: 此脚本需要 root 权限"
    echo "请使用: sudo ./scripts/rotate-logs.sh"
    exit 1
fi

# 配置
LOGS_DIR="/export/llmuser/projects/llm-gateway-lite/logs"
KEEP_DAYS=30
DATE=$(date +%Y%m%d-%H%M%S)

echo "=== 开始日志轮转 ==="
echo "时间: $(date)"
echo "日志目录: $LOGS_DIR"
echo "保留天数: $KEEP_DAYS"
echo ""

cd "$LOGS_DIR" || {
    echo "错误: 无法进入日志目录 $LOGS_DIR"
    exit 1
}

# 检查是否有日志文件
if ! ls *.log >/dev/null 2>&1; then
    echo "警告: 没有找到日志文件"
    exit 0
fi

# 轮转日志文件
echo "1. 轮转日志文件..."
for log in access.log app.log error.log; do
    if [ -f "$log" ]; then
        size=$(du -h "$log" | awk '{print $1}')
        echo "  - 处理 $log (大小: $size)"
        
        # 复制并重命名
        cp "$log" "${log}.${DATE}"
        
        # 清空原文件
        > "$log"
        
        # 压缩
        gzip "${log}.${DATE}"
        echo "    已创建: ${log}.${DATE}.gz"
    else
        echo "  - 跳过 $log (文件不存在)"
    fi
done

echo ""
echo "2. 删除旧日志 (${KEEP_DAYS} 天前)..."
deleted_count=$(find "$LOGS_DIR" -name "*.log.*.gz" -mtime +${KEEP_DAYS} -type f | wc -l)
if [ "$deleted_count" -gt 0 ]; then
    find "$LOGS_DIR" -name "*.log.*.gz" -mtime +${KEEP_DAYS} -type f -delete
    echo "  已删除 $deleted_count 个旧日志文件"
else
    echo "  没有需要删除的旧日志"
fi

echo ""
echo "3. 重载 nginx..."
if docker exec llm-gateway-lite-llm-gateway-1 nginx -s reopen 2>/dev/null; then
    echo "  ✅ Nginx 已重载"
else
    echo "  ⚠️  Nginx 重载失败或容器未运行"
fi

echo ""
echo "4. 当前日志文件状态:"
ls -lh *.log 2>/dev/null || echo "  无当前日志文件"

echo ""
echo "5. 压缩日志文件 (最近 5 个):"
ls -lht *.log.*.gz 2>/dev/null | head -5 || echo "  无压缩日志文件"

echo ""
echo "=== 日志轮转完成 ==="
