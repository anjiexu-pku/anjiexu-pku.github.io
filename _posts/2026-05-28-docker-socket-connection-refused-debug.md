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

<style>
.lang-switch {
  text-align: right;
  margin-bottom: 1.5em;
  font-size: 0.95em;
  user-select: none;
}
.lang-switch a {
  color: #888;
  text-decoration: none;
  padding: 0 0.3em;
}
.lang-switch a.active {
  color: #333;
  font-weight: 600;
}
.lang-switch a:not(.active):hover {
  text-decoration: underline;
}
</style>

<div class="lang-switch">
  <a class="active" href="#en" onclick="switchLang('en');return false">English</a>|
  <a href="#zh" onclick="switchLang('zh');return false">中文</a>
</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

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

</div>

<div id="lang-en" class="lang-content" markdown="1">

One day, running `docker ps` returned the classic error:

```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
```

Classic, but strange. `pgrep dockerd` showed that the daemon was running, `/var/run/docker.sock` existed, and `ss -xlnp` clearly showed the socket in the LISTEN state. The user was also in the `docker` group. Everything looked normal, but the connection was still refused with `ECONNREFUSED`.

## Step 1: Check "Which Docker" Is Running

`pgrep -a dockerd` gave the first clue:

```
dockerd --group docker --exec-root=/run/snap.docker
         --data-root=/var/snap/docker/common/var-lib-docker
         --config-file=/var/snap/docker/3505/config/daemon.json
```

The paths were full of `snap`: the daemon came from a snap installation.

Then I checked the CLI:

```bash
$ which docker
/usr/bin/docker
$ dpkg -S /usr/bin/docker
docker-ce-cli: /usr/bin/docker
```

The CLI was `docker-ce-cli` installed through apt, version 29.4.0. The snap daemon was 29.3.1.

Having two installations is not fatal by itself. The Docker CLI and daemon communicate through a Unix socket, and API version compatibility is usually enough. But this environment really did have two independent Docker installations from two package managers.

## Step 2: Use `strace` to Inspect the System Call

`curl --unix-socket` also failed, which meant this was not a Docker CLI issue. I used `strace` to see what was actually happening:

```
connect(5, {sa_family=AF_UNIX, sun_path="/run/docker.sock"}, 19)
  = -1 ECONNREFUSED (Connection refused)
```

`ECONNREFUSED`. The socket file existed, and `ss` said it was listening, but the kernel refused the connection. This usually means the listening endpoint is not truly accepting connections.

## Step 3: Find the Root Cause in `journalctl`

```bash
journalctl -u snap.docker.dockerd --no-pager | tail -30
```

The logs repeatedly showed a few error patterns.

**Leftover container conflict:**

```
failed to start container: failed to create task for container:
  OCI runtime create failed: runc create failed:
  container with given ID already exists
```

**Timeout while cleaning up a dead shim:**

```
failed to delete shim: close wait error: context deadline exceeded
```

**Then cleanup could not find the container:**

```
cleanup: failed to delete container from containerd:
  NotFound: container "xxx" in namespace "moby": not found
```

The full failure chain was:

1. When Docker daemon starts, it tries to recover containers that were previously marked as running.
2. The containerd shim processes for those containers no longer exist, but the runc state directories are still there.
3. The daemon tries to create a task, and runc reports "already exists".
4. The daemon tries to clean up, and containerd reports "not found".
5. Cleanup times out, and the daemon gets blocked in its startup loop.
6. The socket file is created, but the API never becomes truly ready, so every connection is refused.

In essence, this was inconsistent Docker state storage, more precisely containerd plus runc state inconsistency. The containers were marked as running in Docker's database, but at the containerd/runc layer they were half-dead zombie state.

## Fix

Clean the leftover state and start fresh:

```bash
sudo snap stop docker.dockerd

# Clean containerd task state
sudo rm -rf /run/snap.docker/containerd/daemon/io.containerd.runtime.v2.task/moby

# Clean Docker's container records
sudo rm -rf /var/snap/docker/common/var-lib-docker/containers/*

sudo snap start docker.dockerd
```

After that, `docker ps` returned normally.

## Checklist

When Docker's socket exists but cannot be connected to, debug in this order:

1. `pgrep dockerd`: is the daemon running?
2. `strace -e connect curl --unix-socket /run/docker.sock http://localhost/version`: is the failure `ENOENT` or `ECONNREFUSED`?
3. `journalctl -u snap.docker.dockerd` for snap, or `journalctl -u docker` for apt: what is the daemon doing?
4. If logs contain `runc create failed: container with given ID already exists`, it is a leftover-state problem. Clean the task directory under `/run/snap.docker/containerd/`.

This sequence covers the key information sources on the path from "everything looks normal" to the actual root cause.

</div>

<script>
function switchLang(lang) {
  document.getElementById('lang-zh').style.display = lang === 'zh' ? '' : 'none';
  document.getElementById('lang-en').style.display = lang === 'en' ? '' : 'none';
  const links = document.querySelectorAll('.lang-switch a');
  links.forEach(a => a.classList.remove('active'));
  document.querySelector('.lang-switch a[href="#' + lang + '"]').classList.add('active');
  history.replaceState(null, '', '#' + lang);
}
if (location.hash === '#zh') {
  switchLang('zh');
}
</script>
