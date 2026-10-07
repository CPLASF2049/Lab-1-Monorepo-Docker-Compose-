# Windows 正式验收记录（进行中）

验收日期：2026-10-05（Asia/Shanghai）。执行方式：Codex 在用户本机执行；实际验收人姓名待填写。

## 本次代码来源

按用户明确要求，使用 GitHub 仓库替代 PDF 中的 CodeArts 克隆地址：
https://github.com/CPLASF2049/Lab-1-Monorepo-Docker-Compose-.git

分支：`main`。

本次待验收 Commit SHA：`6d4afbc97c109abff93978f7da29f54ff9a522bf`。

刚克隆时 `git status --short` 无输出。用户说明其文件与 CodeArts 相同，本次未能独立核对 CodeArts 内容。仓库中已有的 `docs/acceptance-evidence.txt` 是此前机器上的历史记录，不代表本次验收结果。

## 环境和前置检查

- Windows 10 专业版，版本 10.0.19045，64 位。
- Docker CLI：29.8.2，build 7fc2dff。
- Docker Compose：v5.5.1。
- Docker Desktop 安装目录：`C:/Users/86137/AppData/Local/Programs/DockerDesktop`。
- 已从 `.env.example` 复制 `.env`，使用默认配置。
- `docker compose config -q` 成功，退出码 0。
- Docker 引擎此前启动失败：`Virtual Machine Platform not enabled`。
- 已用管理员权限将 VirtualMachinePlatform 从 Disabled 启用到 Enabled。
- Windows 检测到 RebootPending，需用户重启后继续。
- WSL 运行环境安装状态见 `evidence/windows-wsl-setup.txt`。

## 5.1—5.4 实际结果

| 项目 | 本次状态 |
| --- | --- |
| 5.1 Compose 配置校验 | 通过 |
| 5.1 首次启动、三个服务运行、页面初值 0 | 尚未执行，等待 Docker 引擎可用 |
| 5.2 加减、刷新、另一浏览器与 SQL 一致 | 尚未执行 |
| 5.3 重启服务后仍为 -1，再加到 0 | 尚未执行 |
| 5.4 容器删除重建、卷保留、7 和 6 的持久化 | 尚未执行 |

## 证据

- [本次环境和配置日志](windows-validation.txt)
- [虚拟机平台启用日志](windows-platform-setup.txt)
- [WSL 安装日志](windows-wsl-setup.txt)

## 恢复位置

用户重启 Windows 并打开 Docker Desktop 后，从当前仓库继续。先确认 `docker info --format '{{.OSType}}'` 为 `linux`，并在首次启动之前记录 `lab1-counter_db-data` 是否存在，然后按 PDF 的 5.1—5.4 顺序进行浏览器操作、SQL 检查、截图和容器 ID 对比。

未执行 `docker compose down -v`。未提交或推送。CodeArts 项目成员、助教和权限截图仍待提供。

WSL 安装补充结果：Microsoft.WSL 2.7.13 安装程序报告成功，退出码 0；安装程序明确提示启用虚拟机平台后必须重启。重启后的 WSL 版本和 Docker 引擎运行状态尚待验证。

## 2026-10-05 重启后续查

用户已于 19:31 重启 Windows。继续启动 Docker 时发现报错 `WSL_E_WSL_OPTIONAL_COMPONENT_REQUIRED`：WSL 软件包已安装，但 Windows 的 `Microsoft-Windows-Subsystem-Linux` 可选组件仍为 Disabled。

已于 19:40 使用管理员权限补启用该组件。管理员查询确认：

- `VirtualMachinePlatform`: Enabled。
- `Microsoft-Windows-Subsystem-Linux`: Enabled。
- 此次启用结果 `RestartNeeded: True`，系统 `RebootPending: True`。

需要用户再次重启，让刚启用的 WSL 系统组件生效。5.1—5.4 的运行验收仍未开始，计数器尚未被操作。

证据：[WSL 系统组件启用日志](windows-wsl-feature.txt)。

## 2026-10-06 正式运行验收进度

Docker Engine 29.8.2 / linux 已就绪；首次启动前 `lab1-counter_db-data` 不存在。首次构建因 Docker Hub IPv6 认证连接超时失败，直接 `docker pull node:22-alpine` 和 `docker pull nginx:1.27-alpine` 成功后重试构建通过，未改动项目源码。

5.1 已通过：backend、db、frontend 均运行，db 和 frontend 为 healthy，页面首次加载显示 0。

5.2 已完成：在内置浏览器真实点击加三次、减一次得到 2，刷新后仍为 2。

跨浏览器检查进行中：已打开 Edge InPrivate 窗口，但 Windows Computer Use 工具因无法可靠确定浏览器当前 URL 而停止本轮自动化；尚未在该窗口访问验收页面。当前计数保持 2；未继续减到 -1，也未执行服务重启和容器重建。

新增证据：
- `evidence/windows-validation-20261006.txt`：首次启动前卷状态、构建过程和服务状态。
- `evidence/01-services.txt`：三个服务就绪状态。
- `images/windows-validation/01-initial-0.jpg`：页面初值 0。
- `images/windows-validation/02-refresh-2.jpg`：刷新后仍为 2。

下一步：在 Edge InPrivate 手动访问 http://localhost:8080，确认显示 2；然后继续 PDF 5.2 的减三次到 -1，随后执行 5.3、5.4。
