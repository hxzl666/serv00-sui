# S-UI FreeBSD (Serv00/Hostuno) 适配分支

S-UI 是一款基于 **SagerNet/Sing-Box** 构建的高级 Web 管理面板。本分支专为 **FreeBSD 平台**（特别是 **Serv00** 与 **Hostuno** 虚拟主机）进行了深度适配，支持在**非 root 权限**下进行一键现场编译、安装、面板控制以及进程定时保活守护。

---

## 🌟 核心适配特性

* **免 Root 安装**：自适应非 root 环境，将所有数据及二进制安装至用户家目录（`~/s-ui`）。
* **零配置现场编译**：如果服务器没有 Go 语言环境，脚本会自动在临时目录部署 Go 编译器，编译完成后自动清理，实现零依赖一键构建。
* **前端静态资源嵌入**：预打包前端网页代码，在 Go 编译阶段直接嵌入二进制内部，避免在虚拟主机上运行 npm 构建导致内存溢出（OOM）。
* **服务器 3 入口智能识别**：自动根据机器 hostname 提取并生成 Serv00 节点的 3 个可用网络入口域名（主域名、Web 备用域名、管理面板域名），并在安装成功时直观展示访问地址。
* **定时保活自动守护**：内置去重写入技术，自动将进程检测与拉起任务注册到系统 Crontab 中，实现服务每分钟自动保活及开机自动拉起。
* **自适应控制菜单**：重写了原版脚本中对 Linux systemd 的硬编码依赖，在 FreeBSD 下全面适配为基于 `pgrep` 和 `pkill` 的纯原生控制逻辑。

---

## 🛠️ 安装与部署步骤

### 步骤 1：本地前端构建（只需执行一次）
S-UI 的 Web 页面是在编译时直接打包进后端二进制中的。由于虚拟主机资源极其有限，请先在您的本地环境（有 Node.js 和 npm 环境的 Windows/Mac）中生成前端静态文件：

```bash
# 1. 拉取前端子模块源码
git submodule update --init --recursive

# 2. 进入前端目录安装依赖并构建
cd frontend
npm install
npm run build
cd ..

# 3. 复制前端编译产物到 web/html 供 Go 编译器读取
mkdir -p web/html
cp -R frontend/dist/* web/html/
```

### 步骤 2：上传代码至虚拟主机
将本地的整个项目文件夹（已包含 `web/html` 目录）上传至您的 Serv00 / Hostuno 服务器空间（例如上传至 `~/s-ui-src` 目录）。

### 步骤 3：运行安装脚本
通过 SSH 登录到您的虚拟主机，进入您上传的源码目录，执行：

```bash
bash install.sh
```

**在安装过程中，您需要：**
1. 输入您在服务商后台（如 DevilWEB）提前申请并放行的**面板访问端口**。
2. 输入您申请的**订阅服务端口**。
3. 设置您的管理员账号和密码（默认均为 `admin`）。

安装完成后，脚本会输出以下格式的访问指南，展示您的 **3 个域名入口** 的面板访问地址：
* **主域名入口 (首选)**: `http://sXX.serv00.com:面板端口/app/`
* **Web 备用域名**: `http://webXX.serv00.com:面板端口/app/`
* **管理面板域名**: `http://panelXX.serv00.com:面板端口/app/`

---

## ⌨️ 命令行控制菜单

安装完成后，脚本已在您的家目录下配置了控制快捷方式。您可以在终端中直接输入 `s-ui` 调出交互式图形管理菜单：

```bash
s-ui
```

### 快捷控制指令

| 指令 | 说明 |
| :--- | :--- |
| `s-ui start` | 启动 S-UI 服务 |
| `s-ui stop` | 停止 S-UI 服务 |
| `s-ui restart` | 重启 S-UI 服务 |
| `s-ui status` | 查看服务当前的运行状态 (PID) |
| `s-ui log` | 查看并追踪面板运行日志 |
| `s-ui enable` | 开启 Crontab 每分钟定时自启动保活 |
| `s-ui disable` | 关闭 Crontab 定时保活 |
| `s-ui uninstall` | 彻底卸载面板并删除所有配置数据 |

---

## 💡 注意事项

1. **端口放行**：Serv00/Hostuno 运行的应用必须监听在您名下申请过的端口（Port Reservation），**请勿使用未被分配的端口**，否则服务将无法正常监听和连通。
2. **应用权限**：运行前请确保在 DevilWEB 控制面板的 `Additional services` -> `Run your own applications` 菜单中将权限设置为 `Enabled`。
3. **节点配置**：在使用本面板创建 sing-box 节点入站时，请同样使用您申请并空闲的端口。
