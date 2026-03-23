+++
title = '重新认识事务（Transaction）'

date = 2026-03-20T22:58:46+08:00

categories = ["Spring","Transaction"]

tags = ["事务"]

draft = true

+++

### 重新认识事务（Transaction）



> 为什么要重新认识事务
> 起初我们在刚接触数据库都学过事务，在项目实践中都有过使用事务。着业务的越来越大，功能逻辑越来越复杂，可能在某一次生产事故后，我们才会静下心来想一想我们真的能用好事务吗？
>
> 很多时候，我们对事务的认知还在事务中必须要执行到commit、rollback，甚至是@Transactional一个注解全部解决的层面。
>
> 在实际开发中我们对事务的理解停留在“**加不加**”的问题，而实际上事务是“**怎么加、加在哪、加了会有什么影响**”的系统工程。
>
> 注：本文将从Spring框架角度的进行描述且只聊单体服务



##### 事务Transaction

###### ACID

事务是数据库操作的最小执行单元*，保证要么全部成功，要么全部回滚，

*需要注意的一点是我们平时单表操作，其实也是有事务存在的只不过不是显式声明。

核心遵循ACID原则：

- **原子性（Atomicity）**：操作不可分割，要么全部成功，要么全部失败回滚。
- **一致性（Consistency）**：执行前后数据完整性保持一致
- **隔离性（Isolation）**：并发事务互不干扰
- **持久性（Durability）**：提交后数据永久生效，不丢失



###### 事务传播等级

🔥 高频使用传播等级

1. REQUIRED（默认等级）

- **原理**：当前存在事务，则**加入**该事务；当前无事务，则**新建**一个事务。
- **特性**：内外方法共用同一个事务连接，任意一方抛异常，整个事务全部回滚。
- **适用场景**：常规业务逻辑（增删改）、单业务链嵌套调用，90%场景首选。
- **避坑**：子方法异常会导致父方法一起回滚，无法局部隔离。

2. REQUIRES_NEW

- **原理**：**新建独立事务**，并挂起当前存在的外部事务；新事务执行完毕后，恢复外部事务。
- **特性**：内外事务完全隔离，拥有独立的数据库连接和生命周期，互不干扰。
- **适用场景**：子业务需独立提交/回滚（如日志记录、消息发送、补偿操作），子方法失败不影响主流程。
- **避坑**：会占用额外数据库连接，大量使用易导致连接池耗尽，严禁长逻辑使用。

3. NESTED（嵌套事务）

- **原理**：基于数据库**保存点（SavePoint）**实现嵌套，外层事务存在时创建子事务保存点；无事务则等价于REQUIRED。
- **特性**：外层事务回滚 → 内层事务必回滚；内层事务回滚 → 仅回滚到保存点，不影响外层事务。
- **适用场景**：局部失败无需全盘回滚、支持部分回滚的复杂业务（如分步提交、容错处理）。
- **避坑**：依赖数据库对SavePoint的支持，JTA分布式事务环境下不生效。

🧊 小众传播等级

4. SUPPORTS

- **原理**：有事务则加入，无事务则**以非事务方式运行**。
- **适用场景**：纯查询方法，兼顾有事务/无事务环境，配合只读事务提升性能。

5. NOT_SUPPORTED

- **原理**：始终以**非事务方式运行**，存在当前事务则挂起。
- **适用场景**：无需事务的耗时操作（如文件读写、大数据量查询），避免长事务占用连接。

6. MANDATORY

- **原理**：强制要求当前存在事务，无事务则**直接抛出异常**。
- **适用场景**：核心写操作，严禁无事务执行，防止漏加事务导致数据不一致。

7. NEVER

- **原理**：强制要求当前无事务，存在事务则**直接抛出异常**。
- **适用场景**：严禁参与事务的操作（如缓存预热、静态资源加载），杜绝事务污染。





##### @Transactional原理

了解的事务的基本概念后，我们通过Spring源码，来看下事务的一些细节。

首先通过`@EnableTransactionManagement`进入`TransactionManagementConfigurationSelector` 类，这个类中包含了事务的全部内容。

![image-20260323113748873](https://filestore.lifepoem.fun/know/202603231137926.png)

```java
	/**
	 * Returns {@link ProxyTransactionManagementConfiguration} or
	 * {@code AspectJ(Jta)TransactionManagementConfiguration} for {@code PROXY}
	 * and {@code ASPECTJ} values of {@link EnableTransactionManagement#mode()},
	 * respectively.
	 */
	@Override
	protected String[] selectImports(AdviceMode adviceMode) {
		switch (adviceMode) {
			case PROXY:
				return new String[] {AutoProxyRegistrar.class.getName(),
						ProxyTransactionManagementConfiguration.class.getName()};
			case ASPECTJ:
				return new String[] {determineTransactionAspectClass()};
			default:
				return null;
		}
	}
```

默认情况下`EnableTransactionManagement` 中

```java
AdviceMode mode() default AdviceMode.PROXY;
```

所以我们重点关注 `AutoProxyRegistrar` 、`ProxyTransactionManagementConfiguration` 

其中 `AutoProxyRegistrar` 是自动代理机制来增强目标对象的功能，和实际事务关系不太大，我们可以先不看。

我们把中心放到 `ProxyTransactionManagementConfiguration` 。

这个类定义了三个Bean。这三个Bean做一件事，就是创建一个事务的advisor

先看一个简单的例子，什么是Advisor：

```java
// 增强逻辑
@Component
public class TaskAdvice implements MethodInterceptor {

    @Override
    public Object invoke(MethodInvocation invocation) throws Throwable {
        System.out.println("方法调用前: " + invocation.getMethod().getName());
        Object result = invocation.proceed();
        System.out.println("方法调用后: " + invocation.getMethod().getName());
        return result;
    }
}

// 配置类
@Configuration
public class TaskConfig {

    // 创建advisor
    @Bean
    public DefaultPointcutAdvisor taskAdvisor(TaskAdvice taskAdvice) {
        // 创建切点
        AnnotationMatchingPointcut matchingPointcut = AnnotationMatchingPointcut.forMethodAnnotation(Task.class);
        DefaultPointcutAdvisor defaultPointcutAdvisor = new DefaultPointcutAdvisor();
        // 切面
        defaultPointcutAdvisor.setAdvice(taskAdvice);
        defaultPointcutAdvisor.setPointcut(matchingPointcut);
        return defaultPointcutAdvisor;
    }
}
```

以上代码在服务启动的时候，会根据切点自动对符合条件得到类进行增强。



再来看事务的配置类，就是做了三件事 ， 创建一个事务的增强实现，创建了一个事务属性信息（包含切点信息），再根据以上信息创建一个事务Advisor。所以我们先关注`TransactionInterceptor`

![image-20260323165948395](https://filestore.lifepoem.fun/know/202603231659482.png)



增强细节，如下图，图二就是我们使用了@Transactional的方法的真实执行时的代码。

![image-20260323181058325](https://filestore.lifepoem.fun/know/202603231810394.png)

![image-20260323181132368](https://filestore.lifepoem.fun/know/202603231811434.png)

![image-20260323220703546](https://filestore.lifepoem.fun/know/20260323220712630.png)

![image-20260323221243147](https://filestore.lifepoem.fun/know/20260323221243197.png)

![image-20260323221316626](https://filestore.lifepoem.fun/know/20260323221316678.png)



看上面的源码有什么用呢，从源码中我们能发现，原来`@Transactional`是这样运作的，我们从中可以发现几个点

1. 标识了`@Transactional`的整个方法都是放到事务中进行的，事务的粒度非常大。此处在下文中重点描述
2. 声明式事务是AOP技术，声明AdvisorBean代理使用事务的类，所以在实例内调用自己的方法不能触发事务（this.xx调用的是自身，而非增强代理对象）
3. 开启事务时，如果不设置超时时间，则系统默认超时时间为-1，等于没有超时时间
4. 在提交/回滚的方法中，包含`triggerBeforeCommit`等生命周期方法。下一段会重点描述。

接下来，先看一下事务生命周期的相关函数，看了之后我们再对上述的几个点所引出的问题做解答。



##### 进阶知识

###### 事务同步管理器 TransactionSynchronizationManager



> [Spring事务 | Yiwyn's ~ShenZhi Blog](https://blog.lifepoem.fun/posts/互联网/spring/spring事务/)
>
> 这里先引用一下自己的文章

首先，我们先知道`TransactionSynchronizationManager`的作用是什么

```java
// 官方注释
/**
 * Central delegate that manages resources and transaction synchronizations per thread.
 * To be used by resource management code but not by typical application code.
 *
 * <p>Supports one resource per key without overwriting, that is, a resource needs
 * to be removed before a new one can be set for the same key.
 * Supports a list of transaction synchronizations if synchronization is active.
 *
 * <p>Resource management code should check for thread-bound resources, e.g. JDBC
 * Connections or Hibernate Sessions, via {@code getResource}. Such code is
 * normally not supposed to bind resources to threads, as this is the responsibility
 * of transaction managers. A further option is to lazily bind on first use if
 * transaction synchronization is active, for performing transactions that span
 * an arbitrary number of resources.
 *
 * <p>Transaction synchronization must be activated and deactivated by a transaction
 * manager via {@link #initSynchronization()} and {@link #clearSynchronization()}.
 * This is automatically supported by {@link AbstractPlatformTransactionManager},
 * and thus by all standard Spring transaction managers, such as
 * {@link org.springframework.transaction.jta.JtaTransactionManager} and
 * {@link org.springframework.jdbc.datasource.DataSourceTransactionManager}.
 *
 * <p>Resource management code should only register synchronizations when this
 * manager is active, which can be checked via {@link #isSynchronizationActive};
 * it should perform immediate resource cleanup else. If transaction synchronization
 * isn't active, there is either no current transaction, or the transaction manager
 * doesn't support transaction synchronization.
 *
 * <p>Synchronization is for example used to always return the same resources
 * within a JTA transaction, e.g. a JDBC Connection or a Hibernate Session for
 * any given DataSource or SessionFactory, respectively.
 *
 * @author Juergen Hoeller
 * @since 02.06.2003
 * @see #isSynchronizationActive
 * @see #registerSynchronization
 * @see TransactionSynchronization
 * @see AbstractPlatformTransactionManager#setTransactionSynchronization
 * @see org.springframework.transaction.jta.JtaTransactionManager
 * @see org.springframework.jdbc.datasource.DataSourceTransactionManager
 * @see org.springframework.jdbc.datasource.DataSourceUtils#getConnection
 */

// 中文翻译
/**
* 核心委托类，负责管理每个线程的资源及事务同步。 
* 供资源管理代码使用，而非供一般的应用程序代码使用。 
*
* <p>支持“一键一资源”模式，且不允许覆盖；即，若要为同一键设置新资源，必须先移除旧资源。 
* 若事务同步处于激活状态，则支持维护一个事务同步列表。 
*
* <p>资源管理代码应通过 {@code getResource} 方法检查是否存在线程绑定的资源（例如 JDBC
* 连接或 Hibernate Session）。此类代码通常不应自行将资源绑定到线程上，因为这是事务管理器的职责。 
* 另一种可选方案是：若事务同步处于激活状态，则在首次使用时进行“延迟绑定”（lazy bind），
* 以便执行跨越任意数量资源的事务操作。 
*
* <p>事务同步的激活与去激活操作必须由事务管理器通过 {@link #initSynchronization()} 和
* {@link #clearSynchronization()} 方法来执行。这一机制已由 {@link AbstractPlatformTransactionManager}
* 自动实现，因此所有的标准 Spring 事务管理器（例如
* {@link org.springframework.transaction.jta.JtaTransactionManager} 和
* {@link org.springframework.jdbc.datasource.DataSourceTransactionManager}）均支持此功能。 
*
* <p>资源管理代码仅应在当前管理器处于激活状态时注册同步对象（可通过 {@link #isSynchronizationActive}
* 进行检查）；若管理器未处于激活状态，则应立即执行资源清理工作。如果事务同步未处于激活状态，
* 则意味着当前不存在事务，或者当前的事务管理器不支持事务同步功能。 
*
* <p>事务同步机制的一个典型应用场景是：在 JTA 事务的整个生命周期内，确保针对给定的
* DataSource 或 SessionFactory，始终返回同一个资源实例（例如同一个 JDBC 连接或 Hibernate Session）。 *
* @author Juergen Hoeller
* @since 2003年6月2日
* @see #isSynchronizationActive
* @see #registerSynchronization
* @see TransactionSynchronization
* @see AbstractPlatformTransactionManager#setTransactionSynchronization
* @see org.springframework.transaction.jta.JtaTransactionManager
* @see org.springframework.jdbc.datasource.DataSourceTransactionManager
* @see org.springframework.jdbc.datasource.DataSourceUtils#getConnection
```

简单说，就两件事

**存储事务上下文**：在当前线程中绑定事务相关的核心信息（比如数据库连接、事务是否激活、事务名称、隔离级别等），让同一线程内的所有操作都能获取到当前事务的上下文。

**管理事务同步器**：允许注册 `TransactionSynchronization` 类型的回调对象，这些对象会在事务的关键阶段（提交前、提交后、回滚前、回滚后、事务完成）触发执行



存储事务上下文我们一般不会操作，更多的是管理事务同步的使用，以下是翻译了注释的源代码

```java
/**
 * 事务同步回调的接口。
 * 由 AbstractPlatformTransactionManager 提供支持。
 *
 * <p>TransactionSynchronization 实现类可实现 Ordered 接口来影响其执行顺序。
 * 未实现 Ordered 接口的同步器会被追加到同步链的末尾。
 *
 * <p>Spring 自身执行的系统级同步逻辑会使用特定的顺序值，允许对其执行顺序进行细粒度的控制（如有必要）。
 *
 * <p>从 5.3 版本开始，该接口实现了 {@link Ordered} 接口，以支持声明式控制同步器的执行顺序。
 * 默认的 {@link #getOrder() 执行顺序} 为 {@link Ordered#LOWEST_PRECEDENCE}（最低优先级），
 * 表示晚执行；若需提前执行，返回更小的数值即可。
 *
 * @author Juergen Hoeller
 * @since 02.06.2003
 * @see TransactionSynchronizationManager
 * @see AbstractPlatformTransactionManager
 * @see org.springframework.jdbc.datasource.DataSourceUtils#CONNECTION_SYNCHRONIZATION_ORDER
 */
public interface TransactionSynchronization extends Ordered, Flushable {

    /** 事务正常提交时的完成状态 */
    int STATUS_COMMITTED = 0;

    /** 事务正常回滚时的完成状态 */
    int STATUS_ROLLED_BACK = 1;

    /** 因启发式混合完成或系统错误导致的完成状态 */
    int STATUS_UNKNOWN = 2;


    /**
     * 返回此事务同步器的执行顺序。
     * <p>默认值为 {@link Ordered#LOWEST_PRECEDENCE}（最低优先级）。
     */
    @Override
    default int getOrder() {
        return Ordered.LOWEST_PRECEDENCE;
    }

    /**
     * 挂起此同步器。
     * 若管理了相关资源，应将其从 TransactionSynchronizationManager 中解绑。
     * @see TransactionSynchronizationManager#unbindResource
     */
    default void suspend() {
    }

    /**
     * 恢复此同步器。
     * 若管理了相关资源，应将其重新绑定到 TransactionSynchronizationManager。
     * @see TransactionSynchronizationManager#bindResource
     */
    default void resume() {
    }

    /**
     * 将底层会话刷新到数据存储（如适用）：
     * 例如 Hibernate/JPA 会话。
     * @see org.springframework.transaction.TransactionStatus#flush()
     */
    @Override
    default void flush() {
    }

    /**
     * 在事务提交前调用（早于 "beforeCompletion"）。
     * 例如可将事务性的对象关系映射（O/R Mapping）会话刷新到数据库。
     * <p>此回调<b>不代表</b>事务一定会被提交。即使调用了此方法，后续仍可能触发回滚决策。
     * 该回调的设计目的是执行仅在提交仍有可能发生时才需要的操作，比如将 SQL 语句刷新到数据库。
     * <p>注意：此方法抛出的异常会传播到提交调用方，并导致事务回滚。
     * @param readOnly 事务是否被定义为只读事务
     * @throws RuntimeException 发生错误时抛出；异常会<b>传播到调用方</b>
     * （注意：此处不要抛出 TransactionException 子类！）
     * @see #beforeCompletion
     */
    default void beforeCommit(boolean readOnly) {
    }

    /**
     * 在事务提交/回滚前调用。
     * 可在事务完成<b>前</b>执行资源清理操作。
     * <p>即使 {@code beforeCommit} 抛出异常，此方法仍会在其之后被调用。
     * 该回调允许在事务完成前（无论最终结果如何）关闭资源。
     * @throws RuntimeException 发生错误时抛出；异常会<b>被记录但不传播</b>
     * （注意：此处不要抛出 TransactionException 子类！）
     * @see #beforeCommit
     * @see #afterCompletion
     */
    default void beforeCompletion() {
    }

    /**
     * 在事务提交后调用。可在主事务<b>成功</b>提交后立即执行后续操作。
     * <p>例如可提交那些依赖主事务成功提交的后续操作，如发送确认消息或邮件。
     * <p><b>注意：</b>此时事务已完成提交，但事务资源可能仍处于活跃且可访问状态。
     * 因此，此阶段触发的任何数据访问代码仍会“参与”原始事务，允许执行一些清理操作（后续无提交动作），
     * 除非显式声明需要在独立事务中运行。
     * 因此：<b>对此处调用的任何事务性操作，使用 {@code PROPAGATION_REQUIRES_NEW} 传播属性。</b>
     * @throws RuntimeException 发生错误时抛出；异常会<b>传播到调用方</b>
     * （注意：此处不要抛出 TransactionException 子类！）
     */
    default void afterCommit() {
    }

    /**
     * 在事务提交/回滚后调用。
     * 可在事务完成<b>后</b>执行资源清理操作。
     * <p><b>注意：</b>此时事务已完成提交或回滚，但事务资源可能仍处于活跃且可访问状态。
     * 因此，此阶段触发的任何数据访问代码仍会“参与”原始事务，允许执行一些清理操作（后续无提交动作），
     * 除非显式声明需要在独立事务中运行。
     * 因此：<b>对此处调用的任何事务性操作，使用 {@code PROPAGATION_REQUIRES_NEW} 传播属性。</b>
     * @param status 完成状态，取值为 {@code STATUS_*} 常量
     * @throws RuntimeException 发生错误时抛出；异常会<b>被记录但不传播</b>
     * （注意：此处不要抛出 TransactionException 子类！）
     * @see #STATUS_COMMITTED
     * @see #STATUS_ROLLED_BACK
     * @see #STATUS_UNKNOWN
     * @see #beforeCompletion
     */
    default void afterCompletion(int status) {
    }

}
```





##### 事务优化

###### 事务边界控制

坊间有流传这么一个说法：大厂不推荐使用@Transactional注解。

何为其然也？曰：大部分人在写业务功能的时候，一般是上帝Service类，即业务Service中会有大量的业务代码，其中不乏数据库操作、远程调用服务等。

举个坏🌰：

```java
    /**
     * 查询银行审批状态
     *
     * @param bizSeq 业务号
     */
    @Transactional(rollbackFor = Exception.class)
    public void getBankApprovalResult(String bizSeq) {
        // 先查询到订单
        Order order = orderMapper.queryById(bizSeq);

        // 查询银行审批状态
        BankReponse reponse = bankService.queryResult(order.getBankApplyId);

        // 如果查询失败，直接抛异常
        if (!reponse.isSuccess()) {
            throw new RuntimeException();
        }
        // 如果成功更新订单表
        order.setBankApprovalSts("pass");
        orderMapper.update(order);

        // 发送通知
        notifyService.sendNotify(order);
    }
```

好🌰

```java
    /**
     * 查询银行审批状态
     *
     * @param bizSeq 业务号
     */
    public void getBankApprovalResult(String bizSeq) {
        // 先查询到订单
        Order order = orderMapper.queryById(bizSeq);

        // 查询银行审批状态
        BankReponse reponse = bankService.queryResult(order.getBankApplyId);

        // 如果查询失败，直接抛异常
        if (!reponse.isSuccess()) {
            throw new RuntimeException();
        }
        // 如果成功更新订单表
        order.setBankApprovalSts("pass");
        orderMapper.update(order);

        // 发送通知
        notifyService.sendNotify(order);
    }


```



###### 事务超时时间

事务连接超时时间一直以为是被大家忽略的问题

扩展：几乎在所有的高可用系统中，任何的链接都应该设置超时时间，超时时间会让系统在规定时间内快速失败从而释放资源。没有超时时间/超时时间设计不合理会导致等待，若是业务简单则问题可能被掩盖，一旦并发上来，系统雪崩也会随之而来。

**举个坏🌰：**

- A线程更新业务123方法执行完成后没有正常提交或者回滚（可能是更新后同步别的系统一直等待响应，或者就是逻辑漏洞）

- 另一个业务操作线程B也要更新这个业务123，这个时候因为业务123的数据被锁了，他要等A线程释放。

🔥巧了两个事务都没有设置超时，那事情就变得奇妙起来了，Spring层面会默认一直等待，直到数据库层面事务超时释放。于是关于这笔业务的一切行为都停止了，全部都在等待事务释放。

🔥🔥更巧的是如果线程B是一个批量更新的操作，那么批量更新的业务可能都被锁起来，这个时候就不仅仅是业务123的问题了，可能整个系统都在面临着极大的考验。



###### 事务隔离

事务隔离是事务的一个特性，我们在开发复杂业务的时候，



###### 批量操作优化











##### 参考文档：

【1】[spring事务中的超时时间很多人都不理解_spring 事务超时-CSDN博客](https://blog.csdn.net/luoyang_java/article/details/105556722)

【2】[面试官灵魂拷问：为什么 SQL 语句不要过多的 join？ - 知乎](https://www.zhihu.com/question/585496172/answer/1986368315585734057)
