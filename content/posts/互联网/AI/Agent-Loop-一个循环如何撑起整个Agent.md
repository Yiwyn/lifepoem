+++
title = 'Agent Loop：一个循环，如何撑起整个 Agent'
date = 2026-11-15T17:20:00+08:00
categories = ["AI"]
tags = ["AI Agent", "Agent Loop", "ReAct", "Pydantic AI", "LangGraph"]
draft = false
+++

### 背景

> 今天的 Agent 框架长得都不一样：Pydantic AI 把它做成节点流，Spring AI 塞进 Advisor 链，LangGraph 画成一张有环的状态图。但把工具注册、Prompt 模板、对话界面一层层剥掉，最里面都是同一个东西——**请求模型，看响应，执行模型要的动作，把结果塞回去，再请求一次，直到该停为止**。
>
> 这个 `while` 简单到几乎不会被当成设计重点：通常只有十几行，藏在 SDK 内部，没人会去读它。但整个 Agent 的行为——跑不跑得起来、跑得对不对、能不能停下来——几乎都由它决定。
>
> 笔者写过几套 Agent Runtime，也翻过不少别人的实现，最后落在一个很朴素的判断上：**决定一个 Agent 能不能上生产的，往往不是模型选得多好，而是这个循环被设计成了什么样**。它该跑几轮、靠什么状态往下走、由什么条件叫停——这三件事没有答案，循环就只是一个转得挺热闹的 demo。
>
> 所以这篇只讲这一个循环：它到底在跑什么、一帧里发生了什么、状态究竟存在哪几层、终止条件为什么才是真正的开关、怎么让它在生产环境里停得下来。也会说清它**不是什么**——把 Agent Loop 讲成「反复请求模型、判断有没有 Tool Call」，是这类文章最容易犯的错。

---

### 讲哪一层：Loop / Runtime / Infrastructure

Agent 相关的东西常常混成一锅，因为它们确实都长在同一个代码库里。但它们的**归属**不一样，混着讲很容易让人以为「实现一个 Loop 就得顺手把整套基础设施也写一遍」。

| 层次 | 包含什么 | 一句判断标准 |
| :--- | :--- | :--- |
| **Agent Loop**（执行机制） | 请求模型、解析响应、校验决策、执行动作、更新状态、判断继续或终止 | 去掉它，循环跑不完，或者跑错 |
| **Agent Runtime**（配套能力） | 状态持久化、上下文治理、超时与重试、预算控制、权限校验、运行观测 | 去掉它，循环能跑，但上不了生产 |
| **Agent Infrastructure**（基建） | 幂等与事务、分布式调度、多副本一致性、多 Agent 协作 | 去掉它，单机小流量能跑，规模化才出事 |

这篇笔记的主线始终是第一层：**一个循环怎么转、靠什么继续、凭什么停**。第二章的上下文治理、第五章末尾的幂等与并行、第六章的框架对照，都属于「Loop 拉出来的配套」，出现时会标明它站在哪一层——**看得见边界，比把边界抹平更有用**。

---

### 一、这个循环到底在跑什么

#### 1.1 一次 LLM 调用不等于 Agent

很多人对 Agent 的第一印象是「模型 + 工具」。两者之间隔着的，正是这个循环。

| 对比 | 单次 LLM 调用 | Agent Loop |
| :--- | :--- | :--- |
| 模型调用次数 | 1 次 | 多轮，直到终止 |
| 谁推进下一步 | 调用方 | 模型提出决策，Runtime 执行并推进状态 |
| 外部信息 | 需调用方预先拼进 Prompt | 可在运行中按需获取 |
| 典型产物 | 一段文本 | 经过若干次工具交互后的结论 |

一句话定义：**Agent Loop 是让 LLM 从「一次性生成答案」变成「多轮自主执行任务」的执行控制机制**——根据当前运行状态发起模型请求，拿到决策后由 Runtime 校验并执行，把结果并入状态，再判断下一步是继续、等待还是结束。

注意定义里的三个关键词：**状态**、**决策**、**校验执行**。少了任何一个，都会退化成「一个调工具的 while 循环」。

#### 1.2 拆开看，只有五个零件

| 要素 | 职责 | 代码里的样子 |
| :--- | :--- | :--- |
| LLM | 决策者：决定直接回答、调用哪个工具、还是继续行动 | `llm.generate(messages)` |
| 消息上下文 `messages` | 承载用户输入、模型响应、工具调用与结果，是 Loop 最核心的交互状态 | `messages.append(...)` |
| 工具集 Tools | Runtime 可执行的外部动作：查库、读文件、调 API | `execute_tool(...)` |
| Observation | 工具执行结果，必须成对回灌给模型才能构成闭环 | `result` → `messages` |
| 控制策略 | 决定这一轮之后是「继续 / 等待 / 终止」，以及以哪种原因终止 | `continue` / `suspend(state)` / `finish(reason)` |

这里有一条贯穿全文的分工：**LLM 负责提出决策，Runtime 负责控制决策的执行、校验与状态推进**。

别把它理解成「模型动脑、Runtime 动手」。Runtime 不只是工具执行器，它还负责权限校验、拦截不该执行的调用、决定要不要重试、切换模型、控制预算、调度子 Agent、以及在必要时强制终止。模型提议转账，Runtime 完全可以拒绝。

第五个零件（控制策略）最容易被写窄。很多实现把它压缩成一个 `if`：有工具调用就继续，没有就返回——等于把「继续 / 等待 / 终止」三种判断塞进一个 `finished` 布尔值（1.3 末尾正好有这样一个写法）。2.3 会说明为什么它不够，4.3 会说明「等待」这一条是怎么被丢掉的。

#### 1.3 最小骨架

```python
while True:                    # 这里刻意没有上界，原因见下
    response = llm.generate(messages)

    if response.has_tool_call:
        result = execute_tool(response.tool_call)
        messages.append(result)
    else:
        return response.output  # 唯一出口：模型不再请求工具
```

这段代码只有一个出口，就是模型不再请求工具。**如果它每一轮都在请求，循环不会停**——这不是疏忽，是「剥掉终止条件」的直接后果，第五章补的就是这个上界。所以在真实系统里它只配当骨架，不能直接上生产。

剥掉这些之后，Loop 只剩三个动作：**请求模型 → 处理响应 → 更新上下文**。展开成一轮迭代是六步：

1. 把当前上下文交给 LLM；
2. 判断响应类型：最终答案、工具调用，还是要求继续；
3. 有 Tool Call 就由 Runtime 校验并执行（可能多个）；
4. 把执行结果追加进上下文；
5. **再次请求模型**，让它基于新信息决定下一步；
6. 判断是否结束，否则回到第 1 步。

除了上界，骨架还省掉了**「等待」**。真实 Runtime 里有一条出口不是「结束」，而是**挂起**——等人工审批、等外部事件、等异步任务回填。它不返回结果，也不继续循环，而是把状态存下来先退出。2.3 会把它作为独立的一种响应补上，5.3 给出完整实现。

**还有一步省得更隐蔽：工具调用消息要成对保存。**

上面这段代码为了好读，省略了一个真实协议里不能省的细节。**上下文里不只要保存工具的执行结果，还要保存模型发出的那条工具调用请求**，而且两者必须通过 `tool_call_id` 关联：

```text
User:      查询订单 A1001
Assistant: tool_calls=[{id: "call_1", name: "query_order", args: {...}}]
Tool:      tool_call_id: "call_1"  →  "已发货，预计明天送达"
Assistant: 订单已发货，目前不需要催单
```

如果只把一个裸的 `result` 塞进列表，模型下一轮可能无法把结果对应回它当初发的那个调用，尤其在并行调用多个工具时。所以准确的说法是：

> 模型的工具调用请求和 Runtime 返回的执行结果都属于上下文的一部分，结果必须与原始调用建立关联，不能简单追加一个普通字符串。

好消息是多数框架（Pydantic AI、Spring AI、LangGraph 的 `ToolNode`）已经替你完成这套组装，业务代码不必手写。但你要知道它们在做什么，出问题时才查得下去——「工具明明执行了，模型却说没看到结果」这类 bug，十有八九是这一步没接对。

最后排一个写法上的坑。不少教程为了让骨架「看起来有终止条件」，会写成 `finished = False` 加 `while not finished`，再在 else 分支里置 `True`：

```python
finished = False
while not finished:
    response = llm.generate(messages)

    if response.has_tool_call:
        result = execute_tool(response.tool_call)
        messages.append(result)
    else:
        finished = True
        return response.output   # 问题就在这两行
```

这里的 `finished` 是写后即弃的：唯一一次赋值发生在 `return` 的上一行，循环条件再也读不到它——死代码，只是看着像终止控制。把 `return` 挪到循环外能消掉这个 bug，但消不掉冗余：那时它只是给 `break` 换了个名字，初始 `False`、只在一个分支变 `True`，整段等价于 `while True`。

真正的害处是错觉。读者看到 `while not finished`，会默认循环已经有上界，于是不再追问「模型一直调工具怎么办」。1.2 说「把三种判断塞进一个布尔值」，说的就是这个形状——**终止不能由模型「不再调工具」来兜底，必须由循环外的东西兜底**：累计步数、截止时刻、连续重复的动作集合、累计 Token、单次上下文规模，也就是第五章那五层（L1 步数收尾、L2 时钟、L3 重复、L4 累计预算、L5 单次上下文）。

#### 1.4 一次完整迭代，上下文怎么滚

```text
[用户问题]
  → LLM 返回 Tool Call
[用户问题, Assistant(tool_calls), Tool(result)]
  → LLM 返回 Tool Call 或最终文本
[用户问题, Assistant(tool_calls), Tool(result), ..., 最终文本]
  → 返回给用户
```

两个动作缺一不可：**执行结果必须重新放回上下文，且必须再次请求模型**。这才构成闭环。只执行一次工具就结束，可以算一次很简单的 Agent 行为——模型做了选择，Runtime 执行了动作——但它没有形成多轮迭代的 Loop。这里关心的是后者。

#### 1.5 `messages` 是核心交互状态，但不是全部状态

很多讲解到这里会说「`messages` 就是 Agent 的唯一状态」。这句话在最简单的 Tool Calling Agent 里近似成立，但放到真实系统里会误导人。**上下文是交互状态，不是运行状态的全集。**

| 状态层 | 具体内容 | 存在哪 |
| :--- | :--- | :--- |
| 对话状态 | `messages`、工具调用与结果历史 | 上下文 / 会话存储 |
| 任务状态 | 当前计划、已完成项、待执行项、子任务 | 计划对象 / State |
| 执行状态 | 当前步骤、重试次数、每步结果、错误 | Runtime 变量 / 图状态 |
| 预算状态 | 累计 Token、成本、剩余请求次数 | Usage 对象 |
| 协作状态 | 子 Agent 状态、任务分配、审批结果 | 编排层 / 共享状态 |
| 运行状态 | 截止时刻、取消信号、run_id、trace | Runtime 上下文 |

前面提到的 Plan-and-Execute、Reflection、Multi-Agent，本身就已经证明了这一点：计划、评估结果、子任务状态都不是 `messages` 能自然承载的东西。它们要么放在图状态（LangGraph 的 `State`）、要么放在 Runtime 的结构化对象里。

一个实用的判断：**下一次模型请求需要看到的，放 `messages`；下一次 Runtime 决策需要的，放运行状态**。前者是模型的世界，后者是系统的世界。

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

比常见的三联图多出来的，正是最容易出问题的地方：**判定响应类型的出口不止两个**，以及**执行工具前的「校验」**（不是模型说要执行就执行）。

#### 2.2 两个角色，职责并不对称

| 角色 | 拿到什么 | 产出什么 | 不该做什么 |
| :--- | :--- | :--- | :--- |
| LLM | 当前完整上下文 | 一段文本，或一组工具调用请求 | 不自己碰数据库、发 HTTP；也不该由它决定预算、权限和最终是否放行 |
| Runtime | 模型的响应 | 校验结论、执行结果、状态更新 | 不替模型编造下一步计划；但可以拒绝执行、要求重试、强制终止 |

这张表有一个反直觉的地方：**Runtime 的权力比「执行器」大得多，但它的权力是「否决权」而不是「代笔权」**。它可以拦下一次越权调用、可以把失败包装成 Observation 让模型自己改、可以在预算耗尽时终止；但它不能替模型决定「接下来查哪个订单」。

这也是为什么「把工具结果 append 进上下文」这一行如此关键：**它是两个角色之间唯一的交接点**。少一次 append，模型下一次请求时看到的还是旧世界；少一次 `llm.generate`，结果就只是一堆躺在列表里的数据，没人据此做决策。

从状态机角度看：一帧做的事，就是读取运行状态（其中包含 `messages`）、生成一次决策、把决策的后果写回运行状态。所谓 Agent 的行为，就是这些状态转移在多轮里连起来的轨迹。

#### 2.3 响应不是两类，而是五类

绝大多数教程把响应分成两类：有工具调用、没有工具调用。这个简化在 demo 里够用，但它会在三个地方咬人。

**第一，它无法表达「模型还没做完，但也没要求调工具」。** 真实场景里这种响应并不罕见：

- 结构化输出要求必须调用 `final_answer` 工具，模型却回了一段普通文本；
- 响应被 `max_tokens` 截断，状态是 incomplete，框架需要再请求一次续写；
- 输出校验（schema 或 validator）失败，需要带着错误信息重试；
- 框架的结束策略判定「还有待处理的工具结果」，需要继续下一轮。

这些情况下，「没有 Tool Call」不等于「可以返回」。

**第二，它让「空转」变成一个无法描述的 bug。** 如果代码只有两个分支，那么任何不匹配的响应都只能落到 `else` 里被当成最终答案返回——包括那些本该重试的。反过来，如果框架偷偷把「非最终文本」都当成继续，就可能出现永远出不去的循环，而代码里根本找不到对应的分支。

**第三，它没有「等一等」这个选项。** 需要人工审批、需要外部回调、需要异步任务回填时，两类模型只能二选一：当成「没说完」继续请求模型（空转烧钱），或者当成「说完了」返回（丢掉半成品）。正确的动作是第三种——挂起。

所以更准确的模型是五种，加一个兜底：

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
    return finish("COMPLETED", decision.output)

if decision.kind == "TOOL_CALLS":
    validate_and_authorize(decision.tool_calls)        # 不是模型说要执行就执行
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

**先说清这五个名字的身份**：它们是这篇文章为了讲清 Runtime 控制流而定义的**抽象决策类型**，不是 OpenAI、Anthropic 或任何供应商的统一响应协议，也不是某个框架的 API 枚举。多数协议里模型只给得出「文本」和「工具调用」两种，剩下几种要靠 Runtime 结合输出校验、业务状态和外部事件自己判定。

其中两个尤其容易被误读：

- **`WAIT` 不是模型能产出的东西**，它是 Runtime 的控制状态。模型不会说「我要挂起」，是 Runtime 判断「缺一个当前拿不到的外部输入」，然后决定停在这里。把它当成一种「模型响应类型」去找对应的 API 字段，是找不到的。
- **`CONTINUE` 也不能由模型的一句话直接触发**。模型回一句「我还需要进一步分析」，本身不构成有效的继续事件——它必须伴随着实际的状态推进（新的工具调用、新的结构化计划、新的分页游标），否则就落进 `NO_PROGRESS`。**「允许继续」是一个需要被证明的许可，不是一句声明。**

**分类是 Runtime 的责任，不是模型的**——这句话决定了你会把它写成一个 `if`，还是写成一个状态机。

##### `RETRY` 和 `CONTINUE` 的边界

这两个最容易混，混了不是空转就是误重试。区别在**这一次响应对不对**，而不在**要不要继续**：

| | `RETRY` | `CONTINUE` |
| :--- | :--- | :--- |
| 判断的是 | 本次响应**不可用**（校验失败、截断、参数非法） | 本次响应**可用**，但任务没完 |
| 要不要重发同样的请求 | 要，但带上错误提示 | 不要，继续推进 |
| 计不计入重试上限 | 计 | 不计，但要计步数 |
| 典型信号 | schema 报错、`finish_reason=length`、工具参数非法 | 模型给出结构化的下一步、分页还有下一页 |

一句话：**`RETRY` 是「这句不算」，`CONTINUE` 是「这句算了，接着来」。** 所以只有 `CONTINUE` 需要证明状态推进；`RETRY` 需要的是次数上限，因为它本来就不推进状态。

##### `RETRY` 本身就分三种，别共用一个计数器

「重试」这个词在 Agent 里被用得太宽，实际上有三件完全不同的事：

| 来源 | 典型场景 | 谁处理 | 该记在哪 |
| :--- | :--- | :--- | :--- |
| 传输层重试 | 网络抖动、429 限流、5xx | 模型客户端（SDK 内置） | 记 `provider_attempts`（观测用），不进业务重试预算 |
| 响应不可用重试 | schema 校验失败、被 `max_tokens` 截断、工具参数非法 | Runtime | 记 `retry_count`，挂 `MAX_RETRIES` |
| 工具失败后的模型修正 | 工具返回业务错误，模型换个参数再试 | 模型自己决定，Runtime 只执行 | 不算重试，是一次新的 `TOOL_CALLS` |

混在一起的后果很具体：把 SDK 的网络重试也算进 `retry_count`，一次网络抖动就把业务的重试预算吃掉两次；反过来，把模型「换个参数再来」当成重试来限流，会让它连正常纠错的机会都没有。**只有中间那一行才属于「这一帧不算数」，也才该被 `RETRY` 分支处理。**

#### 2.4 上下文不是越长越好

1.4 讲的滚动方式是「一路 append」。示例里这样最清楚，放到长任务里会出事：跑三十轮，每轮的工具结果都留着，上下文很快顶到窗口上限；更糟的是真正有用的信息被埋在中间，模型开始抓不住重点。

真实 Runtime 不会把「完整历史」直接当成「本次请求的输入」。它至少要做四件事：

| 手段 | 省下什么 | 代价 / 风险 |
| :--- | :--- | :--- |
| 只保留最近的工具结果 | 省掉陈旧的 Observation | 留最近 N 条时必须保证 `tool_call_id` 成对，不能孤零零留一个结果 |
| 把早期对话压成摘要 | 省掉大量原始文本 | 摘要有损：订单号、金额、错误码这类关键值必须原样保留 |
| 计划、进度、结论存成结构化状态 | 省掉重复叙述 | 要多维护一份状态，见 1.5 那张表 |
| 原始记录归档、按需检索 | 让「完整历史」不进每次请求 | 检索得能命中，否则等于丢了 |

一句话：**运行状态可以比每次发给模型的消息更完整；模型的输入也不等于完整历史。**

但压缩不能乱来，两个坑要提前防：**摘要丢证据**——被压掉的原始响应在排障时往往正是关键，所以归档要留、`run_id` 要能串起来；**裁剪破坏协议**——切消息时如果切掉了 `Assistant(tool_calls)` 只留下 `Tool` 结果，下一轮请求会直接报错。

> **本节小结**：一帧的核心是「读取状态 → 请求模型 → 解释响应 → 执行动作或处理控制事件 → 更新状态」。Tool Call 与 Tool Result 必须正确关联，状态管理也不该被简化成无限 append。

---

### 三、容易混淆的边界：ReAct 不是 Loop，Tool Call 也不是

#### 3.1 四个层次，别放在一起比

ReAct（Reasoning and Acting）让模型交替推理和行动：Thought → Action → Observation → 再次 Thought → Final Answer。它常被直接当成「Agent Loop 的实现」，其实两者处在不同的层。

> 图中的 Thought 是论文对推理阶段的概念化表示，**不意味着 Runtime 一定能读到模型的内部推理**。现代模型的思维链未必以独立字段暴露，有的还会被隐藏或摘要。Runtime 能可靠观察到的通常只有三样：模型响应、工具调用请求、工具执行结果——这也是为什么整个循环的设计都围绕这三样，而不是围绕「怎么拿到 Thought」。

| 层次 | 概念 | 解决的问题 |
| :--- | :--- | :--- |
| 交互范式 | ReAct | 一步之内如何交替思考、行动和观察 |
| 执行机制 | Agent Loop | 如何持续推进、更新状态、并决定何时停 |
| 动作接口 | Tool Calling | 模型如何表达「我要调这个工具」 |
| 工程框架 | Pydantic AI / Spring AI / LangGraph | 如何组织模型、工具、状态与控制流 |

**ReAct 是可以在 Loop 里实现的一种交互范式，Loop 是承载它的执行机制。** 而且 Loop 不一定采用 ReAct。

```python
from pydantic_ai import Agent

agent = Agent("openai:your-model", instructions="你是一个订单分析助手")

@agent.tool_plain
def query_order(order_id: str) -> str:
    return f"订单 {order_id} 已发货"

result = agent.run_sync("帮我查询订单 A1001 的状态")
print(result.output)
```

`agent.run_sync()` 内部就是那套循环：请求 LLM → 判定响应 → 有 Tool Call 则执行、回灌、再请求；没有则产出 `End`。想看清节点怎么衔接，用 `agent.iter()` 观察（见 6.1）。

表里那行「动作接口」值得单独拎出来说，因为它是被混得最厉害的一个——**有工具调用，完全可以没有循环**。下一节就拆这个。

#### 3.2 Tool Calling 不是 Loop

Tool Calling 只解决一件事：模型怎么把「我要调这个工具」这个意图表达出来。它不负责定义任务怎么推进、什么时候算完。

最直接的证据是：**有工具调用，可以完全没有循环。**

```text
用户提问 → 模型给出 Tool Call → Runtime 执行 → 结果直接交给业务层
```

一次就结束，没有第二轮。这种用法很常见——让模型把自然语言转成一次 API 调用参数，剩下的交给业务代码。它是一条直线，不是循环；这个系统可以称为一个极简的 Agent，但它没有 Loop。

还有一种更隐蔽的情况：Spring AI 的 `@Tool(returnDirect = true)` 会让工具结果**直接返回调用方，不再回灌模型**。这也是工具调用流程的一条显式出口。它恰好说明「工具执行完必须再问模型一次」不是协议强制，而是 Runtime 的设计选择——而这个选择，正是 1.4 里「闭环」与「一次调用」的分界线。

所以两者的关系是：**Tool Calling 提供一个动作事件，Agent Loop 决定这个事件之后要不要再来一轮。** 前者是接口，后者是控制流。

顺带把另一个常见混淆也拆掉：

| 架构 | 有没有循环 | 循环条件 |
| :--- | :--- | :--- |
| 固定工作流（DAG） | 通常没有，节点只走一遍 | 不适用 |
| Plan-and-Execute | 有，在执行层 | 计划中还有未完成任务 |
| Reflection | 有，在生成—评估层 | 评估未通过 |

固定工作流可以被同一个编排 Runtime 调度，但它本身不是 Agent Loop——它没有「回头再跑一次」这件事。**「同一个 Runtime 能实现」不等于「它们是同一个循环」**，这个区分在第六节看 LangGraph 时会再次出现。

三个最常见的误区：

| 误区 | 正确理解 |
| :--- | :--- |
| 把 Agent Loop 等同于 Tool Calling | Tool Call 只是触发下一轮的一类事件，Loop 是执行控制机制 |
| 把 ReAct 和 Agent Loop 当成两个要分别实现的模块 | 先让 Loop 跑起来，再理解 ReAct 怎么利用它做自主决策 |
| 换个 Agent 架构就得重写一个 Loop | 运行原语可以复用，但复杂架构往往是多个嵌套循环加外层编排 |

#### 3.3 四种「模式」不在同一个分类维度

把 ReAct、Plan-and-Execute、Reflection、Multi-Agent 放进一张表然后说「只是继续条件不同」，是一种很诱人但过度抽象的讲法。它们回答的根本不是同一个问题。

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

这里不是「一个 Loop 换了几行条件」，而是**多个 Agent 各自的 Loop，加一层负责任务分配和收敛判断的外层编排**。

所以更准确的说法是：

> 不同 Agent 架构可以复用底层的运行原语——请求模型、校验决策、执行动作、更新状态——但它们的整体控制流未必是同一个 Loop。复杂系统通常是多个嵌套循环，外面再套一层状态机或工作流编排。

这句话看起来只是措辞更谨慎，但它决定了你设计系统时会不会在一个 `while` 里硬塞五种职责。

> **本节小结**：Loop 只有一个运行原语，但可以有多个实例、多层嵌套。ReAct 是范式，Planning 是架构，Reflection 是机制，Multi-Agent 是协作——它们不是同一层的四个选项。

---

### 四、终止条件：这个循环真正的开关

#### 4.1 「没有 Tool Call 就结束」是默认约定，不是定义

这个约定之所以好用，是因为在典型 Tool Calling Agent 里，**工具调用是模型要求 Runtime 执行外部动作的信号**：模型还没给最终答案，先把活派出来；Runtime 办完把结果送回去，模型再决定下一步。

一次完整交互：模型先返回 `{"tool_calls":[{"name":"query_order","arguments":{"order_id":"A1001"}}]}`；Runtime 拿到「已发货，预计明天送达」；结果回灌，模型第二次返回纯文本「订单已发货，目前不需要催单」——没有工具调用，循环结束。

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

这是一段能跑、也符合协议的写法——注意它没有退回「只 append 一个裸结果」的老写法，工具调用请求和结果是一起进去的。

但它悄悄做了一件事：**把「响应里没有 tool_calls」直接等同于「模型说完了」**。这个等价关系成立，需要两个前提：

1. 模型只可能产出「调工具」和「说完了」两种响应；
2. 任何纯文本都是完整的最终答案。

前提 1 在 2.3 已经不成立——结构化输出、截断、校验失败都会产生第三种情况。前提 2 也靠不住：一段被 `max_tokens` 砍断的文本，看起来是纯文本，其实不是答案。

所以那句常被引用的话要补一个限定：**Loop 的本质不是判断有没有工具调用，而是判断是否达到终止条件；「无 Tool Call」只是最常见的一种默认判定。**

#### 4.2 不同架构，继续条件长在不同地方

| 架构 | 循环继续条件 | 循环在哪一层 | 还额外需要什么状态 |
| :--- | :--- | :--- | :--- |
| ReAct | 模型要求继续行动，通常表现为 Tool Call | 单个 Agent 内 | 基本只要上下文 |
| Plan-and-Execute | 计划中还有未完成任务 | 执行层（外层还有规划） | 计划、已完成项、待执行项 |
| Reflection | 评估结果未达标 | 生成—评估内循环 | 评估结果、轮次上限 |
| Multi-Agent | 协作任务尚未完成 | 每个 Agent 各有内循环 | 任务分配、子 Agent 状态、审批 |

注意最后一列：**继续条件越复杂，需要的状态就越多**。这正是 1.5 那张表的由来——`messages` 撑不起计划、评估和协作。

这张表只比较两件事：循环发生在哪一层、靠什么继续。它不表示这四者处在同一个分类维度上——那正是 3.3 说的问题。

```python
# Reflection：条件不是 Tool Call，而是评估是否通过
while not evaluation.passed and attempt < MAX_ATTEMPTS:
    result = generate()
    evaluation = evaluate(result)
    attempt += 1
return result
```

顺带说一句：Reflection 的评估**必须引入客观证据**——编译通过、测试结果、静态扫描、schema 校验——只让模型自评「我觉得更好了」，通常只是把错误换了个说法。

#### 4.3 终止的三种来源

把终止条件拆开看，其实只有三类来源，它们对应完全不同的处理方式：

| 来源 | 典型场景 | Runtime 该做什么 |
| :--- | :--- | :--- |
| 正常完成 | 得到最终答案、评估通过 | 返回结果，记录 usage |
| 主动等待 | 需要人工审批、需要外部事件 | 挂起并持久化状态，等事件回来再续跑 |
| 强制终止 | 超步数、超时、重复动作、超预算 | 返回结构化终止原因 + 已有部分结果 |

对照 2.3 的五种响应就清楚了：`FINAL` 落在第一类，`WAIT` 是第二类，其余几种最终都指向第三类。

中间那一类最容易被忽略：**Agent Loop 不一定是「跑到底」的，它需要能被安全地暂停和恢复**。这一点在 LangGraph 里体现得最明显（checkpointer + interrupt），在自研 Runtime 里则常常被忘掉，最后变成「审批等了三小时，进程重启，全部重来」。

「暂停」和「结束」在实现上差得很远，值得单独列一遍：

| | 结束（`FINAL` / 强制终止） | 挂起（`WAIT`） |
| :--- | :--- | :--- |
| 任务状态 | 终态，不再继续 | 中间态，等着被唤醒 |
| 进程 | 可以退出 | 必须能退出，靠持久化恢复 |
| 返回什么 | 结果或终止原因 | 断点标识（`run_id`）+ 待办 |
| 谁唤醒 | 不会再有人 | 审批回调、事件、定时任务 |
| 最常见的错法 | 用 `raise` 代替返回 | 当成「继续」在当前线程里空转 |

> **本节小结**：写循环之前先问「什么情况下必须停」，再问「怎么知道该停了」。前一个问题属于设计，后一个问题属于工程——下一节就是它的答案。

---

### 五、当循环停不下来：分层防死循环

#### 5.1 为什么一层不够

Agent Loop 最常见的生产事故是**死循环**：LLM 反复调用同一个工具，或不断产出新内容却永远不给最终答案。防御必须是多层级的，因为每种「停不下来」的原因根本不同。

| 死循环形态 | 表现 | 只靠步数限制能否兜住 |
| :--- | :--- | :--- |
| 重复动作型 | 相同工具 + 相同参数被反复调用 | 能挡，但要空转到第 N 步，白白烧预算 |
| 空转推理型 | 每步都有输出，既不调工具也不给最终答案 | 只能靠步数或时间兜底 |
| 卡死型 | 某一步工具调用超时或阻塞，循环停在原地 | 步数不增长，步数限制完全失效 |
| 膨胀型 | 动作各不相同但上下文持续膨胀，逼近窗口上限 | 步数未必触发，需要预算限制 |

第二行值得单独解释一句，因为它和「没有 Tool Call 就结束」看起来矛盾。**在只有两个分支的实现里，这种形态确实不会发生**——没有 Tool Call 就直接返回了。它成立的前提是框架允许「继续」这条路（2.3 的 `CONTINUE` / `RETRY`）：结构化输出要求必须调 `final_answer` 工具、响应被截断需要续写、输出校验失败需要重试。这些情况下，模型会一轮轮产出「不是答案的文本」，而循环一轮轮继续。

所以更准确的说法是：**空转不是模型的行为，是「允许继续」这条路径没有被约束的后果**。如果框架不允许继续，就不需要防它；一旦允许，就必须有闸门。

**单一策略无法覆盖所有场景**，这不是防御写得够不够严谨，是维度不够。

#### 5.2 五层机制

| 防御层 | 策略 | 实现方式 | 触发场景 | 行为 |
| :--- | :--- | :--- | :--- | :--- |
| L1 步数 + 收尾 | 正常推进上限，另留收尾请求 | `transition_count` 达上限后进入收尾阶段：摘掉普通工具、只允许输出 | 反复推理不收敛 | 收尾成功则返回结果；仍不收敛返回「请求预算用尽」 |
| L2 时间限制 | 全局截止时刻 | 换算成 `deadline`，入口检查，并传给每次请求与每次工具 | 某一步工具调用卡死 | 返回「执行超时，任务未完成」 |
| L3 重复检测 | 按**轮**的动作集合去重 | 连续 N 轮的动作**集合**完全相同才终止 | 死循环重复同一批操作 | 返回「连续多轮动作完全相同」 |
| L4 累计预算 | Token / 成本上限 | 整个 Run 累计消耗超预算则终止 | 多轮累积导致成本失控 | 返回「Token 预算耗尽」 |
| L5 单次上下文 | 上下文窗口上限 | **请求之前**估算输入 + 预留输出，超了先压缩 | 上下文逼近窗口上限 | 返回「压缩后仍超出上下文预算」 |

**L4 和 L5 必须分开，这是最常被合并错的一对。** 它们限制的根本不是同一个东西：

| 限制 | 含义 | 解决的问题 | 超限的典型信号 |
| :--- | :--- | :--- | :--- |
| L4 累计 Token / 成本 | 整个 Run 消耗的总量 | 成本和资源失控 | 跑了 10 轮，累计 10 万 Token |
| L5 单次上下文 | 这一次请求发过去的输入规模 | 单次 Prompt 超过窗口，或性能退化 | 每轮上下文都是 10 万 Token |

举个具体的例子：一个 Agent 连续跑 10 轮，每轮输入 1 万 Token。累计消耗到了 10 万，触发的应该是 L4；但每一轮其实只有 1 万，窗口完全装得下。反过来，一个 Agent 只跑 2 轮，但每轮塞了 30 万 Token，L4 可能还没超，L5 早就该拦了。

这两层的工程含义也不同：L4 是**事后统计**（响应回来才知道用了多少），L5 是**事前预防**（如果能在请求前估算 `count_tokens(messages)`，就不必为一次注定超窗的请求付钱）。框架通常把两者做成不同参数，比如 Pydantic AI 的 `total_tokens_limit` 与 `per_request_input_tokens_limit`（见 6.1）。

五层是**并列检查**，不是依次降级。但它们的动作不完全一样，这一点得说清楚：

| 层 | 触发后做什么 | 真正的终止由谁完成 |
| :--- | :--- | :--- |
| L1 | **不终止**，切换到收尾阶段（摘工具、提示收尾） | 收尾失败后由 `MAX_MODEL_REQUESTS` 兜底 |
| L2 / L3 / L4 / L5 | 直接终止 | 自身 |

L1 是唯一「先降级、后终止」的一层，因为它的目标不是「立刻停下」，而是「让已经做的工作有个交代」——原因见下一小节。

检查位置同样关键：**L1/L2/L4 在每轮迭代入口**，**L5 在请求发出之前**，**L3 在拿到本轮工具调用之后、执行之前**。位置放错，闸门就是事后追认——这一点在 5.3 的代码里逐行对应。

##### L1 为什么必须带一个收尾预算

只设一个「最大步数」，会踩到一个很具体的坑：

```text
第 5 步：模型请求工具 → 工具执行成功 → 数据全都拿到了
第 6 步入口：已用步数 >= 最大步数 → 直接终止
结果：用户拿到「任务未完成」，而那批数据一次都没被总结
```

问题不在闸门本身，而在**「执行预算」和「收尾预算」被合成了一个数**。模型刚把活干完，恰恰是最需要一次请求把结果写成答案的时候，预算却已经用完了。

所以 L1 要拆成两个参数：

| 参数 | 含义 | 作用 |
| :--- | :--- | :--- |
| `MAX_TRANSITIONS` | 允许的**正常推进**次数 | 真正约束「循环转了几圈」 |
| `FINALIZE_RESERVE` | 额外预留的**收尾请求**数，通常为 1 | 保证干完活之后还有一次机会把结果说出来 |
| `MAX_MODEL_REQUESTS` | 上面两者之和 | 总请求上限，兜住「收尾也收不干净」的情况 |

进入收尾阶段后做两件事：**把普通工具摘掉**，让模型除了输出没有别的选择；**把剩余次数告诉它**，让它知道该给结论了。这套做法和 Pydantic AI 官方那个 `WrapUpNearRequestLimit` capability 是同一个思路（见 6.1），区别只是它要自己写，而你可以直接做进循环里。

有一个边界要提前认清：**收尾预算不等于收尾一定成功**。如果最后一次输出仍然校验失败，或者模型死活不肯收尾，最终还是会撞到 `MAX_MODEL_REQUESTS`——这时返回的就该是「任务未完成 + 已有进展」，而不是假装成功。

#### 5.3 整合进一次循环

下面是示意伪代码。`fingerprint_of` / `normalize` / `update_state` / `build_request` / `estimate_tokens` / `compact_context` 按项目自行实现；`finish()` 与 `suspended()` 共用同一个结果类型，只是 `status` 不同（见 5.7）。

有两个贯穿全段的设计决定，先说在前面：**所有状态只有一个来源 `state`**（不再有「一份 `messages` 变量 + 一份 `state`」）；**所有闸门都在动作发生之前检查**，而不是在结果回来之后追认。

```python
from collections import deque
from time import monotonic

# ── 预算：正常推进与收尾分开算 ──
MAX_TRANSITIONS = 8        # 正常执行最多推进 8 次
FINALIZE_RESERVE = 1       # 再多留 1 次请求，专门让模型收尾
MAX_MODEL_REQUESTS = MAX_TRANSITIONS + FINALIZE_RESERVE
MAX_RETRIES = 3
MAX_WALL_TIME, STEP_TIMEOUT, REQUEST_TIMEOUT = 120, 30, 60
REPEAT_ROUNDS, REPEAT_WINDOW = 3, 10

MAX_TOTAL_TOKENS = 200_000       # L4：整个 Run 的累计预算
MAX_CONTEXT_TOKENS = 100_000     # L5：单次请求的输入上限
RESERVED_OUTPUT_TOKENS = 4_000   # 给输出留的空间，估算时要加上

deadline = monotonic() + MAX_WALL_TIME
state = RunState(run_id=run_id, messages=[], usage=RunUsage(), completed=[])
recent_rounds = deque(maxlen=REPEAT_WINDOW)   # 每轮放一个「动作集合」，不是一个调用
retry_count = 0        # 只数「本次响应不可用」
request_count = 0      # Runtime 发起的模型请求
transition_count = 0   # 有效状态推进（L1 用这个）

def finalizing() -> bool:
    return transition_count >= MAX_TRANSITIONS

while True:
    # ── 入口闸门：L1 / L2 / L4 ──
    if request_count >= MAX_MODEL_REQUESTS:
        return finish("REQUEST_BUDGET", "请求预算用尽，任务未完成", state)
    if monotonic() >= deadline:
        return finish("TIMEOUT", "执行超时，任务未完成", state)
    if state.usage.total_tokens >= MAX_TOTAL_TOKENS:
        return finish("TOKEN_BUDGET", "Token 预算耗尽", state)

    # ── L5：在请求之前拦，不是响应回来之后追认 ──
    request = build_request(state, finalize=finalizing())   # 收尾时自动摘掉普通工具
    if estimate_tokens(request) + RESERVED_OUTPUT_TOKENS > MAX_CONTEXT_TOKENS:
        request = compact_context(request)                  # 摘要 / 裁剪，见 2.4
        if estimate_tokens(request) + RESERVED_OUTPUT_TOKENS > MAX_CONTEXT_TOKENS:
            return finish("CONTEXT_TOO_LARGE", "压缩后仍超出上下文预算", state)

    # ── 请求模型：单次超时，且不越过全局 deadline ──
    request_count += 1
    response = llm.generate(request, timeout=min(REQUEST_TIMEOUT, deadline - monotonic()))
    state.usage += response.usage    # 输入 + 输出一起累计，不只记工具那次

    decision = classify_response(response)

    if decision.kind == "FINAL":
        return finish("COMPLETED", decision.output, state)

    if decision.kind == "TOOL_CALLS":
        # 收尾阶段还想要工具：回灌提示，把它的路收窄到「只能输出」
        if finalizing():
            state.messages.append(assistant_tool_call_message(decision))
            state.messages.extend(rejected_tool_results(decision, "已进入收尾阶段，请直接给出结论"))
            continue                 # 不增 transition_count，由 MAX_MODEL_REQUESTS 兜底

        # L3：按「轮」判重 —— 同一批里的三个相同调用是并行，不是死循环
        batch = frozenset(
            fingerprint_of(call.name, normalize(call.arguments))
            for call in decision.tool_calls
        )
        recent_rounds.append(batch)
        if (len(recent_rounds) >= REPEAT_ROUNDS
                and len(set(list(recent_rounds)[-REPEAT_ROUNDS:])) == 1):
            return finish("REPEATED_ACTION", "连续多轮动作完全相同，请检查逻辑", state)

        # 协议要求：调用请求与结果成对回灌
        state.messages.append(assistant_tool_call_message(decision))

        remaining = deadline - monotonic()
        if remaining <= 0:
            return finish("TIMEOUT", "执行超时，任务未完成", state)
        results = execute_tools(
            decision.tool_calls,
            timeout=min(STEP_TIMEOUT, remaining),      # 工具也受全局 deadline 约束
            idempotency_key=lambda call: fingerprint_of(
                run_id, call.name, normalize(call.arguments)
            ),
        )
        state.messages.extend(results)
        state.completed.extend(describe(c) for c in decision.tool_calls)
        transition_count += 1
        continue

    if decision.kind == "WAIT":
        persist(run_id, state)       # 落盘的就是刚刚更新过的 state，不存在「两份状态」
        return suspended(decision.reason, run_id, state)

    if decision.kind == "RETRY":
        if retry_count >= MAX_RETRIES:
            return finish("RETRY_EXHAUSTED", decision.reason, state)
        retry_count += 1
        state.messages.append(retry_hint(decision.reason))   # 告诉模型错在哪
        continue

    if decision.kind == "CONTINUE":
        # 允许继续，但必须证明状态有推进，否则就是空转
        if not update_state(state, decision):
            return finish("NO_PROGRESS", "响应未推进任何状态", state)
        transition_count += 1
        continue

    # 未知响应：显式失败，不要默默回到循环入口
    return finish("UNEXPECTED_RESPONSE", f"无法处理的响应类型：{decision.kind}", state)
```

这份代码里有十处不那么直观，每一处都对应一个具体的坑——其中前四处是**控制流本身的漏洞**，不是风格问题：

| 这一版的做法 | 修掉的坑 |
| :--- | :--- |
| L3 用「每轮一个 `frozenset`」判重 | 按单个调用判重时，模型一次并行发三个相同的 `query_order(A1001)` 会被误判成死循环，其实那是同一批合法请求 |
| L1 用 `MAX_MODEL_REQUESTS = 正常轮数 + 收尾预留` | 只设一个最大步数，会在「工具刚执行完、数据刚拿到」的下一轮入口掐断，结果永远没机会被总结 |
| L5 在 `llm.generate` **之前**估算并压缩 | 响应回来才检查，那次超窗请求已经发出、已经计费，甚至已经报错 |
| 工具 `timeout=min(STEP_TIMEOUT, remaining)` | 全局只剩 1 秒、单工具 30 秒时，工具仍会跑满 30 秒，deadline 形同虚设 |
| 只有一份 `state`，`messages` 挂在里面 | 两份状态并存时，`messages` 更新了而 `state` 没更新，`persist` 存下的是旧快照，恢复后丢掉最后一轮 |
| `transition_count` 而不是 `step` | 名字叫「最大步数」却不统计所有轮次，读代码的人会以为它管住了全部循环 |
| 收尾阶段收到 `TOOL_CALLS` 只回灌提示、不执行 | 直接执行会真的跑出去；直接终止又太粗暴，回灌提示能让模型自己转成输出 |
| `RETRY` 不增 `transition_count`，只增 `retry_count` | 一是让重试吃掉正常预算，二是让空转伪装成重试 |
| `usage` 每次响应都累加 | 只在工具执行后统计，最终答案、输入 Token、重试开销全漏 |
| 未识别响应走 `finish("UNEXPECTED_RESPONSE")` | 没有 else 分支时，会带着没更新的上下文回到入口，形成真空转 |

还有两点是代码表达不出来的，但落地时必须知道：

- **`estimate_tokens` 是估算，不等于供应商的计费口径。** 不同模型的分词器不同，多模态输入、工具 schema 也会占 token。所以 `RESERVED_OUTPUT_TOKENS` 要留够余量，估算值只能当「提前预警」，不能当「精确账单」——真实用量仍以响应里的 `usage` 为准。
- **`timeout` 参数只能结束「等待」，不一定能结束「执行」。** 同步工具跑在工作线程里，超时之后那个线程可能还在跑，甚至稍后把副作用落了盘。真正要中断，得靠支持取消的执行器；否则就要靠幂等键兜（见 5.8）。

#### 5.4 五个计数器，两类用途

很多实现只有一个 `iteration` 计数器，能跑通 demo，但一上量就同时出现漏判和误伤。问题在于它把「数什么」和「给谁看」混成了一件事。

**控制用的三个**——它们会触发终止，口径必须精确：

| 计数器 | 数什么 | 挂哪个上限 | 数错的后果 |
| :--- | :--- | :--- | :--- |
| `transition_count` | 有效状态推进：工具执行完、`CONTINUE` 确有推进 | `MAX_TRANSITIONS` | 用工具调用数代替，纯文本空转永远不触发 |
| `request_count` | **Runtime 发起**的模型请求次数 | `MAX_MODEL_REQUESTS`（正常轮数 + 收尾预留） | 用它替代 `transition_count`，重试会吃掉正常预算 |
| `retry_count` | 「本次响应不可用」的重试（见 2.3 的三种重试） | `MAX_RETRIES` | 把传输层重试也算进来，一次网络抖动吃掉两次业务预算 |

**观测用的两个**——它们不该直接当闸门，但决定了你的阈值调得对不对：

| 指标 | 数什么 | 为什么不能拿来当闸门 |
| :--- | :--- | :--- |
| `tool_call_count` | 模型提出的工具调用数量（一次响应可并发多个） | 与 `transition_count` 不是 1:1；串行三个工具算 1 还是 3 取决于实现 |
| `provider_attempts` | 供应商侧实际尝试次数，含 HTTP 重试与 fallback | **只有模型客户端知道**；外层计数器数不到，硬数就会把网络问题算成业务轮数 |

这里最容易错的是最后一行。`llm.generate()` 内部可能已经重试了三次，但外层 `request_count += 1` 只加了一次——这不是 bug，而是两个不同层级的指标。想要 `provider_attempts`，得从模型客户端或网关的观测数据里取，不能指望循环自己数出来。

一句话原则：**L1 数「循环转了几圈」，不要数「调了几次模型」或「跑了几次工具」；而「供应商试了几次」只能由客户端上报，不能靠外层猜。**

还有一个容易被忽略的用法：**这几个指标的比值本身就是诊断信号。**

| 比值 | 持续偏高说明什么 | 该调哪里 |
| :--- | :--- | :--- |
| `request_count / transition_count` | 重试或空转在变多，正常推进效率低 | 查 `RETRY` 来源，或收紧 `NO_PROGRESS` 判定 |
| `tool_call_count / transition_count` | 并行度高，一轮里塞了很多调用 | L3 的按轮判重更安全；并发执行策略要检查（见 5.8） |
| `provider_attempts / request_count` | 网络或供应商侧不稳 | 这不是业务问题，别去调 `MAX_TRANSITIONS` |

没有这套比值，你只能看到「任务被拦下了」，看不到「为什么被拦下」——而后者才是调阈值的依据。

#### 5.5 时间限制的真实边界

把 `if monotonic() - start > MAX_WALL_TIME` 叫作「全局超时」，容易让人以为它能兜住一切卡死。它不能。

这个判断只在**控制权回到循环入口**时才会执行。如果 `llm.generate()` 本身阻塞了十分钟，或者某个工具调用永远不返回，代码根本走不到那行 `if`——循环入口的检查再严密也没用。

真正要配的是三层，缺一不可：

| 层级 | 管什么 | 怎么实现 |
| :--- | :--- | :--- |
| 全局 Deadline | 整个 Run 的总时长 | 开始时算出 `deadline`，每轮入口检查，并作为下面两层的时间上界 |
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

只写 `timeout=STEP_TIMEOUT` 会发生什么：全局只剩 1 秒，单工具上限 30 秒，那个工具照样跑满 30 秒——**入口检查得再勤，也拦不住已经冲出去的那一步**。三层超时如果不同源，最短的那一层才是真实上限，其他的只是文档。

Pydantic AI 的 `timeout=` 就是这个思路：run 级 deadline 会传给子 Agent，子 Agent 自己的 `timeout=` 只能把它缩短、不能延长。

还有一点常被忽略：**超时之后，任务未必该被判为失败**。一次工具调用超时，可能只是响应慢，也可能工具已经执行成功了（见 5.8 第三小节）。前者可以重试，后者重试就是灾难。

#### 5.6 停下来之后交回什么

> 这一节已经跨到 **Runtime 层**。Loop 只负责判断「该停了」，而「停下来交回什么」是 Runtime 的接口约定——它不影响循环能不能跑对，但决定了循环跑完之后还有没有价值。

前面五层都在讲「怎么停」，这里讲最后一环。这件事如果一开始没设计，最后一定长这样：超时了 `raise TimeoutError`，步数超了 `return None`，上层 catch 一下记条日志——用户等了五轮，拿到一句「出错了」。

建议应用层统一一个 Run 结果结构，**正常完成、被拦下、挂起都走它**：

```json
{
  "status": "interrupted",
  "termination_reason": "REQUEST_BUDGET",
  "output": null,
  "run_id": "run_01HX...",
  "completed": ["query_order(A1001)", "query_logistics(A1001)"],
  "pending": ["notify_customer"],
  "messages_ref": "s3://.../run_01HX/messages.jsonl",
  "usage": {
    "model_requests": 5,
    "tool_calls": 2,
    "total_tokens": 8400,
    "cost_usd": 0.03
  }
}
```

`status` 建议只留这几个值，多了就没法做告警分级：

| `status` | 含义 | 典型 `termination_reason` |
| :--- | :--- | :--- |
| `completed` | 正常完成 | `COMPLETED` |
| `interrupted` | 被闸门拦下，任务没做完 | `REQUEST_BUDGET` / `TOKEN_BUDGET` / `CONTEXT_TOO_LARGE` / `REPEATED_ACTION` / `NO_PROGRESS` |
| `suspended` | 主动等待，可恢复 | `WAITING_APPROVAL` / `WAITING_EVENT` |
| `timed_out` | 超过截止时间 | `TIMEOUT` |
| `failed` | 不可恢复错误 | `UNEXPECTED_RESPONSE` / `RETRY_EXHAUSTED` |
| `cancelled` | 用户或上游主动取消 | `CANCELLED` |

三个细节值得单独说：

- **`completed` 和 `interrupted` 必须分得开。** 监控上这是两个完全不同的指标：前者是成功率，后者是防护触发率。混在一起，你永远不知道闸门是不是设得太紧——把正常完成算进「被拦下」，会让人误以为限流过严；反过来，被拦下也算成功，防护就形同虚设。
- **失败要带得回进展。** `completed` / `pending` 两个字段看着朴素，却是「半成品有没有价值」的关键：用户拿到「已查到订单和物流，还没来得及通知客户」，比拿到「任务失败」有用得多。
- **`suspended` 必须带 `run_id` 和断点。** 没有它，「等审批」就等于「从头再来」——这正是 4.3 说的那类事故。

还有一层分寸要拿捏：**「所有强制终止都返回结构化结果」是应用层规范，不能要求框架内部也这样。** Pydantic AI 用异常 `UsageLimitExceeded`，LangGraph 用 `GraphRecursionError`，这是它们的接口约定。你的 Runtime 该做的是在自己的边界上把这两类异常翻译成统一结果，而不是要求框架改行为。

#### 5.7 落地要点与常见误伤

| 要点 | 说明 |
| :--- | :--- |
| 动作指纹要归一化 | 参数字典排序、去掉时间戳 / request_id 等易变字段后再 hash，否则同一动作会被判成不同动作，L3 形同虚设 |
| 窗口要有界 | 用 `deque(maxlen=N)`；用无限 list 再取尾部，内存会随轮次线性增长，长任务里就是泄漏 |
| 按轮判重，不按调用判重 | 同一批并行发出的相同调用是合法的；判重单位应该是「这一轮的动作集合」，见 5.3 |
| 区分「连续」与「累计」 | 连续 N 轮较严格；分页查询等合法重复调用要留白名单或放宽阈值，避免误杀 |
| L3 挡不住交替循环 | A → B → A → B 不会命中「连续相同」，需要窗口内周期检测，或靠 L1 / L4 兜底 |
| 预算要预留 | 在接近窗口上限前终止，给终止说明和结果摘要留够 Token |
| 留出收尾预算 | 只设一个最大步数，会在「工具刚执行完」的下一轮入口掐断；要用 `MAX_TRANSITIONS + FINALIZE_RESERVE` 两段预算，见 5.2 |
| 可观测 | 记录每层触发次数、步数、耗时、Token 曲线，用来反推阈值是否合理 |

写进预算还不够，还得**让模型知道时间快到了**。同样剩一次请求，一种做法是直接掐断，用户拿到「任务未完成」；另一种是在这次请求里告诉它「这是最后一次机会，请给出当前最佳答案」，用户拿到一份不完整但可用的结果。差别全在那句提示上。

**但别指望框架自动帮你做这件事。** Pydantic AI 到了 `request_limit` 会直接抛 `UsageLimitExceeded`，即使模型其实已经把该查的都查完了；官方给的是一个需要自己实现的 capability 范式（见 6.1）。LangGraph 的 `create_react_agent` 曾用 `RemainingSteps` 提前收尾，但这个接口已经弃用。结论很朴素：收尾逻辑要么自己写，要么没有。

#### 5.8 并行、异常、幂等，分别属于哪一层

前面几节防的是「循环停不下来」。这一节回到开头那张层次表，把三个最常被塞进 Loop 的问题各自归位——**混在一起讲，最容易造成的误解是「实现一个 Loop 就得顺手把所有事都做了」**。

| 问题 | 属于哪一层 | 判断依据 |
| :--- | :--- | :--- |
| 一次响应多个工具调用 | **Agent Loop** | 它决定「一帧里怎么执行动作」，不处理就是控制流不完整 |
| 工具异常没分类 | **Agent Runtime** | 它决定「错误怎么反馈给模型」，Loop 本身不关心错误类型 |
| 超时重试产生重复副作用 | **Agent Infrastructure** | 它涉及外部系统的状态一致性，单机低流量可以蒙过去 |

##### 一次响应多个工具调用 —— 属于 Loop

模型经常一次返回三个 tool call。Runtime 要决定：并发执行还是串行？部分失败怎么办？

| 策略 | 适用 | 代价 |
| :--- | :--- | :--- |
| 全部并发 | 工具之间无依赖、都幂等 | 需要处理部分失败与顺序不确定 |
| 全部串行 | 有依赖，或有副作用 | 延迟高 |
| 并发只读、串行写 | 混合场景的稳妥选择 | 实现复杂一点 |

部分失败的语义也要定清楚：三个里成功两个，是整体失败、还是把两个结果和一个错误一起回灌让模型决定？多数情况下后者更好——模型能看到已有进展，不会从头再来一遍。

这也解释了 5.3 里为什么判重必须按「轮」而不是按「调用」：同一批里的三个 `query_order(A1001)` 是并行请求，不是三次重复尝试。

##### 工具异常分类 —— 属于 Runtime

一个工具抛错，Runtime 该重试、该降级、还是该把错误原样告诉模型？这三条路的处理完全不同：

| 错误类型 | 例子 | 处理 |
| :--- | :--- | :--- |
| 可重试 | 网络超时、429 限流、锁冲突 | 指数退避重试，有上限 |
| 不可重试 | 参数校验失败、权限不足、资源不存在 | 包装成 Observation 回灌，让模型自己改参数或换路径 |
| 致命 | 凭证失效、依赖服务全挂 | 直接终止，不要浪费模型调用 |

把不可重试错误当成可重试来循环，是最常见的浪费；把可重试错误直接抛给模型，会让它误以为「这个工具坏了」，从此绕路。

##### 幂等与副作用 —— 属于 Infrastructure

这是三个里最容易被低估的一个，也最不该被塞进 Loop 里。完整走一遍它的链路：

```text
Agent 调用 create_order 工具
       ↓
订单在服务端已经创建成功
       ↓
HTTP 响应超时（或连接断开）
       ↓
Agent 认为执行失败
       ↓
重试 create_order
       ↓
产生重复订单
```

这段流程里最容易被忽略的一点是：**「失败就重试」这条默认策略，对有副作用的操作是不成立的**。重试之前必须先确认上一次到底有没有成功。三种做法，按代价从低到高：

1. **幂等键**：请求带 `idempotency_key`，由 `run_id` + 工具名 + 规范化参数生成（和 L3 的动作指纹同源），服务端按键去重；
2. **结果核查**：重试前先查一次「这个操作是不是已经生效」，例如按业务唯一键查订单；
3. **人工兜底**：无法自动判定的，转人工确认，不要赌。

**为什么它不算 Loop 的职责？** 因为一个单副本、低流量、不重试的循环，完全可以不管这件事而正常工作。它变致命是在有并发、有重试、有多副本之后——那是基础设施要解决的问题。Loop 能做的只有一件事：**把幂等键传下去**，剩下的交给服务端的去重约定。

> **本节小结**：并行是 Loop 的事，异常分类是 Runtime 的事，幂等是基础设施的事。**分清归属，才不会在一个 `while` 里硬写出一套分布式系统。**

#### 5.9 上线前检查清单

按层次分组。第一组不做，循环就是错的；后两组不做，循环能跑，但会在生产上以别的方式找回来。

**Loop 本身**

- [ ] L1 数的是**有效状态推进**次数，不是模型请求次数或工具调用次数
- [ ] 执行预算与收尾预算分开：`MAX_TRANSITIONS + FINALIZE_RESERVE`，干完活还有一次机会总结
- [ ] 每轮入口统一检查推进次数、全局 deadline、累计预算
- [ ] 单次上下文在**请求发出之前**估算，超了先压缩，压缩后仍超才终止
- [ ] 全局 deadline 会向下传递到模型请求**和工具执行**，不只在循环入口检查
- [ ] 重复动作检测按「轮」判重（动作集合），不是按单个调用判重
- [ ] 非最终、非工具调用的响应有明确分支，未知响应显式失败
- [ ] 只有一份运行状态，`messages` 挂在里面；`persist` 落盘的就是刚更新的那份
- [ ] 上下文裁剪之后，`tool_call_id` 仍然成对
- [ ] 一次响应多个工具调用时，并发策略与部分失败语义已定义

**Runtime 层（上生产前）**

- [ ] 所有强制终止都返回 `termination_reason` 与已有结果，不裸抛异常
- [ ] 终止结果区分 `completed` / `interrupted` / `suspended` / `timed_out` / `failed` / `cancelled`
- [ ] 「等待」是独立出口：状态落盘、能用 `run_id` 恢复，不在当前进程里空转
- [ ] 工具异常做了分类：可重试 / 不可重试 / 致命
- [ ] 终止原因进日志与告警，能区分「正常完成」和「被闸门拦下」

**Infrastructure 层（规模化之前）**

- [ ] 有副作用的工具都接受幂等键，超时重试前能判断上次是否已生效
- [ ] 有分页 / 重试等合法重复场景的白名单，避免误杀
- [ ] 明确哪些能力交给框架、哪些要自己补（见第六章）

**验证**

- [ ] 压测过至少一种人为注入的死循环，确认五层各自都能触发
- [ ] 人为制造一次「最后一步工具刚跑完」，确认收尾预算能让它输出结论而不是被掐断

> **本节小结**：步数管不收敛，时间管卡死，去重管原地打转，累计预算管成本，上下文上限管窗口——这五层齐了，Loop 才算可控。至于幂等、异常分类、多副本一致性，它们分别落在 Runtime 和基础设施层：**Loop 要做的是把该传的信息传下去，而不是把它们全塞进 `while` 里。**

---

### 六、框架里，这个循环长什么样

前五节讲的都是抽象骨架。落到真实框架上，会发现它们做的是同一件事，只是把「循环」放在了不同的位置：**框架预定义的节点流、Advisor 递归、自己画的有环图**。读一个陌生的 Agent 框架，只要找齐三样东西——状态在哪、循环由谁驱动、上限由谁兜底——基本就能读懂它。

#### 6.1 Pydantic AI：把循环显式成节点流

`agent.run()` / `run_sync()` 内部跑的是一张 agent graph；`agent.iter()` 会把这张图逐个节点暴露出来，正好可以逐帧对照第二节：

```python
from pydantic_ai import Agent, UsageLimits

agent = Agent("openai:your-model")

async with agent.iter(
    "帮我查询订单 A1001 的状态",
    usage_limits=UsageLimits(request_limit=12),   # L1：最多 12 轮
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

这里有个容易写错的地方：**`CallToolsNode` 不等于「工具执行节点」**。官方文档的示例问「法国的首都是哪里」，模型只回了一段纯文本，节点序列里**同样有 `CallToolsNode`**，然后才进 `End`。它处理的是「响应」，不是「工具」——没有工具调用时，它做的是输出校验和终止判定。

所以数轮数要看 `ModelRequestNode` 出现的次数，不要看 `CallToolsNode`。

内置的刹车集中在 `UsageLimits`，覆盖面比想象中宽：

| 参数 | 限制什么 | 对应前面 |
| :--- | :--- | :--- |
| `request_limit` | 提交到 run 历史的模型响应数，也就是 Loop 的轮数（默认 50，官方提醒数字会随版本变，别背） | L1 步数 |
| `tool_calls_limit` | 成功执行的工具调用次数 | 不直接对应：它限总量，不判重复 |
| `total_tokens_limit` / `input_tokens_limit` / `output_tokens_limit` | 整个 Run 累计 Token | L4 累计预算 |
| `cost_limit` | 整个 Run 累计成本（美元） | L4 |
| `per_request_input_tokens_limit` | **单次请求**的输入 Token 上限 | L5 上下文窗口 |

最后一行是关键：它和 `input_tokens_limit` 不是一回事，前者独立检查每一次请求的输入规模，后者是整个 Run 的累计值——正好对应 5.2 里 L4 与 L5 的区分。设置 `count_tokens_before_request=True` 可以在请求前就拦住超窗调用，否则那次请求仍会被发出并计费。

超时和取消也不止 `tool_timeout`：

| 能力 | 作用 |
| :--- | :--- |
| `Agent(tool_timeout=...)` | 单个工具的执行超时 |
| run 级 `timeout=` | 整个 Run 的执行时长上限，超时抛 `RunTimedOut` |
| `CancellationToken` | 从外部取消，可共享给父子 Agent 整棵树 |
| `ctx.cancel()` / `AgentRun.cancel()` | 在工具体内或手动驱动 `iter()` 时主动取消 |

所以它实际覆盖的是 **L1、L2、L4、L5 四层**，比「只管工具超时」的印象要完整得多。子 Agent 会继承父 Agent 的 deadline，自己的 `timeout=` 只能缩短不能延长——这就是 5.5 说的「Deadline 向下传递」。

还有两个容易踩的细节：

- `request_limit` 数的是 loop 轮数，不是发给供应商的每一次 HTTP 请求；FallbackModel 放弃的尝试和传输层重试不计入，但它们的 Token 和成本仍然计入额度。
- Token 与成本限制是**响应返回之后**才检查的，越过上限的那次请求已经产生费用——这是「限制」和「省钱」之间的一道缝，靠事前估算或 `count_tokens_before_request=True` 才能补上。

**到了 `request_limit` 就是抛异常，它不会自己收尾。** 官方写得很直白：达到上限时 Run 抛 `UsageLimitExceeded`，**即使模型其实已经把该查的都查完了**。想让它「带着已有信息给个结论」，得自己实现一个 capability——在 `before_model_request` 里算还剩几次、把剩余次数告诉模型，最后一次请求把 function tools 摘掉，让它除了输出别无选择。这正好对应 5.2 讲的收尾预算，区别是：在自研循环里它是三行代码，在框架里它得包成一个扩展点。

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
    "查一下 A1001 的订单和物流",
    usage_limits=UsageLimits(request_limit=8),
)
```

四行代码里有四个不能省的细节：

- **`AbstractCapability[Any]` 要带类型参数**。它是泛型基类，官方示例都写 `[Any]`；省掉在类型检查严格的项目里会报错。
- **提示要走 `ctx.enqueue(SystemPromptPart(...))`，不能直接改 `request_context.messages`**。后者是「只改这一次发送的内容」，不会进历史；`enqueue` 才会作为一条 `ModelRequest` 进历史，也才会出现在 trace 里。
- **`scope="request"` 是关键**。默认是 `conversation`，那条提示会一直留在后续请求里；设成 `request` 后，它只对这一次生效——每轮看到的是当前剩余次数，而不是一串过期的「只剩 3 次」。
- **`prepare_tools` 只摘 function tools**，结构化输出用的 output tool 会保留，所以有 `output_type` 的 Agent 仍然能正常产出结构化结果。

还有一个边界必须说清：**这套收尾策略不保证成功**。官方文档明确写了——如果模型最后一次输出仍然校验失败，已经没有请求留给重试，run 照样抛 `UsageLimitExceeded`。收尾能把「有数据但没总结」的概率压低，压不到零。

**同步工具的「超时」可能只是不再等。** 这条在排障时值钱：用同步 `def` 写的工具跑在工作线程里，超时触发时 Runtime 结束的是「等待结果」这件事，底层线程未必真的被终止——它可能还在跑，甚至稍后把副作用落了盘。所以有副作用的同步工具，光配 `tool_timeout` 不够，仍然要幂等键或执行结果核查（见 5.8 第三小节）。

另外，官方并未提供开箱的动作去重，**L3 重复检测仍需业务层自己补**——这正是第五章那套分层不能省的原因。

#### 6.2 Spring AI 2.0：把循环放进 Advisor 链

这里有个容易踩的版本差异。Spring AI 1.x 在每个 `ChatModel` 里内置了工具执行循环，可用 `internalToolExecutionEnabled` 开关；**2.0 起这个选项和「每模型内置循环」都被移除**，循环统一交给 `ChatClient` 的 `ToolCallingAdvisor` 驱动：有工具时自动注册，`ToolCallingManager` 负责执行，直到模型返回不带 tool calls 的响应。

```java
// 有工具时 ToolCallingAdvisor 自动驱动循环，无需手写 while
String answer = chatClient.prompt()
    .user("帮我查一下订单 A1001 的状态")
    .tools(orderTools)
    .call()
    .content();

// 想自己掌控循环：关闭自动注册，或直接调 ChatModel
// .advisors(AdvisorParams.toolCallingAdvisorAutoRegister(false))
// 再自行检查 chatResponse.hasToolCalls() 并用 ToolCallingManager 驱动
```

默认循环条件可以在 `ToolCallingAdvisor.Builder` 上替换，其默认判定就是 `chatResponse -> chatResponse != null && chatResponse.hasToolCalls()`——和前面 4.1 那行 `if response.tool_calls` 是同一句话，也一样带着 4.1 说的那个隐含前提。

三个和 Loop 直接相关的设计：

**`returnDirect` 是一次显式跳出，但有多工具例外。** `@Tool(returnDirect = true)` 让工具结果直接返回调用方、不回灌模型。但如果模型**一次请求了多个工具**，只有全部工具都标了 `returnDirect = true`，才会真的直接返回；只要有一个没标，结果仍然会回灌、循环继续。这是个很容易在联调时困惑的行为。

**Advisor 顺序决定观测粒度。** 放在 loop 外只看得到首尾（memory 默认如此），放进 loop 内才能逐轮看到完整的工具请求与响应——这就是 5.7 说的「可观测」。

**循环本身不计数，但工具调用有额度。** 这是最容易说岔的一处，得拆成两句话讲。

`ToolCallingAdvisor` 的 `adviseCall` 是一个「调用模型 → 有工具就执行 → 再调用」的循环，官方 API 里**确实没有「最多跑几轮」这个参数**——所以按**轮**计的 L1 要自己补，在 `ToolCallingManager` 外层包一层计轮次即可。

但它也**不是「完全没有限制」**。`DefaultToolCallingManager` 管着另一套额度：

| 配置项 | 含义 | 默认值 |
| :--- | :--- | :--- |
| `spring.ai.tools.limits.max-calls-per-tool-default` | 单轮中对**单个工具**的最大调用次数 | 40 |
| `spring.ai.tools.limits.max-calls-per-tool.<name>` | 单个工具的覆盖值，`-1` 表示豁免 | — |
| `spring.ai.tools.limits.max-total-tool-calls` | 单轮中跨**所有工具**的最大调用次数 | 150 |
| `spring.ai.tools.limits.on-limit-exceeded` | 超限行为：`THROW` 或 `RETURN_ERROR_RESPONSE` | `THROW` |

超限时抛 `ToolCallLimitExceededException`，异常里**带着 `ToolExecutionResult` 的部分结果**，已执行的调用不会被丢弃；`ToolCallingAdvisor` 会捕获它并作为最终响应返回，`finish_reason` 是 `ToolCallLimitExceededException.FINISH_REASON`。选 `RETURN_ERROR_RESPONSE` 则不中断循环，而是合成一条错误 `ToolResponse` 回灌给模型，让它自己收敛——后者更温和，但也意味着你需要别的闸门来兜底。

这里有个必须分清的差别：**工具调用次数不等于模型请求次数。** 一轮里模型可以合法地发 5 个工具调用，也可以 5 轮里只发 1 个。所以这套额度能挡住「原地打转」，挡不住「每轮只发一个、却跑了 50 轮」——后者仍然要自己加轮数上限。L3、L4、L5 同理。

还有一个迁移细节：照着 1.x 教程写 `internalToolExecutionEnabled(false)` 在 2.0 已经编译不过，要换成关闭自动注册或直接调 `ChatModel`。

#### 6.3 LangChain / LangGraph：用有环图表达迭代

先澄清一个容易混的点：**Graph 和 Loop 不是一回事，也不在同一层**。

| | Graph（图 / 编排模型） | Loop（循环 / 控制流行为） |
| :--- | :--- | :--- |
| 回答的问题 | 有哪些节点、状态怎么在节点间流动、谁先谁后 | 同一段流程要不要再跑一次、跑到什么时候 |
| 是否必须有环 | 不一定；DAG 也是图，每个节点只跑一次 | 必须有回边或重复执行，并配上终止条件 |
| LangGraph 里对应 | `StateGraph`、节点、边、状态、checkpointer、super-step 调度 | 图里存在 `tools → agent` 回边，且条件边能路由到 `END` |

有个流传很广的说法是「LangGraph 就是给 DAG 加了一条回边」。这个说法抓到了直觉，但低估了它的定位。更准确的理解是：**LangGraph 是底层的、有状态的编排 Runtime**——它提供共享状态、确定性节点与模型驱动节点、分支与循环、持久化（checkpointer）、人工介入（interrupt）。循环只是它支持的一种拓扑，不是它的全部。

对应地，「LangChain 的链是有向无环图，节点只能走一遍」这句话也要收一收。LangChain 早期的 LCEL 组合确实是管道式的无环结构，但现在的分工是：LangChain 提供 Agent 层抽象（`create_agent`、中间件），LangGraph 提供底层的图执行运行时。两者不是「DAG 与有环图」的简单对立。

回到循环本身。旧版 `AgentExecutor` 是最直白的实现：一个显式 `while`，`AgentAction` → 执行工具 → `Observation` 回灌 → 直到 `AgentFinish`，`max_iterations` 和 `max_execution_time` 兜底。它已废弃。LangGraph 不再把循环写成一段 `while`，而是让你把迭代表达成图拓扑：

```python
from langgraph.graph import StateGraph, MessagesState, START
from langgraph.prebuilt import ToolNode, tools_condition

builder = StateGraph(MessagesState)
builder.add_node("agent", call_model)
builder.add_node("tools", ToolNode(tools))
builder.add_edge(START, "agent")
builder.add_conditional_edges("agent", tools_condition)  # 终止判定：有 tool_calls → tools，否则 END
builder.add_edge("tools", "agent")                       # 回边：让图成为有环图，迭代由此产生
graph = builder.compile()
```

`tools_condition` 承担终止判断，`add_edge("tools", "agent")` 这条回边承担「结果回灌后再请求模型」。**两者合起来才是完整的 Loop**：缺了前者是死循环，缺了后者只是一条直线。状态放在 `MessagesState` 里由框架在节点间传递；`ToolNode` 会把工具结果组装成带 `tool_call_id` 的 `ToolMessage` 加回状态——就是 1.3 说的那套协议。

`recursion_limit` 限制的是 **super-step 数量**，不是递归深度，也不等于 Agent 轮数。这个区别在复杂图里会放大：一次模型请求 + 一次工具执行，可能跨好几个 super-step；如果图里还有并行分支、条件路由和子图，super-step 和「模型被调用了几次」就更没有固定比例。

所以它的定位要说准：**这是图执行层的安全保护，不是业务层的迭代预算。** 想限「最多几轮」，得自己数 `ModelRequestNode` 的进入次数（或用 6.1 那种 capability），不能指望这个参数。默认值在不同版本间差异较大，以所用版本文档为准，超限抛 `GraphRecursionError`。排查死循环时，`stream_mode="updates"` / `"debug"` 可以逐节点看状态变化——对应 5.7 的可观测要求。

**一个必须注意的版本变化**：`create_react_agent`（`langgraph.prebuilt`）在 LangGraph v1 已标记弃用，官方建议迁移到 `langchain.agents.create_agent`——它运行在 LangGraph 之上，并提供了中间件系统。上面的 `StateGraph` 示例不受影响（自己画图不会弃用），但如果你在旧教程里看到 `create_react_agent`，要知道它已经是历史接口。它曾经用 `RemainingSteps` 做的「临近上限时提前收尾」，在 `create_agent` 里由中间件机制承担。

#### 6.4 横向对照

| 框架 | 循环如何被表达 | 状态放在哪 | 默认终止条件 | 挂起 / 恢复 | 内置覆盖哪几层 | 能否接管循环 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Pydantic AI | 框架预定义 agent graph 的节点流 | `ModelMessage` 历史 + RunUsage | 产出 `End(FinalResult)` | 支持（deferred / suspended 续跑，具体 API 依版本） | L1（`request_limit`）、L2（`timeout`）、L4（`total_tokens_limit`）、L5（`per_request_input_tokens_limit`） | 可用 `next(node)` 手动推进 |
| Spring AI 2.0 | `ToolCallingAdvisor` 递归调用 | loop 内的会话历史 | 响应无 tool calls；`returnDirect` 直接返回 | 无内置，业务层自己做 | 工具调用额度（单工具 40 / 总量 150）；**轮数上限需自建** | 关闭自动注册或直连 `ChatModel` |
| LangGraph | 有环 `StateGraph` 的回边（Pregel super-step 调度） | `State` / `MessagesState` + checkpointer | 条件边路由到 `END` | 原生（checkpointer + `interrupt`） | 图执行层兜底（`recursion_limit` 数 super-step，**不等于** Agent 轮数） | 自定义边即可 |

三家的差异在表里很明显：Pydantic AI 把限制做成了一等公民，Spring AI 把循环藏在 Advisor 里、只给工具调用额度，LangGraph 把循环交给图拓扑、只给一个图执行上限。**没有一个框架替你解决全部五层**，尤其 L3 重复检测和全局 deadline，三家都需要业务层补。挂起能力也一样：只有 LangGraph 把 checkpointer + interrupt 做成核心概念，另两家要么靠版本特性、要么全靠自己。

#### 6.5 小结

三种表达，一张图：状态 + 一帧 + 终止条件。差别只在「循环由谁表达」——框架预定义的节点流、Advisor 递归、你自己画的有环图。这里还有个用词陷阱：Pydantic AI 和 LangGraph 都叫 graph，但前者是框架内部预定义好的执行图、你只能观察节点，后者拓扑由你画边决定、环也是你引入的；**两者都不意味着「图等于循环」**。

框架能帮你的是「循环怎么跑」，帮不了的是「循环什么时候必须停」——后者永远取决于你的业务阈值。所以第五章那套分层，用了框架也照样要设计一遍。

再往上收一层看：这三家解决的都只是 **Loop 层**的问题。状态怎么持久化、多副本怎么一致、幂等怎么保证，它们要么不管，要么只给一个钩子——那属于 Runtime 和基础设施层，不在「一个循环怎么转」的范畴里。**用框架不等于买了整套能力，看清它管到哪一层，比记住它有多少 API 更重要。**

---

### 结语

把整篇笔记压成一句话：**LLM 提出决策，Runtime 校验并执行，状态承载进展，终止条件负责叫停。**

这四件事里，只有最后一件是 Agent Loop 自己要回答的——**继续，还是停**。其余三件都是它调用别人的结果。所以看一个循环写得好不好，其实只需要问四个问题：

1. **状态有几个来源？** 两个以上，早晚会出现「消息更新了、状态没更新」，恢复时丢掉最后一轮。
2. **闸门装在动作之前还是之后？** 装在之后，都是事后追认：请求已经发出、工具已经跑完、钱已经花了。
3. **预算是几段？** 只有一段，干完活的那一刻就交不出答案；要拆成「执行」和「收尾」两段。
4. **它允不允许「等」？** 不允许，「审批三小时」就会变成「重跑三小时」。

这四个问题不需要框架知识，也不需要读源码，看一遍 `while` 就能答出来。

至于 `messages` 之外的那些东西——计划、预算、审批、子任务、幂等、多副本——它们是真实存在的，但**它们属于 Runtime 和基础设施，不属于这个循环本身**。把界线划清楚有两个好处：写循环时不会过度设计，读框架时也不会被 API 数量唬住。

ReAct、Planning、Reflection 换的是「谁在什么时候做决定」；Tool Calling 只是触发下一轮的一类事件；五层防护加一段收尾预算，解决的是「万一它停不下来」。想清楚这几件事，再看 Pydantic AI 的节点流、Spring AI 的 Advisor 链、LangGraph 的有环状态图，都只是在给同一个循环换外壳——找状态、找条件、找上限，三分钟就能看懂它的骨架。

下一次写 `while True` 之前，先花一分钟回答那四个问题——这一分钟通常比事后查线上死循环便宜得多。

---

### 附：参考资料与版本说明

官方文档（核对时间：2026 年 11 月）：

- Pydantic AI — Agents / Usage Limits（`request_limit` 默认值、`per_request_input_tokens_limit`、收尾 capability 范式）：`https://pydantic.dev/docs/ai/core-concepts/agents/`
- Spring AI 2.0 — Tool Calling（`ToolCallingAdvisor`、`ToolCallingManager`、`returnDirect`）：`https://docs.spring.io/spring-ai/reference/api/tools.html`
- Spring AI 2.0 — Advisors（`toolCallingAdvisorAutoRegister`）：`https://docs.spring.io/spring-ai/reference/api/advisors.html`
- Spring AI — Tool Call Limits（`spring.ai.tools.limits.*`、`ToolCallLimitExceededException`）：同上 tools 文档的「工具调用限制」小节
- Pydantic AI — Building Custom Capabilities（`AbstractCapability`、`ctx.enqueue`、`prepare_tools`、`wrap_node_run`）：`https://pydantic.dev/docs/ai/capabilities/custom`
- LangGraph — Graph API 与递归限制：`https://docs.langchain.com/oss/python/langgraph/use-graph-api`

**几处已知会随版本变化的地方**，正文里都标了「以版本为准」，落地前请再核一遍：

| 事项 | 变化情况 |
| :--- | :--- |
| Pydantic AI `request_limit` 默认值 | 当前为 50；官方明确提醒数字会变，建议从异常信息里读，不要背常量 |
| Pydantic AI 达到 `request_limit` 的行为 | 抛 `UsageLimitExceeded`，不自动收尾；收尾要自己写 capability |
| Spring AI 的循环位置 | 1.x 在各 `ChatModel` 内，2.0 起统一到 `ToolCallingAdvisor`，`internalToolExecutionEnabled` 已移除 |
| Spring AI Advisor 参数名 | 2.x 期间仍在调整，如 `toolCallingAdvisorAutoRegister` |
| LangGraph `recursion_limit` 默认值 | 版本间差异很大（旧文档 25，后续版本有 10000 / 10007 等），不要写死 |
| LangGraph `create_react_agent` | 已标记弃用，迁移到 `langchain.agents.create_agent` |
| Pydantic AI Capability 基类 | 需带类型参数（`AbstractCapability[Any]`）；请求级提示用 `ctx.enqueue(SystemPromptPart(..., scope="request"))`，直接改 `request_context.messages` 不进历史 |
| Pydantic AI 收尾成功率 | 最后一次输出校验失败时仍会抛 `UsageLimitExceeded`；收尾是概率改善，不是保证 |
| Spring AI 工具调用额度 | 由 `spring.ai.tools.limits.*` 控制（单工具默认 40、单轮总量默认 150）；与「最多跑几轮」不是一回事 |
