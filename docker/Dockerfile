FROM openresty/openresty:alpine

# 安装必要的工具：logrotate（日志轮转）和 cronie（定时任务）
RUN apk add --no-cache ca-certificates logrotate dcron

WORKDIR /app

COPY nginx /app/nginx
COPY lua /app/lua
COPY docker/entrypoint.sh /app/entrypoint.sh
COPY docker/logrotate.conf /etc/logrotate.d/llm-gateway.conf
COPY docker/crontab /etc/crontabs/root

RUN chmod +x /app/entrypoint.sh && \
    chmod 0644 /etc/logrotate.d/llm-gateway.conf && \
    chmod 0644 /etc/crontabs/root

EXPOSE 8080

ENTRYPOINT ["/app/entrypoint.sh"]
