+++
title = 'Agent Loop：一个循环，如何撑起整个 Agent'
date = 2026-11-15T17:20:00+08:00
categories = ["AI"]
tags = ["AI Agent", "Agent Loop", "ReAct", "Pydantic AI", "LangGraph"]
draft = false
+++

### 背景

> 笔者写过几套 Agent Runtime，也翻过不少框架的实现，发现它们外形差得很远：Pydantic AI 把循环做成节点流，Spring AI 塞进 Advisor 链，LangGraph 画成一张有环的图。可剥掉这些外壳，最里面都是同一件事——**请求模型，看响应，执行模型要的动作，把结果塞回去，再请求一次，直到该停为止**。
>
> 这个循环本身并不新。2022 年 10 月 ReAct 那篇论文给出 Thought → Action → Observation 的形状时，Action 还只是模型吐出的一段文本，形如 `Search[某个关键词]`，靠外面的代码用正则识别、执行，再把结果拼回上下文；2023 年 6 月 function calling 把动作变成了结构化的 JSON 请求，省去手工解析；2024 年 11 月 MCP 又把「有哪些工具、怎么调」统一了描述。协议一路在标准化，但**谁去执行、结果怎么送回去、下一轮什么时候停，始终留在应用层**。
>
> 所以这篇笔记只讲这个循环：它在跑什么、一帧里发生什么、状态存在哪几层、靠什么停、审批时怎么挂起和恢复、停下来交回什么，最后拿到三个框架里对照一遍。

为什么非要有这个循环？因为单次调用解决不了三件事：模型不知道刚产生的工单和生产日志，得靠工具取回来；它说一句「已回填工单」并不算写入，实际操作由外部代码执行；下一步动作还取决于查询结果——查日志之前不知道异常在哪个代码位置，读完源码才能确定复现和验证方向。任务开始时通常无法一次备齐所有信息，只能逐轮获取。

当然，也有一次调用直接返回、或由固定工作流处理的场景，不必都写成循环。

动手之前先划清范围，否则后面很容易把三层东西搅在一起：

| 范围 | 关注什么 | 这篇笔记怎么展开 |
| :--- | :--- | :--- |
| Agent Loop | 请求模型、处理响应、执行动作、更新状态、继续或停止 | 主体内容 |
| Agent Runtime | 为循环提供权限、上下文、预算、超时、持久化与观测 | 在执行与恢复处说明接口和约定 |
| 基础设施与外部系统 | 状态存储、调度、并发一致性、外部副作用 | 讨论断点与幂等所需的保证 |

三层有交叠，也不意味着基础设施问题只在大流量下出现——一次写入超时重试，就可能产生重复评论。区分它们，是为了说清哪些检查由 Loop 发起，哪些保证需要执行器、存储或外部接口提供。

---

### 一、这个循环到底在跑什么

#### 1.1 一次 LLM 调用不等于 Agent

将模型与工具连接起来，还需要控制流程决定何时请求模型、执行工具，以及是否继续下一轮。

| 对比 | 单次 LLM 调用 | Agent Loop |
| :--- | :--- | :--- |
| 模型调用次数 | 1 次 | 支持多轮；具体任务也可能一次就返回 |
| 谁推进下一步 | 调用方 | 模型提出决策，Runtime 执行并推进状态 |
| 外部信息 | 需调用方预先拼进 Prompt | 可在运行中按需获取 |
| 典型产物 | 一段文本 | 经过若干次工具交互后的结论 |

可以这么定义：Agent Loop 是一个执行控制机制，让 LLM 从「一次性生成答案」变成「多轮自主执行任务」。它运行时做四件事：按当前状态发起模型请求，拿到决策后校验并执行，把结果并入状态，判断下一步是继续、等待还是结束。

实际实现时，需要明确状态存在哪里、如何解释模型响应，以及动作执行前有哪些检查。后面逐步补齐这些部分。

#### 1.2 拆开看，只有五个零件

| 要素 | 职责 | 代码里的样子 |
| :--- | :--- | :--- |
| LLM | 决策者：决定直接回答、调用哪个工具、还是继续行动 | `llm.generate(messages)` |
| 消息上下文 `messages` | 承载用户输入、模型响应、工具调用与结果，是这篇笔记循环示例中的交互状态 | `messages.append(...)` |
| 工具集 Tools | Runtime 可执行的外部动作：查库、读文件、调 API | `execute_tool(...)` |
| Observation | 工具执行结果；继续请求模型时，按协议关联原调用并回传 | `result` → `messages` |
| 控制策略 | 决定这一轮之后是「继续 / 等待 / 终止」，以及以哪种原因终止 | `continue` / `suspend(state)` / `finish(reason)` |

LLM 和 Runtime 的分工是：LLM 提出决策，Runtime 控制决策怎么执行、怎么校验、状态怎么推进。

Runtime 除了执行工具，还可以负责权限校验、拦截调用、重试、模型切换、预算控制、子 Agent 调度和强制终止。具体能力取决于实现和配置。模型提议写入工单，Runtime 可以要求审批，也可以拒绝。

如果控制策略只区分有无工具调用，就没有为等待审批、输出校验失败等情况定义独立处理方式。控制分支在 2.3 展开，挂起与结束的区别在 4.3。

#### 1.3 最小骨架

循环落到代码上，只展示主要动作时，可以写成这样：

```python
while True:                    # 这里刻意没有上界，原因见下
    response = llm.generate(messages)

    if response.has_tool_call:
        result = execute_tool(response.tool_call)
        messages.append(result)
    else:
        return response.output  # 唯一出口：模型不再请求工具
```

这段代码只有一个出口：模型不再请求工具。它要是每一轮都在请求，循环就停不下来。这不是漏写，是故意省掉终止条件的结果，第五章补的就是这个上界。所以它只是个骨架，真拿去用，得自己加上界。

骨架剩下三个动作：请求模型、处理响应、更新上下文。一轮迭代展开是六步：

1. 把当前上下文交给 LLM
2. 判断响应类型：最终答案、工具调用，还是要求继续
3. 有工具调用就校验并执行，可能不止一个
4. 结果写回上下文
5. 再次请求模型，让它基于新信息决定下一步
6. 判断是否该结束，不结束就回到第 1 步

这个骨架还省了两样东西。

一是「等待」。需要人工审批、外部事件或异步任务结果时，Runtime 可以退出当前执行并返回待处理请求。应用保存现场，收到事件后再通过框架接口继续。这里的「挂起」指业务任务尚未完成，不一定表示框架的同一次 `run()` 还活着；Pydantic AI 的 Deferred Tools 外部审批流程就会结束本次 run，再发起后续 run。2.3 说明控制状态，4.4 和第六章展开审批。

二是工具调用消息要成对保存。

上面那段代码为了好读，把这件事省了。以 Chat Completions 的工具调用消息格式为例，上下文要保存模型发出的调用请求和工具结果，两者通过 `tool_call_id` 对应（示例用 1.6 的工单）：

```text
User:      读取工单 INC-2026-1115
Assistant: tool_calls=[{id: "call_1", name: "read_ticket", args: {...}}]
Tool:      tool_call_id: "call_1"  →  "导出接口 500，trace_id=tr-7f3a"
Assistant: 已拿到故障线索，接下来按 trace 查询日志
```

如果只塞一个裸的 `result` 进列表，模型下一轮可能对不上这是哪次调用的结果，并行调多个工具时尤其明显。

Pydantic AI、Spring AI 的工具执行流程和 LangGraph 的 `ToolNode` 提供了调用与结果消息的组装能力。使用这些组件时，业务代码可以交由框架处理。「工具明明执行了，模型却说没看到结果」，可以先检查调用与结果是否正确进入了下一次请求。

#### 1.4 一次完整迭代，上下文怎么滚

```text
[用户问题]
  → LLM 返回 Tool Call
[用户问题, Assistant(tool_calls), Tool(result)]
  → LLM 返回 Tool Call 或最终文本
[用户问题, Assistant(tool_calls), Tool(result), ..., 最终文本]
  → 返回给用户
```

两个动作缺一不可：执行结果放回上下文，然后再次请求模型。这才算闭环。只执行一次工具就结束，可以说是很简单的 Agent 行为，模型做了选择，Runtime 执行了动作，但它没有形成多轮迭代。这里讨论的是后者。

#### 1.5 `messages` 是核心交互状态，但不是全部状态

`messages` 记录对话与工具交互。任务计划、执行位置、重试次数、预算和审批等信息也可以构成运行状态；是否需要保存这些信息，取决于任务和 Runtime 的设计。

| 状态层 | 具体内容 | 存在哪 |
| :--- | :--- | :--- |
| 对话状态 | `messages`、工具调用与结果历史 | 上下文 / 会话存储 |
| 任务状态 | 当前计划、已完成项、待执行项、子任务 | 计划对象 / State |
| 执行状态 | 当前步骤、重试次数、每步结果、错误 | Runtime 变量 / 图状态 |
| 预算状态 | 累计 Token、成本、剩余请求次数 | Usage 对象 |
| 协作状态 | 子 Agent 状态、任务分配、审批结果 | 编排层 / 共享状态 |
| 运行状态 | 截止时刻、取消信号、run_id、trace | Runtime 上下文 |

后面会讨论的 Plan-and-Execute、Reflection、Multi-Agent，还会引入计划、评估结果和子任务状态。这些信息可以写进消息，也可以保存为结构化记录，例如 LangGraph 的 `State` 或 Runtime 的状态对象。结构化记录便于程序按字段读取、校验和更新。

一种设计方式是：将下一次模型请求需要的信息组织为 `messages`，其余控制信息由 Runtime 保存。模型不能直接读取未加入请求的 Runtime 内部状态；需要让模型读取的运行状态，应显式加入请求。

#### 1.6 一个贯穿全文的工单案例

为了对照后面的状态和限制，这里构造一张工单，后面几节会反复用到它：

```text
工单：INC-2026-1115
服务：report-service
现象：v2.8.0 发布后，部分 POST /reports/export 返回 500
样本：trace_id=tr-7f3a
任务：定位原因、提出并验证方案，审批后回填工单
范围：不执行生产发布，不自动关闭工单
```

读工单后查日志，拿到异常 `TypeError: 'NoneType' object is not subscriptable`、位置 `report_service.py:42` 和部署 revision `a13c9e7`。然后读取对应版本代码，发现下面的逻辑：

```python
def build_query(payload):
    filters = payload.get("filters")
    return {"region": filters["region"]}
```

请求样本没有传 `filters`。此时可以怀疑 `None` 被当成字典使用，但还需要核对接口约定并复现。若 filters 必填，应补请求校验；本例约定它可以缺省、null 或空对象，region 也允许缺省，因此修复要处理这些输入，并保留有效过滤行为。

案例的后续路径是：复现与验证 → 整理原因和方案 → 等待回填审批 → 写入评论。配套工具设为 `read_ticket`、`search_logs`、`read_source`、`verify_patch`、`update_ticket`。

任务完成条件是形成经过验证的诊断并回填，生产修复仍需评审、集成验证、发布和上线后观测。后面的 `completed` 表示本次 Agent 任务完成，不表示生产故障已经解决。

工单、日志、代码注释里的内容作为分析材料，不能覆盖用户授权或工具执行规则。

---

### 二、把循环拆成一帧：请求、决策、校验、执行、回灌

#### 2.1 一帧长什么样

上一节是骨架，这一节看它跑起来的一帧。

```text
运行状态（messages + 任务 / 预算 / 运行上下文）
  └─▶ 请求模型，拿到响应
        └─▶ 判定响应类型
              ├─ FINAL       拿到可返回的输出 → 结束
              ├─ TOOL_CALLS  校验 → 执行 → 成对回灌 → 回到运行状态
              ├─ WAIT        持久化 → 挂起，等事件回来续跑
              ├─ RETRY       带错误提示重来（有次数上限）→ 回到运行状态
              ├─ CONTINUE    状态确有推进 → 回到运行状态
              └─ 其他        显式失败，不要默认继续
```

这里把响应处理和运行状态一起纳入判断。除了执行或返回，还需要处理等待和修正；工具执行前也要检查权限与参数。

#### 2.2 两个角色，职责并不对称

| 角色 | 拿到什么 | 产出什么 | 不该做什么 |
| :--- | :--- | :--- | :--- |
| LLM | 本次构造的上下文 | 一段文本，或一组工具调用请求 | 不自己碰数据库、发 HTTP；也不该由它决定预算、权限和最终是否放行 |
| Runtime | 模型响应、业务与运行状态 | 校验结论、执行结果、状态更新 | 按规则检查和路由，不能把未执行的动作记成成功 |

Runtime 可以拦截越权调用、把失败反馈给模型，或在预算耗尽时终止。它也可以包含确定性业务规则，例如根据日志里的 revision 限定源码版本，或在回填前检查审批。模型决策与程序路由可以共同组织流程。

这也解释了为什么「把工具结果 append 进上下文」这一行这么关键：这是工具执行结果交给下一轮模型判断的地方。少一次 append，模型下一次请求看到的还是旧世界；少一次 `llm.generate`，结果就只是一堆躺在列表里的数据，没人据此做决策。

从状态机角度看，一帧做的事是：读运行状态（里面有 `messages`），生成一次决策，把决策的后果写回运行状态。Agent 的行为就是这些状态转移在多轮里连起来的轨迹。

#### 2.3 从模型响应到五种控制决策

1.3 的骨架只区分「有工具调用」和「没有工具调用」。若任务还需要处理输出校验、截断和外部等待，就要补充相应分支。

第一个问题，它没有区分「可返回的最终输出」和「没有工具调用、但仍需处理的响应」。后者包括：

- 结构化输出要求必须调用 `final_answer` 工具，模型却回了一段普通文本；
- 响应被 `max_tokens` 截断，状态是 incomplete，框架需要再请求一次续写；
- 输出校验（schema 或 validator）失败，需要带着错误信息重试；
- 框架的结束策略判定「还有待处理的工具结果」，需要继续下一轮。

这些情况下，没有 Tool Call 不等于可以返回。

第二个问题，只有两个分支时，没有工具调用的响应都会落到 `else` 里，包括本该重试的响应。反过来，如果实现把所有非最终响应都作为继续事件，又没有次数、时间或进展限制，就可能持续循环。

第三个问题，它没有定义等待外部输入的处理方式。需要人工审批、外部回调或异步任务结果时，可以保存当前状态并挂起，等事件到达后恢复；继续请求模型并不能替代这些外部输入。

这里用五种控制决策描述运行时的处理方式，另加未知类型兜底：

| 状态 | 判据 | 谁决定 | 这一轮之后 | 需要的状态 |
| :--- | :--- | :--- | :--- | :--- |
| `FINAL` | 拿到了可返回的完整输出 | 模型 + Runtime 校验 | 结束，返回结果 | 输出内容 |
| `TOOL_CALLS` | 模型要求执行一个或多个外部动作 | 模型 | 校验 → 执行 → 回灌，继续 | 调用请求与结果 |
| `WAIT` | 缺一个当前拿不到的外部输入 | Runtime 判定 | 持久化，挂起，等事件回来续跑 | 断点、待办、恢复入口 |
| `RETRY` | 本次响应不可用，但可以重来 | Runtime 判定 | 带错误提示重试，有次数上限 | 重试次数、错误原因 |
| `CONTINUE` | 模型要求继续，且状态确有推进 | 模型提议 + Runtime 确认 | 更新状态，继续 | 推进证据 |
| 其他 | 协议之外的响应 | — | 显式失败 | — |

```python
if decision.kind == "FINAL":
    return evaluate_completion_and_finish(decision.output, state)

if decision.kind == "TOOL_CALLS":
    validate_and_authorize(decision.tool_calls)
    if requires_external_approval(decision.tool_calls):
        stage_calls_and_approval(state, decision)     # 保存请求，尚未执行
        persist(run_id, state)
        return suspended("WAITING_APPROVAL", run_id)
    results = execute_tools(decision.tool_calls)
    messages.extend([assistant_tool_call_message(decision), *results])   # 成对，见 1.3
    continue

if decision.kind == "WAIT":
    persist(run_id, state)                             # 断点落盘，进程可以真的退出
    return suspended(decision.reason, run_id)          # 不是「结束」，是「先停在这」

if decision.kind == "RETRY":
    if retry_count >= MAX_RETRY:
        return finish("RETRY_EXHAUSTED", decision.reason)
    retry_count += 1
    messages.append(retry_hint(decision.reason))       # 告诉它错在哪，别让它瞎猜
    continue

if decision.kind == "CONTINUE":
    if not update_state(decision):                     # 没有推进就是空转
        return finish("NO_PROGRESS", "响应未推进任何状态")
    continue

return finish("UNEXPECTED_RESPONSE", decision.kind)    # 未知类型必须显式处理
```

FINAL 表示已有可返回输出，最终状态还要检查任务目标；只完成部分诊断时应交回部分结果，不能仅因模型停止调用工具就标记 completed。5.3 的完成函数负责这项检查。

这五个名字需要说明一下。它们是为了讲清 Runtime 控制流而定义的抽象类型，不是 OpenAI、Anthropic 或哪家供应商的统一响应协议，也不是某个框架的 API 枚举。这里的 `WAIT`、`RETRY` 和 `CONTINUE` 由 Runtime 结合响应内容、输出校验、业务状态和外部事件判定。实际 API 还可能返回拒绝、不完整输出、多模态内容等，需按所用协议解析。

其中两种决策的触发条件如下。

`WAIT` 是 Runtime 的控制状态。模型可以提出需要审批或外部输入，但是否挂起、挂起前保存什么，由 Runtime 决定，不能把模型说「已经批准」当成有效审批。供应商 API 中未必有对应字段。需要审批的 `TOOL_CALLS` 也可以在工具执行边界转入 `WAIT`；不需要模型另行输出一个等待指令。上面的伪代码只展示这一转移，完整的恢复处理见 4.4 和第六章。

`CONTINUE` 也不能由模型一句话触发。模型回一句「我还需要进一步分析」，本身不算有效的继续事件，它得伴随实际的状态推进：新的工具调用、新的结构化计划、新的分页游标，否则就落进 `NO_PROGRESS`。

分类时要同时看响应、校验结果和业务状态。只支持工具与最终输出的实现，也可以不提供独立的 `CONTINUE`。

##### `RETRY` 和 `CONTINUE` 的边界

这篇笔记按**本次响应是否可用**区分 `RETRY` 和 `CONTINUE`；两者都可能引发下一次请求：

| | `RETRY` | `CONTINUE` |
| :--- | :--- | :--- |
| 判断的是 | 本次响应**不可用**（校验失败、截断、参数非法） | 本次响应**可用**，但任务没完 |
| 下一次请求 | 按错误调整提示、长度或上下文，再请求 | 使用更新后的状态继续请求 |
| 计不计入重试上限 | 计 | 不计，但计入请求次数 |
| 典型信号 | schema 报错、`finish_reason=length`、工具参数非法 | 模型给出结构化的下一步、分页还有下一页 |

`RETRY` 是「这句不算」，`CONTINUE` 是「这句算了，接着来」。只有 `CONTINUE` 需要证明状态推进，`RETRY` 需要的是次数上限，它本来就不推进状态。

##### `RETRY` 本身就分三种，别共用一个计数器

这篇笔记区分三类可能触发再次尝试的情况：

| 来源 | 典型场景 | 谁处理 | 该记在哪 |
| :--- | :--- | :--- | :--- |
| 传输层重试 | 网络抖动、429 限流、5xx | 模型客户端（SDK 内置） | 记 `provider_attempts`（观测用），不进业务重试预算 |
| 响应不可用重试 | schema 校验失败、被 `max_tokens` 截断、工具参数非法 | Runtime | 记 `retry_count`，挂 `MAX_RETRIES` |
| 工具失败后的模型修正 | 工具返回业务错误，模型换个参数再试 | 模型自己决定，Runtime 只执行 | 不算重试，是一次新的 `TOOL_CALLS` |

混在一起的后果很具体。把 SDK 的网络重试也算进 `retry_count`，一次网络错误引发的多次底层尝试可能占用业务重试预算；反过来，把模型「换个参数再来」当成重试来限流，可能提前耗尽模型修正参数的额度。三行里只有中间那行属于「这一帧不算数」，也只该由 `RETRY` 分支处理。

#### 2.4 上下文不是越长越好

1.4 的示例持续追加消息。如果每轮保留全部工具结果，请求输入会随历史增长，并可能超过模型的上下文窗口。是否超限取决于消息长度、输出预留和模型窗口大小。

Runtime 可以将完整历史与本次请求输入分开管理。下面是四种可选手段，应按信息保留需求组合使用：

| 手段 | 省下什么 | 代价 / 风险 |
| :--- | :--- | :--- |
| 只保留最近的工具结果 | 省掉陈旧的 Observation | 留最近 N 条时必须保证 `tool_call_id` 成对，不能孤零零留一个结果 |
| 把早期对话压成摘要 | 省掉大量原始文本 | 摘要有损：工单号、trace_id、错误码这类关键值必须原样保留 |
| 计划、进度、结论存成结构化状态 | 省掉重复叙述 | 要多维护一份状态，就是前面那张状态分层表 |
| 原始记录归档、按需检索 | 让「完整历史」不进每次请求 | 检索得能命中，否则等于丢了 |

运行状态可以比每次发给模型的消息更完整，模型的输入也不必等于完整历史。

压缩需要检查两类风险：一是摘要可能丢失后续排查所需的证据，需要追溯时应归档原始响应并关联 `run_id`；二是裁剪可能破坏协议要求，例如在要求调用与结果配对的接口中，只保留 `Tool` 结果可能导致请求被拒绝。

---

### 三、容易混淆的边界：ReAct 不是 Loop，Tool Call 也不是

#### 3.1 四个层次，别放在一起比

ReAct（Reasoning and Acting）让模型交替推理和行动：Thought → Action → Observation → 再次 Thought → Final Answer。这篇笔记分别从交互范式和执行机制两个角度讨论 ReAct 与 Agent Loop。

这里的 Thought 是论文对推理阶段的概念化表示，不代表 Runtime 一定能读到模型的内部推理。现代模型的思维链未必以独立字段暴露，有的还会被隐藏或摘要。这篇笔记围绕 Runtime 可取得的模型响应、工具调用请求和工具执行结果设计循环，不依赖获取模型的内部思维链。

| 层次 | 概念 | 解决的问题 |
| :--- | :--- | :--- |
| 交互范式 | ReAct | 一步之内如何交替思考、行动和观察 |
| 执行机制 | Agent Loop | 如何持续推进、更新状态、并决定何时停 |
| 动作接口 | Tool Calling | 模型如何表达「我要调这个工具」 |
| 工程框架 | Pydantic AI / Spring AI / LangGraph | 如何组织模型、工具、状态与控制流 |

ReAct 可以在 Loop 里实现，Loop 是承载它的执行机制。Loop 也不一定采用 ReAct。

```python
from pydantic_ai import Agent

agent = Agent("openai:your-model", instructions="你是一个工单分析助手")

@agent.tool_plain
def read_ticket(ticket_id: str) -> str:
    return f"工单 {ticket_id}：report-service 导出接口 500，trace_id=tr-7f3a"

result = agent.run_sync("读取工单 INC-2026-1115 的摘要")
print(result.output)
```

`agent.run_sync()` 内部会请求 LLM 并处理响应：有 Tool Call 则执行、回灌、再请求；输出通过校验并满足结束策略后，产出 `End`。想看清节点怎么衔接，可以用 `agent.iter()` 逐个节点观察，第六章有完整示例。

Tool Calling 定义动作接口，但一次工具调用之后是否继续请求模型，由控制流程决定。下一节展开这一区别。

#### 3.2 Tool Calling 不是 Loop

Tool Calling 只解决一件事：模型怎么把「我要调这个工具」这个意图表达出来。它不定义任务怎么推进，也不管什么时候算完。

最直接的证据是，有工具调用，可以完全没有循环。

```text
用户提问 → 模型给出 Tool Call → Runtime 执行 → 结果直接交给业务层
```

这个例子一次就结束，没有第二轮：模型把自然语言转成一次 API 调用参数，剩下的交给业务代码。它是一条直线，不是循环；这个系统可以称为一个极简的 Agent，但它没有 Loop。

Spring AI 还提供 `@Tool(returnDirect = true)`。在满足直接返回条件时，工具结果直接返回调用方，不再回灌模型；同批多个工具的条件见 6.2。这是工具调用流程的一条显式出口。它也说明「工具执行完必须再问模型一次」不是协议强制，而是 Runtime 的设计选择。这个选择，就是 1.4 里「闭环」和「一次调用」的分界线。

两者的关系可以这么看：Tool Calling 提供一个动作事件，Agent Loop 决定这个事件之后要不要再来一轮。前者是接口，后者是控制流。

还需要区分固定工作流。

| 架构 | 有没有循环 | 循环条件 |
| :--- | :--- | :--- |
| 固定工作流（DAG） | 图的边不构成环；节点内部仍可实现重试或循环 | 不适用 |
| Plan-and-Execute | 有，在执行层 | 计划中还有未完成任务 |
| Reflection | 有，在生成—评估层 | 评估未通过 |

固定工作流可以被同一个编排 Runtime 调度，但它本身不是 Agent Loop，它没有「回头再跑一次」这件事。「同一个 Runtime 能实现」不等于「它们是同一个循环」。这个区分在第六章看 LangGraph 时还会出现。

这三个概念可以按职责区分：Tool Calling 表达动作请求，ReAct 组织推理与行动，Agent Loop 负责推进状态与判断终止。请求模型、执行工具等操作可以在不同架构中复用。

#### 3.3 四种「模式」不在同一个分类维度

ReAct、Plan-and-Execute、Reflection 和 Multi-Agent 分别描述交互、规划、评估和协作，分类维度不同。

| 概念 | 更准确的定位 | 它回答的问题 |
| :--- | :--- | :--- |
| ReAct | 推理与行动的交互范式 | 一步之内怎么想、怎么做 |
| Plan-and-Execute | 任务规划与执行架构 | 先规划再执行，还是边做边想 |
| Reflection | 反馈评估与自我修正机制 | 做完怎么知道好不好、怎么改 |
| Multi-Agent | 多 Agent 协作架构 | 一个 Agent 忙不过来时怎么分工 |

它们可以组合，不是互相替代。一个真实的系统可能长这样：

```text
Orchestrator（外层编排 / 状态机）
    ├── Planner Agent      （自己跑一个 ReAct 循环）
    ├── Research Agent     （自己跑一个 ReAct 循环）
    └── Reviewer Agent     （自己跑一个 Reflection 循环）
```

这不是「一个 Loop 换几行条件」，而是多个 Agent 各自的 Loop，外面加一层负责任务分配和收敛判断的编排。

不同 Agent 架构可以复用底层的运行原语：请求模型、校验决策、执行动作、更新状态。但整体控制流未必是同一个 Loop。例如上图由多个 Agent 循环和外层编排共同组成；任务分配与单个 Agent 的执行可以分别实现。

Agent Loop 可以有多个实例，也可以嵌套在外层控制流程中。ReAct 是范式，Planning 是架构，Reflection 是机制，Multi-Agent 是协作，它们不在同一个层次上。

---

### 四、终止条件：这个循环真正的开关

#### 4.1 「没有 Tool Call 就结束」是默认约定，不是定义

「没有 Tool Call 就结束」这个约定好用，是因为在典型的 Tool Calling Agent 里，工具调用就是模型要求 Runtime 执行外部动作的信号：模型还没给最终答案，先把活派出来；Runtime 办完把结果送回去，模型再决定下一步。

一次最简单的交互：用户只要求读取工单摘要，模型返回 `{"tool_calls":[{"name":"read_ticket","arguments":{"ticket_id":"INC-2026-1115"}}]}`；Runtime 拿到故障描述和 trace；结果回灌后，模型返回工单摘要，没有工具调用，循环结束。完整排查任务还需要后续查询与验证。

```python
while True:
    response = llm.generate(messages)

    if response.tool_calls:
        messages.append(assistant_tool_call_message(response))  # 调用请求也要进上下文
        results = execute_tools(response.tool_calls)            # 一次可能多个
        messages.extend(results)                               # 结果与调用成对，见 1.3
        continue

    return response.content
```

这段代码能跑，也符合协议。工具调用请求和结果是一起进去的，没有退回只 append 一个裸结果的老写法。

但它默认了一件事：响应里没有 tool_calls，就等于模型说完了。这个等价关系要成立，得有两个前提：

1. 模型只可能产出「调工具」和「说完了」两种响应；
2. 任何纯文本都是完整的最终答案。

前提 1 在 2.3 已经不成立，结构化输出、截断、校验失败都会产生第三种情况。前提 2 也靠不住：一段被 `max_tokens` 砍断的文本，看起来是纯文本，其实不是答案。

所以要给这个约定补一个限定：Loop 的本质不是判断有没有工具调用，而是判断是否达到终止条件。无 Tool Call 是这篇笔记的基础示例和 6.3 中 `tools_condition` 采用的结束判据，不是 Loop 的定义。

#### 4.2 不同架构，继续条件长在不同地方

| 架构 | 循环继续条件 | 循环在哪一层 | 还额外需要什么状态 |
| :--- | :--- | :--- | :--- |
| ReAct | 模型产出下一步动作；动作可用文本或 Tool Call 表达 | 单个 Agent 内 | 推理、动作与观察记录；执行限制另存 |
| Plan-and-Execute | 计划中还有未完成任务 | 执行层（外层还有规划） | 计划、已完成项、待执行项 |
| Reflection | 评估结果未达标 | 生成—评估内循环 | 评估结果、轮次上限 |
| Multi-Agent | 协作任务尚未完成 | 每个 Agent 各有内循环 | 任务分配、子 Agent 状态、审批 |

表中的计划、评估和协作信息都需要被记录。它们可以编码进消息，也可以独立存储；程序需要按字段校验和更新时，可以使用 1.5 所列的结构化状态。

这张表只比较两件事：循环发生在哪一层，靠什么继续。它不表示这四者处在同一个分类维度上，3.3 说的就是这个。

```python
# Reflection：条件不是 Tool Call，而是评估是否通过
while not evaluation.passed and attempt < MAX_ATTEMPTS:
    result = generate()
    evaluation = evaluate(result)
    attempt += 1
return result
```

Reflection 的反馈可以来自模型，也可以来自外部评估。对于代码和接口任务，编译、测试、静态扫描与 schema 校验可以提供可复核的证据；模型对自身输出的评价本身不能证明结果正确。

#### 4.3 完成、挂起与强制终止

离开当前执行循环时，可以区分下面几种情况：

| 来源 | 典型场景 | Runtime 该做什么 |
| :--- | :--- | :--- |
| 正常完成 | 得到最终答案、评估通过 | 返回结果，记录 usage |
| 主动等待 | 需要人工审批、需要外部事件 | 挂起并持久化状态，等事件回来再续跑 |
| 强制终止 | 超请求次数、超时、重复动作、超预算 | 返回结构化终止原因 + 已有部分结果 |

对照 2.3 的五种响应就清楚了：`FINAL` 落在第一类，`WAIT` 是第二类；`TOOL_CALLS`、`RETRY`、`CONTINUE` 继续推进后，仍可能完成、挂起或因限制而终止。

需要等待审批或外部事件的任务，可以通过持久化实现挂起与恢复。LangGraph 提供 checkpointer 和 `interrupt`；自研 Runtime 也需要保存恢复所需的状态。若状态只存在进程内，进程退出后就无法仅凭这些内存数据恢复执行。

暂停和结束在实现上差得很远：

| | 结束（`FINAL` / 强制终止） | 挂起（`WAIT`） |
| :--- | :--- | :--- |
| 业务任务状态 | 本轮交付或终止；是否重开另行定义 | 尚未完成，等待外部事件 |
| 当前执行 | 返回结果或报告异常 | 可以返回待审批请求；恢复时可能发起新的框架 run |
| 返回什么 | 结果或终止原因 | 业务任务标识 + 暂停标识 / 待办，另关联框架 run |
| 后续处理 | 依结果交付；需要恢复时另行定义策略 | 审批回调、事件、定时任务按恢复入口继续 |
| 应用层要处理的问题 | 将框架异常转换为包含进展的结果 | 保存断点并退出当前执行，避免持续请求模型 |

#### 4.4 审批放在工具执行边界，恢复后仍可能再次等待

`agent.run()` 或 `ChatClient.prompt().call()` 封装了循环，不意味着应用必须重写循环才能接入审批。如果框架提供工具审批与继续执行接口，就在工具执行边界配置策略：模型提出动作，框架在调用业务函数之前检查是否需要审批；需要时返回待审批请求，应用保存现场并结束当前 HTTP 请求。审批事件到达后，再调用框架接口执行已批准的调用、回传结果并继续。

审批策略应由应用或框架配置决定。以前面那张工单为例，`read_ticket`、`search_logs` 可直接执行，`update_ticket` 必须审批。Prompt 中写「先征求同意」可以帮助模型表达意图，但不代替执行器的检查。审批也不代替业务授权：实际写入时，工具或 MCP Server 仍需校验当前用户权限、数据范围和业务状态。

同一业务任务可以多次经过审批。以「回填工单，再通知负责人」为扩展示例，假设两个写工具都需要审批：

```text
查询与验证 → 请求 update_ticket → 保存暂停点 A → 返回待审批
审批 A 通过 → 执行回填 → 工具结果交回框架 → 模型请求 notify_owner
          → 保存暂停点 B → 再次返回待审批
审批 B 通过 → 执行通知 → 工具结果交回框架 → 校验最终输出与任务完成条件
```

每次启动或恢复后，都需要走同一个结果处理入口：检查新的审批请求、外部延迟结果、错误和执行限制；只有输出有效且业务目标达成时才标记完成。没有新的待审批项，只能说明没有识别到这一类等待，不能单独证明任务成功。拒绝某个调用也不一定结束任务：框架可以把拒绝原因作为工具结果交回模型，由模型说明限制或提出其他方案；拒绝不应被转成对后续调用的通用批准。

应用保存的审批现场至少应包括：

| 内容 | 恢复时的用途 |
| :--- | :--- |
| 稳定的业务任务 / 会话 ID、本次暂停 ID、框架 run 标识 | 区分同一任务中的不同执行段与审批批次 |
| 完整消息历史、原始待执行响应、工具调用 ID / key 和顺序 | 关联原调用并保留暂停前已获取的信息 |
| 工具名、具体参数、工具与策略版本、业务资源版本 | 确认审批展示内容与实际执行内容对应 |
| 审批人、逐调用决策、理由、时间、有效期 | 校验谁批准了哪次操作，拒绝过期或越权审批 |
| 操作 ID、执行状态与结果、任务累计预算 | 防止重复副作用，避免恢复后重置限制 |

这些数据保存在服务端可信存储中。前端提交暂停 ID 和决策；后端读取原调用并验证审批权限，不接受前端提供一份任意消息历史或 `ChatResponse` 来执行。工具参数经校验器或 hook 转换时，还要核对展示参数与最终生效参数；若操作目标或含义改变，重新审批。

审批记录与执行记录应分开。`APPROVED` 表示允许执行，不表示写入成功；`DENIED` 的调用不进入成功执行状态。允许执行的操作还需记录 `NOT_STARTED / EXECUTING / SUCCEEDED / FAILED / UNKNOWN` 等状态。用条件更新或租约防止两个恢复请求同时推进同一任务；若远端已经写入但本地尚未记录就崩溃，仍需稳定操作 ID、幂等键或结果核查，数据库里一个「已审批」标记不能解决这个窗口。

暂停点 A 的执行结果应在再次请求模型前保存。若生成暂停点 B 时进程退出，恢复入口应从已保存的工具结果继续，不能重做 A 的副作用。等待期间也不能把未完成的工具调用直接留给一次无关的新提问；应先处理或按协议拒绝旧调用，或者为新任务建立独立会话。

这里的外层逻辑处理业务任务生命周期和审批事件；模型与工具之间的迭代仍可由框架执行。第五章的自研循环用于解释控制与限制，并非接入审批的必需实现。

---

### 五、当循环停不下来：分层防死循环

#### 5.1 为什么一层不够

Agent Loop 可能反复调用同一个工具，或持续生成内容而不满足终止条件。不同限制针对不同问题：请求次数约束调用总量，超时约束阻塞时长，重复检测检查动作是否取得进展。

| 死循环形态 | 表现 | 只靠请求次数限制能否兜住 |
| :--- | :--- | :--- |
| 重复动作型 | 相同工具 + 相同参数被反复调用 | 能挡，但要空转到第 N 步，白白烧预算 |
| 空转推理型 | 每步都有输出，既不调工具也不给最终答案 | 能限制请求总量，也可结合时间和进展检查 |
| 卡死型 | 某一步工具调用超时或阻塞，循环停在原地 | 请求次数不增长，请求次数限制完全失效 |
| 膨胀型 | 动作各不相同但上下文持续膨胀，逼近窗口上限 | 请求次数未必触发，需要预算限制 |

第二行要单独解释一句，它和「没有 Tool Call 就结束」看起来矛盾。只有两个分支的实现里，这种形态确实不会发生，没有 Tool Call 就直接返回了。它成立的前提是框架允许「继续」这条路（2.3 的 `CONTINUE` / `RETRY`）：结构化输出要求必须调 `final_answer` 工具、响应被截断需要续写、输出校验失败需要重试。这些情况下，模型会一轮轮产出「不是答案的文本」，而循环一轮轮继续。

这里的空转需要控制流程允许继续，并且后续响应始终没有满足终止条件。实现中可以用请求次数、时间和进展检查限制这条路径。

单一策略覆盖不了所有场景。这不是防御写得够不够严谨的问题，是维度不够。

#### 5.2 五层机制

| 防御层 | 策略 | 检查位置 | 触发后的处理 |
| :--- | :--- | :--- | :--- |
| L1 请求次数与收尾 | 普通请求上限，另留收尾请求 | 每次模型请求前 | 普通额度用尽后收尾；收尾仍失败则返回部分结果 |
| L2 时间限制 | 活跃执行时间上限（5.5 的全局 Deadline）、单次超时与取消 | 入口和模型/工具执行内部 | 超时或取消，记录已有结果 |
| L3 重复检测 | 按轮比较动作与观察，核对进展 | 本轮结果更新后，下一次可疑动作执行前 | 换路径、收尾或中断，按业务配置 |
| L4 累计预算 | 整个 Run 的 Token / 成本 | 请求前估算或预留，响应后对账 | 达额度后停止新增消耗 |
| L5 单次上下文 | 本次输入加输出预留不超窗口 | 请求发送前 | 先裁剪/摘要，仍超限就不发送 |

L2 说的「活跃执行时间」是循环真正在运行的时间，不含等待审批、等待外部事件的挂起时段。按墙钟计时，会把「审批等了三小时」算成超时；按活跃执行时间，才能表达「任务总共只准跑五分钟」。

L4 和 L5 限制的是不同东西。连续十轮，每轮输入一万 Token，累计可能已经达到十万，但每次都能装进窗口。反过来，第一次就发送三十万 Token，此前消耗再少也可能超窗。

累计消耗的实际值要依赖响应 usage 等计费记录，但不是只能事后处理。对硬预算要求，可以在请求前估算并预留，返回后对账；估算误差、缓存价格、fallback 和外部工具费用仍需明确口径。仅在响应后检查，能阻止下一请求，无法撤销本次费用。

五层可以同时生效，处置优先级也要定义。用户取消、硬时间或费用边界触发后，不能因为还留着收尾请求就继续调用模型。L3 是启发式检查，相同查询也可能是合法轮询；它不能替代 L1、L2、L4 的上限。

##### L1 为什么要单独留收尾请求

```text
最后一次普通请求：模型调用 verify_patch，测试结果返回
下一次请求前：普通请求次数已经用完
```

如果此时直接停止，刚得到的验证结果没有机会被模型整理。可以留一段独立额度，只用于根据已有信息输出结论。

| 参数 | 含义 |
| :--- | :--- |
| `MAX_NORMAL_REQUESTS` | 普通阶段最多请求多少次，输出修正也计入 |
| `FINALIZE_RESERVE` | 独立的收尾请求数，这里的示例设为 1 |
| `MAX_MODEL_REQUESTS` | 上面两项之和，表示总请求硬上限 |

这里统一按请求计数。不能把「有效推进 N 次」当成「请求 N 次」：一次 schema 重试会产生请求，却未取得任务进展。如果按推进次数进入收尾、按 N+1 限总请求，预留的一次可能提前被重试占掉。

例如普通额度为 5：先校验失败一次，再读工单、查日志、读代码和验证，共用掉五次。第六次进入独立收尾，报告「方案已验证，工单尚未回填」。收尾阶段去掉普通行动工具，只保留输出通道，提示剩余次数和未完成项。

收尾并不保证输出合格。最后一次仍可能校验失败；这时返回已有进展与未完成项，不能宣告任务完成。6.1 的 capability 示例采用的是接近请求上限时提前收尾的做法，也有这个限制。

#### 5.3 整合进一次循环

下面是自研 Runtime 的接口级伪代码，用于展示预算、pending 操作与状态如何配合。使用框架内置审批接口时，不需要照搬这段 `while`。预算、计数器、重复窗口与 pending 操作都在可持久化运行状态中。恢复入口先处理已有操作，避免再生成一次同样的回填请求。

```python
from time import monotonic

MAX_NORMAL_REQUESTS = 8
FINALIZE_RESERVE = 1
MAX_MODEL_REQUESTS = MAX_NORMAL_REQUESTS + FINALIZE_RESERVE
MAX_RETRIES = 3
REQUEST_TIMEOUT, STEP_TIMEOUT = 60, 30
MAX_TOTAL_TOKENS = 200_000
MAX_CONTEXT_TOKENS = 100_000
RESERVED_OUTPUT_TOKENS = 4_000


def drive(state, event=None):
    apply_verified_event(state, event)
    deadline = monotonic() + state.remaining_active_seconds

    while True:
        # 超时、取消、实际累计预算；异常在应用边界转成统一 Run 结果。
        enforce_cancel_and_hard_limits(state, deadline, MAX_TOTAL_TOKENS)

        if state.pending_operations:
            if needs_external_input(state):
                checkpoint_with_remaining_time(state, deadline)
                return suspended(state.wait_reason, state.run_id, state)

            # 包含权限/参数检查；串行时每个工具重新计算剩余时间。
            # 使用已保存的 operation_id；失败/未知结果不能计入成功。
            execute_pending_and_commit_results(
                state, deadline=deadline, step_timeout=STEP_TIMEOUT,
            )
            checkpoint_with_remaining_time(state, deadline)
            continue

        if state.normal_requests < MAX_NORMAL_REQUESTS:
            phase = "active"
        elif state.finalize_requests < FINALIZE_RESERVE:
            phase = "finalizing"
        else:
            return finish("REQUEST_BUDGET", partial_output(state), state)

        request = build_request(state, finalize=(phase == "finalizing"))
        if estimate_tokens(request) + RESERVED_OUTPUT_TOKENS > MAX_CONTEXT_TOKENS:
            request = compact_context(request, state)
            if estimate_tokens(request) + RESERVED_OUTPUT_TOKENS > MAX_CONTEXT_TOKENS:
                return finish("CONTEXT_TOO_LARGE", partial_output(state), state)

        remaining = deadline - monotonic()
        if remaining <= 0:
            return finish("TIMEOUT", partial_output(state), state)

        # 先预留并保存；即使重启，也不会把已用请求数清零。
        reserve_request_and_cost(state, request, phase)
        checkpoint_with_remaining_time(state, deadline)
        response = llm.generate(request, timeout=min(REQUEST_TIMEOUT, remaining))
        record_response_and_usage(state, response)
        checkpoint_with_remaining_time(state, deadline)
        decision = classify_and_validate(response, state)

        if decision.kind == "FINAL":
            # 检查证据、验证范围与回填结果；部分输出不能标为 completed。
            return evaluate_completion_and_finish(decision.output, state)

        if decision.kind == "TOOL_CALLS":
            if phase == "finalizing":
                return finish("FINALIZE_TOOL_REQUEST", partial_output(state), state)
            validate_and_authorize(decision.tool_calls, state)
            if repeated_without_progress(state, decision.tool_calls):
                return finish("REPEATED_ACTION", partial_output(state), state)
            # 保存完整调用、具体参数、稳定操作 ID、审批条件，然后才执行。
            stage_operations_with_stable_ids(state, decision)

        elif decision.kind == "WAIT":
            stage_wait_condition(state, decision)
            checkpoint_with_remaining_time(state, deadline)
            return suspended(decision.reason, state.run_id, state)

        elif decision.kind == "RETRY":
            if phase == "finalizing" or state.retry_count >= MAX_RETRIES:
                return finish("RETRY_EXHAUSTED", partial_output(state), state)
            state.retry_count += 1
            state.messages.append(retry_hint(decision.reason))

        elif decision.kind == "CONTINUE":
            if not update_state(state, decision):
                return finish("NO_PROGRESS", partial_output(state), state)
            state.transition_count += 1

        else:
            return finish("UNEXPECTED_RESPONSE", decision.kind, state)

        checkpoint_with_remaining_time(state, deadline)
```

几个辅助函数需要明确约定：

- `reserve_request_and_cost` 增加本阶段请求数、总请求数并预留消耗。普通修正占普通额度，不能动用收尾额度。
- `record_response_and_usage` 保存模型响应及协议字段。工具执行函数按调用 ID 写回结果，并分别记录成功、失败和结果未知。
- `stage_operations_with_stable_ids` 在执行前保存调用和审批要求；`needs_external_input` 检查是否仍有未决审批。已收到的决策按原调用匹配，不自动批准新生成的调用。
- `execute_pending_and_commit_results` 逐项核对权限、审批、剩余时间与已知结果。拒绝项写成关联原调用的拒绝结果，不执行工具；批准项取得实际结果后再记录成功、失败或未知。实际取得进展时才增加 `transition_count`，成功记录不能包含失败操作。
- `repeated_without_progress` 按批次检查动作及已有观察，保留有语义的次数和顺序；合法轮询另设策略。
- `checkpoint_with_remaining_time` 保存状态和剩余活跃时间。恢复重建当前进程 deadline，另检查持久化的任务过期时间。

请求发出前保存额度是一种保守策略。进程可能在保存后、发送前退出，从而损失一次额度，但不会在恢复时多出一次请求。要精确核查，可以额外维护请求尝试记录与供应商关联 ID。

`estimate_tokens` 只是估算。工具 schema、多模态输入、输出预留都要考虑；压缩若调用模型，其时间和费用也需入账。请求前的预算检查与响应后的 usage 对账各有用途。

##### 挂起与恢复还需要哪些状态

保存消息不等于保存执行位置。至少还要保留：

| 状态 | 作用 |
| :--- | :--- |
| 业务任务 ID、框架 run_id、版本、阶段、任务进度和证据引用 | 确认恢复的是哪个任务、哪个执行段和位置 |
| pending 操作、operation_id、具体参数和执行结果 | 先核查或继续原操作，不重新生成 |
| 审批条件、审批记录、参数版本 | 防止审批内容与实际执行内容不同 |
| 普通/收尾请求数、修正次数、消耗、重复窗口 | 恢复后限制不重置 |
| 剩余活跃时间与绝对过期时间 | 按既定时间策略继续执行 |

本例可以约定等待审批不消耗活跃执行额度，但任务仍会过期。进程内用单调时钟，持久化时保存剩余额度；不把旧进程的单调时钟绝对读数当成通用的跨重启 deadline。多工作进程恢复还需要租约或状态版本条件，避免同时推进。

审批可能拆出多次框架调用。这篇笔记自研示例的 `run_id` 表示业务运行；接入 SDK 时，应另设稳定任务 ID 关联各段框架 run。累计请求、费用和活跃时间按业务任务管理，不能只依赖每段框架调用重新建立的局部额度。

##### 工单案例：诊断与验证

把上面这套流程用 1.6 的工单跑一遍，修复可以写成：

```python
def build_query(payload):
    filters = payload.get("filters")
    if filters is None:
        filters = {}
    if not isinstance(filters, dict):
        raise ValueError("filters must be an object or null")

    region = filters.get("region")
    if region is not None and (not isinstance(region, str) or not region.strip()):
        raise ValueError("region must be a nonempty string")
    return {} if region is None else {"region": region}
```

验证应覆盖 filters 缺省、null、空字典、有效 region、region 缺省、错误 filters 类型和空 region。前几项验证异常路径，保留有效 region 的用例用于检查原有行为没有被破坏。

这些用例只验证函数语义，HTTP 4xx 映射、查询构造和数据库集成仍要补测。只有实际执行后，回填时才能写「七项通过」；未执行就列为待验证。

```text
原因：trace tr-7f3a 指向 a13c9e7 的 filters 字典读取，缺省/null 可复现。
方案：处理可选字段，保留 region 过滤，补充参数校验。
验证：记录本地七项用例的环境、代码版本与结果。
后续：评审、集成验证、发布和上线后观测。
状态：待发布与生产验证。
```

这份记录还缺一样东西：请求了几次、工具调了几次、总共花了多少。5.4 补的就是这个。

#### 5.4 计数口径与运行观测

一个 `iteration` 很难同时表示请求、工具调用和任务进展，最好分开记录。

| 计数 | 数什么 | 用途 |
| :--- | :--- | :--- |
| `normal_requests` / `finalize_requests` | 普通与收尾模型请求 | 各自限制，隔离预留额度 |
| `request_count` | Runtime 发起的总模型请求 | 核对总上限，统计开销 |
| `retry_count` | 输出不可用后的修正 | 限制修正次数，不混入 SDK 网络重试 |
| `transition_count` | 可验证的任务进展 | 观测效率，也可另设任务推进策略 |
| `tool_call_count` | 模型提出或实际执行的工具数，需注明口径 | 控制工具额度，观察并行度 |
| `provider_attempts` | 含 HTTP 重试和 fallback 的实际尝试 | 客户端或网关观测，可另设限制 |

`llm.generate()` 内部重试三次，外层 `request_count` 仍可能只增加一次。供应商尝试数需要客户端上报，不能从外层循环猜。工具调用数也不是模型请求数：一次响应可以有多个工具调用。

这些数量都可以按业务需要设置上限，但不能相互替代。特别是用「取得了几次进展」替代请求限制，会漏掉一直请求却没有进展的情况。

| 比值 | 持续偏高时可以检查什么 |
| :--- | :--- |
| `request_count / transition_count` | 输出修正、空转或进展判定是否异常 |
| `tool_call_count / request_count` | 单次响应的调用量、并发策略与工具额度 |
| `provider_attempts / request_count` | 网络、供应商错误与重试策略 |

分母为零时单独处理。比值用于定位现象，阈值还要结合任务类型和实际轨迹判断。

#### 5.5 时间限制的真实边界

入口那行 `if monotonic() - start > MAX_WALL_TIME` 看上去能兜住一切卡死。它不能。

这个判断只在**控制权回到循环入口**时才会执行。如果 `llm.generate()` 本身阻塞了十分钟，或者某个工具调用永远不返回，代码根本走不到那行 `if`。循环入口的检查再严密也没用。

真正要配的是三层时间限制，再加一个向下传递的取消信号：

| 层级 | 管什么 | 怎么实现 |
| :--- | :--- | :--- |
| 全局 Deadline | 整个 Run 的活跃执行时间 | 开始时算出 `deadline`，每轮入口检查，并作为下面两层的时间上界 |
| 单次模型请求 Timeout | 一次 API 调用的阻塞 | 传给模型客户端的 `timeout`，取 `min(REQUEST_TIMEOUT, deadline - now)` |
| 单次工具 Timeout | 一次工具执行的阻塞 | 执行器的 timeout 参数，同样取 `min(STEP_TIMEOUT, deadline - now)` |
| 取消信号 | 外部要求中断 | 取消令牌 / `CancellationToken` / 进程级中断，向下传递 |

关键是**Deadline 要向下传递，而不是只在入口检查**。这条规则要覆盖到每一层，包括工具：

```python
remaining = deadline - monotonic()          # 全局只剩多少
if remaining <= 0:
    return finish("TIMEOUT", "执行超时，任务未完成", state)
results = execute_tools(
    decision.tool_calls,
    timeout=min(STEP_TIMEOUT, remaining),   # 不能只写 STEP_TIMEOUT
)
```

例如全局只剩 1 秒，若工具仍只收到 `timeout=30`，它就可能继续运行至单工具超时。入口检查得再勤，也拦不住已经冲出去的那一步。这些限制必须在相应执行层实际生效，并共同服从全局剩余时间。

Pydantic AI 的 `timeout=` 就是这个思路：run 级 deadline 会传给子 Agent，子 Agent 自己的 `timeout=` 只能把它缩短、不能延长。

**工具调用超时后，远端执行结果可能仍未知**。工具可能尚未完成，也可能已执行成功但响应未到达（见 5.8）。有副作用的操作应先核查结果，或使用同一幂等键重试。

#### 5.6 停下来之后交回什么

这一节已经跨到 Runtime 层。Loop 只负责判断该停了，而停下来交回什么是 Runtime 的接口约定。它不影响循环跑得对不对，但决定了循环跑完之后还有没有价值。

如果应用边界只暴露异常或返回 `None`，调用方可能无法取得已完成项、未完成项和终止原因。结果结构需要显式携带这些信息。

建议应用层统一一个 Run 结果结构，正常完成、被拦下、挂起都走它：

```json
{
  "status": "interrupted",
  "termination_reason": "REQUEST_BUDGET",
  "output": null,
  "run_id": "run_01HX...",
  "completed": ["read_ticket(INC-2026-1115)", "search_logs(tr-7f3a)"],
  "pending": ["update_ticket"],
  "messages_ref": "s3://.../run_01HX/messages.jsonl",
  "usage": {
    "model_requests": 5,
    "tool_calls": 2,
    "total_tokens": 8400,
    "cost_usd": 0.03
  }
}
```

这里的示例使用以下 `status` 值，告警规则可结合状态与 `termination_reason` 定义：

| `status` | 含义 | 典型 `termination_reason` |
| :--- | :--- | :--- |
| `completed` | 正常完成 | `COMPLETED` |
| `interrupted` | 被闸门拦下，任务没做完 | `REQUEST_BUDGET` / `TOKEN_BUDGET` / `CONTEXT_TOO_LARGE` / `REPEATED_ACTION` / `NO_PROGRESS` |
| `suspended` | 主动等待，可恢复 | `WAITING_APPROVAL` / `WAITING_EVENT` |
| `timed_out` | 超过截止时间 | `TIMEOUT` |
| `failed` | 不可恢复错误 | `UNEXPECTED_RESPONSE` / `RETRY_EXHAUSTED` |
| `cancelled` | 用户或上游主动取消 | `CANCELLED` |

有三个细节：

- **`completed` 和 `interrupted` 必须分得开。** 监控上这是两个完全不同的指标：前者是成功率，后者是防护触发率。混在一起，你永远不知道闸门是不是设得太紧。把正常完成算进「被拦下」，会让人误以为限流过严；反过来，被拦下也算成功，防护就形同虚设。
- **失败要带得回进展。** `completed` / `pending` 两个字段看着朴素，却是「半成品有没有价值」的关键：用户拿到「已找到相关日志和代码，尚未回填工单」，比拿到「任务失败」有用得多。
- **`suspended` 必须带 `run_id` 和断点。** 没有它，「等审批」就等于「从头再来」，这正是 4.3 说的那类事故。

5.3 末尾那个工单案例正好落在这条线上：本地七项用例通过、结果已回填，本次 Run 返回 `completed`，而生产工单仍是待发布状态；如果预算在回填前耗尽，返回值就该是 `interrupted`，`pending` 里带上没做完的回填。

还有一层分寸：把「所有强制终止都返回结构化结果」作为应用层规范可以，但不能要求框架内部也这样。Pydantic AI 用异常 `UsageLimitExceeded`，LangGraph 用 `GraphRecursionError`，这是它们的接口约定。你的 Runtime 该做的是在自己的边界上把这两类异常翻译成统一结果，而不是要求框架改行为。

#### 5.7 落地要点与常见误伤

| 要点 | 说明 |
| :--- | :--- |
| 动作指纹要归一化 | 参数字典排序、仅去掉不影响语义的追踪字段后再 hash；时间范围和游标等应保留，否则同一动作会被判成不同动作，L3 形同虚设 |
| 窗口要有界 | 用 `deque(maxlen=N)`；用无限 list 再取尾部，内存会随轮次线性增长，长期运行时可能持续占用更多内存 |
| 按轮检查动作与观察 | 同一批多个相似调用不等于多轮重复；批次记录保留有意义的顺序与数量，见 5.3 |
| 区分「连续」与「累计」 | 连续 N 轮检测需结合结果；分页和合法轮询应保留参数语义、间隔与上限 |
| L3 挡不住交替循环 | A → B → A → B 不会命中「连续相同」，需要窗口内周期检测，或靠 L1 / L4 兜底 |
| 预算要预留 | 在接近窗口上限前终止，给终止说明和结果摘要留够 Token |
| 留出收尾预算 | 只设一个最大请求数，会在「工具刚执行完」的下一轮入口掐断；要用 `MAX_NORMAL_REQUESTS + FINALIZE_RESERVE` 两段预算，见 5.2 |
| 可观测 | 记录每层触发次数、轮数、耗时、Token 曲线，用来反推阈值是否合理 |

预留收尾请求时，可以在提示中说明剩余额度，并要求模型根据已有信息整理结论。提示、工具限制和输出校验需要共同配合；预留请求不能保证模型一定返回可用结果。

框架是否提供提前收尾，取决于具体接口。Pydantic AI 的请求上限通过 `UsageLimitExceeded` 报告超限；应用若需要提前整理结果，应配置相应策略。6.1 展示一种实现方式，6.3 说明如何在图中控制请求阶段。

#### 5.8 并行、异常与幂等

这三件事都发生在工具执行那一侧。Loop 要做的不是把它们各自实现一遍，而是把约定定清楚：哪些调用可以并发、失败该由谁处理、一次副作用凭什么算「同一次」。

| 场景 | 归谁 | 关键约定 |
| :--- | :--- | :--- |
| 一次响应多个调用 | Loop | 独立只读可并发，有依赖或有副作用串行；混合时读并发、写串行 |
| 工具报错 | Runtime | 瞬时错误在执行器里退避，业务错误交回模型改参数；写操作不无差别重试 |
| 重复写入 | 基础设施 | 第一次执行前保存 `operation_id`，重试沿用；远端按幂等键去重，同键不同参数应当报错 |

一批三个调用成功两个、失败一个，就把两个结果和一条结构化错误一起回灌，每个结果关联原调用 ID，失败项不计入已完成任务。依赖参数必须来自已经拿到结果，不能因为模型在同一批里提了 A、B，就假设 B 看到了 A 的输出。重复检测也按跨轮轨迹看：一批三个 `read_ticket(INC-2026-1115)` 值得优化，但不是已经循环三轮；次数和顺序有意义时，比较的是序列或多重集合。

429 和临时连接问题在执行器里退避；参数错误、资源不存在、权限不足交回模型改参数或停下；凭证失效直接结束并保留进展；写超时或连接断开先记 unknown 再核查。写操作重试可能产生重复记录，因此需要区分执行失败与执行结果未知。

幂等靠的是第一次执行前生成并保存 `operation_id`，重试沿用同一个，新的有意操作换新 ID；不能拿 run_id、工具名和参数拼出身份，用户可能在同一任务里有意追加两条相同评论。动作指纹管发现可疑重复，操作 ID 管识别一次副作用，两者不能合并。远端不支持幂等，就用可查询的操作元数据核查，确认不了保留 unknown 交人工，这跟单机还是多副本无关。

#### 5.9 上线前检查清单

按执行、运行管理和外部副作用分组检查。任意一组的缺口都可能在第一次异常路径中出现。

**Loop 本身**

- [ ] L1 明确按模型请求计数，普通修正计入普通额度；推进数和工具数另行记录
- [ ] 执行预算与收尾预算分开：`MAX_NORMAL_REQUESTS + FINALIZE_RESERVE`，干完活还有一次机会总结
- [ ] 请求前检查阶段额度、deadline、取消与累计预算，工具执行前再次核对限制
- [ ] 单次上下文在**请求发出之前**估算，超了先压缩，压缩后仍超才终止
- [ ] 全局 deadline 会向下传递到模型请求**和工具执行**，不只在循环入口检查
- [ ] 重复检测按轮比较动作与观察，保留有意义的顺序和数量
- [ ] 非最终、非工具调用的响应有明确分支，未知响应显式失败
- [ ] 状态有明确权威来源，消息、待办、预算与时间记录能一致恢复
- [ ] 上下文裁剪之后，`tool_call_id` 仍然成对
- [ ] 一次响应多个工具调用时，并发策略与部分失败语义已定义

**Runtime 层（上生产前）**

- [ ] 所有强制终止都返回 `termination_reason` 与已有结果，不裸抛异常
- [ ] 终止结果区分 `completed` / `interrupted` / `suspended` / `timed_out` / `failed` / `cancelled`
- [ ] 「等待」是独立出口：保存完整现场，以稳定业务任务 ID 关联各执行段，不依赖原进程存活
- [ ] 每次恢复后重新检查待审批请求；拒绝、再次审批、超时和部分结果有独立处理
- [ ] 审批决策关联原调用与参数版本，恢复后新调用仍执行审批策略
- [ ] 区分审批状态与副作用执行状态，重复回调、执行后崩溃和消息重放均可核查
- [ ] 工具异常做了分类：可重试 / 不可重试 / 致命
- [ ] 终止原因进日志与告警，能区分「正常完成」和「被闸门拦下」

**外部副作用与一致性**

- [ ] 有副作用的工具都接受幂等键，超时重试前能判断上次是否已生效
- [ ] 有分页 / 重试等合法重复场景的白名单，避免误杀
- [ ] 明确哪些能力交给框架、哪些要自己补（见第六章）

**验证**

- [ ] 压测过至少一种人为注入的死循环，确认五层各自都能触发
- [ ] 人为制造一次「最后一步工具刚跑完」，确认收尾预算能让它输出结论而不是被掐断

检查清单需要配合故障注入验证：重复查询是否提前停，阻塞能否超时，收尾额度是否独立，以及挂起后能否恢复已有操作。职责可以分给不同组件，但 Loop 要能正确调用它们。

---

### 六、框架里，这个循环长什么样

前面用伪代码拆开了模型请求、工具执行、状态更新和终止判断。使用下文的 Pydantic AI 和 Spring AI 执行入口时，业务代码可以将这些步骤交给框架内部的循环。

下面分别看 Pydantic AI、Spring AI 和 LangGraph 如何实现这段流程：模型响应由谁处理，工具结果如何进入下一次请求，次数限制和终止判断又放在哪里。把这些位置和前面的代码对应起来，就能看清框架已经提供了哪些能力，以及应用还需要补哪些控制。

#### 6.1 Pydantic AI：把循环显式成节点流

`agent.run()` / `run_sync()` 内部跑的是一张 agent graph；`agent.iter()` 会把这张图逐个节点暴露出来，正好可以逐帧对照第二节：

```python
from pydantic_ai import Agent, UsageLimits

agent = Agent("openai:your-model")

async with agent.iter(
    "读取工单 INC-2026-1115 的摘要",
    usage_limits=UsageLimits(request_limit=12),   # L1：模型请求额度为 12
) as run:
    async for node in run:
        print(type(node).__name__)

# UserPromptNode → ModelRequestNode → CallToolsNode
#               → ModelRequestNode → CallToolsNode → End
```

三个节点的职责，需要说得比「请求 / 执行 / 结束」更精确一点：

| 节点 | 真正做的事 |
| :--- | :--- |
| `ModelRequestNode` | 把准备好的上下文发给模型，拿到响应，累计 usage，写入历史 |
| `CallToolsNode` | **处理模型响应**：判定继续还是终止、执行工具调用、校验输出、失败时生成重试提示 |
| `End` | 携带 `FinalResult`，run 结束 |

`CallToolsNode` 负责处理模型响应，职责不只限于执行工具。模型只返回文本时，也需要经过输出校验和终止判定，随后才能进入 `End`。

所以数轮数要看 `ModelRequestNode` 出现的次数，不要看 `CallToolsNode`。

内置限制主要集中在 `UsageLimits`。下列参数与本次核对的官方源码对应，使用时应核对安装版本：

| 参数 | 限制什么 | 对应哪一层 |
| :--- | :--- | :--- |
| `request_limit` | 提交到 run 历史的模型响应数，也就是 Loop 的轮数（默认值依版本，项目中显式设置） | L1 请求次数 |
| `tool_calls_limit` | 成功执行的工具调用次数 | 不直接对应：它限总量，不判重复 |
| `total_tokens_limit` / `input_tokens_limit` / `output_tokens_limit` | 整个 Run 累计 Token | L4 累计预算 |
| `cost_limit` | 整个 Run 累计成本（美元） | L4 |
| `per_request_input_tokens_limit` | **单次请求**的输入 Token 上限 | L5 上下文窗口 |

最后一行是关键。它和 `input_tokens_limit` 不是一回事：前者独立检查每一次请求的输入规模，后者是整个 Run 的累计值，正好对应 5.2 里 L4 与 L5 的区分。设置 `count_tokens_before_request=True` 可以在请求前就拦住超窗调用，否则那次请求仍会被发出并计费。

超时和取消也不止 `tool_timeout`：

| 能力 | 作用 |
| :--- | :--- |
| `Agent(tool_timeout=...)` | 单个工具的执行超时 |
| run 级 `timeout=` | 整个 Run 的执行时长上限，超时抛 `RunTimedOut` |
| `CancellationToken` | 从外部取消，可共享给父子 Agent 整棵树 |
| `ctx.cancel()` / `AgentRun.cancel()` | 在工具体内或手动驱动 `iter()` 时主动取消 |

按前面的分层，这些配置分别涉及 L1、L2、L4 和 L5。L5 的输入限制不包含输出预留，仍需结合模型窗口配置。子 Agent 会继承父 Agent 的 deadline，自己的 `timeout=` 只能缩短不能延长，这就是 5.5 说的「Deadline 向下传递」。

计数和检查时机需要分别说明：

- `request_limit` 按提交到 Run 历史的模型响应计数，不等于供应商 HTTP 请求次数。FallbackModel 放弃的尝试、续传请求和 SDK 传输层重试不单独计入该次数；框架取得的响应 usage 仍用于统计 Token 和成本，不能据此外推所有底层尝试的费用都已被记录。
- 累计 Token 与成本按响应 usage 更新，超限响应可能已经产生费用。`count_tokens_before_request=True` 可以提前检查输入 Token，并按可用价格数据检查输入成本下界；实际输出消耗仍需在响应后统计。`cost_limit` 还依赖供应商 usage 和价格数据，不能单独作为硬计费保证。

如果下一次请求会超过 `request_limit`，Run 会抛出 `UsageLimitExceeded`；请求上限本身不负责生成总结。想让它「带着已有信息给个结论」，得自己实现一个 capability：在 `before_model_request` 里算还剩几次、把剩余次数告诉模型，最后一次请求把 function tools 摘掉，只保留输出通道。这正好对应 5.2 讲的收尾预算。区别是，在自研循环里直接控制请求阶段，在框架里得包成一个扩展点。

```python
from dataclasses import dataclass
from typing import Any

from pydantic_ai import (
    Agent, RunContext, SystemPromptPart, ToolDefinition, UsageLimits,
)
from pydantic_ai.capabilities import AbstractCapability
from pydantic_ai.models import ModelRequestContext


def requests_left(ctx: RunContext[Any]) -> int | None:
    limit = ctx.usage_limits.request_limit if ctx.usage_limits else None
    return None if limit is None else limit - ctx.usage.requests


@dataclass
class WrapUpNearRequestLimit(AbstractCapability[Any]):
    """剩几次请求时提醒模型收尾，并在最后一次把普通工具摘掉。"""

    warn_at: int = 3

    async def before_model_request(
        self,
        ctx: RunContext[Any],
        request_context: ModelRequestContext,
    ) -> ModelRequestContext:
        left = requests_left(ctx)
        if left is not None and left <= self.warn_at:
            ctx.enqueue(
                SystemPromptPart(
                    f"Only {left} model request(s) left in this run. "
                    "Produce your final output now, using what you already have.",
                    scope="request",     # 只影响这一次请求，不污染后续历史
                )
            )
        return request_context

    async def prepare_tools(
        self,
        ctx: RunContext[Any],
        tool_defs: list[ToolDefinition],
    ) -> list[ToolDefinition]:
        # 最后一次请求摘掉 function tools，只留输出通道
        return [] if requests_left(ctx) == 1 else tool_defs


agent = Agent("openai:your-model", capabilities=[WrapUpNearRequestLimit()])
result = agent.run_sync(
    "分析工单 INC-2026-1115 的日志与代码，给出验证后的方案",
    usage_limits=UsageLimits(request_limit=8),
)
```

这个扩展点示例还有几处需要核对：

- **示例为 `AbstractCapability` 指定了 `[Any]` 类型参数**。它是泛型基类，是否允许省略类型参数取决于类型检查配置。
- **示例通过 `ctx.enqueue(SystemPromptPart(...))` 添加提示**，提示会进入当前请求及消息历史。给 `request_context.messages` 赋一个新列表只改变本次请求；直接 `append` 等原地追加在核对版本中仍会影响历史，但已被弃用。因此不能将所有「修改 messages」操作概括为相同语义。
- **`scope="request"` 是关键**。默认是 `conversation`，那条提示会一直留在后续请求里；设成 `request` 后，它只对这一次生效：每轮看到的是当前剩余次数，而不是一串过期的「只剩 3 次」。
- **`prepare_tools` 只摘 function tools**，结构化输出用的 output tool 会保留，所以有 `output_type` 的 Agent 仍然能正常产出结构化结果。

**这套收尾策略不保证成功**。如果最后一次输出校验失败，后续修正请求仍受 `request_limit` 约束。该策略为整理已有信息留出请求机会，但不能保证输出合格。

同步工具的超时可能只会停止等待结果：用同步 `def` 写的工具跑在工作线程里，超时触发时 Runtime 结束的是「等待结果」这件事，底层线程未必真的被终止。它可能还在跑，甚至稍后把副作用落了盘。所以有副作用的同步工具，光配 `tool_timeout` 不够，仍然要幂等键或执行结果核查，跟前面幂等那节的约定是同一条。

上述额度配置不检查动作是否重复，也不判断业务进展。需要 L3 检查时，应另行定义动作指纹和进展判据。

##### 用 Deferred Tools 接入审批，无需接管节点循环

对于需要由前端或独立审批服务处理的工具调用，可以将 `DeferredToolRequests` 声明为一种输出，并在工具上设置 `requires_approval=True`。未批准时，框架不会进入这个工具的函数体，而是返回待审批调用。应用收集决策后，将原消息历史和 `DeferredToolResults` 传给新的 `run()` / `run_sync()`；批准项由框架执行，拒绝项形成工具结果，再继续模型与工具的交互。

下面沿用工单场景，并增加需要单独审批的通知工具。`model` 是已配置的模型对象，`ticket_service` 是业务服务；`store` 和 `evaluate_and_finish` 是应用接口，持久化与并发约定见代码之后。

```python
from pydantic_ai import Agent, DeferredToolRequests, DeferredToolResults

agent = Agent(model, output_type=[str, DeferredToolRequests])


@agent.tool_plain
def read_ticket(ticket_id: str) -> str:
    return ticket_service.read(ticket_id)


@agent.tool_plain(requires_approval=True)
def update_ticket(ticket_id: str, comment: str) -> str:
    return ticket_service.append_comment(ticket_id, comment)


@agent.tool_plain(requires_approval=True)
def notify_owner(ticket_id: str, content: str) -> str:
    return ticket_service.notify_owner(ticket_id, content)


def handle_result(task_id, result):
    # 首次执行、每一次恢复，都进入同一分流函数。
    if isinstance(result.output, DeferredToolRequests):
        pause_id = store.save_pause(
            task_id=task_id,
            messages=result.all_messages(),
            requests=result.output,
        )
        return {"status": "suspended", "pause_id": pause_id}
    return evaluate_and_finish(task_id, result)


def start(task_id, prompt):
    return handle_result(task_id, agent.run_sync(prompt))


def resume(pause_id, approver, decisions):
    # 服务端读取原现场；校验审批人、有效期、参数版本和每项决策，排除并发恢复。
    checkpoint = store.claim_and_validate(pause_id, approver, decisions)
    pending = checkpoint.requests
    if pending.calls:
        raise ValueError("本例仅处理审批，外部执行结果需走独立回填入口")
    expected = {call.tool_call_id for call in pending.approvals}
    if set(decisions) != expected:
        raise ValueError("审批结果必须覆盖本暂停点的全部待审批调用")

    result = agent.run_sync(
        message_history=checkpoint.messages,
        deferred_tool_results=DeferredToolResults(approvals=decisions),
    )
    return handle_result(checkpoint.task_id, result)
```

`decisions` 按原 `tool_call_id` 映射为 `True`、`False`，或 `ToolDenied("拒绝原因")`；后者从 `pydantic_ai` 导入。这里不额外传「继续执行」用户消息，框架已经能从历史与 deferred results 关联原调用。恢复后如果模型又请求 `notify_owner`，`handle_result` 会保存新的暂停点，而不会把恢复结果直接当作最终文本。

这段代码展示框架调用方式，不是一套完整审批服务。`claim_and_validate` 必须根据服务端记录验证决策，`save_pause` 必须将旧执行段的结果与新暂停点关联。工具执行 hook 或业务执行器还需即时记录操作与结果，不能等整个 `run_sync()` 返回后才记账；即使后续模型请求失败，也要能核查先前副作用。记录与恢复约定见 4.4、5.8。示例未接入任务累计预算，落地时需在每段调用前检查剩余额度、调用后累计 usage。仅对本段设置 `UsageLimits`，不能自动限制跨多次审批的总消耗。

还要区分几个边界：

- `DeferredToolRequests.approvals` 是待批准、批准后由框架执行的调用；`calls` 是等待外部提供结果的调用，结果填入 `DeferredToolResults.calls`。不能把两类请求都当成审批按钮。
- 本节选择返回 deferred output 的方式：本次框架 run 已结束，后续是使用原历史发起的新 run；稳定业务任务 ID 负责跨段关联。不要把旧框架 `run_id` 当作必须原样恢复的进程句柄。
- 若审批条件依参数或上下文变化，可以在副作用之前抛 `ApprovalRequired`，恢复时检查 `ctx.tool_call_approved`。检查前不能先做写入，因为函数可能再次进入。
- Pydantic AI 也提供 `HandleDeferredToolCalls` capability，在同一次 run 内解析 deferred calls。进程内等待与跨请求返回是不同方案；普通 handler 的存在本身不等于已经具备持久化恢复。
- 同一模型响应中，不需要审批的其他工具可能已执行。不能把 Spring AI 的「一项需确认则整批不执行」规则套到这里；保存完整历史及实际执行结果，再区分剩余待处理项。

MCP 工具也可在执行边界加审批。`ApprovalRequiredToolset` 可以包装已有 MCP toolset；下面只给指定工具加门禁，工具名应以该 toolset 的实际定义为准：

```python
from pydantic_ai.toolsets.approval_required import ApprovalRequiredToolset

approved_mcp_tools = ApprovalRequiredToolset(
    mcp_toolset,
    approval_required_func=lambda ctx, tool_def, args: tool_def.name in {
        "update_ticket", "notify_owner",
    },
)
mcp_agent = Agent(
    model,
    toolsets=[approved_mcp_tools],
    output_type=[str, DeferredToolRequests],
)
```

wrapper 控制是否允许发起调用，MCP Server 仍负责业务授权。工具名改变、增加前缀或动态加载时，需要核对审批策略实际匹配到的工具。

#### 6.2 Spring AI 2.x：Advisor 循环与工具确认

这里需要区分版本。Spring AI 1.x 在支持工具调用的 `ChatModel` 实现中内置了工具执行循环，可用 `internalToolExecutionEnabled` 开关；**2.0 起这个选项和「每模型内置循环」都被移除**，循环统一交给 `ChatClient` 的 `ToolCallingAdvisor` 驱动：有工具时自动注册，`ToolCallingManager` 负责执行，直到模型返回不带 tool calls 的响应。

```java
// 有工具时 ToolCallingAdvisor 自动驱动循环，无需手写 while
String answer = chatClient.prompt()
    .user("读取工单 INC-2026-1115 的摘要")
    .tools(ticketTools)
    .call()
    .content();

// 想自己掌控循环：关闭自动注册，或直接调 ChatModel
// .advisors(AdvisorParams.toolCallingAdvisorAutoRegister(false))
// 再自行检查 chatResponse.hasToolCalls() 并用 ToolCallingManager 驱动
```

`ToolCallingAdvisor` 通过 `ToolExecutionEligibilityChecker` 判定是否执行工具，可通过 builder 替换检查器。默认按响应是否包含工具调用判断，与 4.1 的基础分支对应。

三个和 Loop 直接相关的设计：

`returnDirect` 是一次显式跳出，但有多工具例外。`@Tool(returnDirect = true)` 让工具结果直接返回调用方，不回灌模型。但如果模型**一次请求了多个工具**，只有全部工具都标了 `returnDirect = true`，才会真的直接返回；只要有一个没标，结果仍然会回灌、循环继续。

**Advisor 顺序影响可见的调用范围。** 位于循环外的 Advisor 处理外层请求与最终响应，位于循环内的 Advisor 会随每次模型请求执行。文档中的 `MessageChatMemoryAdvisor` 默认位于循环外；需要逐轮记录工具交互时，应配置相应顺序和记录逻辑。

**模型请求次数与工具调用额度需要分别统计。**

这里核对的 `ToolCallingAdvisor.adviseCall` 实现通过循环驱动「调用模型 → 有工具就执行 → 再调用」，该循环没有模型请求次数计数器。模型请求额度应在模型请求边界统计，不能只包住工具执行器；没有工具调用的修正路径也要计入。

`DefaultToolCallingManager` 另行管理工具调用额度：

| 配置项 | 含义 | 默认值 |
| :--- | :--- | :--- |
| `spring.ai.tools.limits.max-calls-per-tool-default` | 一次用户回合中对**单个工具**的最大调用次数 | 40 |
| `spring.ai.tools.limits.max-calls-per-tool.<name>` | 单个工具的覆盖值，`-1` 表示豁免 | — |
| `spring.ai.tools.limits.max-total-tool-calls` | 一次用户回合中跨**所有工具**的最大调用次数 | 150 |
| `spring.ai.tools.limits.on-limit-exceeded` | 超限行为：`THROW` 或 `RETURN_ERROR_RESPONSE` | `THROW` |

超限时抛 `ToolCallLimitExceededException`，异常里**带着 `ToolExecutionResult` 的部分结果**，已执行的调用不会被丢弃；`ToolCallingAdvisor` 会捕获它并作为最终响应返回，`finish_reason` 是 `ToolCallLimitExceededException.FINISH_REASON`。选 `RETURN_ERROR_RESPONSE` 则不中断循环，而是合成一条错误 `ToolResponse` 回灌给模型，让它自己收敛，这种处理会继续请求模型，因此仍需其他执行上限。

这里的用户回合（turn）指从最后一条 `UserMessage` 开始的交互，可以包含多次模型请求。管理器根据该回合中的 `ToolResponseMessage` 重新统计调用数，因此「每次模型响应只调用一个工具」也会累计触及额度。

**工具调用次数仍不等于模型请求次数。** 一次模型响应可以提出多个工具调用，没有工具调用的模型请求也不消耗工具额度。要限制模型请求总量，仍应单独计数；业务进展、时间、费用和上下文限制也需要分别配置。

还有一个迁移细节：照着 1.x 教程写 `internalToolExecutionEnabled(false)` 在 2.0 已经编译不过，要换成关闭自动注册或直接调 `ChatModel`。

##### Spring AI 2.1：工具确认与多次审批

以下接口从 **Spring AI 2.1.0** 引入，本次核对的官方 2.1 文档标示为 **2.1.0-RC2**。这是版本边界说明，不表示这些接口存在于 2.0.x；不要在 2.0.x 直接使用 `requiresConfirmation` 或三参数恢复 API。

声明工具需要确认：

```java
class TicketTools {
    private final TicketService ticketService;

    TicketTools(TicketService ticketService) {
        this.ticketService = ticketService;
    }

    @Tool(description = "读取工单")
    public String readTicket(String ticketId) {
        return ticketService.read(ticketId);
    }

    @Tool(description = "回填工单评论", requiresConfirmation = true)
    public String updateTicket(String ticketId, String comment) {
        return ticketService.appendComment(ticketId, comment);
    }

    @Tool(description = "通知工单负责人", requiresConfirmation = true)
    public String notifyOwner(String ticketId, String content) {
        return ticketService.notifyOwner(ticketId, content);
    }
}
```

默认确认策略读取工具 metadata，也可通过 `ToolCallConfirmationPolicy` 按工具名或参数配置。检查在 `ToolCallingManager` 执行工具前发生：**同一模型响应只要有一项需要确认，这一响应的整批调用都不执行**。`ToolCallingAdvisor` 捕获 `ToolCallConfirmationRequiredException`，返回带待确认 key 的 `ChatResponse`。暂停前更早轮次的工具可能已经执行，不能将整批未执行理解为整个用户回合都没有副作用。

应用使用 `ToolCallDecisions.awaitingDecision(response)` 检查暂停；不要只读 `.content()`，暂停响应的文本可以为空。恢复时，`ToolCallDecisions` 必须覆盖该响应中的**全部调用**，包括未要求人工确认的调用。待审批项使用已核验的人工作出的决策，其他项按服务端策略决定，不能把所有 key 一律映射为 `allow`。key 通常是调用 ID；缺失或重复 ID 时，框架使用 `#0`、`#1` 等位置 key，所以要通过 `toolCallKeys` 获取，并保存原响应及调用顺序。

##### 先保存完整历史，再恢复原批次

`ChatResponse` 只包含触发暂停的模型响应，不包含 Loop 内更早的查询与工具结果。仅保存「用户问题 + 暂停响应」，会丢掉模型作出该调用时已取得的上下文，也可能漏计本回合已执行的工具次数。

下面用官方文档仍支持的 `MessageChatMemoryAdvisor` 说明如何逐轮记录。它与 `ChatMemory` 在 2.1 中已标记弃用，计划在 3.0 移除；新项目可按目标版本采用 Session Memory。本例选用此兼容接口，是为了明确历史保存与恢复关系，不应把它当成长期固定入口。

```java
// Spring Boot 场景：builder 与恢复入口使用同一个自动配置的 ToolCallingManager。
// chatMemory 需接持久化后端，并保存本任务完整的工具消息，不能只留一个短滑动窗口。
ChatClient chatClient = builder
    .defaultTools(ticketTools)
    .defaultAdvisors(MessageChatMemoryAdvisor.builder(chatMemory)
        .order(ToolCallingAdvisor.DEFAULT_ORDER + 100) // 放在工具循环内
        .build())
    .build();
```

自动注册的 `ToolCallingAdvisor` 会识别内层 Memory Advisor，协调内部历史转发；若手动构造 ToolCallingAdvisor，需要按文档设置 `disableInternalConversationHistory()`。同一批工具的恢复仍需完整 turn 历史给 manager 计数，而再次进入 Memory Advisor 时只提交新工具结果，避免重复追加整个历史。

下面是服务层核心方法，省略类、依赖注入与 import。`approvalStore`、`trustedToolOptions`、`classifyAndValidateOutcome` 是应用接口；`ToolCallDecision`、`ToolCallDecisions`、`ToolCallingManager`、`ToolExecutionResult` 位于 `org.springframework.ai.model.tool`。示例不使用 `returnDirect` 工具。

```java
AgentOutcome start(String conversationId, String question) {
    approvalStore.requireNoPendingPause(conversationId);
    ChatResponse reply = chatClient.prompt()
        .user(question)
        .advisors(a -> a.param(MemoryAdvisor.CONVERSATION_ID, conversationId))
        .call().chatResponse();
    return handleResponse(conversationId, reply);
}

AgentOutcome handleResponse(String conversationId, ChatResponse reply) {
    List<String> awaiting = ToolCallDecisions.awaitingDecision(reply);
    if (!awaiting.isEmpty()) {
        // 内层 memory 已保存本轮 Assistant 调用，包含暂停前查询的完整消息。
        Prompt prompt = new Prompt(
            List.copyOf(chatMemory.get(conversationId)),
            trustedToolOptions(conversationId));
        String pauseId = approvalStore.savePause(
            conversationId, prompt, reply, awaiting);
        return AgentOutcome.suspended(pauseId);
    }
    // 还需检查 null、拒绝、截断、超限、输出与业务完成条件，不能直接 completed。
    return classifyAndValidateOutcome(conversationId, reply);
}

AgentOutcome resume(String pauseId, Approver approver,
                    Map<String, HumanDecision> submitted) {
    // 服务端读取原 Prompt/ChatResponse；核验审批并取得会话推进权。
    ApprovalCheckpoint cp = approvalStore.claimAndValidate(pauseId, approver, submitted);
    ToolExecutionResult execution = cp.savedExecution();
    if (execution == null) {
        List<String> keys = ToolCallDecisions.toolCallKeys(cp.reply().getResult().getOutput());
        ToolCallDecision[] decisions = keys.stream()
            // 人工待审批项来自已核验记录，其他项按服务端策略给出 allow / deny。
            .map(key -> approvalStore.decisionFor(cp, key))
            .toArray(ToolCallDecision[]::new);

        approvalStore.markExecuting(cp); // 执行前记账，异常后不能把无结果视为未执行
        execution = toolCallingManager.executeToolCalls(
            cp.prompt(), cp.reply(), ToolCallDecisions.of(decisions));
        // 先保存执行结果与 READY_TO_CONTINUE 状态，再请求模型。
        approvalStore.saveExecution(cp, execution);
    }

    List<Message> history = execution.conversationHistory();
    Message toolResults = history.get(history.size() - 1);
    // memory 已有原调用，仅追加 ToolResponseMessage；不要再追加整份 history。
    // 返回尚未追加的消息；若结果已在 memory，返回空列表，避免重试时重复追加。
    List<Message> newMessages = approvalStore.messagesToAppend(cp, toolResults);
    ChatResponse next = chatClient.prompt()
        .messages(newMessages)
        .advisors(a -> a.param(MemoryAdvisor.CONVERSATION_ID, cp.conversationId()))
        .call().chatResponse();

    return handleResponse(cp.conversationId(), next); // 可能产生新的 pauseId
}
```

审批拒绝用 `ToolCallDecision.deny(key, "拒绝原因")`；框架不会执行该调用，而是生成相应工具结果。允许项用 `ToolCallDecision.allow(key)`。三参数恢复直接执行传入的逐调用决策，不重新咨询确认策略；因此原批次、工具配置与决策必须由服务端校验和关联。它只执行原批次，后续模型请求仍交给 `ChatClient` / `ToolCallingAdvisor` 驱动，新调用仍经过确认策略。

上面的应用接口承担以下约定，不能用一个内存 Map 或「已审批」布尔值代替：

- `savePause` 冻结服务端的完整消息、原始响应、调用 key / 顺序、工具与参数版本，并返回唯一暂停 ID。恢复时重建相同工具配置；工具回调对象本身不作为跨进程序列化数据，用户身份与授权由当前可信上下文提供。
- `claimAndValidate` 核验审批人权限、过期时间与参数版本，并串行化同一会话的推进。只有确认尚未执行时，才允许进入首次执行分支；重复请求返回既有状态或继续已保存的后续阶段，不重新执行已知成功的工具。`markExecuting` 在副作用之前保存执行意图。审批决定逐项保存，不能只提交一次「全部同意」。
- `saveExecution` 保存已完成工具的实际结果和下一执行阶段。若工具已经产生副作用而保存前崩溃，仍按操作 ID 核查；`savedExecution == null` 本身不足以证明工具没有运行。状态为 `EXECUTING` / `UNKNOWN` 时先核查，不能直接走示例中的首次执行分支。
- 完成旧暂停点、保存新暂停点或最终结果需要按会话版本关联提交；仅把旧审批标记为 resolved 后返回一段文本，会漏掉再次审批和崩溃恢复。`messagesToAppend` 需核对本批工具结果是否已完整进入 memory；Memory 写入与审批记录若不在同一事务中，还需消息 ID / 阶段记录来去重和补偿。
- 三参数 `executeToolCalls` 超工具额度时，`ToolCallLimitExceededException` 直接交给应用处理，没有 Advisor 自动捕获。异常边界需保存部分结果并返回结构化终止状态；重新调用 `ChatClient` 时也继续执行任务级请求、时间和费用限制。

如果不用 Memory Advisor，可以由应用通过逐轮 hook 或记录组件保存完整历史；恢复时传完整 `Prompt` 给 manager，再把 `execution.conversationHistory()` 交给 ChatClient。这时不要同时启用一套会再次追加同样消息的 Memory 流程。若使用 `returnDirect`，恢复执行后还应检查 `execution.returnDirect()`，按直接返回语义处理，不额外请求模型。

MCP 工具无需改写为本地 `@Tool`。在 2.1 自动配置场景中，可通过 `spring.ai.tools.confirmation.tools` 指定实际注册的工具名，例如：

```yaml
spring:
  ai:
    tools:
      confirmation:
        tools:
          - update_ticket
          - notify_owner
```

需要按前缀、工具发现和当前策略核对最终名称。该配置控制客户端是否发出调用，不替代 MCP Server 的授权与幂等检查。

对于没有内置 Confirmation API 的版本，可以在工具回调或执行拦截层实现等价门禁，并由应用保存和恢复现场；具体是否需要手动推进，取决于所用框架扩展点。不能以一次普通工具错误模拟「已暂停」，让框架继续空转；也不能仅因缺少这套 API 就断定必须重写整个 Agent Loop。

#### 6.3 LangChain / LangGraph：用有环图表达迭代

前面的例子把循环写在 `while` 里。LangGraph 可以把同一段流程拆成节点，再通过边决定下一步执行哪个节点。模型调用和工具执行各占一个节点，工具执行后回到模型节点，就能继续下一轮。

LangChain 的 `create_agent` 提供较高层的 Agent 接口，底层基于 LangGraph 运行。如果需要自己控制节点、路由和状态，可以直接使用 LangGraph 的 `StateGraph`。下面用后一种方式展开，看看循环具体放在哪里。

##### 先把循环画出来

对于工单排查，最简单的工具调用流程是：

```text
START → agent（请求模型）
          ├── 有工具调用 → tools（执行工具）→ agent
          └── 无工具调用 → END
```

这里实际只有两个业务节点：`agent` 和 `tools`。`agent` 的响应决定走向工具还是结束；`tools` 把结果写回状态后，再回到 `agent`。

代码可以写成下面这样。假设 `model` 是已经配置好的 LangChain 聊天模型，`tools` 是已定义的工单查询、日志查询等工具：

```python
from langgraph.graph import StateGraph, MessagesState, START, END
from langgraph.prebuilt import ToolNode, tools_condition

model_with_tools = model.bind_tools(tools)


def call_model(state: MessagesState):
    response = model_with_tools.invoke(state["messages"])
    return {"messages": [response]}


builder = StateGraph(MessagesState)
builder.add_node("agent", call_model)
builder.add_node("tools", ToolNode(tools))
builder.add_edge(START, "agent")
builder.add_conditional_edges(
    "agent",
    tools_condition,
    {"tools": "tools", "__end__": END},
)
builder.add_edge("tools", "agent")
graph = builder.compile()
```

`tools_condition` 检查最后一条模型消息：有工具调用就路由到 `tools`，否则路由到 `END`。`tools → agent` 这条边负责在执行后重新请求模型。原来 `while` 中的判断和 `continue`，在这里分别由条件边和回边表达。

图本身不要求有环，也可以表达固定顺序的工作流。这里由于工具节点会回到模型节点，才形成了重复执行的路径。LangGraph 还提供状态、调度和持久化等能力，循环只是其中一种用法。

##### 一轮执行时，消息怎么变化

`MessagesState` 中的 `messages` 配置了消息合并规则。上面 `call_model` 返回的是本节点新增的消息，框架负责把它合并进已有历史；节点不需要每次返回完整对话。

以查询日志为例，状态会经过下面的变化：

```text
进入 agent：
  User：分析工单 INC-2026-1115，相关 trace 为 tr-7f3a

agent 返回后：
  User：……
  Assistant：tool_calls=[search_logs(trace_id="tr-7f3a")]

tools 返回后：
  User：……
  Assistant：tool_calls=[……]
  Tool：TypeError，report_service.py:42，revision=a13c9e7

再次进入 agent：
  模型读取日志结果，可能请求读取对应版本的代码
```

`ToolNode` 根据模型消息执行工具，并生成关联原调用 ID 的 `ToolMessage`。这些结果合并进状态后，回边使 `call_model` 再次执行。工具结果因此进入下一次模型输入。

这个示例仍然沿用前面那个简化约定：没有工具调用就结束。如果还需要校验诊断结果、检查工单是否成功回填，就要在模型节点或额外节点中增加判断，并使用自己的路由函数。`tools_condition` 本身不检查业务目标是否完成。

##### 图执行上限与模型请求额度

LangGraph 的 `recursion_limit` 约束图执行的 super-step 数量。super-step 可以理解为图调度的一轮，同一轮中可能执行多个并行节点。

在上面这个简单图里，一次模型执行和一次工具节点执行分别占用调度步骤；增加验证节点、并行分支或子图后，图步数与模型调用次数的关系还会变化。因此，不能把 `recursion_limit=20` 直接解释成「最多请求模型二十次」。

如果业务要求「普通请求最多八次，再留一次收尾」，应在模型请求处记录阶段和次数，按前面那套计数规则切换工具及路由。`recursion_limit` 继续作为图执行层的上限，超限时抛出 `GraphRecursionError`。图的默认上限按所用版本核对，应用边界负责把异常转换成带进展的运行结果。

排查时可以使用 `stream_mode="updates"` 查看节点更新，或按版本支持的调试流查看执行事件。重点看模型节点是否重复进入、工具结果是否进入状态，以及条件边实际选择了哪条路径。

##### 等审批时如何恢复

在工单案例中，可以在回填工具执行前设置审批节点。配合 checkpointer 保存图状态，节点通过 `interrupt` 等待审批；审批事件到达后，使用同一个 `thread_id` 调用图，并以 `Command(resume=...)` 提交决策。后续再次执行到审批节点时仍可触发新的 interrupt，应用每次执行后都要检查是否还有中断，而不是恢复一次就默认结束。

需要注意，恢复时节点中的部分代码可能重新执行。待回填内容、审批对应的参数版本和稳定操作 ID 应在副作用之前保存；外部工单写入仍要遵守前面那套幂等与核查约定。图保存了执行位置，不等于远端评论一定没有写入过。

`AgentExecutor` 和 `langgraph.prebuilt.create_react_agent` 是另外两个 Agent 入口。前者把动作、Observation 和结束判断封装在执行器中；后者是预构建 Agent 接口。LangChain v1 提供 `langchain.agents.create_agent`；具体迁移按安装版本核对。上面手动构建的 `StateGraph` 用来说明节点和边如何组成 Loop，不依赖这两个旧入口。

#### 6.4 横向对照

| 框架 | 循环如何被表达 | 状态放在哪 | 默认终止条件 | 挂起 / 恢复 | 内置覆盖哪几层 | 能否接管循环 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Pydantic AI | 框架预定义 agent graph 的节点流 | `ModelMessage` 历史 + RunUsage | 图到达 `End`；结果可能是正常输出或 deferred requests | Deferred Tools：返回待处理请求，以历史与结果发起后续 run；也可 inline handler | L1（`request_limit`）、L2（`timeout`）、L4（`total_tokens_limit`）、L5（`per_request_input_tokens_limit`） | 可用 `next(node)` 手动推进 |
| Spring AI 2.x | `ToolCallingAdvisor` 驱动循环 | loop 内的会话历史 | 响应无 tool calls；`returnDirect` 直接返回 | 2.1 引入 Tool Call Confirmation；现场持久化与多次恢复由应用负责 | 每用户回合工具调用额度（单工具 40 / 总量 150）；**模型请求上限需自建** | 关闭自动注册或直连 `ChatModel` |
| LangGraph | 有环 `StateGraph` 的回边（Pregel super-step 调度） | `State` / `MessagesState` + checkpointer | 条件边路由到 `END` | 原生（checkpointer + `interrupt`） | 图执行层兜底（`recursion_limit` 数 super-step，**不等于** Agent 轮数） | 自定义边即可 |

从表中可以看到，各框架在额度、工具执行和图调度上暴露的控制点不同。Pydantic AI 提供 usage 和 run 时间限制，Spring AI 需要区分工具额度与请求次数，LangGraph 需要区分图步数与模型请求次数。L3 的业务进展判据需由应用按任务目标定义。挂起和恢复能力也要结合所选版本、检查点后端及业务状态设计。

#### 6.5 三种表达，一个循环

这篇笔记从状态、单轮执行和终止条件三个方面比较这三种实现。它们分别用框架预定义节点流、Advisor 控制流和有环图表达循环。Pydantic AI 和 LangGraph 都叫 graph，但前者在常规 Agent 用法中使用内部预定义图，也可以手动推进节点；后者拓扑由你画边决定，环也是你引入的。两者都不意味着「图等于循环」。

框架提供部分终止与限制机制；应用仍需要选择阈值、定义业务完成条件，并补齐所用接口没有覆盖的控制。

这些框架也会提供持久化、恢复、超时等运行能力，覆盖范围依版本和配置而定。外部写入的一致性与幂等保证仍需结合工具和远端接口设计。看清恢复时哪些代码会重执行，比单独比较 API 数量更有帮助。

---

### 结语

从最小 while 到框架里的节点流、Advisor 和状态图，循环都需要维护当前状态，处理模型响应，并把动作结果带到下一次请求中。保留这些实现细节，是为了遇到异常时能定位到具体环节。

工单案例里，日志告诉我们读哪个版本的代码，接口约定决定修复方向，验证结果决定可以交付哪些结论。请求额度和时间约束执行范围，待办、审批与操作 ID 为恢复提供依据。

实现时可以分别检查：调用与结果是否配对，响应是否校验，普通与收尾额度是否分开，断点是否包含完整执行位置，以及写入结果未知时能否核查。正常路径跑通之后，再注入重复查询、格式修正和进程退出，才容易发现这些缺口。

笔者的体会是，先把「什么情况下必须停、停下来交回什么」想清楚，再回头写那个 `while`，比先跑起来再补闸门要省事得多。

---

### 附：参考资料与版本说明

官方参考链接（2026 年 11 月 17 日核对；Pydantic AI 引用 main 分支文档，Spring AI 审批示例对照 2.1.0-RC2 文档与源码。下列未固定版本的链接可能随项目更新）：

示例验证范围：Pydantic AI 审批代码使用 2.69.0 的 `FunctionModel` 验证了连续两次审批、首次拒绝、第二次拒绝及混合工具批次。该验证不包含真实业务写入和持久化后端；Spring AI 核对了框架 API 与文档，服务层代码包含应用接口，未作为完整 Spring 服务编译运行。

- Pydantic AI — Agents / Usage Limits（`request_limit` 默认值、`per_request_input_tokens_limit`、收尾 capability 范式）：[官方文档源文件](https://github.com/pydantic/pydantic-ai/blob/main/docs/agent.md#usage-limits)
- Spring AI 2.0 — Tool Calling（`ToolCallingAdvisor`、`ToolCallingManager`、`returnDirect`）：[官方资料](https://docs.spring.io/spring-ai/reference/api/tools.html)
- Spring AI 2.0 — Advisors（`toolCallingAdvisorAutoRegister`）：[官方资料](https://docs.spring.io/spring-ai/reference/api/advisors.html)
- Spring AI — Tool Call Limits（`spring.ai.tools.limits.*`、`ToolCallLimitExceededException`）：[官方文档](https://docs.spring.io/spring-ai/reference/api/tools.html)
- Pydantic AI — Building Custom Capabilities（`AbstractCapability`、`ctx.enqueue`、`prepare_tools`）：[官方文档源文件](https://github.com/pydantic/pydantic-ai/blob/main/docs/capabilities/custom.md)
- Pydantic AI — UsageLimits / RunUsage 的计数与检查逻辑：[官方源码](https://github.com/pydantic/pydantic-ai/blob/main/pydantic_ai_slim/pydantic_ai/usage.py)
- Spring AI — ToolCallingAdvisor 的循环实现：[2.1.0-RC2 源码](https://github.com/spring-projects/spring-ai/blob/v2.1.0-RC2/spring-ai-client-chat/src/main/java/org/springframework/ai/chat/client/advisor/ToolCallingAdvisor.java)
- Spring AI 2.1 — Tool Call Confirmation（整批暂停、逐调用决策、历史与恢复）：[官方文档](https://docs.spring.io/spring-ai/reference/2.1/api/tools/tool-call-confirmation.html)
- Spring AI 2.1 — ToolCallingManager 三参数恢复接口：[2.1.0-RC2 源码](https://github.com/spring-projects/spring-ai/blob/v2.1.0-RC2/spring-ai-model/src/main/java/org/springframework/ai/model/tool/ToolCallingManager.java)
- Pydantic AI — Deferred Tools（审批、外部执行、后续 run 与 inline handler）：[官方文档源文件](https://github.com/pydantic/pydantic-ai/blob/main/docs/deferred-tools.md)
- Pydantic AI — ApprovalRequiredToolset：[官方源码](https://github.com/pydantic/pydantic-ai/blob/main/pydantic_ai_slim/pydantic_ai/toolsets/approval_required.py)
- LangGraph — Graph API 与递归限制：[官方资料](https://docs.langchain.com/oss/python/langgraph/graph-api)

**版本相关配置与行为**，使用时应与安装版本对应：

| 事项 | 变化情况 |
| :--- | :--- |
| Pydantic AI `request_limit` 默认值 | 本次核对的源码默认值为 50；项目可显式设置 |
| Pydantic AI `request_limit` 的行为 | 下一请求会超限时抛 `UsageLimitExceeded`；上限本身不负责收尾 |
| Spring AI 的循环位置 | 1.x 由支持工具调用的 `ChatModel` 实现驱动；2.0 交给 `ToolCallingAdvisor`，`internalToolExecutionEnabled` 已移除 |
| Spring AI Advisor 参数 | 这里的示例使用 `toolCallingAdvisorAutoRegister`；迁移时按目标版本 API 核对 |
| Spring AI 工具确认 | 从 2.1.0 引入；这篇笔记对照 2.1.0-RC2，不适用于 2.0.x |
| Spring AI Memory 接口 | `ChatMemory` / `MessageChatMemoryAdvisor` 从 2.1 标记弃用、计划 3.0 移除；新项目按目标版本采用 Session Memory |
| Pydantic AI 外部审批恢复 | `DeferredToolRequests` 结束当前 run；后续 run 使用原历史与 `DeferredToolResults`，任务级预算需跨段累计 |
| LangGraph `recursion_limit` 默认值 | 按安装版本核对；这里的示例不依赖其默认值 |
| LangGraph `create_react_agent` | 已标记弃用，迁移到 `langchain.agents.create_agent` |
| Pydantic AI Capability 提示 | 示例使用 `AbstractCapability[Any]`；请求级提示通过 `ctx.enqueue(SystemPromptPart(..., scope="request"))` 加入历史，生效范围限当前请求 |
| Pydantic AI 收尾边界 | 预留收尾请求不保证输出通过校验，后续修正仍受请求上限约束 |
| Spring AI 工具调用额度 | 由 `spring.ai.tools.limits.*` 控制（每用户回合单工具默认 40、总量默认 150）；与「最多跑几轮」不是一回事 |
