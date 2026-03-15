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
> 下文中，领域驱动设计=DDD，读者在看的时候自动代入自己喜欢的说法即可。



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

（核心域、支撑域、通用域的划分不是固定的，会随公司战略变化）

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



实体在属性上可能和数据库 DO（数据对象）有重叠，但实体聚焦业务逻辑，DO 仅聚焦数据存储，因此不会直接复用 DO 作为领域实体，因为DO中包含太多无关字段，实体更关注这个聚合（下文会讲）下需要用的信息



---



###### 值对象（Value Object）



值对象是没有唯一的标识，只关心本身的对象（一种用于表达值的对象）。

值对象不可变的核心原因是避免状态混乱，比如地址一旦创建，修改时应新建而非修改原有对象

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



聚合是一组紧密关联的领域对象（实体 + 值对象）的集合，通过聚合根划定业务一致性边界，保证聚合内数据的完整性和一致性（驱动这个业务关联的实体的集合）

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

聚合中的实体一般都是充血模型（下文有充血模型的简单说明），聚合中会对外开放领域的行为。

聚合通常会作为领域服务中的最小单位，这也就意味着，我们的代码，在领域设计中，在涉及到领域服务中，要尽可能的将业务对象转换为领域对象。

于是就有了**防腐层**（ACL），防腐层会将第三方接口等信息返回的结果转成领域对象，通常可以设计为防腐层返回的信息即可领域模型。

对于系统自身的数据等仍然是通过持久层（Dao、Mapper）来处理。



---



###### 充血&贫血



充血模型是DDD设计中非常核心的一个概念，重新模型不仅有数据还有业务规则和行为。

贫血模型比较简单，正常MVC开发中的大部分实体类都是贫血模型，几乎是只有属性。

充血模型 🌰：

```java
public class Contract {

    private Long id;
    private ContractStatus status;

    public void startSigning() {

        if (status != ContractStatus.DRAFT) {
            throw new DomainException("状态错误");
        }

        status = ContractStatus.SIGNING;
    }
}
```

充血模型的行为必须符合业务规则，所有对实体状态的修改都应通过实体自身的方法完成，而非外部直接 set，这是保证业务规则不被破坏的核心。这个特性是DDD的核心（网络上部分博主会把这一点省略掉，不理解）



---



###### 限定上下文（Bounded Context）

限定上下文是一个领域模型适用的边界（同一个概念在不同的上下文中的含义不同）

🌰：客户

- 交易系统：客户ID、交易金额
- 风控系统：客户姓名、身份证号、手机号



尽管都是客户的概念，但是在不同的上下文中模型不同，含义不同。



---



##### 对比MVC

###### 结构对比

既然提到了DDD，就不得不提MVC架构，以往的资料中对于DDD和MVC都是单选题，不过在我看来，作为一个成熟的开发，我全都要。

不过为了理解，还是简单对比一下。

MVC 架构

```tex
Controller
   ↓
Service
   ↓
Repository
```

DDD架构

```tex
Controller
   ↓
ApplicationService
   ↓
DomainService
   ↓
Aggregate
   ↓
Repository
```



我们可以看到在DDD架构中，代码的分层添加ApplicationService、DomainService和Aggregate。

从层级职责来看：

ApplicationService层负责的内容是领域服务的调用、编排，是对领域之间的解耦

DomainService层负责的内容是对聚合的调用、编排，是对聚合之间的解耦，而聚合又是领域驱动中对外部开放的可操作最小单位

Aggregate层负责了领域实体的处理。

**从代码分层的角度来看，DDD中将MVC架构中“上帝类”Service进行了解耦，每个领域对象更加关注自己所需要处理的事件，由上层编排下层，下层的修改不会影响到上一层，达到极强的可扩展性。**



###### 模型/组件对比

MVC架构中所使用的实体模型，大多数情况下为贫血模型。而DDD中则尽可能的将模型完善至充血模型。

贫血模型 VS 充血模型

贫血模型：仅包含getter/setter方法，无业务规则和行为。纯数据的载体。

充血模型：既包含属性，又包含业务行为、规则、状态变更。数据+行为的载体。



🌰：充血模型的优势，同样一个金额 ->>> 此时某个逻辑需要判断金额>0 且 对金额进行加工后面拼接“元”

```java
// 贫血模型
@Data
@AllArgsConstructor
public class Order {
		// 订单金额
    private BigDecimal amount;
}

// ..xxxServie
Order order = OrderDao.queryById(OrderId);
if order.getAmount().compareTo(Bigdecimal.ZERO) > 0 
  String amtZh = order.getAmount() + "元"

```

```java
// 充血模型
@Getter
@AllArgsConstructor
public class Order {
	// 订单金额
  public BigDecimal amount;
  	
  // greater than 大于0
  public boolean gt0(){
    return order.getAmount().compareTo(BigDecimal.ZERO) > 0 ;
  }
  
  public String cnAmt(){
    return order.getAmount() + "元";
  }
  
}

// 调用的位置
Order order = OrderDao.queryById(OrderId);
if order.gt0()
  String amtZh = order.cnAmt();

```

对比两种写法，可能大家第一眼会感觉，同样的东西换了个位置，并没有什么出彩的地方。

如果我们从另一个角度来看。

账单的金额>0 是一个非常常见的规则，金额填充单元“元”是一个非常常见的用法。及从某个角度来讲这两个方法在某些限定上下文中是固定的行为。

当系统中出现了大量的类似判断的时候，MVC架构的书写方案则需要对所有进行使用的地方进行修改， 而DDD方法仅需要对充血模型进行修改，并且充血模型还可以带来更多的行为，例如

```java
@Getter
@AllArgsConstructor
public class Order {
	// 订单金额
  public BigDecimal amount;
  	
  // greater than 大于0
  public boolean gt0(){
    return order.getAmount().compareTo(BigDecimal.ZERO) > 0 ;
  }
  	
  // 判断输入的金额是否大于0
  public boolean gtInput(BigDecimal input){
    return order.getAmount().compareTo(input) > 0 ;
  }
  
  public String cnAmt(){
    return order.getAmount() + "元";
  }
  
}

```

看到这里那么又有同学可以问了，我在充血模型中大量的提供方法等，会不会影响实体类的纯净？

这个问题在DDD中很容易解释，领域模型是抽象出来的实体，本身就是负责业务领域事件的，其甚至可以和数据库等底层数据不相关，领域仓储会保证领域中心的纯净（领域仓储会讲DO等转位Domain）。



###### 持久层

MVC（Dao/Repository） VS DDD（Repository）

在MVC中，一个Dao对应一个数据库表，其直接暴露给业务系统，Service层直接关注Dao的操作。

在DDD中，领域仓储，与**聚合根**强耦合，一个仓储对应一个聚合根，而非一张数据库表，屏蔽了底层数据库的结构、关联、存储，仓储的核心是‘面向业务’而非‘面向数据’，比如一个订单聚合根的仓储可能需要关联订单表、订单项表，但对外只暴露订单聚合的操作接口

领域仓储对领域对象提供持久化方法，领域层提供仓储接口，由基础设施层（infrastructure）进行实现，故在领域层实现了依赖倒置。领域层无论什么时候都不需要关心领域仓储的实现。

```java
// 领域层：仓储接口，面向聚合根
public interface IContractRepository {
    Contract findByContractId(String contractId);
    void save(Contract contract);
}
// 基础设施层：仓储实现，面向数据库
@Repository
public class ContractRepositoryImpl implements IContractRepository {
    @Autowired
    private ContractMapper contractMapper;
    @Override
    public Contract findByContractId(String contractId) {
        // 底层可做联表查询、数据转换，领域层无感知
        ContractDO contractDO = contractMapper.selectByContractId(contractId);
        return ConvertUtils.toContract(contractDO);
    }
    @Override
    public void save(Contract contract) {
        ContractDO contractDO = ConvertUtils.toContractDO(contract);
        contractMapper.insert(contractDO);
    }
}
```



##### 代码组织结构

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





##### 落地困难

由于DDD中概念繁多，且千人千面，甚至同一个人不能和其他时间的自己达成共识，这也就导致了DDD落地的困难。在当前的开发环境中，沉淀下来做设计、每个人都有统一的设计概念、都有良好的抽象能力是非常难的。且大部分场景更加需要敏捷开发，而非系统性的设计。

举个最简单的例子，上述的文字中大家能了解我在写的时候对DDD的了解吗？

（后续补充代码案例。。。）





参考文档：

【1】[领域驱动设计（DDD）全面解析：从概念到实践](https://www.zhihu.com/tardis/zm/art/1921246706936292234?source_id=1005)

【2】[迄今为止最完整的DDD实践 - 知乎](https://zhuanlan.zhihu.com/p/651873384)

