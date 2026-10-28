在 macOS 菜单栏查看多个 Codex 会话的状态和公开进度。

- 每个会话一个独立图标，左键打开会话，右键预览完整进度。
- 运行中黄色呼吸光，出错红色常亮，完成绿色呼吸光。
- 完成后保留，点击打开后只收起这一条，其他会话继续显示。
- 支持字号、宽度、颜色和滚动设置，可在程序中设置登录后启动。

本次更新：恢复与应用图标一致的石墨灰底色，改用清晰的实色浅色文字，移除深浅模式与镂空选项。切换窗口后仍保持固定配色，边框在呼吸光变暗时也保持可见。

![菜单栏与右键预览](https://github.com/wenrui0128/codex-menu/releases/download/v0.5.6/CodexMenu-right-click-preview.png)

[查看高清图](https://github.com/wenrui0128/codex-menu/releases/download/v0.5.6/CodexMenu-right-click-preview.png)

支持 macOS 13 或以上，Apple Silicon / Intel。

命令行安装（默认 `~/Applications`，无需 sudo，需自行设置自动启动）：

```sh
curl -fsSL https://github.com/wenrui0128/codex-menu/releases/latest/download/install.sh -o /tmp/codex-menu-install.sh
bash /tmp/codex-menu-install.sh
```

仅下载、不安装：

```sh
bash /tmp/codex-menu-install.sh --download-only "$HOME/Downloads/CodexMenu"
```

更新前请退出旧版。安装器校验 SHA-256 和应用签名。应用尚未经过 Apple 公证，如被 macOS 拦截，可在“系统设置 → 隐私与安全性”中批准打开。
