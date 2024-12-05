+++
title = 'Spring事务'

date = 2024-12-04T15:05:36+08:00

categories = ["Spring"]

tags = ["事务"]

+++



本文将以Spring中事务进行展开，主要讨论以下几点

- 事务
  - 编程式事务

  - 声明式事务

- 事务同步
  - TransactionSynchronizationManager 
    - 事务钩子
    - 事务监听






#### 事务

事务的开启方式

- PlatformTransactionManager  管理事务

  ```java
   public String test() {
  
          DefaultTransactionDefinition def = new DefaultTransactionDefinition();
          def.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
          def.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRED);
  
          // 开始事务
          TransactionStatus status = transactionManager.getTransaction(def);
  
          // 需要在事务前配置事务钩子
          if (TransactionSynchronizationManager.isSynchronizationActive()) {
              TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                  @Override
                  public void afterCompletion(int status) {
                      try {
                          String name = TransactionSynchronizationManager.getCurrentTransactionName();
                          System.out.println("当前事务名：" + name);
                          String a = null;
                          System.out.println("事务状态：" + status);
                      } catch (Exception e) {
                          log.error("钩子函数执行异常:", e);
                      }
                  }
              });
          }
  
          try {
              User u = new User();
              u.setId(1);
              u.setUsername("测试");
              userMapper.insert(u);
              Integer id = u.getId();
  
              transactionManager.commit(status);
          } catch (Exception e) {
              // 异常时回滚事务
              transactionManager.rollback(status);
              throw e; // 继续抛出异常
          }
          return "success";
      }
  ```

- TransactionTemplate

  ```java
  public String demo2() {
          transactionTemplate.execute(new TransactionCallback<Object>() {
              @Override
              public Object doInTransaction(TransactionStatus status) {
  
                  // 需要在事务前配置事务钩子
                  if (TransactionSynchronizationManager.isSynchronizationActive()) {
                      TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                          @Override
                          public void afterCompletion(int status) {
                              try {
                                  String name = TransactionSynchronizationManager.getCurrentTransactionName();
                                  System.out.println("当前事务名：" + name);
                                  String a = null;
                                  System.out.println("事务状态：" + status);
                              } catch (Exception e) {
                                  log.error("钩子函数执行异常:", e);
                              }
                          }
                      });
                  }
  
                  try {
                      User u = new User();
                      u.setId(1);
                      u.setUsername("测试");
                      userMapper.insert(u);
                      Integer id = u.getId();
  
                      transactionManager.commit(status);
                  } catch (Exception e) {
                      // 异常时回滚事务
                      transactionManager.rollback(status);
                      throw e; // 继续抛出异常
                  }
                  return null;
              }
          });
          return "success";
      }
  ```

- 注解@Transactional

  ```java
  @Transactional
  public String test() {
      return demo3();
  }
      
   public String demo3() {
          // 需要在事务前配置事务钩子
          if (TransactionSynchronizationManager.isSynchronizationActive()) {
              TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                  @Override
                  public void afterCompletion(int status) {
                      try {
                          String name = TransactionSynchronizationManager.getCurrentTransactionName();
                          System.out.println("当前事务名：" + name);
                          String a = null;
                          System.out.println("事务状态：" + status);
                      } catch (Exception e) {
                          log.error("钩子函数执行异常:", e);
                      }
                  }
              });
          }
  
          try {
              User u = new User();
              u.setId(1);
              u.setUsername("测试");
              userMapper.insert(u);
              Integer id = u.getId();
          } catch (Exception e) {
              throw new RuntimeException(e); // 继续抛出异常
          }
  
          return "success";
      }    
  
  ```

  大概了解了开始事务的方式，即可进入接下来的环境，开始接触事务同步器





#### 事务同步（器）



##### 事务同步基本使用【三个小问题】

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



----



逐一解答：



###### 问题1

1. ![image-20241205172231728](https://filestore.lifepoem.fun/know/202412051722779.png)

   代码中可以发现 ThreadLocal类型的静态变量synchronizations 若不为空，则返回true

```java
	private static final ThreadLocal<Set<TransactionSynchronization>> synchronizations =
			new NamedThreadLocal<>("Transaction synchronizations");
```

这个ThreadLocal变量什么时候有的值呢，在上文中提到的开启事务的方法中，我们可以看一下他们的源代码。

以@Transactional为例

【注】首先要搞清楚@Transactional注解声明的方法中，事务是如何进行的。此处不展开说明；

事务注解代理的方法执行： org.springframework.transaction.interceptor.TransactionAspectSupport#invokeWithinTransaction

<img src="https://filestore.lifepoem.fun/know/202412052318336.png" alt="image-20241205231821229"  />

看到 PlatformTransactionManager 就很亲切了，无论是手动创建的两种形式还是注解的形式，最终都到了这个工具。进一步探索

![image-20241205231956281](https://filestore.lifepoem.fun/know/202412052319351.png)

看到这个方法则完全的眼熟了，就是编程式事务中我们手写的事务开启的部分。继续下探

![image-20241205232132333](https://filestore.lifepoem.fun/know/202412052321393.png)

终于看到了一个熟悉的名字prepareSynchronization ，进去看下。

![image-20241205232152003](https://filestore.lifepoem.fun/know/202412052321049.png)

果然进行初始化操作

![image-20241205232248749](https://filestore.lifepoem.fun/know/202412052322796.png)

![image-20241205232313690](https://filestore.lifepoem.fun/know/202412052323734.png)

至此，我们isSynchronizationActive()方法终于知道是在什么时候会返回true，使用的时候可以更加大胆。



###### 问题2



TransactionSynchronization 主要包含那些内容，及这些函数是什么时候执行的。

```java
public interface TransactionSynchronization extends Ordered, Flushable {

    /** 事务正确提交时的状态 */
    int STATUS_COMMITTED = 0;

    /** 事务正确回滚时的状态 */
    int STATUS_ROLLED_BACK = 1;

    /** 在混合完成状态或系统错误时的状态 */
    int STATUS_UNKNOWN = 2;


    /**
     * 返回此事务同步的执行顺序。
     * <p>默认返回 {@link Ordered#LOWEST_PRECEDENCE}。
     */
    @Override
    default int getOrder() {
        return Ordered.LOWEST_PRECEDENCE;
    }

    /**
     * 暂停此同步。
     * 如果管理任何资源，应从 TransactionSynchronizationManager 中解绑资源。
     * @see TransactionSynchronizationManager#unbindResource
     */
    default void suspend() {
    }

    /**
     * 恢复此同步。
     * 如果管理任何资源，应重新绑定资源到 TransactionSynchronizationManager。
     * @see TransactionSynchronizationManager#bindResource
     */
    default void resume() {
    }

    /**
     * 刷新底层会话到数据存储，如果适用：
     * 例如，刷新 Hibernate/JPA 会话。
     * @see org.springframework.transaction.TransactionStatus#flush()
     */
    @Override
    default void flush() {
    }

    /**
     * 在事务提交之前调用。
     * 例如，在这里可以将事务性 O/R 映射会话刷新到数据库。
     * <p>此回调并不意味着事务会被提交。
     * 在此方法被调用后，事务仍然有可能回滚。此回调主要用于执行一些只在提交时相关的操作，
     * 例如将 SQL 语句刷新到数据库。
     * <p>注意，如果在此方法中抛出异常，事务将会回滚。
     * @param readOnly 事务是否为只读事务
     * @throws RuntimeException 如果出现错误，会被抛到调用者
     * @see #beforeCompletion
     */
    default void beforeCommit(boolean readOnly) {
    }

    /**
     * 在事务提交/回滚之前调用。
     * 用于在事务完成之前进行资源清理工作。
     * <p>此方法会在 {@code beforeCommit} 后被调用，即使 {@code beforeCommit} 抛出了异常。
     * 这使得可以在事务完成之前进行资源清理。
     * @throws RuntimeException 如果出现错误，会被记录但不会传播
     * @see #beforeCommit
     * @see #afterCompletion
     */
    default void beforeCompletion() {
    }

    /**
     * 事务成功提交后调用。
     * 可以在此处执行进一步的操作，如发送确认消息或电子邮件等。
     * <p>注意：事务已经提交，但事务资源仍然处于活动状态，因此任何在这里调用的数据访问代码，
     * 仍然会“参与”原事务中，除非明确声明需要运行在独立的事务中。
     * 因此：对于从此处调用的事务操作，使用 {@code PROPAGATION_REQUIRES_NEW}。
     * @throws RuntimeException 如果出现错误，会被抛到调用者
     */
    default void afterCommit() {
    }

    /**
     * 在事务提交/回滚之后调用。
     * 用于执行事务完成后的资源清理工作。
     * <p>注意：事务已经提交或回滚，但事务资源仍然处于活动状态，因此在此处调用的数据访问代码，
     * 仍然会“参与”原事务中，除非明确声明需要运行在独立事务中。
     * 因此：对于从此处调用的事务操作，使用 {@code PROPAGATION_REQUIRES_NEW}。
     * @param status 根据 {@code STATUS_*} 常量，事务的完成状态
     * @throws RuntimeException 如果出现错误，会被记录但不会传播
     * @see #STATUS_COMMITTED
     * @see #STATUS_ROLLED_BACK
     * @see #STATUS_UNKNOWN
     * @see #beforeCompletion
     */
    default void afterCompletion(int status) {
    }

}

```



执行位置，到了执行位置，由于我们之前找了初始化synchronizations 的经历，再来查找具体的执行位置就简单很多。还是以最复杂的注解事务来说明。

老地方：org.springframework.transaction.interceptor.TransactionAspectSupport#invokeWithinTransaction

【注】此处仅找一个作为提供思路

![image-20241205233116480](https://filestore.lifepoem.fun/know/202412052331549.png)



![image-20241205233152601](https://filestore.lifepoem.fun/know/202412052331653.png)



![image-20241205233240880](https://filestore.lifepoem.fun/know/202412052332941.png)

![image-20241205233337149](https://filestore.lifepoem.fun/know/202412052333207.png)



###### 问题三

这个问题其实在问题二的注释中已经有了体现，此说简单按上图举例。

![image-20241205233611612](https://filestore.lifepoem.fun/know/202412052336671.png)

![image-20241205233630447](https://filestore.lifepoem.fun/know/202412052336495.png)



可以看到不同的函数对于报错的处理方式是不同的。造成的后果当然也不相同。谨慎使用...







##### 事务监听器

基于Spirng自身的事件发布监听能力实现；

Q： 我们为什么需要使用这种形式的事务监听

A：如果我们大量的重复的逻辑如发送通知，在事务提交后，我们需要在大量的位置添加大量的代码，侵入性过强（虽然事件发布也有侵入），使用事件发布监听机制，我们只需要设置一处监听，即可对所有发布事件进行回应。

showCode 【Spring ApplicationEventPublisher 并不复杂，此处不赘述】



创建监听器

 @TransactionalEventListener 针对事务的监听，区别于普通的监听@EventListener；

```java
package com.yiwyn.demo.event;

import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.stereotype.Component;

@Slf4j(topic = "事务监听器")
@Component
public class MyTransactionEventListener {


    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)  // 事务提交后触发
    public void handleTransactionCommit(MyTransactionEvent event) {
        log.info("事务提交:{}", event.getMessage());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_ROLLBACK)  // 事务回滚后触发
    public void handleTransactionRollback(MyTransactionEvent event) {
        System.out.println("Transaction rolled back: " + event.getMessage());
        log.error("事务进行了回滚:{}", event.getMessage());
    }
}

```

既然是事件，那么携带的消息也可以手动创建；我们可以发现，其实这个ApplicationEvent的实现就是监听器方法的入参，这两者是绑定的。

```java
package com.yiwyn.demo.event;

import lombok.Getter;
import org.springframework.context.ApplicationEvent;

@Getter
public class MyTransactionEvent extends ApplicationEvent {

    private static final long serialVersionUID = 6829841024745232695L;
    private final String message;


    public MyTransactionEvent(Object source, String message) {
        super(source);
        this.message = message;
    }

}
```



剩下了最重要的发布环节，在执行demo4Listener时就会发布事件，同时根据事务的动作触发不同的监听器。

```java
 
  @Autowired
    private ApplicationEventPublisher applicationEventPublisher;
 
 // ... 
 
  @Transactional
  public String test() {
      return demo4Listener();
  }
 
 public String demo4Listener() {
        // 需要在事务前配置事务钩子
        applicationEventPublisher.publishEvent(new MyTransactionEvent(this,"demo4操作事务"));
        try {
            User u = new User();
            u.setId(1);
            u.setUsername("测试");
            userMapper.insert(u);
            Integer id = u.getId();
        } catch (Exception e) {
            throw new RuntimeException(e); // 继续抛出异常
        }

        return "success";
    }
```





