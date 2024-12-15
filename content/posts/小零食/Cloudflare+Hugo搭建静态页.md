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

![image-20241214231229774](https://filestore.lifepoem.fun/know/202412142312869.png)



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







##### Github自动部署

