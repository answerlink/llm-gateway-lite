# LLM Gateway Lite

<div align="center">

🚀 **轻量级、高性能的 LLM API 网关** 🚀

[![Docker](https://img.shields.io/badge/Docker-20.10%2B-blue)](https://www.docker.com/)
[![OpenResty](https://img.shields.io/badge/OpenResty-Latest-brightgreen)](https://openresty.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

*基于 OpenResty 构建，为多个 LLM Provider 提供统一的 OpenAI 兼容 API 接口*

[特性](#-核心特性) • [快速开始](#-快速开始) • [配置说明](#-配置说明) • [路由策略](#-路由策略) • [文档](#-文档)

</div>

---

## 🌟 核心特性

### 🎯 统一接口
- **OpenAI 兼容 API**：支持 `/v1/chat/completions`、`/v1/embeddings`、`/v1/models` 等标准接口
- **灵活路径匹配**：支持 `/v1/`、`/v1beta/`、`/v2/`、`/api/v1/` 等多种路径格式
- **统一模型管理**：通过模型别名统一访问不同 Provider 的模型

### 🔄 智能路由
- **优先级路由**：通过 `default_provider` 指定首选 Provider
- **加权负载均衡**：通过 `weight` 配置按权重分配流量
- **自动故障转移**：Provider 不可用时自动切换到备用
- **多 Key 轮询**：支持多个 API Key 轮询使用，提高配额利用率

### ⚡ 高性能
- **异步非阻塞**：基于 OpenResty 的高性能异步架构
- **流式响应**：完整支持 Server-Sent Events (SSE) 流式输出
- **连接复用**：HTTP/1.1 keepalive 连接池
- **零拷贝转发**：最小化内存占用和延迟

### 🛡️ 企业级
- **热配置重载**：配置文件变更自动检测并重载，无需重启服务
- **完善的日志系统**：
  - 访问日志（access.log）
  - 应用日志（app.log）
  - 错误日志（error.log）
  - 上游请求日志（upstream.log，包含完整请求/响应）
- **自动日志轮转**：容器内自动日志轮转，保留 30 天
- **Key 冷却机制**：失效的 Key 自动冷却，避免频繁重试
- **可观测性**：支持通过响应头暴露 Provider 和 Key 选择信息

### 🔌 多 Provider 支持
- OpenAI
- OpenRouter
- Google Gemini
- 智谱 AI (GLM)
- 阿里云百炼
- 其他 OpenAI 兼容 API

---

## 🚀 快速开始

### 环境要求

- Docker 20.10+
- Docker Compose 2.0+

### 三步部署

#### 1️⃣ 克隆项目

```bash
git clone https://github.com/answerlink/llm-gateway-lite.git
cd llm-gateway-lite
```

#### 2️⃣ 配置 API Keys

```bash
# 复制示例配置
cp configs/providers.yaml.example configs/providers.yaml
cp configs/models.yaml.example configs/models.yaml

# 编辑 providers.yaml，填入你的 API Keys
vim configs/providers.yaml
```

**providers.yaml 示例**：

```yaml
version: 1

providers:
  openai:
    type: openai_compat
    base_url: "https://api.openai.com"
    endpoints:
      chat_completions: "/v1/chat/completions"
    auth:
      mode: "bearer"
      header: "Authorization"
      prefix: "Bearer "
    keys:
      - id: "openai-key-1"
        value: "sk-your-api-key-here"  # 直接填写 API Key
    weight: 5
    timeout_ms: 60000
```

**models.yaml 示例**：

```yaml
version: 1

models:
  gpt-3.5-turbo:
    aliases:
      - "gpt-3.5-turbo"
      - "chatgpt3.5"
    provider_map:
      openai: "gpt-3.5-turbo"
      openrouter: "openai/gpt-3.5-turbo"
    policy:
      default_provider: "lark-code-plan"  # 优先使用 lark-code-plan
```

#### 3️⃣ 启动服务

```bash
# 构建并启动
docker-compose up -d --build

# 查看日志
docker-compose logs -f
```

### 测试接口

```bash
# 查看可用模型
curl http://localhost:13030/v1/models

# 测试聊天接口
curl http://localhost:13030/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# 测试流式输出
curl http://localhost:13030/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Count to 10"}],
    "stream": true
  }'
```

### 支持的路径格式

网关支持多种路径格式，灵活适配不同客户端：

```bash
# OpenAI 标准格式
http://localhost:13030/v1/chat/completions

# Google AI 风格
http://localhost:13030/v1beta/openai/chat/completions

# 自定义版本号
http://localhost:13030/v2/chat/completions
http://localhost:13030/v3/anything/chat/completions

# 规则：只要以 /chat/completions 结尾即可
```

---

## 📋 配置说明

### 配置文件结构

```
configs/
├── providers.yaml    # Provider 配置（API Keys、endpoints、权重）
└── models.yaml       # 模型配置（别名、路由策略）
```

### providers.yaml 配置项

| 配置项 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `type` | string | ✅ | Provider 类型，目前支持 `openai_compat` |
| `base_url` | string | ✅ | API 基础 URL |
| `endpoints` | object | ✅ | 端点配置（chat_completions、embeddings） |
| `auth` | object | ✅ | 认证配置（mode、header、prefix） |
| `keys` | array | ✅ | API Key 列表（支持多 Key 轮询） |
| `weight` | int | ❌ | 权重（用于负载均衡，默认 1） |
| `timeout_ms` | int | ❌ | 超时时间（毫秒，默认 60000） |
| `ssl_verify` | bool | ❌ | 是否验证 SSL 证书（默认 true） |

### models.yaml 配置项

| 配置项 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `aliases` | array | ✅ | 模型别名列表 |
| `provider_map` | object | ✅ | Provider 到真实模型名的映射 |
| `policy.default_provider` | string | ❌ | 首选 Provider（优先级最高） |
| `policy.allow_providers` | array | ❌ | 允许的 Provider 白名单 |

### 环境变量

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `GATEWAY_CONFIG_DIR` | `/etc/llm-gateway/conf.d` | 配置文件目录 |
| `GATEWAY_RELOAD_INTERVAL_SEC` | `5` | 配置热重载检查间隔（秒） |
| `GATEWAY_KEY_COOLDOWN_SEC` | `600` | 失效 Key 冷却时间（秒） |
| `GATEWAY_EXPOSE_SELECTION` | `0` | 是否在响应头中暴露 Provider 和 Key 信息 |
| `GATEWAY_AUTH_ENABLED` | `false` | 是否启用客户端鉴权 |
| `GATEWAY_ADMIN_TOKEN` | 空 | Admin 看板访问令牌（为空则不鉴权） |

### 热配置重载

配置文件修改后会自动重载，**无需重启服务**：

```bash
# 修改配置文件
vim configs/providers.yaml

# 等待 5 秒（默认检查间隔）
# 查看日志确认重载成功
docker-compose logs -f | grep "config loaded"
```

### 轻量可视化看板（内置）

- 统计接口：`/admin/stats?window=60`
- 资源目录接口：`/admin/catalog`
- 可视化页面：
  - 概览：`/admin/dashboard`
  - 模型与渠道：`/admin/dashboard/topology`
- 统计维度：总调用、成功/失败、2xx/4xx/5xx、平均延迟、按分钟趋势
- 数据存储：内存（`ngx.shared_dict`），重启后清零

如果配置了 `GATEWAY_ADMIN_TOKEN`，访问时需要携带：

```bash
# JSON 统计
curl "http://localhost:13030/admin/stats?window=60&admin_token=your-token"

# JSON 资源目录
curl "http://localhost:13030/admin/catalog?admin_token=your-token"

# 浏览器页面
http://localhost:13030/admin/dashboard?admin_token=your-token
http://localhost:13030/admin/dashboard/topology?admin_token=your-token
```

---

## 🎯 路由策略

LLM Gateway 支持**优先级路由**和**加权负载均衡**两种策略。

### 路由选择逻辑

```
📥 请求到达
    ↓
🔍 步骤1: 检查 default_provider
    ├─ 已配置 && 可用 → ✅ 直接使用（优先级最高）
    └─ 未配置 || 不可用 → 进入步骤2
        ↓
⚖️  步骤2: 按 weight 加权随机选择
    ├─ 收集所有可用的 Provider
    ├─ 按权重计算概率
    └─ ✅ 返回选中的 Provider
```

### 场景一：主备模式（推荐）

**适用于**：有明确的主力 Provider 和备用 Provider

**配置示例**：

```yaml
# models.yaml
models:
  gpt-3.5-turbo:
    provider_map:
      openai: "gpt-3.5-turbo"      # 官方 API（主力）
      openrouter: "openai/gpt-3.5-turbo"  # 第三方（备用）
    policy:
      default_provider: "lark-code-plan"   # 优先使用 lark-code-plan

# providers.yaml
providers:
  openai:
    weight: 5  # 权重较高（备用时优先级更高）
    keys:
      - id: "key-1"
        value: "sk-xxx"
  openrouter:
    weight: 1  # 权重较低
    keys:
      - id: "key-1"
        value: "sk-yyy"
```

**效果**：
- ✅ 100% 流量走 `openai`（只要可用）
- 🔄 `openai` 不可用时，自动切换到 `openrouter`

### 场景二：负载均衡模式

**适用于**：多个 Provider 价格和质量相当，希望分散流量

**配置示例**：

```yaml
# models.yaml
models:
  gpt-3.5-turbo:
    provider_map:
      openai: "gpt-3.5-turbo"
      azure: "gpt-35-turbo"
    # 不配置 default_provider，直接按权重分配

# providers.yaml
providers:
  openai:
    weight: 7  # 70% 流量
    keys:
      - id: "key-1"
        value: "sk-xxx"
  azure:
    weight: 3  # 30% 流量
    keys:
      - id: "key-1"
        value: "xxx"
```

**效果**：
- ✅ 70% 流量 → `openai`
- ✅ 30% 流量 → `azure`
- 🔄 某个 Provider 不可用时，流量自动转移到其他 Provider

### 多 Key 轮询

每个 Provider 可配置多个 API Key，网关会按轮询策略使用：

```yaml
providers:
  openai:
    keys:
      - id: "key-1"
        value: "sk-key1"
      - id: "key-2"
        value: "sk-key2"
      - id: "key-3"
        value: "sk-key3"
```

**轮询策略**：
1. 按顺序轮询使用（Round Robin）
2. 失效的 Key 进入冷却期（默认 600 秒）
3. 冷却期内的 Key 不参与轮询
4. 所有 Key 都失效时，Provider 标记为不可用

---

## 📊 日志管理

### 日志文件

项目会生成 4 个日志文件（挂载到 `./logs` 目录）：

| 文件 | 说明 | 用途 |
|------|------|------|
| `access.log` | Nginx 访问日志 | 记录所有 HTTP 请求的基本信息 |
| `app.log` | 应用日志（info 级别） | 记录应用运行状态、配置加载等 |
| `error.log` | 错误日志（warn 级别） | 只记录错误和警告信息 |
| `upstream.log` | 上游请求日志 | 记录完整的请求（用于调试） |

### 自动日志轮转

项目已配置**容器内自动日志轮转**，无需额外配置：

- ✅ **定时轮转**：每天凌晨 2 点自动执行
- ✅ **大小轮转**：日志文件超过 100MB 自动轮转
- ✅ **自动压缩**：轮转后自动 gzip 压缩
- ✅ **保留策略**：保留最近 30 天的日志

---

## 🛠️ 运维指南

### 启动/停止服务

```bash
# 启动
docker-compose up -d

# 停止
docker-compose down

# 重启
docker-compose restart

# 重新构建
docker-compose up -d --build
```

### 更新配置

```bash
# 修改配置文件
vim configs/providers.yaml

# 配置会在 5 秒内自动重载（无需重启）
# 查看日志确认
docker-compose logs -f | grep "config loaded"
```

---

## 🤝 贡献指南

欢迎贡献代码、报告问题或提出建议！

### 如何贡献

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

### 报告问题

如果你发现了 bug 或有功能建议，请[创建 Issue](https://github.com/answerlink/llm-gateway-lite/issues)。

提交 Issue 时请包含：
- 问题描述
- 复现步骤
- 预期行为
- 实际行为
- 相关日志（`logs/error.log` 或 `docker-compose logs`）

---

## 📄 许可证

本项目采用 [Apache License 2.0](LICENSE) 开源协议。

---

## 🙏 致谢

- [OpenResty](https://openresty.org/) - 高性能 Web 平台
- [lua-resty-http](https://github.com/ledgetech/lua-resty-http) - Lua HTTP 客户端
- [lyaml](https://github.com/gvvaughan/lyaml) - Lua YAML 解析器

---

<div align="center">

**⭐️ 如果这个项目对你有帮助，请给个 Star！ ⭐️**

Made with ❤️ by [AnswerLink]

</div>
