# lab1-counter — 共享计数器（Monorepo + Docker Compose 多容器应用）

Lab 1 实验仓库。前端、后端、数据库初始化脚本与 Compose 部署配置全部放在同一个 Git 仓库中，
执行一次 `docker compose up -d --build` 即可在单台 Docker 主机上启动三个容器组成的多容器应用。

计数结果保存在 PostgreSQL 中；刷新页面、`docker compose restart`，以及 `docker compose down`
后重新 `up`（容器被删除并重建）之后，计数都不会丢失。

---

## 1. 小组成员与分工

> 提交前请把下表替换为本组真实信息（评分项「CodeArts 与小组协作」需要）。

| 角色 | 姓名 | 学号 | Git 身份（user.name） | 实际分工 |
| --- | --- | --- | --- | --- |
| 组长 | 待填写 | 待填写 | 待填写 | Compose 与数据卷、持久化验收、仓库汇总 |
| 组员 | 待填写 | 待填写 | 待填写 | 后端 API 与数据库初始化、前端页面与 nginx 反向代理 |
|

联系助教：待填写　|　CodeArts 项目：`2026高级软件工程_第X小组`　|　代码仓库：`lab1-counter`

## 2. 技术栈与目录结构

| 组件 | 技术选型 | 基础镜像 |
| --- | --- | --- |
| frontend | nginx + 原生 HTML/CSS/JS | `nginx:1.27-alpine`（提供静态页面，并把 `/api` 反向代理到后端） |
| backend | Node.js 22 + Express 4 + `pg` | `node:22-alpine`（计数 API，读写 PostgreSQL） |
| db | PostgreSQL 17 | `postgres:17-alpine`（独立数据库容器，命名卷持久化） |

> 基础镜像均写明具体版本，未使用 `latest`。若需更严格的复现，可在能够访问 Docker Hub 的环境中
> 将三个镜像固定到补丁版本或 digest（例如 `postgres:17-alpine@sha256:…`）。

```text
lab1-counter/
├── frontend/
│   ├── Dockerfile            # 基于 nginx:1.27.4-alpine 构建
│   ├── .dockerignore
│   ├── nginx.conf            # 静态页面 + /api 反向代理到 backend:3000
│   └── html/
│       ├── index.html        # 计数页面
│       ├── styles.css
│       └── app.js            # 调用 /api/counter*
├── backend/
│   ├── Dockerfile            # 基于 node:22-alpine 构建，npm ci 安装依赖
│   ├── .dockerignore
│   ├── package.json
│   ├── package-lock.json     # 锁定依赖版本，保证可复现构建
│   └── server.js             # Express API + 连接重试 + 幂等建表/初始化
├── database/
│   └── init/
│       └── 01-init-counter.sql   # 首次初始化（仅空数据目录时执行）
├── docs/
│   ├── validation.md         # 验收过程、结果与证据说明
│   └── images/               # 验收截图（待补充）
├── compose.yaml              # 三个服务、网络与命名数据卷
├── .env.example              # 环境变量示例
├── .gitignore
├── validate.ps1              # 可选：一键跑完 5.1–5.4 验收并留证
└── README.md
```

## 3. 服务职责与请求流向

```text
浏览器
  │  GET http://localhost:8080/            → 前端容器 nginx 返回 index.html
  │  GET/POST http://localhost:8080/api/…  → 前端容器 nginx 反向代理
  ▼
frontend 容器 (nginx:80)
  │  proxy_pass http://backend:3000        （Compose 网络内按服务名解析）
  ▼
backend 容器 (node:3000)
  │  pg 连接 db:5432                       （Compose 网络内按服务名解析）
  ▼
db 容器 (postgres:5432) ── 命名卷 db-data 挂载到 /var/lib/postgresql/data
```

要点：容器内的 `localhost` 指向容器自身，所以后端用服务名 `db` 连接数据库；浏览器中的
JavaScript 也无法解析 `backend` 这个服务名，因此页面请求同源的 `/api/...`，由前端容器
内的 nginx 转发到 `backend:3000`。

## 4. 运行环境要求

| 依赖 | 版本要求 | 检查命令 |
| --- | --- | --- |
| Git | 任意较新版本 | `git --version` |
| Docker Engine / Docker Desktop | 20.10+ | `docker --version`、`docker info` |
| Docker Compose 插件 | v2+ | `docker compose version` |

宿主机**不需要**安装 Node.js、nginx 或 PostgreSQL：前后端依赖在镜像构建时安装，
数据库使用官方镜像。

## 5. 环境变量说明

复制示例文件后按需修改（默认值可直接使用）：

```bash
cp .env.example .env
```

| 变量 | 默认值 | 作用 |
| --- | --- | --- |
| `FRONTEND_PORT` | `8080` | 前端发布到宿主机的端口，即浏览器访问端口 |
| `BACKEND_PORT` | `3000` | 后端容器内监听端口（不发布到宿主机） |
| `DB_PORT` | `5432` | 数据库发布到宿主机的端口，供数据库客户端查询；若本机已装 PostgreSQL 造成端口占用，改成如 `55432` |
| `POSTGRES_DB` | `counterdb` | 数据库名 |
| `POSTGRES_USER` | `counter` | 数据库用户 |
| `POSTGRES_PASSWORD` | `counter` | 数据库密码 |
| `DB_CONNECT_RETRIES` | `30` | 后端启动时连接数据库的最大重试次数 |
| `DB_CONNECT_RETRY_DELAY_MS` | `2000` | 每次重试间隔（毫秒） |
| `COMPOSE_PROJECT_NAME` | `lab1-counter` | Compose 项目名，决定数据卷名称 `lab1-counter_db-data` |

真正的 `.env` 已被 `.gitignore` 忽略，不要提交到仓库。

## 6. 启动、停止与访问地址

在仓库根目录执行：

```bash
# 1. 准备环境变量
cp .env.example .env

# 2. 校验 Compose 配置语法
docker compose config -q

# 3. 构建镜像并启动全部服务
docker compose up -d --build

# 4. 查看服务状态（三个服务都应为 running / healthy）
docker compose ps -a

# 5. 查看日志
docker compose logs -f backend
```

浏览器访问地址：**http://localhost:8080**（改过 `FRONTEND_PORT` 则相应替换端口）。

停止与重启：

```bash
docker compose restart          # 重启容器，数据保留
docker compose down             # 删除容器和网络，保留命名数据卷 db-data
docker compose up -d --build    # 重新创建容器，数据仍然保留
docker compose down -v          # ⚠️ 删除命名数据卷，计数数据会被清空（持久化验收时禁止执行）
```

## 7. 接口说明

| 方法 | 路径 | 行为 | 成功响应 |
| --- | --- | --- | --- |
| `GET` | `/api/counter` | 查询当前计数值（不修改数据） | `{"value": 0}` |
| `POST` | `/api/counter/increment` | 数据库中的值加 1，返回提交后的值 | `{"value": 1}` |
| `POST` | `/api/counter/decrement` | 数据库中的值减 1，返回提交后的值 | `{"value": 0}` |
| `GET` | `/api/health` | 后端与数据库连通性检查 | `{"status":"ok","database":"up"}` |
| `GET` | `/healthz` | 后端存活检查（容器内） | `{"status":"ok"}` |

失败时返回非 2xx 状态码和 JSON 错误体，例如 `{"error":"failed to increment counter"}`，
前端会显示可见的错误提示。

命令行自测：

```bash
curl http://localhost:8080/api/counter
curl -X POST http://localhost:8080/api/counter/increment
curl -X POST http://localhost:8080/api/counter/decrement
```

## 8. 数据库表结构与查询命令

```sql
CREATE TABLE IF NOT EXISTS counter (
  id         INTEGER     PRIMARY KEY,        -- 固定为 1，全应用共享同一条记录
  value      BIGINT      NOT NULL DEFAULT 0, -- 计数值，允许为负数
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO counter (id, value) VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;                 -- 仅在缺失时初始化为 0，绝不覆盖已有值
```

计数的唯一可信来源是数据库；前端不使用 `localStorage` 或内存变量保存计数。
加减操作由 `UPDATE counter SET value = value + $1 ... RETURNING value` 在事务中原子完成，
并发点击不会相互覆盖。

**查询计数值的完整命令**（适用于 PostgreSQL，需先 `cp .env.example .env`）：

```bash
docker compose exec db psql -U counter -d counterdb -c "SELECT id, value, updated_at FROM counter;"
```

只取值：

```bash
docker compose exec -T db psql -U counter -d counterdb -tAc "SELECT value FROM counter WHERE id = 1;"
```

也可以从宿主机用数据库客户端连接 `localhost:5432`（`DB_PORT`），
用户名 / 密码 / 数据库名见 `.env`。

## 9. 数据卷与持久化

| 项目 | 值 |
| --- | --- |
| 数据卷名称 | `lab1-counter_db-data`（`${COMPOSE_PROJECT_NAME}_db-data`，可用 `docker volume ls` 查看） |
| 挂载位置 | `db` 容器的 `/var/lib/postgresql/data`（postgres 官方镜像的数据目录） |
| 声明位置 | `compose.yaml` 顶层 `volumes:`，由 `db` 服务引用 |

因为数据保存在命名卷而不是容器可写层：

- 刷新页面 / 换浏览器：读到的仍是数据库中的值；
- `docker compose restart`：容器重启，卷不变，数据保留；
- `docker compose down` 后 `up`：**容器被删除并重建**，卷保留，数据仍然存在。

注意：验收持久化时不要执行 `docker compose down -v`，也不要手工删除数据卷或修改计数值。

## 10. 常见问题排查

| 现象 | 原因与处理 |
| --- | --- |
| `docker compose up` 报端口占用 `bind: address already in use` | 宿主机 8080/5432 已被占用。改 `.env` 中的 `FRONTEND_PORT` / `DB_PORT`，再 `docker compose up -d`。查看占用：`netstat -ano \| findstr :8080` |
| 后端日志反复出现 `[db] attempt n/30 failed` | 数据库尚未就绪或密码不一致。确认 `db` 服务 `healthy`：`docker compose ps`；确认 `.env` 中 `POSTGRES_USER/PASSWORD` 与后端使用的值一致。后端自带连接重试，数据库就绪后会自动恢复 |
| `pg_isready` 健康检查一直不通过 | 若曾用旧参数初始化过数据卷，容器内数据库凭据与 `.env` 不一致。开发阶段可 `docker compose down -v` 重建（会清空计数数据），正式验收环境不要这样做 |
| 页面显示「读取失败」或计数不动 | 后端或数据库不可用。先看 `docker compose logs backend`，再访问 `http://localhost:8080/api/health` 确认数据库连通性 |
| 镜像拉取失败 / 超时（`dial tcp … timeout`） | 网络无法访问 Docker Hub。配置镜像加速器或代理后重试；`docker compose up -d --build` 可重复执行 |
| 页面能打开但 `/api/...` 返回 502 | 后端容器未就绪或已退出。`docker compose ps -a` 查看状态，`docker compose logs backend` 查看原因 |
| `docker info` 报 `Docker Desktop is unable to start` / `WSL is unresponsive` | WSL 卡死。见下方「Windows 上修复 WSL」小节 |

## 11. 验收记录

完整验收过程、命令输出与截图见 [`docs/validation.md`](docs/validation.md)。
在 Docker 环境可用后，可在仓库根目录执行 `.\validate.ps1`（Windows PowerShell）按 5.1–5.4
的顺序自动完成一遍验收检查，结果写入 `docs/acceptance-evidence.txt`。

## 12. 附：Windows 上修复 WSL（Docker Desktop 起不来的排查记录）

本节记录本项目开发机上真实遇到并解决的问题，供遇到同样报错的同学参考。

**现象**

```text
Docker Desktop - WSL is unresponsive
running wslexec: ... c:\windows\system32\wsl.exe -l -v --all: exit status 1
```

`wsl -l -v` 一直挂起；`Get-Service WslService` 永远是 `StartPending`；事件日志反复出现：

```text
由于下列错误，WslService 服务启动失败: 服务没有及时响应启动或控制请求。
等待 WslService 服务的连接超时(30000 毫秒)。        （错误 1053）
```

**根因**：机器上已装了新版 WSL 2.7.14（`C:\Program Files\WSL\wsl.exe`），但
`WslService` 的服务注册项仍指向 Windows 自带的旧启动器 `C:\Windows\System32\wsl.exe`，
服务进程根本没起来，于是 WSL 命令全部挂起，Docker Desktop 判定 WSL 无响应。

**排查命令**

```powershell
Get-Service WslService
sc.exe qc WslService          # 看 BINARY_PATH_NAME
sc.exe query WslService       # 看 STATE 与是否 NOT_STOPPABLE
(Get-Item 'C:\Program Files\WSL\wsl.exe').VersionInfo.FileVersion
(Get-Item 'C:\Windows\System32\wsl.exe').VersionInfo.FileVersion
```

**修复（管理员 PowerShell）**：把服务指向新版二进制后启动。

```powershell
sc.exe config WslService binPath= '"C:\Program Files\WSL\wslservice.exe"'
sc.exe config WslService start= auto
sc.exe start WslService
Get-Service WslService        # 应为 Running
wsl -l -v                     # 应立即返回，不再挂起
```

如果 `C:\Program Files\WSL\` 下没有新版二进制，先用管理员身份执行
`wsl --update --web-download`（走微软 CDN，不依赖 Microsoft Store）。

> 注意：`Stop-Service WslService -Force` 对处于 `START_PENDING` 状态的服务会报
> 「服务无法接受控制消息」，此时不要反复重启机器，直接按上面的 `sc config` 改注册项即可。

**网络提示**：如果 `docker compose up -d --build` 报
`failed to resolve reference ... EOF` 或 BuildKit 卡在
`auth.docker.io` 的 IPv6 地址超时，先显式拉取基础镜像再构建：

```bash
docker pull postgres:17-alpine
docker pull node:22-alpine
docker pull nginx:1.27-alpine
docker compose up -d --build
```

`docker pull` 走 registry 客户端（IPv4）通常能成功，而 BuildKit 解析元数据时可能优先走 IPv6。
若完全无法访问 Docker Hub，则需要配置可用代理或在可联网的网络下构建。

