# Windows 启动项清理工具（图形界面版）

这是一个适合代码小白使用的 Windows 开机自启动识别/清理工具。

它会识别开机自启动项和当前高内存进程，并把启动项分成：

- `KEEP`：建议保留，通常和系统、安全、驱动、输入法、网络代理等有关。
- `OPTIONAL_DISABLE`：通常可关闭，不影响 Windows 正常使用，需要时可手动打开软件。
- `REVIEW`：需要你确认用途后再决定。

## 最简单使用方法

双击这个文件：

```text
Launch-StartupCleaner-GUI.bat
```

如果禁用时提示权限不足，请右键 `Launch-StartupCleaner-GUI.bat`，选择“以管理员身份运行”。

## 图形界面怎么用

1. 打开后会自动扫描，也可以点“扫描启动项”。
2. 黄色的 `OPTIONAL_DISABLE` 是通常可以关闭的开机自启动项。
3. 点击“勾选建议关闭”，或自己手动勾选想关闭的项目。
4. 点击“禁用勾选项”。
5. 重启电脑后观察内存是否下降。
6. 如果有问题，打开工具点“恢复已禁用”。

## 命令行用法（可选）

只扫描并生成报告：

```powershell
powershell -ExecutionPolicy Bypass -File .\StartupCleaner.ps1 -Scan
```

交互式选择要禁用的可选启动项：

```powershell
powershell -ExecutionPolicy Bypass -File .\StartupCleaner.ps1 -Interactive
```

恢复被脚本禁用的注册表启动项和计划任务：

```powershell
powershell -ExecutionPolicy Bypass -File .\StartupCleaner.ps1 -Restore
```

报告会保存到 `startup-cleaner-output` 文件夹。

## 根据你截图的初步建议

通常可以考虑禁用自启动，但不卸载：

- 微信 / WeChat / Weixin / WeChatAppEx：需要时手动打开即可。
- 360 安全浏览器：如果不是每天开机就用，可关闭自启动。
- Google Chrome：浏览器本身不应常驻大量后台进程，可关闭后台运行和自启动。
- CodePilot / Codex：如果不是开机立即使用，可关闭自启动。
- CC Switch：如果不是必须开机自动切换配置，可关闭。

建议保留或谨慎处理：

- Windows 资源管理器、搜索、输入法、驱动、显卡、声卡、安全防护组件。
- Clash Verge：如果你依赖代理联网，可保留；不用代理时可关闭。
- Microsoft Edge WebView2：很多软件界面依赖它，不建议单独删除。

## 安全说明

工具默认先扫描，不会自动乱禁用。图形界面会阻止你禁用 `KEEP` 项；对 `REVIEW` 项会再次提醒确认。禁用前会保存备份，方便恢复。
