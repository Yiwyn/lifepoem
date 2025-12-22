+++
title = 'SpringAI光速入门'

date = 2025-12-22T12:32:06+08:00

categories = ["Spring"]

tags = ["AI","Spring AI"]

draft = true

+++



### Spring AI 光速入门



> 背景：AI成为了大多数人提效的工具，尽管现在AI工具的使用已经非常方便，但是我们还是需要思考，如何让个人/系统更加适配AI，或者如何尽可能发挥AI的最大能力。于是agent开发框架开始进入AI开发工程师的视野，例如：LangChain，LangChain4j。 作为一名Java程序员，Spring这颗大树推出了Spring AI，本文将通过Spring AI来展开对Java中AI开发的概念解析与开发流程设计。



##### 关键概念

- ###### ChatModel（对话模型）

  本质是大语言模型（LLM）的 “对话交互模型”，是能理解自然语言、生成符合上下文的对话式回复的 AI 核心引擎（比如 GPT-4、Claude 3、文心一言、通义千问都属于 ChatModel）

  相当于 AI 应用的 “大脑”，负责思考和回答问题。

- ###### ChatClient（对话客户端）

  是开发者 / 用户与 ChatModel 交互的 “接口工具” 或 “封装层”，本质是简化与大模型 API 通信的代码库 / 工具。

  在开发中应优先使用ChatClient而非更加底层的ChatModel。（适配器模式；需要添加模型的时候，实现ChatClient即可）

  关键作用：

  - 封装底层 API 调用逻辑（比如处理请求头、密钥、参数格式）；
  - 统一不同 ChatModel 的调用方式（比如调用 GPT-4 和 Claude 的代码风格一致）；
  - 处理网络请求、异常重试、响应解析等通用逻辑。

- ###### Prompt（提示词）

  发送给模型的”指令“，引导AI生成内容的信息，是生成预期内容的主要手段。

  一般包含定义模型的角色、任务、格式

- ###### Advisors（顾问/指导）

  Spring AI Advisors API 提供了灵活而强大的方式来拦截、修改和增强与AI模型的交互的，类似Web中的Filter。

- ###### Embedding Model（嵌入模型）

  将文本、图片、视频等媒体信息转换成高维数值常量的过长，向量的距离能反应数据的语义相似度

- ###### VectorStore（向量存储）

  顾名思义，用来存储Embedding 向量信息的数据库。

- ###### RAG（Retrieval-Augmented Generation，检索增强生成）

  我们开发专用的AI工具的核心，核心逻辑是“先检索外部知识库（例如上述VectorStore）,再把结果和问题一起发给ChatModel生成回答”，用来让AI知道我们提供的信息。

- ###### Tool Calling（工具调用）

  让ChatModel可以根据用户需求，自主决定调用我们预设的一些功能，可以让AI帮我们实际做一些事情，而非仅仅聊天对话。





##### SpringAI 开始前的准备

> 版本：Spring AI 1.1.2
>
> Java：17
>
> Spring Boot：3.5.9



[Introduction :: Spring AI Reference](https://docs.spring.io/spring-ai/reference/index.html)



###### 一、创建SpringBoot项目

```shell
Spring AI supports Spring Boot 3.4.x and 3.5.x.
```



###### 二、pom文件中添加spring-ai-bom

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>org.springframework.ai</groupId>
            <artifactId>spring-ai-bom</artifactId>
            <version>1.1.2</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
```



###### 三、我们选择已OpenAI的形式对接「豆包」的模型

PS：豆包的模型对应的AK信息如何获取此处不做演示

[OpenAI Chat :: Spring AI Reference](https://docs.spring.io/spring-ai/reference/api/chat/openai-chat.html)

引入openai llm模型

```xml
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-starter-model-openai</artifactId>
</dependency>
```



###### 四、配置文件

application.yml配置参数

```yml
spring:
  application:
    name: ai-demo #非必要
  ai:
    openai: #以下参数必填
      api-key: 223080d***************d830af65 
      base-url: https://ark.cn-beijing.volces.com/api/v3
      chat:
        options:
          model: doubao-1-5-lite-32k-250115
        completions-path: /chat/completions

server:
  servlet:
    encoding:
      charset: utf-8
      enabled: true
      force: true
```



到了这里我们的基础配置已经完成。

pom.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.5.9</version>
        <relativePath/> <!-- lookup parent from repository -->
    </parent>
    <groupId>com.yiwyn</groupId>
    <artifactId>spring-ai-demo</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>spring-ai-demo</name>
    <description>spring-ai-demo</description>
    <url/>
    <licenses>
        <license/>
    </licenses>
    <developers>
        <developer/>
    </developers>
    <scm>
        <connection/>
        <developerConnection/>
        <tag/>
        <url/>
    </scm>
    <properties>
        <java.version>17</java.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>

        <dependency>
            <groupId>org.springframework.ai</groupId>
            <artifactId>spring-ai-starter-model-openai</artifactId>
        </dependency>


    </dependencies>


    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.ai</groupId>
                <artifactId>spring-ai-bom</artifactId>
                <version>1.1.2</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>

</project>

```



##### 实战环节



###### 做一个 代码检测工具 



我们在配置好了基础的信息后，首先我们需要创建一个ChatClient，ChatClient封装了很多AI处理，可以大幅提升开发效率

创建配置类：

```java
package com.yiwyn.springaidemo.config;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.openai.OpenAiChatModel;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

/**
 * @className: ChatConfig
 * @author: Yiwyn
 * @date: 2025/12/22 13:06
 * @Version: 1.0
 * @description: 接入配置
 */
@Configuration
public class ChatConfig {

		
    // OpenAiChatModel 是依赖 ： spring-ai-starter-model-openai 中自带的，我们直接使用该model进行创建client
    @Bean(name = "chatClient")
    @Primary
    public ChatClient chatClient(OpenAiChatModel openAiChatModel) {
        return ChatClient.create(openAiChatModel);
    }
}
```









