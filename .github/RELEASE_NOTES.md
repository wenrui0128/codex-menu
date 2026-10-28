v0.5.5 收紧总入口图标旁的留白，修复浅色外观，并加入自定义颜色和整圈状态呼吸光。

- 总入口无溢出计数时从 44 pt 收紧至 28 pt；显示“+N”时按需展开。
- 默认使用透明底色，融入系统菜单栏；手动选择浅色、深色会立即应用到每个会话条目。
- 设置新增“颜色与外观”：可选底色、文字颜色和底色不透明度，预览即时更新。
- 状态光环沿整个会话条目显示：运行中黄色呼吸、完成绿色呼吸、错误红色常亮。左侧圆点保留状态色。悬停仅暂停文字；关闭动效或启用系统“减少动态效果”时，光环保持常亮。

![透明底色、深色菜单栏与强制浅色效果](https://github.com/wenrui0128/codex-menu/releases/download/v0.5.5/appearance-proof.jpg)

[查看颜色设置界面](https://github.com/wenrui0128/codex-menu/releases/download/v0.5.5/CodexMenu-colors.png)

原生 macOS 菜单栏工具，用独立图标显示多个本机 Codex 会话的公开进度。

- 每个会话一个原生图标，左键打开会话，右键预览公开进度。
- 运行中黄色呼吸光、错误红色常亮、完成绿色呼吸光。
- 保留完成会话，打开后仅收起该条；支持字号、宽度、主题和滚动设置。
- Universal 2 安装包：Apple Silicon / Intel，macOS 13 或以上。

**右键预览**

右键会话条目即可查看对应会话的完整公开进度。

![Codex Menu 右键预览，红框强调菜单栏与对应进度卡片](https://github.com/wenrui0128/codex-menu/releases/download/v0.5.2/CodexMenu-right-click-preview.png)

[下载高清原图（3200 × 2000 PNG）](https://github.com/wenrui0128/codex-menu/releases/download/v0.5.2/CodexMenu-right-click-preview.png)

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
