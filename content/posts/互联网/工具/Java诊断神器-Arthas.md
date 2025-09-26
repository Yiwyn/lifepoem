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

- 热更新代码

  当生产/测试环境出现了紧急问题，如逻辑判断错误等重大问题，此时为了避免发版对整体在途业务的影响，可以选择热更新







