# API 文档

LLM Gateway Lite 提供 OpenAI 兼容的 API 接口。

## 基础信息

- **Base URL**: `http://your-host:13030`
- **认证**: 不需要（网关层不需要认证，API Keys 在配置文件中管理）
- **Content-Type**: `application/json`

## 支持的路径格式

网关支持多种路径格式，灵活适配不同客户端：

```
✅ /v1/chat/completions
✅ /v1beta/openai/chat/completions
✅ /v2/chat/completions
✅ /api/v1/chat/completions
✅ 任何以 /chat/completions 结尾的路径
```

## 端点列表

### 1. 聊天补全（Chat Completions）

#### 请求

```http
POST /v1/chat/completions
Content-Type: application/json
```

```json
{
  "model": "gpt-3.5-turbo",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant."
    },
    {
      "role": "user",
      "content": "Hello!"
    }
  ],
  "temperature": 0.7,
  "max_tokens": 1000,
  "stream": false
}
```

#### 响应

```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "gpt-3.5-turbo",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you today?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 20,
    "total_tokens": 30
  }
}
```

#### 流式响应

当 `stream: true` 时，使用 Server-Sent Events (SSE) 格式：

```json
data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-3.5-turbo","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-3.5-turbo","choices":[{"index":0,"delta":{"content":"!"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-3.5-turbo","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

#### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model` | string | ✅ | 模型名称或别名（在 models.yaml 中配置） |
| `messages` | array | ✅ | 消息列表 |
| `temperature` | float | ❌ | 采样温度（0-2，默认 1） |
| `max_tokens` | integer | ❌ | 最大生成 token 数 |
| `top_p` | float | ❌ | 核采样（0-1，默认 1） |
| `n` | integer | ❌ | 生成的回复数量（默认 1） |
| `stream` | boolean | ❌ | 是否流式输出（默认 false） |
| `stop` | string/array | ❌ | 停止序列 |
| `presence_penalty` | float | ❌ | 存在惩罚（-2.0 到 2.0） |
| `frequency_penalty` | float | ❌ | 频率惩罚（-2.0 到 2.0） |

---

### 2. 文本嵌入（Embeddings）

#### 请求

```http
POST /v1/embeddings
Content-Type: application/json
```

```json
{
  "model": "text-embedding-ada-002",
  "input": "Hello world"
}
```

#### 响应

```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "embedding": [0.0023064255, -0.009327292, ...],
      "index": 0
    }
  ],
  "model": "text-embedding-ada-002",
  "usage": {
    "prompt_tokens": 2,
    "total_tokens": 2
  }
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model` | string | ✅ | 嵌入模型名称 |
| `input` | string/array | ✅ | 输入文本（字符串或字符串数组） |

---

### 3. 模型列表（Models）

#### 请求

```http
GET /v1/models
```

#### 响应

```json
{
  "object": "list",
  "data": [
    {
      "id": "gpt-3.5-turbo",
      "object": "model",
      "created": 1677610602,
      "owned_by": "openai",
      "providers": ["openai", "openrouter"]
    },
    {
      "id": "gpt-4o-mini",
      "object": "model",
      "created": 1677610602,
      "owned_by": "openai",
      "providers": ["openai", "openrouter"]
    }
  ]
}
```

---

## 响应头

### 标准响应头

```
Content-Type: application/json
X-Request-ID: req_abc123
```

### 可观测性响应头

当设置 `GATEWAY_EXPOSE_SELECTION=1` 时，响应头会包含：

```
X-Selected-Provider: openai
X-Selected-Key-Id: openai-key-1
```

这些响应头用于调试和可观测性，显示网关实际选择的 Provider 和 API Key。

---

## 错误响应

### 格式

```json
{
  "error": {
    "message": "错误描述",
    "type": "invalid_request_error",
    "code": "model_not_found"
  }
}
```

### 常见错误码

| HTTP 状态码 | 错误类型 | 说明 |
|------------|---------|------|
| 400 | invalid_request_error | 请求参数错误 |
| 401 | authentication_error | 认证失败（上游 API Key 无效） |
| 404 | not_found_error | 模型或资源不存在 |
| 429 | rate_limit_error | 请求频率超限 |
| 500 | api_error | 内部服务器错误 |
| 503 | service_unavailable | 所有 Provider 都不可用 |

---

## 示例代码

### cURL

```bash
# 聊天补全
curl http://localhost:13030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# 流式输出
curl http://localhost:13030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Count to 10"}],
    "stream": true
  }'

# 模型列表
curl http://localhost:13030/v1/models
```

### Python (OpenAI SDK)

```python
from openai import OpenAI

# 配置自定义 base_url
client = OpenAI(
    base_url="http://localhost:13030/v1",
    api_key="dummy"  # 网关不需要 API Key
)

# 聊天补全
response = client.chat.completions.create(
    model="gpt-3.5-turbo",
    messages=[
        {"role": "user", "content": "Hello!"}
    ]
)
print(response.choices[0].message.content)

# 流式输出
stream = client.chat.completions.create(
    model="gpt-3.5-turbo",
    messages=[{"role": "user", "content": "Count to 10"}],
    stream=True
)
for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="")
```

### JavaScript (OpenAI SDK)

```javascript
import OpenAI from 'openai';

// 配置自定义 baseURL
const openai = new OpenAI({
  baseURL: 'http://localhost:13030/v1',
  apiKey: 'dummy'  // 网关不需要 API Key
});

// 聊天补全
async function chat() {
  const response = await openai.chat.completions.create({
    model: 'gpt-3.5-turbo',
    messages: [{ role: 'user', content: 'Hello!' }]
  });
  console.log(response.choices[0].message.content);
}

// 流式输出
async function streamChat() {
  const stream = await openai.chat.completions.create({
    model: 'gpt-3.5-turbo',
    messages: [{ role: 'user', content: 'Count to 10' }],
    stream: true
  });
  
  for await (const chunk of stream) {
    process.stdout.write(chunk.choices[0]?.delta?.content || '');
  }
}

chat();
```

---

## 模型别名

网关支持通过模型别名访问不同 Provider 的模型。别名在 `configs/models.yaml` 中配置。

### 示例

```yaml
models:
  chatgpt3.5:
    aliases:
      - "gpt-3.5-turbo"      # OpenAI 官方名称
      - "chatgpt3.5"         # 简短别名
      - "openai/chatgpt3.5"  # Provider 前缀
    provider_map:
      openai: "gpt-3.5-turbo"
      openrouter: "openai/gpt-3.5-turbo"
```

所有这些别名都可以使用：

```bash
curl ... -d '{"model": "gpt-3.5-turbo", ...}'
curl ... -d '{"model": "chatgpt3.5", ...}'
curl ... -d '{"model": "openai/chatgpt3.5", ...}'
```

---

## 最佳实践

### 1. 错误处理

```python
from openai import OpenAI
import time

client = OpenAI(base_url="http://localhost:13030/v1", api_key="dummy")

def chat_with_retry(messages, max_retries=3):
    for i in range(max_retries):
        try:
            response = client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=messages
            )
            return response
        except Exception as e:
            if i == max_retries - 1:
                raise
            time.sleep(2 ** i)  # 指数退避
```

### 2. 流式处理

```python
def stream_chat(messages):
    stream = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=messages,
        stream=True
    )
    
    full_response = ""
    for chunk in stream:
        if chunk.choices[0].delta.content:
            content = chunk.choices[0].delta.content
            full_response += content
            print(content, end="", flush=True)
    
    return full_response
```

### 3. 超时设置

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:13030/v1",
    api_key="dummy",
    timeout=30.0  # 30 秒超时
)
```

---

## 兼容性

LLM Gateway Lite 完全兼容 OpenAI SDK：

- ✅ Python SDK (openai)
- ✅ JavaScript/TypeScript SDK (openai)
- ✅ 任何支持自定义 base_url 的 OpenAI 兼容客户端

只需修改 `base_url` 即可使用网关。
