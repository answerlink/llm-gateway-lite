# 贡献指南

感谢你考虑为 LLM Gateway Lite 做出贡献！

## 如何贡献

### 报告 Bug

如果你发现了 bug，请[创建 Issue](https://github.com/your-username/llm-gateway-lite/issues/new) 并包含以下信息：

1. **问题描述**：简要描述问题
2. **复现步骤**：详细的复现步骤
3. **预期行为**：你期望发生什么
4. **实际行为**：实际发生了什么
5. **环境信息**：
   - OS 版本
   - Docker 版本
   - Docker Compose 版本
6. **相关日志**：
   - `logs/error.log`
   - `docker-compose logs` 输出

### 提出功能建议

我们欢迎功能建议！请[创建 Issue](https://github.com/your-username/llm-gateway-lite/issues/new) 并说明：

1. **功能描述**：你希望添加什么功能
2. **使用场景**：这个功能解决什么问题
3. **实现思路**：（可选）你认为如何实现

### 提交代码

#### 1. Fork 并克隆仓库

```bash
# Fork 仓库到你的 GitHub 账号
# 然后克隆你的 fork
git clone https://github.com/YOUR_USERNAME/llm-gateway-lite.git
cd llm-gateway-lite
```

#### 2. 创建分支

```bash
# 从 main 分支创建特性分支
git checkout -b feature/your-feature-name

# 或者修复 bug
git checkout -b fix/bug-description
```

#### 3. 开发和测试

```bash
# 修改代码后，本地测试
docker-compose up -d --build

# 运行测试
curl http://localhost:13030/v1/models

# 查看日志
docker-compose logs -f
```

#### 4. 提交更改

```bash
# 添加更改
git add .

# 提交（使用清晰的提交信息）
git commit -m "feat: add support for new provider"

# 或者
git commit -m "fix: resolve timeout issue in streaming"
```

**提交信息规范**：

- `feat:` - 新功能
- `fix:` - Bug 修复
- `docs:` - 文档更新
- `style:` - 代码格式（不影响功能）
- `refactor:` - 重构（不改变功能）
- `perf:` - 性能优化
- `test:` - 测试相关
- `chore:` - 构建/工具相关

#### 5. 推送并创建 Pull Request

```bash
# 推送到你的 fork
git push origin feature/your-feature-name
```

然后在 GitHub 上创建 Pull Request。

### Pull Request 规范

一个好的 PR 应该包含：

1. **清晰的标题**：简要描述更改
2. **详细的描述**：
   - 更改了什么
   - 为什么要这样更改
   - 如何测试
3. **关联 Issue**：如果相关，使用 `Closes #123` 关联 Issue
4. **截图/日志**：如果适用，添加截图或日志输出

### 代码规范

#### Lua 代码

- 使用 2 空格缩进
- 变量名使用 `snake_case`
- 函数名使用 `snake_case`
- 添加必要的注释

```lua
-- 好的示例
local function select_provider(model_name, exclude_providers)
  -- 实现逻辑
end

-- 不好的示例
local function SelectProvider(modelName, excludeProviders)
  -- 实现逻辑
end
```

#### YAML 配置

- 使用 2 空格缩进
- 字符串使用双引号
- 添加注释说明

```yaml
# 好的示例
providers:
  openai:
    type: "openai_compat"
    base_url: "https://api.openai.com"
    # API Keys 列表
    keys:
      - id: "key-1"
        value: "sk-xxx"
```

#### Nginx 配置

- 使用 2 空格缩进
- 每个指令单独一行
- 添加注释说明

```nginx
# 好的示例
location ~ ^/.*/chat/completions$ {
  # 处理聊天补全请求
  content_by_lua_file /app/lua/handlers/chat_completions.lua;
}
```

### 文档

如果你的更改涉及用户可见的功能，请更新相关文档：

- `README.md` - 主要文档
- `docs/*.md` - 详细文档
- 配置示例文件

### 测试

在提交 PR 前，请确保：

- [ ] 代码可以成功构建：`docker-compose build`
- [ ] 服务可以正常启动：`docker-compose up -d`
- [ ] 基本功能可用：`curl http://localhost:13030/v1/models`
- [ ] 没有引入新的错误日志：`tail logs/error.log`
- [ ] 配置文件可以正常加载：检查日志中的 "config loaded"

### 审查流程

1. 提交 PR 后，维护者会进行代码审查
2. 如果需要修改，请在原分支上继续提交
3. 通过审查后，维护者会合并 PR
4. 你的贡献会出现在下一个版本的更新日志中

### 行为准则

- 尊重所有贡献者
- 欢迎建设性的反馈
- 专注于对项目最有利的事情
- 展现同理心

## 开发环境设置

### 本地开发

```bash
# 克隆仓库
git clone https://github.com/your-username/llm-gateway-lite.git
cd llm-gateway-lite

# 复制配置文件
cp configs/providers.yaml.example configs/providers.yaml
cp configs/models.yaml.example configs/models.yaml

# 编辑配置，添加测试用的 API Keys
vim configs/providers.yaml

# 启动开发环境
docker-compose up -d --build

# 查看日志
docker-compose logs -f
```

### 调试技巧

#### 1. 查看详细日志

```bash
# 应用日志（info 级别）
tail -f logs/app.log

# 错误日志
tail -f logs/error.log

# 上游请求日志（包含完整请求/响应）
tail -f logs/upstream.log
```

#### 2. 进入容器

```bash
# 进入容器内部
docker exec -it llm-gateway-lite-llm-gateway-1 sh

# 查看 nginx 配置
cat /app/nginx/nginx.conf

# 测试 nginx 配置
nginx -t

# 重载 nginx
nginx -s reload
```

#### 3. 测试配置重载

```bash
# 修改配置文件
vim configs/providers.yaml

# 观察日志，等待自动重载（5秒）
docker-compose logs -f | grep "config loaded"
```

#### 4. 手动触发请求

```bash
# 测试聊天接口
curl -v http://localhost:13030/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "test"}]
  }'

# 查看响应头（包含 Provider 信息）
curl -I http://localhost:13030/v1/models
```

## 项目架构

```
请求流程：
1. 客户端请求 → Nginx (gateway.conf)
2. Nginx → Lua Handler (chat_completions.lua)
3. Lua → 加载配置 (loader.lua)
4. Lua → 选择 Provider (路由策略)
5. Lua → 发送请求到上游 (http_client.lua)
6. 上游响应 → 返回给客户端
7. log_by_lua → 记录日志 (log.lua)
```

### 关键模块

- `lua/config/loader.lua` - 配置加载和热重载
- `lua/core/http_client.lua` - HTTP 客户端（发送上游请求）
- `lua/core/auth.lua` - Key 管理和轮询
- `lua/core/observe.lua` - 日志记录和可观测性
- `lua/handlers/chat_completions.lua` - 聊天接口处理
- `lua/handlers/openai_compat.lua` - OpenAI 兼容层

## 获取帮助

如果你在贡献过程中遇到问题：

1. 查看 [文档](docs/)
2. 搜索 [已有 Issues](https://github.com/your-username/llm-gateway-lite/issues)
3. 在 [Discussions](https://github.com/your-username/llm-gateway-lite/discussions) 提问
4. 创建新的 Issue

## 感谢

感谢所有为这个项目做出贡献的人！你的努力让这个项目变得更好。

---

再次感谢你的贡献！🎉
