# devspace-mcp-tunnel

把本地代码工作区通过 [DevSpace](https://github.com/Waishnav/devspace)（一个本地 MCP 服务器）
暴露给 ChatGPT / Codex 的完整套件。

核心问题：DevSpace 的公网地址需要一个隧道（本项目用 [Pinggy](https://pinggy.io) 免费 SSH 隧道），
而免费隧道地址是**临时、会过期**的（Pinggy 免费版约 60 分钟）。一旦过期，所有配置里的 URL 都得改。

本仓库提供：

- `setup.sh` —— 安装 DevSpace 并交互式初始化配置（`devspace init`）。
- `refresh-devspace-mcp.sh` —— 一键**重建隧道 → 抓取新地址 → 同步 3 处配置 → 重启 DevSpace**，
  解决"隧道过期后手动改一堆地方"的痛点。
- `.mcp.json.example` —— `项目级 MCP 配置`模板。
- `.gitignore` —— 已配置好，避免把含密码的 `.devspace/` 和带临时地址的 `.mcp.json` 提交上去。

---

## 工作原理

```
 ChatGPT / Codex  ──HTTPS──▶  公网隧道(临时域名)  ──local──▶  DevSpace(127.0.0.1:7676)  ──▶  本地工作区文件/Shell
```

- DevSpace 监听本机 `127.0.0.1:7676`，并通过 OAuth（Owner 密码）做授权审批。
- 隧道把公网 HTTPS 域名反向代理到本机 7676 端口。
- MCP 客户端连接的是 `https://<隧道域名>/mcp`，DevSpace 的 OAuth `issuer` 来自配置里的 `publicBaseUrl`（即隧道域名，不带 `/mcp`）。

> ⚠️ **关键坑**：`publicBaseUrl` 必须是**域名根（不带 `/mcp`）**；只有客户端的连接 URL 才带 `/mcp`。
> 写错会导致 `issuer mismatch` OAuth 报错。`refresh-devspace-mcp.sh` 已自动处理这个细节。

---

## 快速开始

### 1. 安装并初始化

```bash
git clone https://github.com/Embracecactus/devspace-mcp-tunnel.git
cd devspace-mcp-tunnel
chmod +x setup.sh refresh-devspace-mcp.sh

# 国内网络加 --mirror 走 npmmirror，速度快很多
./setup.sh --mirror
```

`setup.sh` 会交互式运行 `devspace init`，按提示填：

- **项目目录**：想让 ChatGPT/Codex 访问的本地目录（如 `/path/to/your/project`）
- **端口**：`7676`
- **公网 base URL**：先随便填，`refresh-devspace-mcp.sh` 第一次运行会自动改写 `config.json` 的 `publicBaseUrl`

### 2. 启动隧道 + 同步配置 + 启动服务

```bash
./refresh-devspace-mcp.sh --tunnel-cmd "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 443 -R0:localhost:7676 a.pinggy.io"
```

脚本会依次：停旧隧道 → 起新隧道 → 抓取新地址 → 更新 `.mcp.json`、`~/.devspace/config.json`、`~/.codex/config.toml` → 重启 DevSpace。

### 2b. 用其他隧道（ngrok / cloudflared / bore …）

本脚本**不绑定 Pinggy**，只要告诉它怎么抓地址即可：

**方式 A：让脚本抓地址**（隧道会把 URL 打到 stdout）

```bash
# ngrok 示例：用 --url-regex 指定抓取规则
./refresh-devspace-mcp.sh \
  --tunnel-cmd "ngrok http 7676" \
  --url-regex 'https://[a-z0-9-]+\.ngrok-free\.app'

# cloudflared 示例
./refresh-devspace-mcp.sh \
  --tunnel-cmd "cloudflared tunnel --url http://localhost:7676" \
  --url-regex 'https://[a-z0-9-]+\.trycloudflare\.com'
```

**方式 B：你已经有地址，跳过隧道管理**

```bash
./refresh-devspace-mcp.sh --known-url "https://abc-123.ngrok-free.app/mcp"
```

脚本只做"同步 3 处配置 + 重启 DevSpace"，不打理隧道（你自己的隧道自行运行）。

### 3. 客户端授权

**Codex CLI：**

```bash
codex mcp login devspace
# 浏览器打开后，输入 DevSpace 的 Owner 密码（在 ~/.devspace/auth.json 里）完成授权
```

**网页版 ChatGPT：**

Settings → Apps & Connectors → Advanced → Developer Mode → Create connector，
填入 `https://<隧道域名>/mcp`，按页面提示用 Owner 密码授权。

> 注意：网页版 ChatGPT 的连接器地址在隧道过期后需**手动**更新；Codex CLI 与 `.mcp.json`
> 可通过重跑 `refresh-devspace-mcp.sh` 自动同步。

### 4. 隧道过期后

免费隧道约 60 分钟失效。重跑第 2 步的命令即可**全自动**刷新（无需手动改任何配置）。

### 5. 把它当 agent 用：静态代码审查（不改代码）

本套件的目的不是"只把文件给你看"，而是让连上来的 ChatGPT/Codex **像一个 agent 一样**
直接操作你的工作区：读文件、`grep`/读代码、跑脚本、产出审查结论——全程不需要本地
CodeBuddy 参与。DevSpace 暴露的 **shell + 文件访问** 就是 agent 的"手和眼"
（等价 `codegraph + shell` 的组合）。

典型用法：让 agent 做**纯静态人工审查 + 问题清单 + 报告**，不修改源码、不参与 CI 修复。
本仓库附带 `review.sh` 与 `templates/`，把这套产出结构化、可复用：

```bash
# 在已被 DevSpace 暴露的工作区里（或直接由 agent 通过 DevSpace shell 调用）
./review.sh --path src --glob '*.c' --out review-report.md
```

- `review.sh`：只读脚本。扫描目录、列出待审查文件、生成带空问题表的报告骨架。
  **不修改任何源码**，agent 在骨架上填写发现的问题即可。
- `templates/review-report.md`：完整报告模板（概述 / 范围 / 原则 / 文件清单 / 问题清单 / 总结）。
- `templates/issue-list.md`：精简的问题清单模板（单表）。

和 agent 约定的审查原则：纯静态人工审查、不修改代码、不参与 CI 修复；
仅产出问题清单与报告，是否采纳修复由人工决定。

---

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `setup.sh` | 安装 DevSpace + 跑 `devspace init`（`--mirror` 走国内镜像） |
| `refresh-devspace-mcp.sh` | 重建隧道、抓新地址、同步 3 处配置、重启 DevSpace |
| `review.sh` | 静态审查脚手架（只读）：扫描目录、生成带问题表的报告骨架 |
| `templates/review-report.md` | 完整审查报告模板 |
| `templates/issue-list.md` | 精简问题清单模板 |
| `.mcp.json.example` | 项目级 MCP 配置模板，复制为 `.mcp.json` 后把 URL 换成实际隧道地址 |
| `.gitignore` | 忽略含密码的 `.devspace/` 和带临时地址的 `.mcp.json` |

`refresh-devspace-mcp.sh` 还支持更多参数（见 `./refresh-devspace-mcp.sh --help`），
例如自定义 `devspace serve` 命令、停止旧进程的命令、超时时间、codex 配置路径等。

---

## 踩坑记录（Troubleshooting）

1. **`Authorization server issuer mismatch`**
   客户端报 `expected .../ , received .../mcp`。原因：`config.json` 的 `publicBaseUrl`
   被写成了带 `/mcp` 的地址。DevSpace 用 `publicBaseUrl` 推导 OAuth issuer，再用
   `publicBaseUrl + "/mcp"` 作为 MCP 端点。修复：让 `publicBaseUrl` 为纯域名根，
   仅客户端 URL 带 `/mcp`。`refresh-devspace-mcp.sh` 已自动剥离 `/mcp`。

2. **`devspace: command not found` / `Permission denied`**
   - 非交互 shell 不会继承某些 shell 快照注入的 PATH。脚本已自动补全 pi-node/npm 全局 bin 目录到 PATH。
   - npm 有时给 `devspace` 的 bin 软链接目标（cli.js）不加可执行位，导致 `Permission denied`。
     脚本已加 `chmod +x` 自愈。手动修：`chmod +x $(readlink -f $(which devspace))`。

3. **脚本自杀（重启/清理时把自己 kill 掉）**
   用 `pkill -f 'pinggy'` / `pkill -f 'devspace serve'` 这类模式匹配，会命中脚本自身 argv
   （里面含有这些字符串）而误杀自己。脚本改为：用 tmux session 名 + pidfile 记录 PID 来精确清理隧道，
   用匹配 `cli.js serve` 与 `devspace serve` 两种进程形态来停旧 DevSpace。

4. **`setsid: failed to execute eval`**
   `setsid` 不能 exec shell 内建命令 `eval`。改为 `setsid bash -c "$CMD"`。

5. **npm 默认源卡死**
   国内网络直接用默认 npm registry 会长时间挂起。用 `./setup.sh --mirror`（已 `npm config set registry https://registry.npmmirror.com`）。

---

## 安全提示

- **绝不要提交** `~/.devspace/`（含 `auth.json` 里的 Owner 密码）和带临时地址的 `.mcp.json`。
  仓库 `.gitignore` 已默认忽略它们。
- 隧道是公网可达的，任何知道地址 + Owner 密码的人都能读写你的工作区。只在**需要时**开启隧道，
  用完用 `tmux kill-session -t pinggy` 关掉。免费隧道本就会 60 分钟自动失效。
- DevSpace 的 OAuth Owner 密码建议设置成自定义强密码（在 `devspace init` 时指定）。

---

## 关于额度（usage limit）

`You've hit your usage limit` 这类提示**来自 OpenAI Codex/ChatGPT 侧**，不是 DevSpace 的问题。
DevSpace 只是把本地目录暴露给 Codex，真正消耗额度的是 Codex 跑模型。额度到上限后去
`chatgpt.com/codex/settings/usage` 购买或等待提示中的重置时间点即可，与本地隧道/配置无关。
