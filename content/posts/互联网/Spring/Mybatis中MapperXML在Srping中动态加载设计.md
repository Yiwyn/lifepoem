+++
title = 'Mybatis中MapperXML在Spring中动态加载设计'

date = 2026-01-18T04:13:32+08:00

categories = ["Spring"]

tags = ["Mybatis","Spring"]

+++





### Mybatis中MapperXML在Spring中动态加载设计





> 背景：现在市面上大多数系统使用的是MyBatis作为ORM层框架，在开发的过程中，作为数据库和JavaEntity映射的Mapper.xml（或称Dao.xml文件，以下统一简称Mapper文件）文件则至关重要。
>
> 随着项目的不断迭代更新，Mapper文件的管理维护慢慢的变得复杂起来，于是在项目交付的几个环节我们总是能碰到以下问题：
>
> 1. 在测试阶段，若测试环境Mapper.xml文件有误，但是重新打包发版需要大量时间，且多系统之间交互会因为发版重启出现问题。
> 2. 在生产阶段，若Mapper.xml文件有误，若无法避开，则是死局，只能重新发版，问题会比测试环境发版更加严重。
>
> 基于以上考量，为了事后补偿保障（本文不涉及事前检查），于是就有了本次的设计探讨。



#### 设计目标

- 提供外置加载Mapper XML的入口
- 不能对现有系统正常运行产生影响
- 使用足够简单



#### 方案

参考Mybatis项目启动加载Mapper文件的方式，开放一套运行时加载方案。只需要开放一个方法，传入指定路径即可重新加载对应的XML配置。

有了这个开放的方法，那么无论是API形式调用，还是其他形式调用，都可以满足设计目标



#### 设计过程

1. 参考源代码，我们首先找到加载mapper的配置，点击进入到 MybatisProperties.java

![image-20260118191222888](https://filestore.lifepoem.fun/know/20260118191233230.png)

2. 循着mapperLocations使用的位置，发现了这个方法

   ![image-20260118191349428](https://filestore.lifepoem.fun/know/20260118191349467.png)

3. 接着从第二步找到的方法，我们跳转到了 MybatisAutoConfiguration，Spring需要SqlSessionFactory的Bean，熟悉Spring的同学就比较了解了，这里的factory 类型为`SqlSessionFactoryBean` ，再往下看就能看到FactoryBean接口中提供的方法。Mybatis的初始化就发生在这里面，由`SqlSessionFactoryBean`创建SqlSessionFactory的Springbean。![image-20260118191549272](https://filestore.lifepoem.fun/know/20260118191549302.png)

![image-20260118193340984](https://filestore.lifepoem.fun/know/20260118193341017.png)



4. 深入了解一下factroy.getObject()，一路下探找到了 SqlSessionFactory 构建的地方

![image-20260118193550906](https://filestore.lifepoem.fun/know/20260118193550937.png)

![image-20260118193605801](https://filestore.lifepoem.fun/know/20260118193605831.png)



5. 在 buildSqlSessionFactory 中寻找步骤2中 mapperLocations的使用的位置，代码如下

   ![image-20260118193839195](https://filestore.lifepoem.fun/know/20260118193839220.png)



到了这一步，就是我们最熟悉的领域了，CV走起



代码如下：

```java
public void refreshExternalMapperByMyBatisNative(String mapperPath) throws NestedIOException {
    /**
     * 参考mybatis源码
     * @see SqlSessionFactoryBean#buildSqlSessionFactory()
     * @see org.mybatis.spring.boot.autoconfigure.MybatisProperties#resolveMapperLocations()
     */

    Resource[] mapperLocations = Stream.of(Optional.of(new String[]{mapperPath}).orElse(new String[0]))
            .flatMap(location -> Stream.of(getResources(location))).toArray(Resource[]::new);


    // 获取bean （对应上面的 buildSqlSessionFactory ）
    SqlSessionFactory bean = applicationContext.getBean(SqlSessionFactory.class);


    /**
     * @see /Users/yiwyn/dev-tools/maven-repository/org/mybatis/mybatis-spring/2.0.7/mybatis-spring-2.0.7-sources.jar!/org/mybatis/spring/SqlSessionFactoryBean.java:624
     */
    Configuration configuration = bean.getConfiguration();

    /**
     * /Users/yiwyn/dev-tools/maven-repository/org/mybatis/mybatis-spring/2.0.7/mybatis-spring-2.0.7-sources.jar!/org/mybatis/spring/SqlSessionFactoryBean.java:600
     */
    if (mapperLocations.length == 0) {
        // LOGGER.warn(() -> "Property 'mapperLocations' was specified but matching resources are not found.");
        System.out.println("没有检查到文件");
    } else {
        for (Resource mapperLocation : mapperLocations) {
            if (mapperLocation != null) {
                try {
                    XMLMapperBuilder xmlMapperBuilder = new XMLMapperBuilder(mapperLocation.getInputStream(), configuration, mapperLocation.toString(), configuration.getSqlFragments());
                  
                    xmlMapperBuilder.parse();
                } catch (Exception e) {
                    throw new NestedIOException("Failed to parse mapping resource: '" + mapperLocation + "'", e);
                } finally {
                    ErrorContext.instance().reset();
                }
                System.out.println("Parsed mapper file: '" + mapperLocation + "'");
            }
        }
    }
}
```



#### 解决问题

##### 问题一：重复加载时提示already contains 相关问题

我们的初版代码设计好后，来试验一下，很快就出新了第一个问题

![image-20260118195610014](https://filestore.lifepoem.fun/know/20260118195610062.png)

大概意思是说这个配置文件已经加载过了，不能重复添加。这个问题比较好处理，添加之前先处理掉。

 xmlMapperBuilder.parse(); 方法中configurationElement方法会添加各种mapper文件中的元素

![image-20260118195813350](https://filestore.lifepoem.fun/know/20260118195813369.png)

再往下看，会发现最中这些Mapper中解析到的数据会被缓存到如下的map中，其中`StrictMap`是Mybatis自己实现的Map，也就是不允许我们重复插入的根源。![image-20260118200256035](https://filestore.lifepoem.fun/know/20260118200256062.png)

![image-20260118200312144](https://filestore.lifepoem.fun/know/20260118200312184.png)



所以我们添加清理重复MapperConfig的操作，代码如下，以下为完整代码。

```java
package com.yiwyn.hotxml.boot.utils;

import lombok.extern.slf4j.Slf4j;
import org.apache.ibatis.builder.xml.XMLMapperBuilder;
import org.apache.ibatis.builder.xml.XMLMapperEntityResolver;
import org.apache.ibatis.executor.ErrorContext;
import org.apache.ibatis.parsing.XNode;
import org.apache.ibatis.parsing.XPathParser;
import org.apache.ibatis.session.Configuration;
import org.apache.ibatis.session.SqlSessionFactory;
import org.mybatis.spring.SqlSessionFactoryBean;
import org.springframework.context.ApplicationContext;
import org.springframework.context.ApplicationContextAware;
import org.springframework.core.NestedIOException;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.core.io.support.ResourcePatternResolver;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.Iterator;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Stream;


@Slf4j
@Component
public class MyBatisHotReloadUtils implements ApplicationContextAware {

    // Spring应用上下文（用于获取SqlSessionFactory Bean）
    private static ApplicationContext applicationContext;


    @Override
    public void setApplicationContext(ApplicationContext applicationContext) {
        MyBatisHotReloadUtils.applicationContext = applicationContext;
    }

    public void refreshExternalMapperByMyBatisNative() throws NestedIOException {
        // 配置外部加载的路径
        String path = "file:/Users/yiwyn/IdeaProjects/spring-demo/mybatis-xml-hot-demo/hot-xml/*Mapper.xml";
        refreshExternalMapperByMyBatisNative(path);
    }

    public void refreshExternalMapperByMyBatisNative(String mapperPath) throws NestedIOException {
        /**
         * 参考mybatis源码
         * @see SqlSessionFactoryBean#buildSqlSessionFactory()
         * @see org.mybatis.spring.boot.autoconfigure.MybatisProperties#resolveMapperLocations()
         */

        Resource[] mapperLocations = Stream.of(Optional.of(new String[]{mapperPath}).orElse(new String[0]))
                .flatMap(location -> Stream.of(getResources(location))).toArray(Resource[]::new);


        // 获取bean （对应上面的 buildSqlSessionFactory ）
        SqlSessionFactory bean = applicationContext.getBean(SqlSessionFactory.class);


        /**
         * @see /Users/yiwyn/dev-tools/maven-repository/org/mybatis/mybatis-spring/2.0.7/mybatis-spring-2.0.7-sources.jar!/org/mybatis/spring/SqlSessionFactoryBean.java:624
         */
        Configuration configuration = bean.getConfiguration();

        /**
         * /Users/yiwyn/dev-tools/maven-repository/org/mybatis/mybatis-spring/2.0.7/mybatis-spring-2.0.7-sources.jar!/org/mybatis/spring/SqlSessionFactoryBean.java:600
         */
        if (mapperLocations.length == 0) {
            // LOGGER.warn(() -> "Property 'mapperLocations' was specified but matching resources are not found.");
            System.out.println("没有检查到文件");
        } else {
            for (Resource mapperLocation : mapperLocations) {
                if (mapperLocation != null) {
                    try {
                        XMLMapperBuilder xmlMapperBuilder = new XMLMapperBuilder(mapperLocation.getInputStream(), configuration,mapperLocation.toString(), configuration.getSqlFragments());

                        XPathParser xPathParser = new XPathParser(mapperLocation.getInputStream(), true, configuration.getVariables(), new XMLMapperEntityResolver());

                        XNode xNode = xPathParser.evalNode("/mapper");
                        String namespace = xNode.getStringAttribute("namespace");
                        System.out.println("重新加载mybatis：" + namespace);

                        // 先清除已有的数据
                        /**
                         * 为什么需要清除，而不是自动覆盖 因为mybatis创建了strictMap，添加重复的key自动报错
                         * @see Configuration.StrictMap
                         */
                        clearDuplicateMapperConfig(configuration, namespace);

                        xmlMapperBuilder.parse();
                    } catch (Exception e) {
                        throw new NestedIOException("Failed to parse mapping resource: '" + mapperLocation + "'", e);
                    } finally {
                        ErrorContext.instance().reset();
                    }
                    System.out.println("Parsed mapper file: '" + mapperLocation + "'");
                }
            }
        }
    }

    private Resource[] getResources(String location) {
        try {
            ResourcePatternResolver resourceResolver = new PathMatchingResourcePatternResolver();
            return resourceResolver.getResources(location);
        } catch (IOException e) {
            return new Resource[0];
        }
    }

    private void clearDuplicateMapperConfig(Configuration configuration, String namespace) {

        // 4. 修正核心：清空该namespace下的SqlFragment（返回Map<String, XNode>，遍历key集移除）
        Map<String, XNode> sqlFragments = configuration.getSqlFragments();
        // 迭代器遍历（避免Map遍历过程中修改引发ConcurrentModificationException）
        Iterator<String> fragmentKeyIterator = sqlFragments.keySet().iterator();
        while (fragmentKeyIterator.hasNext()) {
            String fragmentKey = fragmentKeyIterator.next();
            // 匹配namespace + "." 前缀，移除该mapper对应的所有SQL片段
            if (fragmentKey.startsWith(namespace + ".")) {
                fragmentKeyIterator.remove(); // 安全移除，不会触发并发修改异常
            }
        }

        configuration.getResultMaps().removeIf(rm -> rm.getId().startsWith(namespace + "."));

        configuration.getParameterMaps().removeIf(pm -> pm.getId().startsWith(namespace + "."));

        configuration.getMappedStatements().removeIf(ms -> ms.getId().startsWith(namespace + "."));

        configuration.getCaches().removeIf(cache -> cache.getId().startsWith(namespace + "."));

        System.out.println("已清空namespace [" + namespace + "] 下的所有旧配置，准备加载新配置");
    }
}
```



##### 问题二：加载一次之后，再次加载却无法生效了

答案非常简单，由于没有 loadedResources 没有提供remove相关的api，同时作为热加载使用场景比较少。

![image-20260118202258010](https://filestore.lifepoem.fun/know/20260118202258039.png)

这个给出解决方案是在创建`XMLMapperBuilder`的时候传入的 resource添加UUID作为唯一标识。

```java
 // resource 细节添加UUID, 防止被认定为已加载资源
                        XMLMapperBuilder xmlMapperBuilder = new XMLMapperBuilder(mapperLocation.getInputStream(), configuration, UUID.randomUUID() + mapperLocation.toString(), configuration.getSqlFragments());
```



#### 实战操作

故意写错insertSelective方法，执行插入报错。

![image-20260118202603993](https://filestore.lifepoem.fun/know/20260118202604035.png)

![image-20260118202647155](https://filestore.lifepoem.fun/know/20260118202647199.png)



这个时候操作热更新替换没有问题的XML配置，重新插入问题解决，并且无论重复插入多少次可以正常生效。

![image-20260118202721521](https://filestore.lifepoem.fun/know/20260118202721576.png)

![image-20260118202801842](https://filestore.lifepoem.fun/know/20260118202801899.png)
