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



###### Step 1. 原始

先写一个简单的场景，我们创建10w用户，并给10w用户通过反射将手机号附加到用户名上。

```java
    public void step1() throws NoSuchFieldException, IllegalAccessException, NoSuchMethodException, InvocationTargetException {
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

        // 模拟反射调用登陆
        for (User user : list) {
            Class<User> userClass = User.class;
            Method loginMethod = userClass.getDeclaredMethod("login", String.class);
            loginMethod.setAccessible(true);
            Object invoke = loginMethod.invoke(user, user.getUserName());
            user.setLoginStatus((Boolean) invoke);
        }
    }
```

可以得倒火焰图如下：

![image-20251203120506952](https://filestore.lifepoem.fun/know/202512031205027.png)

![image-20251203120540391](https://filestore.lifepoem.fun/know/202512031205432.png)

我们可以看到在方法step1执行的过程中，setAccessible 和 Field.set 的占用是比较高的。整体耗时占比50，其中一半的耗时在反射相关的操作上



###### Step 2.  把耗时的部分抽出来

于是我们第一个优化方案将就有了， 减少上述两个方法的调用。

```java
    public void step2() throws NoSuchFieldException, IllegalAccessException, NoSuchMethodException, InvocationTargetException {
        // 用户集合
        List<User> list = new ArrayList<>();

        // 创建10w个用户，并把给手机号赋值
        for (int i = 0; i < 100_000; i++) {
            User us = new User();
            us.setPhone("" + i);
            list.add(us);
        }
        // 将影响性能的调用抽出来，一次调用
        Class<User> userClass = User.class;
        Field phone = userClass.getDeclaredField("phone");
        phone.setAccessible(true);
        Field userName = userClass.getDeclaredField("userName");
        userName.setAccessible(true);

        // 使用反射将手机号给用户民赋值
        for (User user : list) {
            Object o = phone.get(user);
            userName.set(user, "用户" + o);
        }

        // 将影响性能的调用抽出来，一次调用
        Method loginMethod = userClass.getDeclaredMethod("login", String.class);
        loginMethod.setAccessible(true);
        // 模拟反射调用登陆
        for (User user : list) {
            Object invoke = loginMethod.invoke(user, user.getUserName());
            user.setLoginStatus((Boolean) invoke);
        }

    }
```

重新执行，可以发现反射相关的性能损耗得倒有效的降低。

如下图：

![PixPin_2025-12-07_15-50-48](https://filestore.lifepoem.fun/know/20251207155102864.png)

###### Step 3. 缓存一下

先看一段源码，这个是getDeclaredField方法的实现，我们能看发现从这个方法中获取的Field实例其实是copy出来的，也就是每次使用getDeclaredField 方法总会得到一个新的Field，尽管他们是同一个字段。

![PixPin_2025-12-02_23-04-18](https://filestore.lifepoem.fun/know/20251202230435641.png)

所以就有了大家经常看到的优化方案，各种视频&博客（包括我）都会教大家把Field、Method缓存起来。

于是就有了

```java
private static final Map<Class<?>, Field[]> fieldCache = new ConcurrentHashMap<>();
private static final Map<Class<?>, Method[]> methodCache = new ConcurrentHashMap<>();

public void step3() throws NoSuchFieldException, IllegalAccessException, InvocationTargetException {
    // 用户集合
    List<User> list = new ArrayList<>();

    // 创建10w个用户，并把给手机号赋值
    for (int i = 0; i < 100_000; i++) {
        User us = new User();
        us.setPhone("" + i);
        list.add(us);
    }
    // 将影响性能的调用抽出来，一次调用

		// 模拟使用缓存，实际使用还有偏差
 		Field[] fields = fieldCache.computeIfAbsent(User.class, aClass -> {
            Field[] declaredFields = aClass.getDeclaredFields();
            for (Field declaredField : declaredFields) {
                declaredField.setAccessible(true);
            }
            return declaredFields;
        });
    Field phone = Arrays.stream(fields).filter(p -> p.getName().equals("phone")).findFirst().get();
    Field userName = Arrays.stream(fields).filter(p -> p.getName().equals("userName")).findFirst().get();


    // 使用反射将手机号给用户民赋值
    for (User user : list) {
        Object o = phone.get(user);
        userName.set(user, "用户" + o);
    }
		
    // 模拟缓存
     Method[] methods = methodCache.computeIfAbsent(User.class, aClass -> {
            Method[] declaredMethods = aClass.getDeclaredMethods();
            for (Method declaredMethod : declaredMethods) {
                declaredMethod.setAccessible(true);
            }
            return declaredMethods;
        });
    Method loginMethod = Arrays.stream(methods).filter(m -> m.getName().equals("login")).findFirst().get();

    // 模拟反射调用登陆
    for (User user : list) {
        Object invoke = loginMethod.invoke(user, user.getUserName());
        user.setLoginStatus((Boolean) invoke);
    }
    
}
```

到了这一步，看起来好像都好起来，在将大部分反射耗时操作缓存后效果已经非常明显了。

火焰图如下：





但是我们可不会止步于此～

###### Step 4.   不止于此

作为一个成熟的开发，如何仅仅到了缓存元数据的层面，还不足以称为高效。

众所周知，Java从发布起就有反射，通过反射可以在运行时做一些更加高级操作，但是执行速度慢一直以来是一个大问题。于是Java7开始提供了另一套API **MethodHandle**  

本文简单看一下Methodhandle的优势（后续有机会单独分析讲解）

| 特性                | 传统反射 (Method/Field)  | MethodHandle                 |
| ------------------- | ------------------------ | ---------------------------- |
| 性能                | 低（JIT 难以优化）       | 高（接近原生调用，JIT 友好） |
| 类型安全            | 调用时校验（运行时错误） | 初始化时校验（提前暴露问题） |
| 访问控制            | 粗暴（setAccessible）    | 精细（基于 Lookup 上下文）   |
| 方法适配            | 无（需手动转换）         | 丰富（绑定、转换、组合）     |
| 模块化适配（JDK9+） | 需额外配置 opens         | 天然适配                     |
| 动态语言支持        | 差                       | 优（基于 invokedynamic）     |



于是我们重新将step2的代码优化了一下

```java
public void step00() throws Throwable {
        // 用户集合
        List<User> list = new ArrayList<>();

        // 创建10w个用户，并把给手机号赋值
        for (int i = 0; i < loopSize; i++) {
            User us = new User();
            us.setPhone("" + i);
            list.add(us);
        }
        MethodHandles.Lookup lookup = MethodHandles.lookup();
        // 将影响性能的调用抽出来，一次调用
        Class<User> userClass = User.class;
        Field phone = userClass.getDeclaredField("phone");
        phone.setAccessible(true);
        MethodHandle phoneMethodHandle = lookup.unreflectGetter(phone);
        Field userName = userClass.getDeclaredField("userName");
        userName.setAccessible(true);
        MethodHandle usernameMethodHandle = lookup.unreflectSetter(userName);

        // 使用反射将手机号给用户民赋值
        for (User user : list) {
            Object o = phoneMethodHandle.invoke(user).toString();
            usernameMethodHandle.invoke(user, "用户" + o);
        }

        Method loginMethod = userClass.getDeclaredMethod("login", String.class);
        MethodHandle loginMethodHandle = lookup.unreflect(loginMethod);

        loginMethod.setAccessible(true);
        // 模拟反射调用登陆
        for (User user : list) {
            Object invoke = loginMethodHandle.invoke(user, user.getUserName());
            user.setLoginStatus((Boolean) invoke);
        }

    }
```

优化后，我们来看一下火焰图

![PixPin_2025-12-07_15-52-54](https://filestore.lifepoem.fun/know/20251207155306918.png)

可以看到，多了linkToTargetMehtod的消耗，这个就是使用了MethodHandle的消耗，同时我们发现，step2中也有这个方法消耗，其实Java8中部分场景下反射也会被动的被优化MethodHandle相关。

到了这一步，我们继续使用火焰图来看的性能已经不是非常方便了（可能会因为误差导致误判断，实际上上面的几个step也有可能被其他因素影响），于是我们使用另外的工具进行性能评测。



JMH，我们使用JAVA官方提供的基准性能测试工具来进行接下来的性能比较。如果不了解JMH的读者，可以翻一下以往的文章，或者直接百度 Java JMH

[JMH基准性能测试 | Yiwyn's ~ShenZhi Blog](https://blog.lifepoem.fun/posts/互联网/工具/jmh基准性能测试/)



###### Step 5. 还是不太够

我们已经使用了MethodHandle，这么样才能更快呢，我们发现MethodHandle中还有出了invoke()外还有一个API， invokeExact()，更加精准的调用，我们来看一下两种调用方法的差距

| 特性       | invokeExact                                                  | invoke                                                      |
| ---------- | ------------------------------------------------------------ | ----------------------------------------------------------- |
| 类型匹配   | 严格匹配 `MethodType`（精确到类型、数量、顺序，包括基本类型 / 包装类） | 宽松匹配，自动做类型适配（拆箱 / 装箱、宽化转换、参数重排） |
| 运行时开销 | 无额外适配开销，直接执行目标方法                             | 需动态校验 + 转换类型，有适配开销                           |
| 性能       | 接近原生方法调用（JIT 优化友好）                             | 略低（适配逻辑消耗 CPU）                                    |
| 异常       | 类型不匹配抛 `WrongMethodTypeException`                      | 适配失败才抛异常（如无法转换类型）                          |

于是我们有了接下来一段代码



```java
    
    @Benchmark
    public void step0() {
        // 用户集合
        List<User> list = new ArrayList<>();

        // 创建10w个用户，并把给手机号赋值
        for (int i = 0; i < loopSize; i++) {
            User us = new User();
            us.setPhone("" + i);
            list.add(us);
        }

        // 使用反射将手机号给用户民赋值
        for (User user : list) {
            user.setUserName("用户" + user.getPhone());
        }

        // 模拟反射调用登陆
        for (User user : list) {
            user.login(user.getUserName());
        }
    }
    
    @Benchmark
    public void step00() throws Throwable {
        // 用户集合
        List<User> list = new ArrayList<>();

        // 创建10w个用户，并把给手机号赋值
        for (int i = 0; i < loopSize; i++) {
            User us = new User();
            us.setPhone("" + i);
            list.add(us);
        }
        MethodHandles.Lookup lookup = MethodHandles.lookup();
        // 将影响性能的调用抽出来，一次调用
        Class<User> userClass = User.class;
        Field phone = userClass.getDeclaredField("phone");
        phone.setAccessible(true);
        MethodHandle phoneMethodHandle = lookup.unreflectGetter(phone);
        Field userName = userClass.getDeclaredField("userName");
        userName.setAccessible(true);
        MethodHandle usernameMethodHandle = lookup.unreflectSetter(userName);

        // 使用反射将手机号给用户民赋值
        for (User user : list) {
            Object o = phoneMethodHandle.invoke(user));
            usernameMethodHandle.invoke(user, "用户" + o);
        }

        Method loginMethod = userClass.getDeclaredMethod("login", String.class);
        MethodHandle loginMethodHandle = lookup.unreflect(loginMethod);

        loginMethod.setAccessible(true);
        // 模拟反射调用登陆
        for (User user : list) {
            Object invoke = loginMethodHandle.invoke(user, user.getUserName());
            user.setLoginStatus((Boolean) invoke);
        }

    }

    @Benchmark
    public void step01() throws Throwable {
        // 用户集合
        List<User> list = new ArrayList<>();

        // 创建10w个用户，并把给手机号赋值
        for (int i = 0; i < loopSize; i++) {
            User us = new User();
            us.setPhone("" + i);
            list.add(us);
        }
        MethodHandles.Lookup lookup = MethodHandles.lookup();
        // 将影响性能的调用抽出来，一次调用
        Class<User> userClass = User.class;
        Field phone = userClass.getDeclaredField("phone");
        phone.setAccessible(true);
        MethodHandle phoneMethodHandle = lookup.unreflectGetter(phone);
        Field userName = userClass.getDeclaredField("userName");
        userName.setAccessible(true);
        MethodHandle usernameMethodHandle = lookup.unreflectSetter(userName);

        // 使用反射将手机号给用户民赋值
        for (User user : list) {
            String o = (String) phoneMethodHandle.invokeExact(user);
            usernameMethodHandle.invokeExact(user, "用户" + o);
        }

        Method loginMethod = userClass.getDeclaredMethod("login", String.class);
        MethodHandle loginMethodHandle = lookup.unreflect(loginMethod);

        loginMethod.setAccessible(true);
        // 模拟反射调用登陆
        for (User user : list) {
            boolean invoke = (boolean) loginMethodHandle.invokeExact(user, user.getUserName());
            user.setLoginStatus(invoke);
        }

    }
```



跑过JMH后我们得到一下结果

```shell
Benchmark           Mode  Cnt     Score     Error  Units
ReflectDemo.step0   avgt    5  3196.522 ±  54.193  us/op
ReflectDemo.step00  avgt    5  6626.213 ± 236.807  us/op
ReflectDemo.step01  avgt    5  5996.222 ± 169.852  us/op
```

可以发现，性能提升了大约10%。但是这个远远不及预期。还是需要继续优化（可能大家关注的是百分比，其实还需要关注时间单位us，其实现在已经比较极限了）



Step 6. 最终方案

在上面的案例中，Methodhandle创建是有消耗的，反射也是有消耗的，生成环境不会像测试环境这样每次单独调用，所以我们还是需要使用缓存的形式进行优化

```java
    @Setup
    public void setup00() throws IllegalAccessException, NoSuchMethodException {
        fieldCache.computeIfAbsent(User.class, aClass -> {
            Field[] declaredFields = aClass.getDeclaredFields();
            for (Field declaredField : declaredFields) {
                declaredField.setAccessible(true);
            }
            return declaredFields;
        });

        methodCache.computeIfAbsent(User.class, aClass -> {
            Method[] declaredMethods = aClass.getDeclaredMethods();
            for (Method declaredMethod : declaredMethods) {
                declaredMethod.setAccessible(true);
            }
            return declaredMethods;
        });

        Field[] fields = fieldCache.computeIfAbsent(User.class, aClass -> {
            Field[] declaredFields = aClass.getDeclaredFields();
            for (Field declaredField : declaredFields) {
                declaredField.setAccessible(true);
            }
            return declaredFields;
        });
        Field phone = Arrays.stream(fields).filter(p -> p.getName().equals("phone")).findFirst().get();
        Field userName = Arrays.stream(fields).filter(p -> p.getName().equals("userName")).findFirst().get();


        MethodHandle phoneMethodHandle = lookup.unreflectGetter(phone);

        MethodHandle usernameMethodHandle = lookup.unreflectSetter(userName);

        getterHandleCache.put("phone", phoneMethodHandle);
        setterHandleCache.put("userName", usernameMethodHandle);


        Method loginMethod = User.class.getDeclaredMethod("login", String.class);
        MethodHandle loginMethodHandle = lookup.unreflect(loginMethod);
        getterHandleCache.put("login", loginMethodHandle);

    }


    @Benchmark
    public void step03() throws Throwable {
        // 用户集合
        List<User> list = new ArrayList<>();

        // 创建10w个用户，并把给手机号赋值
        for (int i = 0; i < loopSize; i++) {
            User us = new User();
            us.setPhone("" + i);
            list.add(us);
        }


        MethodHandle phoneMethodHandle = getterHandleCache.get("phone");
        MethodHandle usernameMethodHandle = setterHandleCache.get("userName");
        MethodHandle loginMethodHandle = getterHandleCache.get("login");

        // 使用反射将手机号给用户民赋值
        for (User user : list) {
            String o = (String) phoneMethodHandle.invokeExact(user);
            usernameMethodHandle.invokeExact(user, "用户" + o);
        }

        // 模拟反射调用登陆
        for (User user : list) {
            boolean invoke = (boolean) loginMethodHandle.invokeExact(user, user.getUserName());
            user.setLoginStatus(invoke);
        }

    }
```

在上面的代码中，我将负责的反射，获取MethodHandle等行为都统一放到了setUp中，避免了初始化这些重对象对来的影响。

再来一次JMH！

```shell
Benchmark           Mode  Cnt     Score     Error  Units
ReflectDemo.step0   avgt    5  3343.447 ±  42.489  us/op
ReflectDemo.step00  avgt    5  6415.128 ± 131.741  us/op
ReflectDemo.step01  avgt    5  5868.078 ±  89.074  us/op
ReflectDemo.step03  avgt    5  3903.561 ±  67.826  us/op
```



大获全胜，从上面的代码中，我们知道setp0就是没有反射的写法，换言之就是理想情况下最快的代码，而我们的终版代码，仅仅差距16%。





#### 奇技淫巧

本来文章到这就结束了，但是还有高手，作为一名成熟的开发，大家一定了解MapStruct，它为啥这么快呢？ 接下里的案例借用了其思想，show code。



方案非常简单，我们使用代理增强的思路，UserPlus作为对User的增强，对所有的fileName进行了显式的获取、赋值。

本质也是空间换时间的一个方案。

```java
public class UserPlus extends User {

    public Object get(String fieldName) {
        switch (fieldName) {
            case "userName":
                return this.getUserName();
            case "phone":
                return this.getPhone();
            case "age":
                return this.getAge();
        }
        return null;
    }

    public void set(String fieldName, Object value) {
        switch (fieldName) {
            case "userName":
                this.setUserName((String) value);
                break;
            case "phone":
                this.setPhone((String) value);
                break;
            case "age":
                this.setAge((Integer) value);
                break;
        }
    }
}
```

JHM：

```shell
Benchmark                Mode  Cnt     Score     Error  Units
ReflectDemo.step0        avgt    5  3268.953 ±  30.238  us/op
ReflectDemo.step03       avgt    5  3922.574 ± 108.439  us/op
ReflectDemo.stepPlus  avgt    5  3366.922 ±  35.983  us/op
```

可以看到，极限优化场景下的反射，还是这种增强的方案，这种增强的方案本质上是Java中不使用反射写法的延伸，对反射是降维打击的。



#### 总结

本文通过火焰图🔥，逐步分析排查了反射慢的原因，并且一步步的进行优化，其中不断的进行性能测试，最后得出来近乎于普通开发的速度。

在实际项目中，在需要反射的情况下。

若仅为工具类调用次数很少，推荐直接使用反射。

若作为常用的系统工具类来使用，调用频次非常高，则推荐使用MethodHandle进行优化。

若非常极限的场景，并改动的频次比较少，则推荐上述奇技淫巧方案，实现“零成本”反射。





#### 参考资料

[1] [程序员精进之路：性能调优利器--火焰图 - 知乎](https://zhuanlan.zhihu.com/p/147875569)

[2] [如何读懂火焰图？ - 阮一峰的网络日志](https://www.ruanyifeng.com/blog/2017/09/flame-graph.html)

[3] [秒懂Java之方法句柄(MethodHandle)_java methodhandles-CSDN博客](https://blog.csdn.net/ShuSheng0007/article/details/107066856)

[4] [用上了MethodHandle，妈妈再也不用担心我的反射性能不高了！ - 知乎](https://zhuanlan.zhihu.com/p/23637137020)
