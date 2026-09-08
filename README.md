# Momo Memo

Momo Memo 是一个面向 Windows 的本地优先个人工作备忘与任务管理工具。

> 记录每一件事，只把现在重要的事情留在你面前。

## 第一版功能

- 今日、未来三天、长期任务、Inbox、未完成、全部、已完成、归档和项目视图
- 创建、编辑、完成、恢复、归档、延后与受控删除任务
- 未开始、进行中、暂停、已完成状态，以及自动识别逾期
- P0～P3 优先级、开始/截止时间、“今天必须完成”和长期任务
- 已完成任务与曾归档任务永久保留，只有错误创建的普通未完成任务可真正删除
- 项目管理；系统托盘快速记录默认进入 Inbox
- 工作时间、双休/单休周、本周制度、自动单双周切换和免打扰
- 任务级整点、30 分钟、1 小时、截止前提醒，以及延后提醒
- 低干扰任务栏/托盘图标提醒，可选系统通知、桌面提示、声音或组合
- 本周完成率、逾期、项目和优先级统计
- 本周或全部历史手动导出，支持结构化 Markdown 和稳定字段 CSV
- 每天、每周或每月自动导出，可配置路径、格式及覆盖/版本化
- 本地 JSON 原子保存；自动保留最近 7 份备份

第二阶段的日历视图、高级搜索/筛选、趋势分析和自然语言录入，以及第三阶段的 AI、同步与多端能力不在当前版本范围内。

## Windows 构建与运行

要求：Windows 10/11 与 .NET 8 SDK（仅运行构建产物时需要 .NET 8 Desktop Runtime）。

```powershell
dotnet build .\MomoMemo.sln -c Release
& '.\MomoMemo.Windows\bin\Release\net8.0-windows\MomoMemo.exe'
```

生成单文件 Windows x64 包：

```powershell
dotnet publish .\MomoMemo.Windows\MomoMemo.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o .\artifacts\windows
```

## 数据位置

任务数据随程序保存在便携目录：

```text
<程序目录>\Data\momo-memo.json
```

最近 7 份自动备份保存在：

```text
<程序目录>\Data\Backups
```

自动导出默认保存在：

```text
%USERPROFILE%\Documents\Momo Memo
```

## macOS 原型

仓库仍保留原有 `MomoMemoMac` 原型和 `scripts/build-macos.sh`，但当前第一版开发与验证目标是 Windows WPF 应用。

## License

MIT
