+++
title = 'Java泛型与函数式接口'

date = 2024-12-23T13:27:48+08:00

categories = ["Java"]

tags = ["泛型","函数式接口","Lambda"]

+++



本文主要描述JAVA中泛型和函数式接口的使用，内容为多为个人理解，若有不足之处，请不吝赐教。

* 泛型的基本使用
* 泛型的通配符理解
* 泛型的最佳实践

----------
*本文将不讲述泛型的前世今生，仅着重于实际使用*



#### 一 . 泛型的基本理解

###### 什么是泛型

**泛型**（Generics）是Java语言在JDK 5中引入的一个新特性，它提供了编译时类型安全检测机制，允许程序员在编译时检测到非法的类型。泛型的核心概念是**参数化类型**，即所操作的数据类型被指定为一个参数。这种参数可以用在类、接口和方法的创建中，分别称为泛型类、泛型接口和泛型方法。

###### 为什么推荐使用泛型

- 正确的使用泛型，可以让类型错误在编译阶段暴漏出来，很大程度上可以避免类型转换错误的出现。
- 因为使用了泛型，指定了类型后对对象的操作更加明确（相较于Map<String,Object>或者List<Object>等）
- 因为使用了泛型强调了类型的参与，也就意味着代码的参与者中需要实体类参数，在一定程度上起到了规范的作用，在很大程度上可以提高代码的可修改性和可扩展性

###### 使用场景

结构比较统一的对象，但是某个字段的类型根据业务不用有所差距 

- e.g. 1

```java
package com.yiwyn.demo.api;


import com.yiwyn.demo.domain.User;
import lombok.Data;
import java.io.Serializable;

@Data
public class ApiResposne<T> implements Serializable {
    private static final long serialVersionUID = -931760054084846347L;

    // 请求状态
    private int code;
    // 返回信息
    private String msg;
    // 业务数据
    private T data;
}

// 使用案例，其中ServiceApi为远程服务
class Main {
    public static void main(String[] args) {
        // 获取用户名
        ApiResposne<User> apiResposne = UserServiceApi.getUserById("Yiwyn");
        User data = apiResposne.getData();
        String username = data.getUsername();

        // 获取错误提示
        ApiResposne<String> tipResposne = TipServiceApi.getTipsById("ERROR-9527");
        String tips = tipResposne.getData();
    }
}

```

上述代码中我们可以发现对于data的返回我们是不确定的，但是整体返回的结构我们是确定的，这种场景下我们使用泛型可以让代码更加优雅。

<font color='red'>反面案例</font>

这段代码中最终实现的效果和使用泛型是一致的，代码

```java
package com.yiwyn.demo.api;


import com.yiwyn.demo.domain.User;
import lombok.Data;
import java.io.Serializable;

@Data
public class ApiResposne implements Serializable {
    private static final long serialVersionUID = -931760054084846347L;

    // 请求状态
    private int code;
    // 返回信息
    private String msg;
    // 业务数据
    private Object data;
    // private Map data;
}

// 使用案例
class Main {
    public static void main(String[] args) {
        // 获取用户名
        ApiResposne apiResposne = UserServiceApi.getUserById("Yiwyn");
        User data = (User) apiResposne.getData();
        String username = data.getUsername();
		// Map data = apiResposne.getData();
		// String username = (String) data.get("username");
    }
}
```





泛型（Generic）常见 T U R 等字母，在Java基础库中 **java.util.function** 函数式接口中，大量使用泛型，可从其中观察到Java官方的泛型定义规范。
- 此处以函数式接口展开泛型的使用，不过多描述函数式接口。

----------

e.g. 摘自 **Function** 函数式接口，可以从注释中观察到，<T>定义方法的输入类型;<R>定义方法的返回类型，读者可自行查看其它接口注释，本文不再赘述。
````java 
/**
 * @param <T> the type of the input to the function
 * @param <R> the type of the result of the function
 */
@FunctionalInterface
public interface Function<T, R> {
	//....
}
````


-----------



#### 二 . 泛型的通配符理解

泛型中的通配符 ? 



productor  extends  &  consumer  super



? extends T ： T 以及T的子类的可以传入，限定了传入类的上限

? super T : T 以及T的父类可以传入，限定了传入的下限，最大可至Object



泛型中 <?> <Object> <Type>  如何选择




-------------


#### 三 . 泛型的最佳实践



泛型与Json结合

TypeReference 嵌套泛型









