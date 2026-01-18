+++
title = 'Mybatis中MapperXML在Srping中动态加载设计'

date = 2026-01-18T04:13:32+08:00

categories = ["Spring"]

tags = ["Mybatis","Spring"]

+++





### Mybatis中MapperXML在Srping中动态加载设计





> 背景：现在市面上大多数系统使用的是MyBatis作为ORM层框架，在开发的过程中，作为数据库和JavaEntity映射的Mapper.xml（或称Dao.xml文件，以下统一简称Mapper文件）文件则至关重要。
>
> 随着项目的不断迭代更新，Mapper文件的管理维护慢慢的变得复杂起来，于是在项目交付的几个环节我们总是能碰到以下问题：
>
> 1. 在测试阶段，若测试环境Mapper.xml文件有误，但是重新打包发版需要大量时间，且多系统之间交互会因为发版重启出现问题。
> 2. 在生产阶段，若Mapper.xml文件有误，若无法避开，则是死局，只能重新发版，问题会比测试环境发版更加严重

