原生 macOS 菜单栏工具，用独立图标显示多个本机 Codex 会话的公开进度。

- 每个会话一个原生图标，左键打开会话，右键预览公开进度。
- 运行中黄灯闪烁、错误红灯常亮、完成绿灯闪烁。
- 保留完成会话，打开后仅收起该条；支持字号、宽度、主题和滚动设置。
- Universal 2 安装包：Apple Silicon / Intel，macOS 13 或以上。

命令行安装（默认 `~/Applications`，无需 sudo，需自行设置自动启动）：

```sh
curl -fsSL https://github.com/wenrui0128/codex-menu/releases/latest/download/install.sh -o /tmp/codex-menu-install.sh
bash /tmp/codex-menu-install.sh
```

仅下载、不安装：

```sh
bash /tmp/codex-menu-install.sh --download-only "$HOME/Downloads/CodexMenu"
```

安装器校验 ZIP 的 SHA-256；更新前请先退出旧版工具。应用使用临时本地签名，未经过 Apple 公证。从浏览器下载后若被 macOS 拦截，可在“系统设置 → 隐私与安全性”中批准打开。数据只保存在本机，不包含在发布附件中。
