# Longshot 中文化补丁（简体中文）

给 **Longshot**（塞尔达传说：时之笛 PC 原生移植版）和 **Longshot Launcher**（构建/启动器）补全中文界面的补丁。

> 官方版本自带部分机器翻译，但 v3.1.1 / 启动器 v1.2.0 里仍有大量界面文字是英文（NFC 页、存储页、CRT 滤镜、物品栏编辑器、输入录制等新功能都没进翻译表，启动器 NFC 页甚至是硬编码英文）。本补丁把这些全部补成简体中文，并额外生成对应的繁体中文（游戏菜单内）。

---

## 一、适用范围

| 项目 | 适用版本 | 说明 |
|---|---|---|
| 游戏内菜单（Insert 菜单） | Longshot **v3.1.1** | 替换 `bin\longshot_vk.dll` |
| 启动器界面 | Longshot Launcher **v1.2.0** | 替换 `LongshotLauncher.exe` |

⚠️ 其它版本不保证兼容。游戏版本可在游戏文件夹的 `longshot_version.txt` 里看到；启动器版本可在启动器窗口标题看到。

---

## 二、安装（推荐：直接下载发布包）

1. 打开 [Releases](../../releases) 页面，下载最新的 `Longshot-zhCN-*.zip`。
2. 解压到任意位置（**要整个文件夹一起解压**，不要只拿 .bat 出来）。
3. 先完全退出游戏和启动器。
4. 双击 **`安装游戏汉化.bat`** —— 自动找到游戏文件夹、备份原 DLL、替换成中文版。
5. 双击 **`安装启动器汉化.bat`** —— 自动找到已安装的启动器、备份并替换。
6. 打开启动器 → 界面应为中文；进入游戏按 **Insert** → 菜单应为中文。

脚本找不到安装位置时，会提示你粘贴路径，照着提示操作即可。

### 让菜单显示中文的两个前提

- 游戏语言是简体中文：游戏文件夹的 `language.txt` 里那一行是 `zh-Hans`（官方中文版默认如此）。
- 菜单语言是「自动（跟随游戏语言）」：Insert 菜单 → `语言` 页 → 菜单语言 → 自动。也可以直接选「简体中文」。

---

## 三、还原

双击 **`还原原版.bat`**，会用安装时自动备份的 `.zhCN-backup` 文件把原版恢复回去。

（如果你通过启动器的「重新构建」把游戏升级/重建过，游戏文件本来就已经是官方版了，只有需要时才用还原脚本。）

---

## 四、更新后怎么办

- **启动器更新**：官方更新会覆盖成英文版。等本补丁适配新版本后再装，或者直接用当前版本（启动器不更新也能正常用）。
- **游戏重新构建/更新**：会换成官方英文 DLL。等本补丁适配新版本，或自行按下面的「自行构建」把翻译编译进新版。

---

## 五、本补丁改了什么

### 游戏内菜单（`longshot_vk.dll`）
- 在 `gpu/vk/menu_i18n.h` 的中文表里补了 **415 条**菜单界面翻译（画面/音频/游戏/按键设置/NFC/调试 各页的标签、说明、选项名）。
- 补了 **86 个物品栏道具名**（科吉里剑、大师剑、海利亚盾、德库树盾、火焰箭……）以及 **装备/面具/升级/任务** 分类名。
- 繁体中文表由简体自动转换生成，同步补齐。

### 启动器（`LongshotLauncher.exe`）
- 中文词条从 700 条补到 **1147 条**（设置页、存储页、主页、拉取请求、存档编辑器等）。
- **把 NFC 页面从硬编码英文改为接入翻译系统**（`NfcView.axaml` 21 处文字、`NfcViewModel.cs` 16 处字符串），所以 NFC 页现在是中文。

### 保留英文的部分
- 品牌名：NVIDIA DLSS / DLAA / Reflex、AMD FSR、Intel XeSS、Lanczos、CRT 预设名等（业界惯例保留）。
- 游戏崩溃/报错弹窗（官方所有语言版本都是英文）。
- 少数技术标识（环境变量名、日志行）。

---

## 六、自行构建（给想自己编译的人）

本仓库 `source/` 下是改动后的源文件，可作为 GPL 对应的「可构建源代码」。

**游戏 DLL**（需要已装好官方 Longshot v3.1.1 及其构建工具）：
1. 把 `source/menu_i18n.h` 覆盖到
   `%LOCALAPPDATA%\LongshotLauncher\toolchains\v3.1.1\LongshotBuilder\tools\gpu\vk\menu_i18n.h`
2. 用命令行重新构建（关闭游戏后执行）：
   ```bat
   set TOOLS=%LOCALAPPDATA%\LongshotLauncher\toolchains\v3.1.1\LongshotBuilder\tools
   set PYTHONUTF8=1
   "%TOOLS%\python\python.exe" -I "%TOOLS%\nx2\make_game.py" --update "C:\Games\Longshot\stable\v3.1.1" --work "C:\Games\Longshot\LongshotLauncher\work" --fetch-ngx-sdk --accept-nvidia-license
   ```
   约 10 分钟；构建完 `bin\longshot_vk.dll` 就是中文版。

**启动器**（需要 .NET 10 SDK）：
1. 克隆官方源码 https://git.magicbean.dev/MagicBeanDev/LongshotLauncher ，检出 `v1.2.0`。
2. 用 `source/launcher/` 里的文件覆盖对应的 `App/Views/NfcView.axaml`、`App/ViewModels/NfcViewModel.cs`、`Core/Lang/zh-Hans.json`。
3. 构建：
   ```bat
   dotnet publish App/LongshotLauncher.csproj -c Release -r win-x64 --self-contained ^
     -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none ^
     -p:LongshotTag=v1.2.0 -p:Version=1.2.0 -o out
   ```

---

## 七、许可与致谢

- 本补丁基于 [Longshot](https://git.magicbean.dev/MagicBeanDev/Longshot)（GPL-3.0-or-later）与
  [Longshot Launcher](https://git.magicbean.dev/MagicBeanDev/LongshotLauncher)（GPL-3.0-or-later）的源代码修改而成，
  同样以 **GPL-3.0-or-later** 发布。修改后的源文件见 `source/`。
- 补丁**不包含**游戏本体，也不附带任何 NVIDA/AMD/Intel 的 SDK 文件；游戏本体请用你自己的游戏转储构建。
- 感谢 MagicBeanDev 团队和 Hookshot 项目。

---

## 八、常见问题

**Q：装了之后菜单还是英文？**
A：先确认 `language.txt` 是 `zh-Hans`、Insert 菜单 → 语言 → 菜单语言为「自动」；再确认替换的是**正在玩的那个**游戏文件夹（启动器里可以看每个版本的文件夹路径）。

**Q：启动器打开报错/被 Windows 拦截？**
A：本补丁只是把官方 exe 换成了我们自己用官方源码重新编译的版本（无数字签名，Windows 可能提示"未知发布者"，点"仍要运行"）。

**Q：杀毒软件报毒？**
A：`.bat` 只是调用 PowerShell 复制文件，可自行打开查看内容。exe/dll 为官方源码自行编译。

**Q：游戏更新后中文没了？**
A：正常，更新会覆盖文件。见上面「更新后怎么办」。
