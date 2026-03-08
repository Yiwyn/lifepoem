+++
title = '领域驱动设计DDD-理论&实际（更新中）'

date = 2026-01-07T16:34:06+08:00

categories = ["设计"]

tags = ["领域驱动设计","DDD"]

+++



## 领域驱动设计DDD-理论&实际



> 当系统复杂度到了一定程度的时候，无论是可扩展性还是开发效率亦或是性能考虑等方面总是想要走出当前的困境，于是乎领域驱动设计总会被拾起来。
>
> 项目实践中想要使用DDD来对系统进行改造的难度是非常大的，尤其是大的团队，DDD会颠覆以往的开发思路，更加强调抽象、组合、设计等层面的问题。所以笔者目前会采用DDD的设计思想，在当前项目中做部分设计来提高当前的系统灵活性。
>
> 下文中，领域驱动设计=DDD，读者在看的时候自动带入自己喜欢的说法即可。



领域驱动设计（Domain-Driven Design，简称 DDD）是一种将业务**领域逻辑**作为软件设计核心的方法论，它通过系统化的领域建模和架构设计，帮助团队构建更贴近业务本质、更具可维护性的复杂系统。

**PS：DDD实际在项目种落地是非常困难的，所以我们需要了解的是其思路，学其”神“而非学其”形“。**





##### 前言

###### 为什么要了解DDD

1. DDD作为一个经久不衰的设计方案（2003年首次提出），期间经历过被迷信、被质疑、被技术打架等一系列历史。但是在2026年还能被提及，说明其本身具有非常大的优点，所以我们不一定需要会使用，但是一定要了解其底层思想。取其精华，去其糟粕，才能让我们的代码开发思路、架构设计更加清晰。
2. 由于DDD中聚合和充血模型的特性，领域设计在AI层面上有更大的突破方向。

3. 领域驱动设计是软考系统架构设计师中的一个知识点，常出现在综合和论文题中，所以想尝试软考的同学可以多多关注一下。



###### DDD落地困境

软件工程没有“银弹”*，DDD并不能作为一个项目的答案。

还有另一个层面的问题，我们知道设计模式、设计原则都是非常抽象的内容，这种反而更适合项目的落地，因为我们知道这是一个概念，我们利用概念配合项目进行更好的设计，但是，到了DDD问题就变了， DDD在本身就非常抽象的前提下，提供了非常多的设计细节，这种情况下工程实践上情况千变万化，过多的细节控制返回会使得项目更加的难以控制（最简单的问题就是过度设计），当输出理论的人不去实际介入软件工程，强行DDD是一件非常困难的事。

同时DDD要求团队中的每个人都需要有统一的认识，领域的拆分、领域服务编排、实体设计等，这个通常是不现实的。



*银弹：一种简单而有效的解决复杂问题的方法或工具。（PS：简单的说法换个描述，再解释一下，突然整个文章就变的高端了）



##### 核心概念

###### 领域（Domain）

领域就是系统要解决的业务问题范围。

```tex
例如电商平台中，订单领域、库存领域、支付领域

OA审批系统中，审批、流程
```

DDD认为：一个复杂系统=**多个领域组合**

领域又分三个层级：

- 核心域：这个系统中最重要的能力，公司主要有竞争力的业务领域。

  在金融系统中，核心域可能是交易、资产、风险等； 在电子签约系统中，核心域可能是合同签署

- 支撑域：支撑核心业务，但不是核心竞争力

  在金融系统中，支撑域可能是客户、产品；在电子签约中，支撑域可能是合同、公章管理等

- 通用域：几乎所有系统都会有的能力。

  用户、权限、日志、文件等。



---



###### 实体（Entity）

实体是具有唯一标识（例如主键），并且生命周期内可持续变化的对象（有状态，会更新）

🌰：合同实体（合同号，合同状态），OA实体（流程编号，流程节点）



这里实践中可以发现和数据库一层是类似的，但是不会直接使用数据库的DO，因为DO中包含太多无关字段，实体更关注这个聚合（下文会讲）下需要用的信息



---



###### 值对象（Value Object）



值对象是没有唯一的标识，只关心本身的对象（一种用于表达值的对象）

🌰： 例如金额、地址信息等。一般创建后不允许改变

```java
@Getter
public class Address {

    /**
     * 省
     */
    private final String province;
    /**
     * 市
     */
    private final String city;
    /**
     * 区
     */
    private final String county;
    /**
     * 详细地址
     */
    private final String detailAddress;

    public Address(String province, String city, String county, String detailAddress) {
        this.province = province;
        this.city = city;
        this.county = county;
        this.detailAddress = detailAddress;
    }
}
```



---



###### 聚合（Aggregate）



聚合是领域驱动的核心，是一组相关的对象组成的业务的一致性边界（驱动这个业务关联的实体的集合）

聚合只有一个聚合根 **Aggregate Root**，聚合根就是我们定义这个实体相关集合的地方

🌰：

```java
@Getter
@AllArgsConstructor
public class Contract implements AggregateRoot {
    /**
     * id
     */
    private String contractId;
    /**
     * 合同状态
     */
    private ContractStatus contractStatus;
    /**
     * 签约人
     */
    private List<Signer> signers;
    /**
     * 合同信息
     */
    private ContractDocument contractDocument;
}
```



---



###### 限定上下文（Bounded Context）

限定上下文是一个领域模型适用的边界（同一个概念在不同的上下文中的含义不同）

🌰：客户

- 交易系统：客户ID、交易金额
- 风控系统：客户姓名、身份证号、手机号



尽管都是客户的概念，但是在不同的上下文中模型不同，含义不同。



---



##### 对比MVC

既然谈到了后端，同样是分层架构，这就不得不提到MVC架构。







##### 经典结构

```tex
Controller
   ↓
ApplicationService
   ↓
Aggregate
   ↓
Repository
```



代码组织结构

```tex
contract
 ├── application
 │   ├── ContractApplicationService
 │   └── query
 │       ├── CustomerQueryService
 │       └── OrderQueryService
 │
 ├── domain
 │   ├── contract
 │   │   ├── Contract
 │   │   └── ContractRepository
 │   │
 │   └── service
 │       └── ContractDomainService
 │
 └── infrastructure
     ├── persistence
     │   ├── mapper
     │   │   ├── ContractMapper
     │   │   └── CustomerMapper
     │   │
     │   └── do
     │       ├── ContractDO
     │       └── CustomerDO
```





参考文档：

【1】[领域驱动设计（DDD）全面解析：从概念到实践](https://www.zhihu.com/tardis/zm/art/1921246706936292234?source_id=1005)

【2】[迄今为止最完整的DDD实践 - 知乎](https://zhuanlan.zhihu.com/p/651873384)

