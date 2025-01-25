+++
title = 'Kubernetes的前世今生'

date = 2025-01-12T22:37:30+08:00

categories = ["k8s"]

tags = ["k8s"]

draft = true

+++



##### 基本架构

##### 核心实战

###### Namespace

命名空间用来隔离资源

Shell

```shell
kubectl create ns [namespace name]
kubectl delete ns [namespace name]
```

Yaml

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: [namespace name]
```



###### Pod

运行一组容器，Pod是k8s中应用的最小单位

###### Deployment

###### Service





##### 工作负载

##### 网络服务



