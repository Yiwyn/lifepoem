+++
title = 'Spring事务'

date = 2024-12-04T15:05:36+08:00

categories = ["Spring"]

tags = ["事务"]

+++



本文将以Spring中事务进行展开，主要讨论以下几点

- 事务注解

  

- 事务传播

  - 经典错误场景
    - 事务传播

- 事务同步

  - TransactionSynchronizationManager 
    - 事务钩子
    - 事务监听





#### 事务





#### 事务传播





#### 事务同步（器）

Q：为什么需要事务同步

A：在系统设计中，往往有很多后置通知类的内容，如发送消息等。很多时候有些代码无需在事务中进行，更多的是在确保事务提交或者回滚后进行；在事务中进行会出现诸多隐患，如多余的数据回滚、数据一致性等问题、后置行为http、文件处理等较耗时的行为导致事务时间拉长，增加数据库压力等。



Q：事务同步可以做到什么

A：在事务生效的上下文中，可以注册事务钩子(HOOK)，钩子函数将围绕事务进行增强，如事务提交前，事务提交后，事务提交完成；可以根据事务的提交状态进行自定义操作，如当事务提交时、回滚时进行不同的流程。



Q：如何使用事务同步

A：事务同步围绕事务进行  举个栗子：

![image-20241205164943384](https://filestore.lifepoem.fun/know/202412051649426.png)

这段代码嵌在某个事务中，当事务执行完成后会触发【afterCompletion】方法执行；

由这段代码展开对事务钩子的讨论。

1. TransactionSynchronizationManager.isSynchronizationActive() 的作用
2. TransactionSynchronization 主要包含哪些功能
3. 钩子函数中的程序如果报错了会怎么样





逐一解答：

1. ![image-20241205172231728](https://filestore.lifepoem.fun/know/202412051722779.png)

   代码中可以发现 ThreadLocal类型的静态变量synchronizations 若不为空，则返回true

```java
	private static final ThreadLocal<Set<TransactionSynchronization>> synchronizations =
			new NamedThreadLocal<>("Transaction synchronizations");
```

这个ThreadLocal变量什么时候有的值呢



