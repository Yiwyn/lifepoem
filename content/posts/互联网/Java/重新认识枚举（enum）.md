+++
title = '重新认识枚举（enum）'
date = 2026-04-02T14:48:15+08:00
categories = ["Java"]
tags = ["枚举","Enum"]
draft = false
+++

### 重新认识枚举（Enum）

> 背景：枚举一直以来是我们常用的常量、状态定义工具。相比于直接使用`int`或者`String`常量，枚举往往更加安全、直观并且更加容易扩展。
> 为什么提到重新认识枚举？在日常的开发中，我们发现很多场景下枚举(enum)和常量(constant)存在大量混用的情况，尽管功能是实现了，但是后期的扩展和阅读都存在很多问题。
> 本文将会把枚举相关的知识点做一个重新整理，包括一些进阶用法作实例展示。
> 
> 本文使用 JDK17

#### 从零开始看枚举

##### 1. 枚举的基础语法

在Java中，枚举使用`enum`关键字定义，它是一种特殊的类，包含一组固定的常量。

```java
/**
 * 消息类型枚举
 */
public enum MsgTypeEnum {
    TXT,
    IMG,;
}
```

编译后如下

```java
// class version 61.0 (61)
// access flags 0x4031
// signature Ljava/lang/Enum<Lcom/yiwyn/enumdemo/base/MsgTypeEnum;>;
// declaration: com/yiwyn/enumdemo/base/MsgTypeEnum extends java.lang.Enum<com.yiwyn.enumdemo.base.MsgTypeEnum>
public final enum com/yiwyn/enumdemo/base/MsgTypeEnum extends java/lang/Enum {

  // compiled from: MsgTypeEnum.java

  // access flags 0x4019
  public final static enum Lcom/yiwyn/enumdemo/base/MsgTypeEnum; TXT

  // access flags 0x4019
  public final static enum Lcom/yiwyn/enumdemo/base/MsgTypeEnum; IMG
    
	... 
}
```

结论：

1. 所有枚举类默认**隐式继承 `java.lang.Enum`**，不能再继承其他类；
2. 枚举类默认被 `final` 修饰，**不能被继承、重写扩展**；
3. 每个枚举常量，本质是 `public static final` 的全局单例对象；

---

##### 2. 加载与单例特性

- 枚举常量在**类加载阶段**就完成实例化，JVM 保证全局唯一、天然线程安全；

- 业务代码永远 `new` 不出枚举对象；

  - 枚举构造默认 private、禁止 public、构造可重载互调

- 比较枚举直接用 `==`，更加安全

  - Because there is only one instance of each enum constant, it is permitted to use the `==` operator in place of the `equals` method when comparing two object references if it is known that at least one of them refers to an enum constant.

    The `equals` method in `Enum` is a `final` method that merely invokes `super.equals` on its argument and returns the result, thus performing an identity comparison.

    【译】

    由于每个枚举常量都仅有一个实例，因此在已知两个对象引用中至少有一个指向枚举常量的情况下，比较这两个引用时，允许使用`==`运算符替代`equals()`方法。

    `Enum`类中的`equals()`方法是一个终态方法，它仅会对其参数调用`super.equals()`并返回结果，因此执行的是**引用同一性比较**。

---

##### 3. 枚举的基础使用

###### 3.1 带属性的枚举

枚举可以包含属性、构造函数和方法：

```java
public enum OrderStatus {
    PENDING("待处理", 1),
    PROCESSING("处理中", 2),
    COMPLETED("已完成", 3),
    CANCELLED("已取消", 4);

    private final int code;
    private final String description;

    // 枚举构造函数必须是私有的
    private OrderStatus(String description, int code) {
        this.description = description;
        this.code = code;
    }

    public String getDescription() {
        return description;
    }

    public int getCode() {
        return code;
    }

    // 自定义方法
    public boolean isFinalStatus() {
        return this == COMPLETED || this == CANCELLED;
    }
}
```

**使用`Lombok`的简洁写法（推荐）：**

```java
@Getter
@RequiredArgsConstructor(access = AccessLevel.PRIVATE)
public enum OrderStatus {
    PENDING("待处理", 1),
    PROCESSING("处理中", 2),
    COMPLETED("已完成", 3),
    CANCELLED("已取消", 4);
    
    private final int code;
    private final String description;

    // 自定义方法
    public boolean isFinalStatus() {
        return this == COMPLETED || this == CANCELLED;
    }
}
```

###### 3.2 枚举的方法

```java
public class EnumExample {
    public static void main(String[] args) {
        // values() - 获取所有枚举值
        for (OrderStatus status : OrderStatus.values()) {
            System.out.println(status + ": " + status.getDescription());
        }

        // valueOf() - 根据字符串获取枚举
        OrderStatus status = OrderStatus.valueOf("PENDING");
        System.out.println("Status code: " + status.getCode());

        // ordinal() - 获取枚举的序号
        System.out.println("PENDING的序号: " + OrderStatus.PENDING.ordinal());

        // compareTo() - 比较枚举的顺序
        System.out.println("PENDING vs PROCESSING: " + 
            OrderStatus.PENDING.compareTo(OrderStatus.PROCESSING));
    }
}
```

###### 3.3 枚举与switch语句

```java
public class EnumSwitch {
    public static void processOrder(OrderStatus status) {
        switch (status) {
            case PENDING:
                System.out.println("处理待处理订单");
                break;
            case PROCESSING:
                System.out.println("处理处理中订单");
                break;
            case COMPLETED:
                System.out.println("处理已完成订单");
                break;
            case CANCELLED:
                System.out.println("处理已取消订单");
                break;
            default:
                throw new IllegalArgumentException("未知状态: " + status);
        }
    }
}
```

---

##### 4. 枚举的简单扩展

从上文中我们看知道了表示一个枚举的形式有很多，例如 `name()` `ordinal()` 我们`自己扩展的属性`等，但是实际使用的时候我们很少会使用 `name()`和`ordinal()`因为他们通常（相对而言）是不稳定的。所以一般情况下需要我们提供一个例如`getByCode(T code)`的方法，因为我们的`code`通常具有业务意义不会轻易发生改变。

示例：

```java
@Getter
@RequiredArgsConstructor
public enum MsgTypeEnum {
    TXT(1, "文本"),
    IMG(2, "图片"),
    ;
    private final Integer code;
    private final String msg;

    /**
     * 根据代码获取枚举
     * @param code 代码
     * @return 枚举
     */
    public static MsgTypeEnum of(Integer code) {
        for (MsgTypeEnum type : values()) {
            if (type.code.equals(code)) {
                return type;
            }
        }
        throw new IllegalArgumentException("Invalid code: " + code);
    }
}

```

通过code获取方法这里也推荐另一个写法。使用`Optional<T>`来进行结果的输出，而非使用异常的形式处理无匹配的情况。

```java
/**
 * 根据代码获取枚举
 *
 * @param code 代码
 * @return 枚举
 */
public static Optional<MsgTypeEnum> ofOptional(Integer code) {
    return Arrays.stream(values()).filter(type -> type.code.equals(code)).findFirst();
}
```

```java
public static void main(String[] args) {
    // 根据代码获取枚举
    Optional<MsgTypeEnum> msgTypeEnum = MsgTypeEnum.ofOptional(1);
    // 判断是否存在该枚举，存在则输出对应消息
    if (msgTypeEnum.isPresent()) {
        System.out.println(msgTypeEnum.get().getMsg());
    }
}
```

**【注意】**：如果使用code来获取枚举，则需要保证code唯一，若不唯一则会导致获取到错误的枚举

---

##### 5. EnumSet & EnumMap

1. EnumSet（超高效率集合）

   专为枚举设计，底层是位运算，速度远超普通 HashSet。

   EnumSet 底层是**位掩码（long 二进制位运算）**，不是数组 / 链表 / 哈希表。

   | 对比      | EnumSet                   | HashSet                         |
   | --------- | ------------------------- | ------------------------------- |
   | 底层结构  | long 位掩码（位运算）     | HashMap（数组 + 链表 + 红黑树） |
   | 性能      | 极致快 (O (1) 极简单运算) | 有哈希计算、冲突、扩容          |
   | 内存占用  | 极小（几个 long 搞定）    | 存大量哈希对象，占用高          |
   | 有序性    | 按枚举定义 ordinal 顺序   | 无序                            |
   | 元素限制  | 只能存**同一个枚举**      | 任意对象                        |
   | Null 支持 | **禁止存 null**           | 允许 null                       |

   ```java
   public static void main(String[] args) {
       // 支持发送的消息类型
       EnumSet<MsgTypeEnum> canSendMsg = EnumSet.of(MsgTypeEnum.TXT, MsgTypeEnum.IMG);
   
       if (!canSendMsg.contains(MsgTypeEnum.VOICE)) {
           System.out.println("不支持发送语音消息");
       }
   }
   ```


2. EnumMap（枚举当 Key 的高效 Map）

   EnumMap 是专门给枚举做的 Map，性能吊打 HashMap，但是 Key 必须是枚举。

   | 对比         | EnumMap                         | HashMap                         |
   | ------------ | ------------------------------- | ------------------------------- |
   | **Key 要求** | **必须是枚举**                  | 任意对象                        |
   | **底层结构** | 数组（极快）                    | 数组 + 链表 + 红黑树            |
   | **性能**     | **极快**（O (1) 常数时间）      | 快，但有哈希冲突、扩容开销      |
   | **顺序**     | **按枚举定义顺序有序**          | 无序（JDK8 + 偶尔有序但不保证） |
   | > 内存占用   | 极小                            | 相对高                          |
   | **空键空值** | **Key 不能为 null**，Value 可以 | Key、Value 都可以 null          |
   | 使用场景     | 枚举做 Key 时 **首选**          | 通用场景                        |

   代码示例：

   ```java
   EnumMap<MsgTypeEnum, Boolean> msgMap = new EnumMap<>(MsgTypeEnum.class);
   msgMap.put(MsgTypeEnum.TXT, true);
   msgMap.put(MsgTypeEnum.IMG, true);
   msgMap.put(MsgTypeEnum.VOICE, false);
   
   System.out.println(msgMap.get(MsgTypeEnum.TXT));
   ```


---

##### 6. 枚举的最佳实践

❌ 严禁用 `ordinal()` 存数据库、接口传参（改顺序全崩）

❌ 严禁单纯用 `name()` 做业务持久化（改名全崩）

❌ 枚举字段不写 `final`，破坏不可变性

❌ 在枚举内部写复杂业务逻辑、调用第三方接口

✅ 数据库只存自定义 code（数字 / 字符串）

✅ 所有业务枚举实现统一 `ICodeEnum` 接口

✅ 必提供 `of` 或 `getByCode` 等反向查询方法

✅ 状态判断优先用 `EnumSet`

✅ 枚举比较一律用 `==`

---

#### 枚举的高级应用

##### 1. 实现接口

```java
public interface ICodeEnum<T> {

    T getCode();

    String getDesc();
  
    /**
     * 获取详细信息
     */
    String getDetail();
}
```

你可以这么写，这样这个枚举就有了`getDetail`方法，但是这样的话好像意义不大，desc和detail是一样的。

```java
@Getter
@RequiredArgsConstructor
public enum ErrorCodeEnum implements ICodeEnum<Integer> {
    SUCCESS(200, "请求成功"),
    FAIL(400, "请求失败"),
    ;

    private final Integer code;
    private final String desc;

    @Override
    public String getDetail() {
        return desc;
    }
}
```

我们也可以这样写，这样失败场景的detail就得到了重写。我们可以根据每个枚举常量的具体情况，提供不同的实现逻辑。

```java
@Getter
@RequiredArgsConstructor
public enum ErrorCodeEnum implements ICodeEnum<Integer> {
    SUCCESS(200, "请求成功"),
    FAIL(400, "请求失败") {
        @Override
        public String getDetail() {
            return "网络开小差！！！！请求失败！！！！！";
        }
    },
    ;

    private final Integer code;
    private final String desc;

    @Override
    public String getDetail() {
        return desc;
    }
}
```

##### 2. 抽象方法

枚举中，你可以将每个枚举对象当成实现，枚举中定义了抽象方法，则每个枚举对象**必须**都需要对该方法进行实现。

```java
@Getter
@RequiredArgsConstructor
public enum JsonEnum {

    FAST_JSON(0) {
        @Override
        public String object2json(Object object) {
            return "fastjson" + getCode();
        }
    }, JACKSON(1) {
        @Override
        public String object2json(Object object) {
            return "jackson";
        }
    },
    ;

    private final Integer code;

    /**
     * 将对象转换成json
     * @param object 对象
     * @return json字符串
     */
    public abstract String object2json(Object object);

}
```

##### 3. 函数式接口扩展

使用函数式接口可以更加灵活的赋予枚举可以执行的事件。

```java
@Getter
@RequiredArgsConstructor
public enum MessageEnum {

    TEXT("01", jsonObject -> jsonObject.getString("content")),
    IMAGE("02", jsonObject -> jsonObject.getString("url"));

    private final String code;


    private final IMessageAble messageAble;


    interface IMessageAble {
        String content(JSONObject contentBody);
    }
}
```



#### 高阶用法

###### 工厂&策略模式

```java
package com.yiwyn.enumdemo.advanced.f;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

import java.util.Arrays;
import java.util.Optional;

/**
 * @className: FMain
 * @author: Yiwyn
 * @date: 2026/4/6 18:30
 * @Version: 1.0
 * @description:
 */
public class FMain {

    /**
     * 枚举中定义一个接口，并让枚举实例实现该接口
     */
    @Getter
    @RequiredArgsConstructor
    enum MsgFactory {

        TEXT("text", new TextMsgFactory()),
        IMG("img", new ImgMsgFactory());

        private final String code;
        private final baseMsgFactory baseMsgFactory;


        public static Optional<MsgFactory> getMsgFactory(String code) {
            return Arrays.stream(MsgFactory.values()).filter(msgFactory -> msgFactory.getCode().equals(code)).findFirst();
        }

    }

    /**
     * 基础消息工厂
     */
    static class baseMsgFactory {
    }

    /**
     * 文本消息工厂
     */
    static class TextMsgFactory extends baseMsgFactory {
        @Override
        public String toString() {
            return "TextMsgFactory";
        }
    }

    /**
     * 图片消息工厂
     */
    static class ImgMsgFactory extends baseMsgFactory {
        @Override
        public String toString() {
            return "ImgMsgFactory";
        }
    }
		
		// 实际使用场景
    public static void main(String[] args) {

        /*
         * 根据消息类型获取消息工厂
         */
        String msgType = "text";
        Optional<MsgFactory> msgFactory = MsgFactory.getMsgFactory(msgType);
        if (msgFactory.isPresent()) {
            System.out.println(msgFactory.get().getBaseMsgFactory());
        }

    }

}

```

---

###### 字段提取策略枚举

```java
@Getter
@RequiredArgsConstructor
public enum MessageEnum {

    TEXT("01", jsonObject -> jsonObject.getString("content")),
    IMAGE("02", jsonObject -> jsonObject.getString("url"));

    private final String code;
    private final IMessageAble messageAble;


    interface IMessageAble {
        String content(JSONObject contentBody);
    }
}
```

---

###### 错误升级

```java
@Getter
@RequiredArgsConstructor
public enum LeveEnum {

    LOW("低", lt(3)),
    MIDDLE("中", new LevelPredicate() {
        @Override
        public boolean test(int level) {
            return level <= 5;
        }
    }),
    HIGH("高", gt(5));

    private final String desc;
    private final LevelPredicate levelPredicate;


    /**
     * 等级判断接口
     */
    private interface LevelPredicate {
        boolean test(int level);
    }

    /**
     * 等于
     *
     * @param value 值
     * @return LevelPredicate
     */
    private static LevelPredicate eq(int value) {
        return level -> level == value;
    }

    /**
     * 大于
     *
     * @param value 值
     * @return LevelPredicate
     */
    private static LevelPredicate gt(int value) {
        return level -> level > value;
    }

    /**
     * 小于
     *
     * @param value 值
     * @return LevelPredicate
     */
    private static LevelPredicate lt(int value) {
        return level -> level < value;
    }


    /**
     * 根据等级获取枚举
     *
     * @param level 等级
     * @return 枚举
     */
    public static LeveEnum valueOfLevel(int level) {
        for (LeveEnum leveEnum : LeveEnum.values()) {
            if (leveEnum.levelPredicate.test(level)) {
                return leveEnum;
            }
        }
        throw new IllegalArgumentException("Invalid level: " + level);
    }


}
```






参考文档：

【0】[Chapter 8. Classes](https://docs.oracle.com/javase/specs/jls/se8/html/jls-8.html#jls-8.9)

【1】 [Java实际开发中, enum枚举用的多吗？ - 知乎](https://www.zhihu.com/question/1913219325743067883/answer/2013160036134834695)

【2】[README - 《Effective Java (高效 Java) 第三版》 - 书栈网 · BookStack](https://www.bookstack.cn/read/effective-java-3rd-chinese/docs-README.md)