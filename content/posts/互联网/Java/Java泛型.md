+++
title = 'Java泛型'

date = 2024-12-23T13:27:48+08:00

categories = ["Java"]

tags = ["泛型"]

+++



本文主要描述JAVA中泛型的使用，内容为多为个人理解，若有不足之处，请不吝赐教。

* 泛型的基本使用
* 泛型的通配符理解
* 泛型的最佳实践

----------
*本文将不讲述泛型的前世今生，仅着重于实际使用*



#### 一 . 泛型的基本使用
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




-------------


#### 三 . 泛型的最佳实践
