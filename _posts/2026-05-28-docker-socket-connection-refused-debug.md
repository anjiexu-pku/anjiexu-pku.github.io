---
title: "Docker socket 存在但连接被拒绝：一次 snap + apt 双安装的排障记录"
date: 2026-05-28
categories:
  - tech
  - ops
tags:
  - docker
  - snap
  - debugging
  - linux
excerpt: "docker ps returned ECONNREFUSED but the socket file existed and the daemon was running. A debugging walkthrough through pgrep, strace, and journalctl to find the root cause: zombie container state from a snap + apt dual installation."
---

某天执行 `docker ps`，返回了这个经典错误：

```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
```

经典，但诡异——因为 `pgrep dockerd` 显示 daemon 正在运行，`/var/run/docker.sock` 也存在，而且 `ss -xlnp` 明确显示 socket 处于 LISTEN 状态。用户也在 `docker` 组里。一切看起来都正常，但连接就是被拒绝（`ECONNREFUSED`）。

## 第一步：确认"是哪一个 Docker"

`pgrep -a dockerd` 给出了第一条线索：

```
dockerd --group docker --exec-root=/run/snap.docker
         --data-root=/var/snap/docker/common/var-lib-docker
         --config-file=/var/snap/docker/3505/config/daemon.json
```

路径里到处都是 `snap`——daemon 是 snap 安装的。

再查 CLI：

```bash
$ which docker
/usr/bin/docker
$ dpkg -S /usr/bin/docker
docker-ce-cli: /usr/bin/docker
```

CLI 是 apt 装的 `docker-ce-cli`，版本 29.4.0。而 snap daemon 是 29.3.1。

两套安装本身不致命——Docker CLI 和 daemon 通过 Unix socket 通信，API 版本兼容就行。但这个环境里确实有两套独立的 Docker 来自两个包管理器。

## 第二步：strace 看系统调用

`curl --unix-socket` 也连不上，说明不是 CLI 的问题。用 `strace` 看实际发生了什么：

```
connect(5, {sa_family=AF_UNIX, sun_path="/run/docker.sock"}, 19)
  = -1 ECONNREFUSED (Connection refused)
```

`ECONNREFUSED`。socket 文件存在，`ss` 也说 LISTEN，但内核拒绝连接。这通常意味着 socket 的监听端并没有真正 accept。

## 第三步：journalctl 找到根因

```bash
journalctl -u snap.docker.dockerd --no-pager | tail -30
```

日志里反复出现以下几个错误模式：

**残留容器冲突：**

```
failed to start container: failed to create task for container:
  OCI runtime create failed: runc create failed:
  container with given ID already exists
```

**清理死 shim 超时：**

```
failed to delete shim: close wait error: context deadline exceeded
```

**然后清理又找不到容器：**

```
cleanup: failed to delete container from containerd:
  NotFound: container "xxx" in namespace "moby": not found
```

完整的故障链：

1. Docker daemon 启动时，会尝试恢复之前 running 状态的容器
2. 这些容器的 containerd shim 进程已经不存在了，但 runc 状态目录还在
3. daemon 尝试创建 task → runc 报 "already exists"
4. daemon 尝试清理 → containerd 报 "not found"
5. 清理超时，daemon 被阻塞在启动循环里
6. socket 文件创建了，但 API 从未真正 ready，所有连接都被拒绝

本质上是 Docker（确切地说是 containerd + runc）的状态存储不一致——容器在 Docker 的数据库中标记为 running，但在 containerd/runc 层面已经处于半死半活的僵尸状态。

## 修复

清理残留状态，重新开始：

```bash
sudo snap stop docker.dockerd

# 清理 containerd 的任务状态
sudo rm -rf /run/snap.docker/containerd/daemon/io.containerd.runtime.v2.task/moby

# 清理 Docker 的容器记录
sudo rm -rf /var/snap/docker/common/var-lib-docker/containers/*

sudo snap start docker.dockerd
```

之后 `docker ps` 正常返回。

## 一个检查清单

以后遇到 Docker socket 存在但连不上的情况，按这个顺序排查：

1. `pgrep dockerd` — daemon 是否在跑？
2. `strace -e connect curl --unix-socket /run/docker.sock http://localhost/version` — 到底是 ENOENT 还是 ECONNREFUSED？
3. `journalctl -u snap.docker.dockerd` (snap) 或 `journalctl -u docker` (apt) — daemon 在忙什么？
4. 如果日志里有 `runc create failed: container with given ID already exists` → 残留状态问题，清理 `/run/snap.docker/containerd/` 下的 task 目录

这套步骤覆盖了从"看起来一切正常"到"找到根因"的路径里最关键的信息源。
