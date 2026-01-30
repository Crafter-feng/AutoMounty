# AutoMounty

AutoMounty 是一款 macOS 菜单栏应用，用于自动挂载局域网共享（SMB/AFP/NFS/WebDAV/FTP）。支持规则化自动挂载、Bonjour 发现、启动自动运行、日志记录等功能，适合 NAS / 共享目录的自动连接场景。

## 功能特性

- 共享挂载管理：添加、编辑、删除共享配置
- 自动挂载规则：WiFi / VPN / 运行中的应用，支持 All/Any 逻辑
- 手动卸载保护：手动卸载后不会自动重挂载
- 自动挂载防抖：网络抖动时避免重复挂载
- 菜单栏操作：快速查看状态、挂载/卸载、打开 Finder
- Bonjour 发现：扫描局域网 SMB/AFP 服务器并一键导入
- Bonjour IP 自动更新：在 IP 变化时自动更新配置
- 启动项管理：支持开机自启
- 日志系统：按级别输出并持久化到文件

## 界面预览（占位）

> 你可以在对应位置替换图片文件

- 主界面（配置与规则）

  ![主界面](docs/screenshots/main.png)

- 菜单栏（快捷操作）

  ![菜单栏](docs/screenshots/menubar.png)

- 网络发现（Bonjour 扫描）

  ![网络发现](docs/screenshots/discovery.png)

- 设置（日志与启动项）

  ![设置](docs/screenshots/settings.png)

## 系统要求

- macOS 14+
- Swift 5.9（SwiftPM 构建）

## 快速开始

### 构建

```bash
swift build --disable-sandbox -c release
```

### 打包并启动（推荐）

```bash
./build_app.sh
```

运行后可从菜单栏打开主界面。

## 使用说明

### 添加共享

- 主界面点击 “Add Share” 添加共享
- 可选择简单模式（直接输入 URL）或高级模式（自定义协议/端口/路径）

支持协议示例：

- `smb://user@host/share`
- `afp://host/share`
- `nfs://host/share`
- `http://host:port/share`（WebDAV）
- `https://host:port/share`（WebDAV）
- `ftp://host/share`（只读）

### 自动挂载规则

规则类型：

- WiFi：按 SSID 匹配
- VPN：按接口名/是否连接匹配
- App：按运行中的应用名称匹配（可搜索）

逻辑：

- All：全部条件满足才挂载
- Any：满足任一条件即挂载

无规则时会视为“自动挂载开启且无需网络条件”。

### 菜单栏快捷操作

- 快速查看挂载状态
- 一键挂载 / 卸载
- 打开挂载目录
- 直接进入设置 / 扫描发现页

### 设置

- Launch at Login：开机自启
- Auto Update Server IP via Bonjour：自动更新 Bonjour 发现的 IP
- Log Level：日志级别
- Open Log Folder：打开日志目录

## 数据与日志

### 配置文件

共享配置保存在：

```
~/Library/Application Support/AutoMounty/profiles.json
```

### 日志文件

日志保存在：

```
~/Library/Logs/AutoMounty/automounty.log
```

## 项目结构（简要）

- `source/MountyApp.swift` 应用入口与窗口定义
- `source/ContentView.swift` 主界面与侧边栏
- `source/RuleEditorView.swift` 规则编辑与挂载配置
- `source/MountyMonitor.swift` 网络监控与自动挂载决策
- `source/MountyManager.swift` 挂载/卸载与状态管理
- `source/NetworkDiscovery.swift` Bonjour 发现与解析
- `source/ProfileAddingService.swift` 添加共享的校验与预挂载
- `source/Logger.swift` 日志系统

## 常见问题

### WiFi 规则无法获取 SSID

macOS 获取 SSID 可能需要位置权限，确保系统权限允许应用访问网络信息。

### 为什么会出现重复挂载

已加入“挂载中状态 + 冷却时间”双重防护，避免网络变化时重复挂载。

