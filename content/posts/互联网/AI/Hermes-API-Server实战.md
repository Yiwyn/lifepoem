+++
title = 'Hermes API Server 实战'
date = 2026-09-16T21:30:00+08:00
categories = ["AI"]
tags = ["AI Agent", "Hermes", "Spring AI", "LLM"]
draft = false
+++

### 背景

> 传统的 LLM API 只提供模型推理能力，业务系统想要一个"能动手"的 Agent（执行命令、读写文件、网页搜索），往往需要自己搭一层工具编排。Hermes Agent 提供了另一种思路：把完整的 Agent 运行时直接暴露为 HTTP 端点，即它的 API Server。
> 笔者近期围绕 API Server 做了一轮完整调研与接入验证，涉及配置排障、多轮对话选型、长任务处理以及 Spring AI 集成，本文对过程中的结论做一个整理。

#### 一、定位：Agent 运行时，不是 LLM 代理

先看架构：

```
前端 (Open WebUI / 自研平台 / curl)
        │  HTTP
        ▼
Hermes API Server (:8642)          ← Agent 运行时
        │  创建服务端 AIAgent
        ▼
工具调用：终端 / 文件 / 搜索 / 记忆 / 技能 / MCP
        │
        ▼
最终回复（流式/非流式）
```

与传统 LLM API 对比：

| 维度 | 传统 LLM API | Hermes API Server |
| ---- | ------------ | ----------------- |
| 提供的能力 | 模型推理（prompt → 补全文本） | 完整 Agent 运行时（推理 + 工具执行） |
| 工具调用 | 客户端自行编排 | 服务端内置（终端/文件/搜索/记忆/技能/MCP） |
| 提问"目录下有几个文件" | 瞎猜或编造 | 真实执行 `ls` 后给出准确结果 |

定位上有一个关键认知：**API Server 是 Agent 运行时，不是纯代理**。每个请求会在 API Server 所在主机上创建服务端 `AIAgent` 实例，工具调用全部在**那台机器**上执行。

由此引出一个部署上的推论：工具永远在 API Server 所在的主机上运行。如果笔记本上的 Open WebUI 指向远程服务器，工具就跑在远程服务器上，与笔记本无关。因此部署位置需要提前规划——想让 Agent 查数据库、读文件、访问内网服务，就把它部署在具备这些访问条件的服务器上。官方路线图上有"远程大脑 + 本地双手"的拆分运行时规划（issue #18715），但当前版本不支持。

#### 二、快速上手

配置写入 `~/.hermes/.env`：

```bash
openssl rand -hex 24    # 生成强随机 Key，必须 ≥16 字符，占位符会被安全校验拒绝启动
API_SERVER_ENABLED=true
API_SERVER_KEY=<上一步生成的 hex>
```

启动网关：

```bash
hermes gateway
# [API Server] API server listening on http://127.0.0.1:8642
```

验证：

```bash
curl http://127.0.0.1:8642/health    # 存活探针，免认证
curl -H "Authorization: Bearer $KEY" http://127.0.0.1:8642/v1/models    # 模型发现，需 Bearer 认证
curl http://localhost:8642/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "hermes-agent", "messages": [{"role": "user", "content": "Hello!"}]}'
```

主要环境变量：

| 变量 | 默认值 | 说明 |
| ---- | ------ | ---- |
| `API_SERVER_ENABLED` | `false` | 启用开关 |
| `API_SERVER_PORT` | `8642` | HTTP 端口 |
| `API_SERVER_HOST` | `127.0.0.1` | 绑定地址，默认仅本机 |
| `API_SERVER_KEY` | **必填** | Bearer 认证令牌 |
| `API_SERVER_CORS_ORIGINS` | 无 | 浏览器来源白名单，默认不开 CORS |
| `API_SERVER_MODEL_NAME` | Profile 名 | `/v1/models` 上展示的模型名 |
| `max_concurrent_runs` | `10` | 并发 run 上限，0 表示不限制 |

#### 三、多轮对话：上下文由谁持有

集成时首先需要回答的问题不是技术选型，而是架构问题：**对话历史放在哪一侧？**

Hermes 提供四种方案，按上下文持有方分为两类：

| 方案 | 机制 | 上下文存放 | 适用场景 |
| ---- | ---- | ---------- | -------- |
| ① 不带会话头 | 历史随 `messages` 数组全量重发 | 客户端 | OpenAI SDK、每次全量构造 prompt 的平台 |
| ② `X-Hermes-Session-Id` 头 | 服务端从会话库加载该 ID 的历史，客户端只发最新一条消息 | 服务端 | 省 token，服务端持有上下文 |
| ③ Responses API | `previous_response_id` / `conversation` 参数，服务端从响应链重建完整对话（含全部工具调用与结果） | 服务端（SQLite，LRU 上限 100 条，重启不丢） | 省 token，且需保留工具调用历史 |
| ④ Sessions REST | 先 `POST /api/sessions` 建会话，再向 `/chat` 逐回合发送 | 服务端会话库 | 外部 UI 自建会话管理 |

方案②的请求示例，第二轮起只需发送最新消息：

```bash
curl http://localhost:8642/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "X-Hermes-Session-Id: my-session-001" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"我刚才说我叫什么？"}]}'
# 服务端自动从会话库取该 ID 的历史拼接上下文
```

方案③基于 Responses API（`/v1/responses`），有两个值得注意的设计：

1. 响应链重建的对话**包含之前的所有工具调用与结果**，对"上一步执行了什么命令"这类上下文有直接价值；
2. 除 `previous_response_id` 链式引用外，还支持 `conversation` 参数传入命名会话，服务端自动链到该会话最近的响应，客户端无需自行管理响应 ID。

选型结论：

1. 一问一答、前端自行管理历史 → 方案①，Web 聊天前端基本属于此类；
2. 平台侧要省 token、服务端持有上下文 → 方案②，增加一个请求头即可；
3. 需要保留工具调用历史的连续性 → 方案③；
4. 外部 UI 需要完整的会话生命周期管理（列表、分叉、删除）→ 方案④。

另有一个易混淆点需要单独说明：`X-Hermes-Session-Id` 与 `X-Hermes-Session-Key` 是两个相互独立的请求头。

| 请求头 | 职责 | 特点 |
| ------ | ---- | ---- |
| `X-Hermes-Session-Id` | 上下文连续性：决定本轮请求从会话库加载哪个会话的历史 | 新开对话时会轮换 |
| `X-Hermes-Session-Key` | 长期记忆范围：记忆 Provider 按此范围存取记忆 | 稳定不轮换，多用户环境靠它隔离各终端用户的记忆 |

#### 四、Runs API：长任务的处理方式

这一机制需要重点展开。

先看一个现实约束：Hermes 是完整 Agent 运行时，prompt 自带全量工具上下文（实测约 43k tokens），因此**简单问答的非流式请求也要 17~23 秒**才能返回；多工具、多轮搜索的长任务跑几分钟属于正常情况。业务侧的 HTTP 客户端超时若为 75 秒量级，同步调用必然撞墙。

Runs API 针对这类场景设计，核心模型是**提交与执行解耦**。先看它与 Chat Completions 的整体对比：

| 维度 | Chat Completions | Runs API |
| ---- | ---------------- | -------- |
| 调用模型 | 同步：请求挂起直到 Agent 执行完毕 | 异步：提交后立即返回 `run_id` |
| 响应获取 | HTTP 响应体一次性返回（或 SSE 流式） | 轮询 `GET /v1/runs/{id}` 或订阅 SSE 事件流，两条通道可并用 |
| 长任务适配 | 受客户端 HTTP 超时限制（实测非流式 17~23s 起步，长任务撞墙） | 不受单次 HTTP 超时约束，任务跑几分钟属正常情况 |
| 过程可见性 | 非流式期间客户端无感知；流式可见工具进度 | 全程可观测：工具调用进度、token 增量、生命周期事件、子代理事件 |
| 断线恢复 | 请求失败即重来，无中间状态 | 随时 attach/detach 不丢状态，终态保留供对账 |
| 人工干预 | 无 | 支持运行中停止、审批挂起与恢复 |
| 结果载荷 | 标准 OpenAI 格式（`choices` + `usage`） | 状态对象：`status`、`output`、`usage`、关联的 `session_id` |
| 适用场景 | 一问一答、低延迟交互、常规前端接入 | 长报告生成、巡检类任务、任务面板、需要审批流的场景 |

##### 1. 提交

`POST /v1/runs` 接受 `input` 字符串，可选 `session_id`、`instructions`、`conversation_history`。接口立即返回：

```json
{"run_id": "run_abc123", "status": "started"}
```

提交阶段不等待执行，客户端无需挂起连接。传入 `session_id` 时会在状态响应中回显，便于外部 UI 将 run 与自身的会话 ID 关联。

##### 2. 观察（双通道）

**通道一：轮询**。`GET /v1/runs/{run_id}`，适合不挂 SSE 长连接的 dashboard、或页面导航后重连的 UI：

```json
{
  "run_id": "run_abc123",
  "status": "completed",
  "output": "Done.",
  "usage": {"input_tokens": 50, "output_tokens": 200, "total_tokens": 250}
}
```

终态（`completed` / `failed` / `cancelled`）后状态保留一段时间供轮询对账。

**通道二：SSE 事件流**。实时流出工具调用进度、token 增量与生命周期事件。设计上有两个细节：

1. 连接可随时断开重连而不丢状态——未被消费的事件缓冲 5 分钟后才过期，且过期的只是传输状态，run 本身的执行、审批、停止控制、并发记账均不受影响；
2. Agent 委派后台子代理时，流中出现 `subagent.start` / `subagent.complete` 生命周期事件，子代理超时或失败同样可见，不会出现运行静默。`subagent.complete` 载荷带状态、摘要、耗时、token/成本与 `child_session_id`。子代理内部的逐工具事件被**故意不转发**（高频 UI 噪音），细节查看每子代理的实况转录文件。

##### 3. 控制

| 能力 | 行为 |
| ---- | ---- |
| 停止 | 端点立即返回 `{"status": "stopping"}`，Hermes 在下一个安全中断点停下，执行器退出后 run 落为 `cancelled`；请求停止不会隐藏仍在运行的 worker |
| 审批 | 被审批策略拦下的工具调用（如危险命令）会使 run 挂起等待人工决策，审批端点提交决定后恢复执行，平台侧可嵌入自己的审批 UI |

##### 4. 并发上限

默认最多 10 个并发 run，达到上限后新请求返回 HTTP 429 `Too many concurrent runs`，客户端应退避重试。上限可配置也可禁用，但考虑到每个 run 背后是真实执行工具的进程，建议保留。

#### 五、Spring AI 集成

Spring AI 走标准 Chat Completions 端点，与 Hermes 天然兼容。配置如下，api-key 使用占位符且不设默认值——忘注入时快速失败，避免以弱 Key 静默运行：

```yaml
spring:
  ai:
    openai:
      base-url: http://127.0.0.1:8642
      api-key: ${HERMES_API_KEY}
      chat:
        options:
          model: hermes-agent
```

`ChatClient` 直接可用，流式与非流式仅是方法差异：`.call()` 为非流式，`.stream()` 自动携带 `stream: true` 返回 `Flux<String>`。两者使用同一端点、同一 Key，区别只在请求体的 `stream` 字段。

实测结论：

1. **裸 `model` 值默认被 Hermes 忽略**（需开启 `direct_model_requests` 才生效）。对 Spring AI 而言反而省事——只发 `model` 字段时回落到网关默认模型，无需额外配置；
2. **会话头支持按请求传递**：`OpenAiChatOptions.builder().httpHeaders(Map.of("X-Hermes-Session-Id", sessionId))` 实测可用。1.1.8 版本若发现请求头未带出，兜底方案是 `OpenAiApi$Builder.headers()` 设置全局默认头，缺点是无法按会话切换；
3. **记忆策略采用双写**：Spring AI 侧通过 `MessageChatMemoryAdvisor` + JDBC 仓储在 PostgreSQL 中保存权威历史（可审计、可恢复），Hermes 侧以相同 `X-Hermes-Session-Id` 值保存服务端续聊历史，两侧会话 ID 使用同一值，对齐成本最低；
4. **超时设计**：前端交互的超时需按 17~23 秒的量级起步（建议 ≥120s），并给出"正在执行工具调用"的过程提示，避免被误判为无响应。

#### 六、踩坑记录

排障时间远多于编码时间，以下几条印象较深：

1. **配置了 Key 仍报 `required`**。最隐蔽的一个坑：配置文件中可能同时存在多个 api_server 配置段，且**空字符串 Key 会遮蔽环境变量**——`dict.get` 语义下配置中存在 `key: ''` 就不会回退到 env。反复修改 `.env` 无效，最终是查看适配器源码中 `extra.get` 的真实读取路径才定位到生效落点。结论：怀疑配置问题时先确认代码读取哪一段，不要靠试错。
2. **Key 强度校验是强制的**。短于 16 字符或使用占位符直接拒绝启动。该端点能派发终端级任务，弱 Key 等于暴露远程代码执行能力，此校验合理。
3. **就绪需要 5~20 秒**。`gateway start` 后 `/health` 不会立刻可用，需加载 Agent 与工具 schema。首次 curl 失败不要急于判定配置错误。
4. **前端连不上的首要原因是 Base URL 缺少 `/v1` 后缀**。
5. **Open WebUI 的环境变量仅在首次启动生效**，之后连接设置保存在其自身数据库中。修改配置需走 Admin UI，或删除 volume 重建。
6. **`/v1/models` 是轻量端点**，不枚举全部 Provider/模型组合，也不携带价格信息；需要完整元数据时使用 `/api/model/options`。

#### 七、安全边界

1. **API Server 暴露的是完整工具集，包括终端命令**。因此 Bearer Key 在任何部署形态下都必填——包括默认仅绑定 `127.0.0.1` 的本机部署。Key 一旦泄露，攻击者获得的是服务器上的命令执行能力，而非聊天记录。
2. **CORS 默认关闭是正确的默认值**。Open WebUI 这类服务端前端不需要浏览器 CORS；仅在明确需要浏览器直连时配置白名单，且保持窄范围。
3. **多用户场景使用 Profiles 隔离**。每个 Profile 是完全独立的实例（独立配置、记忆、技能、端口），并支持按平台粒度禁用技能——同一技能可以"CLI 可用、API 请求不可用"。
4. **共享技能目录不是写保护边界**。目录对 Hermes 进程可写，Agent 即可修改其中的技能；需要只读共享时依赖文件系统权限。

#### 小结

当业务需要的不只是文本补全，而是一个能实际执行操作的 Agent 时，把 Agent 运行时封装为 HTTP 端点是目前改造成本最低的接入方式：前端生态可以直接复用，Spring AI 一行配置接入。集成过程中真正需要投入精力的只有两处——**明确上下文的持有方**，以及**长任务采用提交 + 订阅模式而非同步调用**。
