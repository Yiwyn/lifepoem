+++
title = '架构权衡评估方法[ATAM]'
date = 2024-10-16T09:36:10+08:00
categories = ["软件架构"]
tags = ["架构评估","ATAM"]

+++



### 架构权衡评估方法



##### 基本概念

ATAM方法是在SAAM方法基础上发展起来的，主要针对<font color='red'>性能、可用性、安全性、可修改性</font>，在系统开发之前，对这些只来你属性进行评估和折中





##### <font color='red'>ATAM方法采用效用树（Utility tree）</font>

ATAM方法采用效用树工进行分类和优先级排序。

效用树的结构包括：

<font color='red'>树根-质量属性-属性分类-质量属性场景（叶子节点）</font>

ATAM方法主要关注4类质量属性：<font color='red'>性能、安全性、可修改性、可用性</font>

得到初始效用树后，需要对<font color='red'>场景</font>按重要性给定优先级（H/M/L的形式），再按场景实现的难易度来确定优先级（H/M/L的形式）





---



![image-20241016134025682](https://filestore.lifepoem.fun/know/202410161340737.png)





#### 基本阶段

- ##### 介绍ATAM方法

  - 评估小组负责人向参加会议的项目干系人介绍ATAM评估方法。

- ##### 介绍商业动机【业务动机】

  - 项目决策者从业务的角度介绍系统的概况。该描述应该包括系统最重要的功能、技术/管理/经济和政治方面的任何相关限制、与该项目相关的业务目标和上下文、主要的项目干系人，以及架构的驱动因素等。

- ##### 介绍架构【描述架构】

  - 包括技术约束（操作系统、硬件、中间件等）、将与本系统进行交互的其他系统、用以满足质量属性要求的架构方法等。

- ##### 识别使用的架构方法【确定架构方法】

  - 通过理解架构方法来分析架构，在这一步。由架构设计师确定架构方法。

- ##### 生成质量属性效用树

  - 评估小组、设计小组、管理人员和客户代表一起确定系统最重要的质量属性目标，并对这些质量目标设计优先级和细化。

  - <font color='red'>【性能】【安全性】【可用性】【可修改性】</font>

- ##### 分析架构方法

  - 这一步主要结果是以架构方法或风格的列表，与之相关的一些问题，以及设计师对这些问题的回答。通常产生一个风险列表、敏感点和权衡点列表。

- ##### 讨论场景和对场景分级

  - 项目干系人进行两项相关的活动，分别是集体讨论用例场景和改变场景。

- ##### 分析架构方法

  - 在收集并分析了场景之后，设计师就可把最高级别的场景映射到所描述的架构中，并对相关的架构如何有助于该场景的实现做出解释。

- ##### 描述评估结果

  - 把ATAM分析中所得到的各种信息进行归纳，并反馈给项目干系人。
