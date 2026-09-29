# local-tools 跨平台仓库与 Claude RC 自动启动设计

日期：2026-09-29  
状态：已批准并实施
首期平台：macOS

## 1. 背景与目标

`tianweichao92/local-tools` 是面向个人电脑环境的公开工具集合，长期允许同时包含 macOS、Windows 和 Linux 实现。仓库本身不绑定单一操作系统；每个工具独立声明支持矩阵，并在自己的平台目录内实现安装、卸载和测试。

首个工具为 `claude-rc-autostart`。它在 macOS 图形登录后打开 Terminal，并启动 Claude Code Remote Control。首期只交付 macOS 实现，Windows 和 Linux 明确标记为暂未支持，不创建空实现或伪兼容层。

## 2. 非目标

- 不在首期实现 Windows Task Scheduler 或 Linux systemd 用户服务。
- 不安装 Claude Code，不代替用户登录 Claude，不读取、复制或迁移凭证。
- 不使用 `sudo`，不写入系统级 LaunchDaemon。
- 不承诺 Remote Control 服务端永久在线；工具只负责正确启动本地命令。
- 不把任何用户名、主目录、令牌、日志或本机绝对路径提交到公开仓库。

## 3. 仓库结构

```text
local-tools/
├── AGENTS.md
├── LICENSE
├── README.md
├── docs/
│   └── superpowers/specs/
└── tools/
    └── claude-rc-autostart/
        ├── README.md
        ├── platforms/
        │   └── macos/
        │       ├── install.sh
        │       └── uninstall.sh
        └── tests/
            └── macos/
                └── test-install.sh
```

根 README 只说明仓库是跨平台工具集合和各工具的实际支持状态。平台限制写在工具 README 和对应安装器中。

## 4. 支持矩阵

`claude-rc-autostart` 首期支持矩阵：

| 平台 | 状态 | 实现 |
| --- | --- | --- |
| macOS | 已支持 | Terminal.app + 用户级 LaunchAgent |
| Windows | 暂未支持 | 无 |
| Linux | 暂未支持 | 无 |

macOS 安装器首先核验 `uname -s` 为 `Darwin`。其他系统立即返回清晰错误，且在退出前不创建目录、不写文件、不调用系统服务管理命令。

## 5. macOS 安装接口

公开的一键安装命令：

```bash
curl -fsSL https://raw.githubusercontent.com/tianweichao92/local-tools/main/tools/claude-rc-autostart/platforms/macos/install.sh | bash
```

可选指定工作目录：

```bash
curl -fsSL https://raw.githubusercontent.com/tianweichao92/local-tools/main/tools/claude-rc-autostart/platforms/macos/install.sh \
  | bash -s -- --workdir "/path/to/workspace"
```

安装器提供：

- `--workdir PATH`：Remote Control 的工作目录，默认当前登录用户主目录。
- `--dry-run`：仅输出探测结果和计划写入位置，不修改本机。
- `--no-start`：完成文件安装并写入 LaunchAgent 文件，但不立即触发一次启动。
- `--no-start` 的具体行为是只写入 `~/Library/LaunchAgents` 文件，不在当前会话执行 `launchctl bootstrap`；下次图形登录时才加载。
- `--force`：仅在目标位置存在无法确认归属的同名文件时允许显式覆盖；默认不覆盖。
- `--help`：显示用法。

卸载器只移除本工具创建的 LaunchAgent、命令入口和工具文件，不删除 Claude Code 会话或授权。

## 6. 本机路径探测与命令生成

公开脚本不得包含 `/Users/your-name` 一类个人主目录路径或预设的单机 Claude 路径；常见安装位置仅可作为运行时探测候选。

安装流程按以下顺序解析环境：

1. 用 `id -u` 拒绝 root 执行，用 `id -un` 获取当前用户。
2. 用 macOS 用户目录信息获取主目录；无法取得时才回退到经过目录存在性校验的 `$HOME`。
3. 默认 `WORKING_DIR` 为解析后的主目录；提供 `--workdir` 时将其规范化为绝对路径并确认目录存在。
4. 优先使用 `command -v claude`，随后检查 macOS 常见位置，包括 Apple Silicon Homebrew、Intel Homebrew 和用户级安装目录。
5. 确认 Claude 可执行，并从 `claude --help` 验证当前版本包含 Remote Control 能力；不满足时停止安装并提示升级。
6. 安装器把解析出的工作目录写入本机生成的启动脚本；Claude 路径在运行时再次解析，使 Homebrew 或 Claude 升级后的路径变化不必重新安装。
7. 启动脚本使用 zsh 的安全引用能力分别转义工作目录和 Claude 路径，再拼装 Terminal 命令；不直接拼接未经校验的用户输入。

Terminal 中执行正式、可读的入口：

```bash
claude --remote-control
```

它对应本机已验证的 `claude rc` 快捷入口，但公开工具使用完整参数，便于能力检测和维护。

## 7. 安装产物

所有产物位于当前用户目录：

```text
~/.codex/local-tools/claude-remote-control-autostart/
├── start-claude-rc.zsh
└── logs/

~/.codex/bin/claude-rc-autostart
~/Library/LaunchAgents/io.github.tianweichao92.local-tools.claude-remote-control.plist
```

LaunchAgent 使用：

- `LimitLoadToSessionType=Aqua`
- `RunAtLoad=true`
- `KeepAlive` 不设置
- 当前用户的绝对工作目录
- 工具目录内的标准输出和错误日志

因此每次图形登录只运行一次启动器；用户主动关闭 Remote Control 后不会被循环拉起。

## 8. 安全性与幂等性

- 安装器不请求管理员权限，不执行 `sudo`。
- 安装前检查目标文件是否属于本工具。若同名文件不是本工具生成，默认停止，只有显式 `--force` 才允许替换。
- 更新本工具时先生成临时文件、完成语法和 plist 校验，再原子替换正式文件。
- 重复安装先安全卸载同标签的当前用户 LaunchAgent，再载入新版本；不结束已在 Terminal 中运行的 Claude 会话。
- 当前机器已有的旧标签 `com.tianweichao.codex.claude-remote-control` 作为一次性迁移来源。安装器只有在旧 plist 的程序路径和工具目录都符合既有工具签名时才停用并移除旧任务，避免新旧标签在同一登录周期重复启动。
- 日志仅记录时间、启动结果、工作目录和错误类型，不记录提示内容、会话内容、凭证或身份数据。
- 未登录时只记录 `login_required`，不自动执行 OAuth 或反复弹出终端。

## 9. 测试与验收

自动化测试覆盖：

1. `bash -n` 检查安装器和卸载器。
2. 对生成的 zsh 启动脚本执行 `zsh -n`。
3. 对生成的 LaunchAgent 执行 `plutil -lint`。
4. 在临时根目录中验证默认主目录、带空格工作目录、Apple Silicon/Intel/用户级 Claude 路径和重复安装。
5. 验证非 Darwin 环境在任何写入前退出。
6. 验证缺少 Claude、工作目录不存在和 Remote Control 能力缺失时不会留下半安装状态。
7. 验证卸载只删除本工具产物。
8. 验证已知旧标签可安全迁移，未知同名 plist 默认拒绝处理。

当前 Mac 的最终人工验收包括：

- `launchctl print` 显示任务已加载。
- 任务 `runs=1` 且无 `KeepAlive`。
- Terminal 中出现 Remote Control 会话。
- 再次登录系统时只新增一个启动会话。
- 已有会话运行时不会把手动 `kickstart` 描述成“重启现有会话”。

## 10. 发布与版本

- 初始实现完成并通过测试后发布 `v0.1.0`。
- README 同时给出 `main` 的便捷安装命令和版本标签固定的可复现安装命令。
- 后续 Windows 或 Linux 支持分别新增平台目录和测试，不改变 macOS 现有入口。
- 首个可执行里程碑完成后复核是否需要把项目规范升级为固定的 `ai-workbench` 项目级依赖；首期不 vendor、不声明该依赖为验收条件。

## 11. 许可

仓库采用 MIT License，允许公开复用和修改，同时保留版权与许可声明。
