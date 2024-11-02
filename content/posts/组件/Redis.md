+++
title = 'Redis'

date = 2024-11-02T16:59:43+08:00

categories = ["开源工具"]

tags = ["Redis"]

+++



### Redis



#####  常用命令

| 命令              | 作用                   |
| ----------------- | ---------------------- |
| keys *            | 当前数据库中所有的key  |
| dbsize            | 键总数                 |
| exists key        | 键是否存在             |
| del key[key ...]  | 删除键                 |
| expire key sconds | 设置键过期时间         |
| ttl key           | 获取键的有效时长       |
| persist key       | 移除键的过期时间       |
| type key          | 键的数据结构           |
| randomkey         | 随机返回数据库中一个键 |
| rename key1  key2 | 重命名                 |



##### 五大数据类型

| 类型              | 说明         |
| ----------------- | ------------ |
| STRING            | 字符串类型   |
| HASH              | 哈希类型     |
| LIST              | 列表类型     |
| SET               | 集合类型     |
| ZSET（sortedset） | 有序集合类型 |



##### 内存淘汰策略

<font color='orange'>volatile-lru</font>（Least Recently Used，最近最少使用）：仅在设置了过期时间的键中，基于LRU算法淘汰数据

<font color='orange'>volatile-lfu</font>（Least Frequently Used，最不经常使用）：仅在设置了过期时间的键中，基于LFU算法淘汰数据

<font color='orange'>volatile-random</font>（随机数据）：仅在设置了过期时间的键中，随机淘汰

<font color='orange'>volatile-ttl</font>（ttl最小的数据）：仅在设置了过期时间的键中，淘汰TTL最小的键，也就是即将过期的键

<font color='orange'>allkeys-lru</font>：在所有的键中，基于LRU算法淘汰数据

<font color='orange'>allkeys-lfu</font>：在所有的键中，基于LFU算法淘汰数据

<font color='orange'>allkeys-random</font>：在所有的键中，随机选择淘汰





##### 数据恢复

- ##### RDB（Redis DataBase）

  指定的时间间隔内将内存中的数据集快照写入磁盘。也就是<font color='red'>Snapshot快照</font>，恢复时将快照文件直接读到内存中。

  Redis会单独创建(Fork)一个子进程来进行持久化，先将数据写入到一个临时文件中，待持久化过程都结束了，再用这个临时文件替换上次持久化好的文件。整个过程中，主进程是不进行任何IO操作的，这就确保了极高的性能。

  如果需要大规模数据的恢复，且对于数据的完整性不是非常敏感，RDB比AOF更加高效。

  RDB的缺点是最后一次持久化后的数据可能丢失。

  ##### <font color='orange'>优点</font>

  适合大规模的数据恢复

  对数据的完整性和一致性要求不高时适用

  ##### <font color='orange'>缺点</font>

  在一定间隔时间内做一次备份，如果redis意外down掉，就会失去最后一次快照后的所有修改。

  Fork的时候，内存中的数据被克隆了一份，大致2倍的膨胀性需要考略

  

- ##### AOF（Append Only File）

  以日志的形式来记录每个写操作，将Redis执行过的所有指令记录下来（读操作不记录）

  <font color='red'>只许追加文件，但不改写文件</font>，Redis启动之初会读取该文件重新构件数据。

  Redis重启的话就根据日志文件的内容将写指令从前到后执行一次以完成数据的恢复工作

  ##### <font color='orange'>优点</font>

  appendfsync always：每次修改同步。同步持久化，每次发生数据变更会被立即记录到磁盘。<font color='red'>性能较差，但数据完整性较好</font>。

  appendfsync everysec：每秒同步。异步操作，每秒记录，如果一秒内宕机，有数据丢失，

  appendfsync no：不同步。

  ##### <font color='orange'>缺点</font>

  相同的数据集的数据而言，AOF文件远大于RDB文件，恢复速度慢于RDB

  AOF运行效率要慢于RDB，每秒同步策略效率较好，不同步效率与RDB相同。

  



