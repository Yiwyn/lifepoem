+++
title = 'Java泛型实战'

date = 2024-12-23T13:27:48+08:00

categories = ["Java"]

tags = ["泛型"]

+++



本文主要描述JAVA中泛型和函数式接口的使用，内容为多为个人理解，若有不足之处，请不吝赐教。泛型和函数式接口是Java中非常重要的特性，掌握它们可以帮助我们编写更加灵活和安全的代码。

* 泛型的基本使用
* 泛型的通配符理解
* 泛型的最佳实践

----------
*本文将不讲述泛型的前世今生，仅着重于实际使用*



#### 一 . 泛型的基本理解

###### 什么是泛型

**泛型**（Generics）是Java语言在JDK 5中引入的一个新特性，它提供了编译时类型安全检测机制，允许程序员在编译时检测到非法的类型。泛型的核心概念是**参数化类型**，即所操作的数据类型被指定为一个参数。这种参数可以用在类、接口和方法的创建中，分别称为泛型类、泛型接口和泛型方法。

###### 为什么推荐使用泛型

- 正确使用泛型，可以让类型错误在编译阶段暴露出来，很大程度上可以避免类型转换错误的出现。
- 因为使用了泛型，指定了类型后对对象的操作更加明确（相较于`Map<String,Object>`或者`List<Object>`等）
- 因为使用了泛型强调了类型的参与，也就意味着代码的参与者中需要实体类参数，在一定程度上起到了规范的作用，在很大程度上可以提高代码的可修改性和可扩展性
- 我们在做软件工程实践的时候，一直在强调，尽量把风险暴露在前面，能够编译期去检查的错误就不要放在运行期进行检查，Java中泛型出现的概念就是提前去暴露问题暴露风险

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

这段代码最终实现的效果和使用泛型一致，但将类型转换移到了运行时，增加了风险。

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



###### 伪泛型、真泛型

首先明确一点，Java使用的是伪泛型，实际类型其实是Object。



伪泛型：Java中的泛型是伪泛型。泛型只在源码中存在，在编译后的字节码文件中，就已经替换为原来的原生类型（Raw Type，也称裸类型）了，并且在相应的地方插入了强制转型代码。因此，在Java程序的运行期中，`ArrayList<Integer>`和`ArrayList<String>`就是同一个类。这种泛型实现方法称为**类型擦除** ，基于这种方法实现的泛型称为**伪泛型**。

```java
// 类型擦除示例
public class Box<T> {
    private T t;

    public void set(T t) {
        this.t = t;
    }

    public T get() {
        return t;
    }
}

// 编译后
public class Box {
    private Object t;

    public void set(Object t) {
        this.t = t;
    }

    public Object get() {
        return t;
    }
}
```



真泛型：泛型无论在源码、编译后还是运行期都是真实存在，例如List< Integer >和List< String >就是两个不同的类型，它们在系统运行期生成，有自己的虚方法表和类型数据，这种实现称为**类型膨胀**，基于这种方法实现的泛型称为**真实泛型**。C#中的泛型就是真实泛型。



泛型（Generic）常见 T U R 等字母，在Java基础库中 **java.util.function** 函数式接口中，大量使用泛型，可从其中观察到Java官方的泛型定义规范。

- 此处以函数式接口展开泛型的使用，不过多描述函数式接口。

----------

e.g. 摘自 **Function** 函数式接口，可以从注释中观察到，`<T>`定义方法的输入类型;<R>定义方法的返回类型，读者可自行查看其它接口注释，本文不再赘述。
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



###### 三种通配符

- 无限定通配符；`<?>` ，可代表所有的类型
- 上边界限定通配符；`<? extends Type>`，可以传入Type以及Type的子类型
- 下边界限定通配符；`<? super Type>`，可以传入Type以及Type的父类型



![image-20241227163347248](https://filestore.lifepoem.fun/know/202412271633349.png)



###### 通配符使用场景

<font color='red'>Producer Extends, Consumer Super</font>

PECS

即，生产者使用 extends，消费者使用super

这里需要理解两个点

- 生产者和消费者如何定义

- 为什么生产者和消费者要区分通配符



生产者和消费者如何定义

其中对于生产者和消费者的理解是比较抽象的，要理解这个概念我们选择List进行举例，其中以List为第一人称。

生产者，产出对象，即List产生对象，对应逻辑即是 List.get(index)

消费者，消费对象，即List消费对象，对应逻辑即是 List.add(Element)

```java
    public static void main(String[] args) {
       
        List<Animal> elements = new ArrayList<>();
        // 这里从elements中获取到了Animal,可以理解为elements作为生产者提供了一个Animal元素

        Animal animal = elements.get(0);
        // 这里elements添加了一个元素，可以理解为elements消费了一个元素
        elements.add(new Animal());

    }
```

以上述为基础，进行扩展PECS概念

```java
public static void animalDeal(Animal animal) {
        // 这段代码可以正常执行，在使用super的情况下，对象可以正常进行消费行为
        List<? super Animal> animals = new ArrayList<>();
        animals.add(animal);

        // 这段代码使用 animals，animals作为生产者
        for (Object o : animals) {
            // 获取到的是Object ?
        }


        // ========================= 华丽的分割线 ===========================

        // 这段代码会报错，在使用extends的场景中，对象不允许进行消费行为
        List<? extends Animal> animalsExt = new ArrayList<>();
        animalsExt.add(animal);

        // 这段代码使用 animalsExt,animalsExt作为生产者，是可以正常遍历animal元素的，符合producer
        for (Animal animal1 : animalsExt) {
            animal1.call();
        }
    }
```

从上述demo中，我们可以得出以下结论

- 在使用super时，对象作为消费者，可以正常的消费对象 
- 在使用super时，对象作为生产者，获取到的对象是Object，真正使用需要我们强转，实际意义不大

- 在使用extends时，对象作为消费者，不能消费对象 *
  - 为什么不能消费呢，首先我们可以确定 ? extends Animal ， 可以包含Dog、Cat类，如果可以消费的话，这也就意味着，这个List可以消费Dog、Cat，这个时候就有了问题，`List<Dog>`和 `List<Cat>` 可以说是完全不同的两个List，编译器无法确定我们实际给到的列表类型。【本质都是Java的语法约束】
- 在使用extends时，对象作为生产者，可以正常获取到标识的泛型类型，正常使用



泛型中 `<?>` `<Object>` `<Type>`  如何选择



**具体类型参数**（如 `<Animal>`）优先级最高，因为它指定了具体的类型。

**通配符**（`<?>`）通常用于类型不明确的场景，具有灵活性但有限制。使用了`<?>`的对象是只读的，不可进行修改

**`Object`** 是最宽泛的类型，可以作为一个类型的上限，但通常是最后的选择

~~不写建议直接打死~~ 不写其实并没有什么问题，默认会使用Object，但是IDE会警告，同时也违背了使用泛型的初衷。




-------------


#### 三 . 泛型的实践



###### TypeReference 

泛型与Json结合使用，TypeReference 类型引导

```java
package com.yiwyn;

import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.TypeReference;
import lombok.AllArgsConstructor;
import lombok.Data;

public class Main {
    public static void main(String[] args) {

        ApiResponse<Person> apiResponse = new ApiResponse<>();
        apiResponse.setCode(0);
        apiResponse.setMsg("success");
        apiResponse.setData(new Person("Yiwyn", 18));

        String responseJson = JSON.toJSONString(apiResponse);
        // {"code":0,"data":{"age":18,"name":"Yiwyn"},"msg":"success"}

        // 方案1（错误方案） 谈笑风生间把嵌套的泛型抹去了 ApiResponse<Person> => ApiResponse
        ApiResponse apiResponse1 = JSON.parseObject(responseJson, ApiResponse.class);
        Object data = apiResponse1.getData();
        Person p = (Person) data;
        /*
           这里直接转会报错 原因如下
            data 字段的类型信息丢失了。
            这是因为 Java 的泛型在运行时会被擦除（Type Erasure），
            导致 ApiResponse 中的 T 类型信息在运行时无法被保留。
         */
        System.out.println(p);

        // 方案2 使用 TypeReference
        ApiResponse<Person> personApiResponse = JSON.parseObject(responseJson, new TypeReference<ApiResponse<Person>>() {
        });
        Person data1 = personApiResponse.getData();
        System.out.println(data1);
    }

    @Data
    public static class ApiResponse<T> {
        private Integer code;
        private String msg;
        private T data;
    }

    @Data
    @AllArgsConstructor
    public static class Person {
        private String name;
        private Integer age;
    }
    
}
```









