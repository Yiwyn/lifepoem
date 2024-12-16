+++
title = 'Cloudflare+Hugo搭建静态页'

date = 2024-12-10T09:13:33+08:00

categories = ["小零食"]

tags = ["Cloudflare","Hugo"]

draft = true

+++



#### Cloudflare+Hugo搭建静态网页



> 背景：在长时间的工作学习中，很多的知识需要得到有效的保存，于是萌生了写博客文章的想法，于是就有了以下历程
>
> 1. 使用博客园、csdn等形式进行文章发布
> 2. 使用GIT对文章（主要是markdown文档）进行版本管理，同时借助第三方工具对GIT中的文章进行拉取并生成预览
>    1. 自建服务，通过每天晚上定时拉取GIT仓库中的文章并保存到数据库中，后台提供查询接口达成博客功能，运行一段时间发现问题较多，
>    2. 使用Pages服务进行托管，Gitee Pages、Github Pages、Cloudflare Pages【吐槽一下Gitee不出任何声明就停止了Pages服务】



##### Cloudflare

维基百科：

**Cloudflare 公司**是一家美国公司，提供[内容交付网络](https://en.wikipedia.org/wiki/Content_delivery_network)服务、云[网络安全](https://en.wikipedia.org/wiki/Cybersecurity)、[DDoS 缓解](https://en.wikipedia.org/wiki/DDoS_mitigation)、[广域网](https://en.wikipedia.org/wiki/Wide_area_network)服务、[反向代理](https://en.wikipedia.org/wiki/Reverse_proxy)、[域名服务和](https://en.wikipedia.org/wiki/Domain_Name_Service) [ICANN](https://en.wikipedia.org/wiki/ICANN) 认证的[[3\]](https://en.wikipedia.org/wiki/Cloudflare#cite_note-3)[域名注册服务](https://en.wikipedia.org/wiki/Domain_name_registrar)。[[4\]](https://en.wikipedia.org/wiki/Cloudflare#cite_note-CNBC-4)[[5\]](https://en.wikipedia.org/wiki/Cloudflare#cite_note-thinking-big-5)[[6\]](https://en.wikipedia.org/wiki/Cloudflare#cite_note-6) Cloudflare 的总部位于加利福尼亚州旧金山。[[4\]](https://en.wikipedia.org/wiki/Cloudflare#cite_note-CNBC-4)根据 W3Techs 的数据，截至 2024 年，超过 19% 的互联网使用 Cloudflare 提供网络安全服务。



###### Cloudflare Pages

> [Cloudflare Pages documentation · Cloudflare Pages docs](https://developers.cloudflare.com/pages/)

创建可立即部署到 Cloudflare 全球网络的全栈应用程序。

Pages 服务可以将我们的静态网页挂载到对应的服务上，同时并提供域名以提供访问。【可以理解为nginx中指向index.html中的那种模式】，通过将静态文件上传到指定的位置，达成Pages的构建。



举个例子，个人主页、个人博客、产品展示、软件文档等

根据文章首页的信息，我们来设想一个工作状态，如我想要做一个博客。

- 我需要写文章，并可以很方便的进行更新
  - 写文章：使用本地文本编辑工具（MarkDown编辑器之类），
  - 更新：~~不会有程序员不知道Git吧，不会吧不会吧~~  这里我使用Git进行版本控制，将文章放到gitee和github上。
- 我如何将我的文章都处理成静态网页文件呢
  - 其实市面上成熟的方案很多 VuePress、Hexo、Jeklly 、hugo，该类方案大多是以markdown为中心，将markdown文章渲染为静态文件（html、css、js）等形式进行生成，并提供部署方案，下文将重点描述hugo
- 如何部署
  - 关于部署，就有的说了，但是我们正常情况下不会搞一个服务器专门放这个；所以选择Pages服务托管，使用Cloudflare综合了以下考量
    -  费用问题，费用问题是头等问题。Pages上的静态资源是免费的，且无数量限制。![image-20241214233007285](https://filestore.lifepoem.fun/know/202412142330320.png)
    - 访问速度，这也是选择cloudflare的重要原因之一，Github Pages 打开速度简单折磨
    - 自动化部署，每次更新完文章可以自动部署新文章
- 以上工作完成就可以快乐的玩耍了，写完文章随手提交，剩下的等系统自动部署发版就行了



##### hugo



> [The world’s fastest framework for building websites | Hugo](https://gohugo.io/) 

hugo使用go语言开发的，大量文章下相比于其他TS(JS)之类的方案效率要高出很多。

以下将简单描述hugo的使用。

hugo下载地址[Releases · gohugoio/hugo](https://github.com/gohugoio/hugo/releases/)

hugo官网快速开始[Quick start | Hugo](https://gohugo.io/getting-started/quick-start/)



```powershell
# 创建站点
hugo new site quickstart

# 添加主题【示例添加beautifulhugo主题，且hugo项目处于git中】
git submodule add https://github.com/CaiJimmy/hugo-theme-stack.git themes/hugo-theme-stack

# 编辑hugo配置文件 - 配置主题
quickstart/hugo.toml

# 添加文章 执行完成我们就有了第一篇文章
hugo new content content/posts/my-first-post.md

```

~~// 可能会踩坑，但是问题不大~~



当以上步骤完成的时候，我们的静态网站已经初具规模。

以下几点将围绕hugo-theme-stack主题进行展开  <font color='red'>PS：因为这个hugo本身比较简单，所以大部分的工作在主题配置上</font>

因为每个主题都对应有响应的案例站点和源码，我们根据源码来进行配置即可



###### 接下来我们需要关心的点

1. 侧边栏功能开启，如图

<img src="https://filestore.lifepoem.fun/know/202412162231821.png" alt="image-20241216223147742" style="zoom: 80%;" />

![image-20241216223807436](https://filestore.lifepoem.fun/know/202412162238476.png)

可以看到，我们只需要在项目的content/page下创建指定的文件夹以及文件夹下的index.md即可开启对应的功能



2. 评估功能的开启

   ![image-20241216224331427](https://filestore.lifepoem.fun/know/202412162243477.png)

可以看到，这里使用gicus项目来实现评论功能，那这些参数是如何获取到的呢

giscus官网奉上 [giscus](https://giscus.app/zh-CN) 

![image-20241216224554475](https://filestore.lifepoem.fun/know/202412162245512.png)



如图，满足以上规则的仓库即可使用该项功能，这经过一系列的勾选后，我们就可以得到

![image-20241216225939395](https://filestore.lifepoem.fun/know/202412162259445.png)

以上配置完成后，我们进入文章后就能看到giscus提供的评论已经出现了，尝试一点点赞和评论都没有问题![image-20241216230031224](https://filestore.lifepoem.fun/know/202412162300279.png)



3. 文章的结构

   1. 文章的结论直接决定了网站对于tag、categories的处理

      ```markdown
      ---
      title: 测试文章
      description: 这是一个副标题
      date: 2020-09-09
      slug: test-chinese
      image: https://filestore.lifepoem.fun/know/202412051649426.png
      categories: ['测试']
      tags: ['图文']
      ---
      
      ```

      使用该头部信息获取到的具体展示如图

      ![image-20241216230421823](https://filestore.lifepoem.fun/know/202412162304882.png)





关于hugo的配置以及主题的配置，不再赘述，可根据demo和官方文档自行尝试自己需要的风格。



##### Cloudflare部署

https://dash.cloudflare.com/



![image-20241214231229774](https://filestore.lifepoem.fun/know/202412142312869.png)



有两种形式上传方式，正常情况下我们会选择第一种，cloudflare集成了诸多开源项目和工作，如hugo默认是提供了支持的。

第二种方式直接上传源文件的形式，我们可以得到启示，如曾经开发过的vue、react等项目，在build后生成index.html为引的文件，也就说明了我们曾经的一些前端项目是可以很好的进行兼容的（在不方便开源或者不能很好的支持远程打包的那种）



配置如图

![image-20241216231341534](https://filestore.lifepoem.fun/know/202412162313588.png)





![image-20241216231525747](https://filestore.lifepoem.fun/know/202412162315800.png)



环境变量需要根据实际项目来自行配置。



保存并部署，大功告成。
