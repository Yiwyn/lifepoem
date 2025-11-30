+++
title = 'Effective Reflect-高效反射'

date = 2025-11-23T16:51:08+08:00

categories = ["Java"]

tags = ["反射","MethodHandle"]

+++



### 高效Java反射方案



> 文章背景：在日常的开发工作中，反射的应用出现的越来越多，尽管目前反射带来的性能损耗还没有特别明显，但是针对反射行为的优化方案还是必须掌握。
>
> 本文将以JDK1.8为背景，展开讨论反射（类反射）行为的优化方案。
>
> 需要注意！ 本文默认读者对反射已经较为熟悉。





#### 火焰图（Flame Graphs）

> 在开始之前我们先了解一下火焰图，后续的优化跟进将从火焰图出发。



<img src="https://pica.zhimg.com/v2-47c4c8352b1a719960a3d17acd26581e_1440w.jpg" alt="img" style="zoom:67%;" />



火焰图以一个全局的视野来看待时间分布，它从底部往顶部，列出所有可能导致性能瓶颈的调用栈。

###### 特征

- 每一列代表一个调用栈，每一个格子代表一个函数
- 纵轴展示了栈的深度，按照调用关系从下到上排列。最顶上格子代表采样时，正在占用 cpu 的函数。
- 横轴的意义是指：火焰图将采集的多个调用栈信息，通过按字母横向排序的方式将众多信息聚合在一起。需要注意的是它并不代表时间。
- 横轴格子的宽度代表其在采样中出现频率，所以一个格子的宽度越大，说明它是瓶颈原因的可能性就越大。
- 火焰图格子的颜色是随机的暖色调，方便区分各个调用信息。

###### 分析技巧

- 纵轴代表调用栈的深度（栈桢数），用于表示函数间调用关系：下面的函数是上面函数的父函数。

- 横轴代表调用频次，一个格子的宽度越大，越说明其可能是瓶颈原因。

- 不同类型火焰图适合优化的场景不同，比如 on-cpu 火焰图适合分析 cpu 占用高的问题函数，off-cpu 火焰图适合解决阻塞和锁抢占问题。

- 无意义的事情：横向先后顺序是为了聚合，跟函数间依赖或调用关系无关；火焰图各种颜色是为方便区分，本身不具有特殊含义



<font color='red'>本文不会就火焰图相关展开太多，以上内容足够接下来的内容，想要了解具体内容，可关注【参考资料】节点。</font>



#### 反射优化之道

尽管我们都知道，反射是耗费性能的，但是还是需要分析具体慢在哪一步，从而逐步优化。

先写一个简单的场景，我们创建10w用户，并给10w用户通过反射将手机号附加到用户名上。

```java
public void step1() throws NoSuchFieldException, IllegalAccessException {
    // 用户集合
    List<User> list = new ArrayList<>();

    // 创建10w个用户，并把给手机号赋值
    for (int i = 0; i < 100_000; i++) {
        User us = new User();
        us.setPhone("" + i);
        list.add(us);
    }

    // 使用反射将手机号给用户民赋值
    for (User user : list) {
        Class<User> userClass = User.class;
        Field phone = userClass.getDeclaredField("phone");
        phone.setAccessible(true);
        Object o = phone.get(user);
        Field userName = userClass.getDeclaredField("userName");
        userName.setAccessible(true);
        userName.set(user, "用户" + o);
    }
}
```











#### 参考资料

[1] [程序员精进之路：性能调优利器--火焰图 - 知乎](https://zhuanlan.zhihu.com/p/147875569)

[2] [如何读懂火焰图？ - 阮一峰的网络日志](https://www.ruanyifeng.com/blog/2017/09/flame-graph.html)
