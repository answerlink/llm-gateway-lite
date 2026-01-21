# Config

## providers.yaml

```yaml
version: 1
providers:
  provider_name:
    type: openai_compat
    base_url: "https://api.example.com"
    endpoints:
      chat_completions: "/v1/chat/completions"
      embeddings: "/v1/embeddings"
    auth:
      mode: "bearer"
      header: "Authorization"
      prefix: "Bearer "
    headers:
      "X-Custom": "value"
    keys:
      - id: "key-id"
        value: "PROVIDER_API_KEY"
    weight: 1
    timeout_ms: 60000
    ssl_verify: true
```

## models.yaml

```yaml
version: 1
models:
  std_model:
    aliases:
      - "alias"
    provider_map:
      provider_name: "provider_model"
    policy:
      default_provider: "provider_name"
```

## Environment

- `GATEWAY_CONFIG_DIR`: config directory (default `/etc/llm-gateway/conf.d`).
- `GATEWAY_CONFIG_FILE`: load a single config file.
- `GATEWAY_RELOAD_INTERVAL_SEC`: hot reload interval (default `5`).
- `GATEWAY_KEY_COOLDOWN_SEC`: cooldown seconds for invalid keys (default `600`).
- `GATEWAY_EXPOSE_SELECTION`: set to `1` to return `X-Selected-Provider` and `X-Selected-Key-Id`.
