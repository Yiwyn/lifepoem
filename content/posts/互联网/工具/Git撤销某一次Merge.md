+++
title = 'Git撤销某一次Merge'

date = 2025-03-03T13:17:10+08:00

categories = ["GIT"]

tags = ["GIT"]

+++



#### Git撤销某一个Merge



### 1. 找到合并提交

首先，找到合并分支A的提交记录：

复制

```bash
git log --oneline --merges
```

这将列出所有合并提交，找到与分支A相关的合并提交的哈希值。

### 2. 回退到合并前

使用 `git revert` 回退合并提交：

```bash
git revert -m 1 <merge-commit-hash>
```

`-m 1` 表示回退到合并前的第一个父提交（通常是你的分支状态）。

### 3. 处理冲突

如果有冲突，Git 会提示你解决。解决冲突后，继续完成回退：

```bash
git add .
git revert --continue
```

### 4. 强制推送（如果需要）

如果分支已推送到远程仓库，可能需要强制推送：

```bash
git push origin <your-branch> --force
```

### 5. 删除分支A（可选）

如果不再需要分支A，可以删除它：

```shell
git branch -d branchA
```

### 总结

1. 找到合并提交的哈希值。
2. 使用 `git revert` 回退合并。
3. 解决冲突并完成回退。
4. 强制推送更改（如有必要）。
5. 删除分支A（可选）。
