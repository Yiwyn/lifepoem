+++
title = 'Java诊断神器 Arthas'

date = 2025-09-26T14:11:25+08:00

categories = ["Java"]

tags = ["Arthas","测试","诊断","Java"]

+++



### Java诊断神器-Arthas的常用命令指南





> ###### [arthas](https://arthas.aliyun.com/) 
>
> ##### Arthas 是一款线上监控诊断产品，通过全局视角实时查看应用 load、内存、gc、线程的状态信息，并能在不修改应用代码的情况下，对业务问题进行诊断，包括查看方法调用的出入参、异常，监测方法执行耗时，类加载信息等，大大提升线上问题排查效率。





#### retransform

加载指定的 .class 文件，然后解析出 class name，再 retransform jvm 中已加载的对应的类。每加载一个 `.class` 文件，则会记录一个 retransform entry.

【解释】可以在运行中的服务中，动态加载`.class`文件到jvm中，从而达成热更新的效果。同时每次加载后arthas中会存在记录。

> [retransform | arthas](https://arthas.aliyun.com/doc/retransform.html)

##### 使用场景：

###### 热更新代码

当生产/测试环境出现了紧急问题，如逻辑判断错误等重大问题，此时为了避免发版对整体在途业务的影响，可以选择热更新进行错误逻辑的修复。（以下流程针对官方文档进行简单摘要）

1. 对需要修改的类进行修改，修改完成后本地进行编译 maven package，得倒`.class`文件

2. 将`.class`文件上传到目标服务器

3. 使用arthas attach目标Java服务进程

4. ```shell
   # /tmp/Test.class 是步骤2中服务中的class文件的位置
   retransform /tmp/Test.class 
   ```

5. 卸载修改的class<font color='red'>（补充）</font>

   ```shell
   # 查看被重载的class
   retransform -l 
   # 根据id删除对应的retransform entry
   retransform -d 1
   # 重新retransform这个类
   retransfrom --classPattern xx.xxx.Test
   ```

   

> 原理参考文档
>
> [Java动态追踪技术探究 - 美团技术团队](https://tech.meituan.com/2019/02/28/java-dynamic-trace.html)



