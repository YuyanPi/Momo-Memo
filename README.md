# Momo Memo

Momo Memo 是一个 macOS 桌面任务便利贴应用。目标是简单、直观、常驻桌面：快速记下今天要做的事，按项目查看，按周导出。

## 当前功能

- 便利贴样式主窗口：无边框、圆角、可拖动、默认置顶、可隐藏到菜单栏
- 任务创建、编辑、删除、完成、置顶
- 项目分区：名称、颜色、是否允许重复任务
- 标签：创建和颜色记录，任务支持多个标签
- 子任务：用逗号快速录入，卡片中显示
- 日期字段：任务日期、开始日期、完成日期、截止日期
- 优先级：高、中、低
- 重复任务：每日、每周、每月、自定义；由项目开关控制
- 菜单栏快速添加任务
- 今日任务提醒：默认 10:00-18:00，仅菜单栏高亮，不弹窗、不发声
- 免打扰时段：支持多行配置，例如 `12:00-13:30`
- 本周统计：总数、完成数、未完成数、项目完成比例
- 本周导出：Markdown 或 CSV
- 本地 JSON 保存与自动备份，保留最近 7 份

## 构建

macOS 13 或更高版本可直接构建，不需要安装 .NET 或第三方依赖。

```bash
zsh ./scripts/build-macos.sh
open "artifacts/macos/Momo Memo.app"
```

## 安装

构建后把 `artifacts/macos/Momo Memo.app` 拖到 `/Applications` 或 `~/Applications` 即可。

也可以在 GitHub Actions 中下载 `Momo-Memo-macOS.zip`，解压后直接运行。

## 数据位置

任务数据保存在：

```text
~/Library/Application Support/Momo Memo/momo-memo.json
```

自动备份保存在：

```text
~/Library/Application Support/Momo Memo/Backups
```

## 发布

推送到 `main` 会自动构建 macOS 压缩包。推送形如 `v1.0.0` 的 tag 会自动创建 GitHub Release 并上传 `Momo-Memo-macOS.zip`。

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 设计原则

Momo Memo 不追求复杂项目管理，而是优先保证日常使用路径短：

- 快速添加只填标题即可
- 常用字段集中在一个编辑弹窗
- 项目、标签、提醒放进设置
- 提醒默认不打扰，只让菜单栏轻微高亮

## License

MIT
