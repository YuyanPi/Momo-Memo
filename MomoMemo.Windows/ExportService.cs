using System.Text;
using System.IO;

namespace MomoMemo;

public static class ExportService
{
    public static string ExportMarkdown(IEnumerable<MemoTask> source, IReadOnlyList<ProjectItem> projects, string rangeText)
    {
        var tasks = source.ToList();
        var done = tasks.Count(x => x.IsCompleted);
        var output = new StringBuilder()
            .AppendLine("# Momo Memo 工作记录").AppendLine()
            .AppendLine($"时间范围：{rangeText}")
            .AppendLine($"导出时间：{DateTime.Now:yyyy-MM-dd HH:mm}").AppendLine()
            .AppendLine("---").AppendLine()
            .AppendLine("## 工作概览").AppendLine()
            .AppendLine($"- 完成任务：{done}")
            .AppendLine($"- 未完成任务：{tasks.Count - done}")
            .AppendLine($"- 逾期任务：{tasks.Count(x => x.IsOverdue)}")
            .AppendLine($"- 完成率：{(tasks.Count == 0 ? 0 : done * 100 / tasks.Count)}%").AppendLine()
            .AppendLine("---").AppendLine()
            .AppendLine("# 项目").AppendLine();

        foreach (var project in projects)
        {
            var projectTasks = tasks.Where(x => x.ProjectId == project.Id).ToList();
            if (projectTasks.Count == 0) continue;
            output.AppendLine($"## {project.Name}").AppendLine();
            foreach (var status in new[] { "已逾期", "进行中", "暂停", "未开始", "已完成" })
            {
                var statusTasks = projectTasks.Where(x => x.StatusText == status).OrderBy(x => x.Priority).ToList();
                if (statusTasks.Count == 0) continue;
                output.AppendLine($"### {status}").AppendLine();
                foreach (var task in statusTasks)
                    output.AppendLine($"- {(task.IsCompleted ? "[x]" : "[ ]")} [{task.Priority}] {task.Title}（开始：{Format(task.StartAt)}；截止：{Format(task.DueAt)}）");
                output.AppendLine();
            }
        }
        var uncategorized = tasks.Where(x => string.IsNullOrWhiteSpace(x.ProjectId)).ToList();
        if (uncategorized.Count > 0)
        {
            output.AppendLine("## 未分类").AppendLine();
            foreach (var task in uncategorized.OrderBy(x => x.Priority))
                output.AppendLine($"- {(task.IsCompleted ? "[x]" : "[ ]")} [{task.Priority}] {task.Title}（开始：{Format(task.StartAt)}；截止：{Format(task.DueAt)}）");
            output.AppendLine();
        }
        return output.ToString();
    }

    public static string ExportCsv(IEnumerable<MemoTask> tasks, IReadOnlyList<ProjectItem> projects)
    {
        var names = projects.ToDictionary(x => x.Id, x => x.Name);
        var output = new StringBuilder("任务 ID,任务名称,描述,项目,状态,优先级,开始时间,截止时间,创建时间,完成时间,修改时间,是否长期任务,是否逾期,是否归档\r\n");
        foreach (var task in tasks)
        {
            string[] values =
            [
                task.Id, task.Title, task.Description, names.GetValueOrDefault(task.ProjectId, "未分类"), task.StatusText,
                task.Priority, Format(task.StartAt), Format(task.DueAt), Format(task.CreatedAt), Format(task.CompletedAt),
                Format(task.ModifiedAt), YesNo(task.IsLongTerm), YesNo(task.IsOverdue), YesNo(task.IsArchived)
            ];
            output.AppendLine(string.Join(',', values.Select(Escape)));
        }
        return output.ToString();
    }

    public static string BuildBaseName(DateTime start, DateTime end, string source, string period) =>
        $"momo-memo_{source}_{period}_{start:yyyy-MM-dd}_to_{end:yyyy-MM-dd}";
    public static string BuildAllBaseName() => $"momo-memo_all_{DateTime.Today:yyyy-MM-dd}";

    public static string AvailablePath(string directory, string baseName, string extension, bool overwrite)
    {
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, $"{baseName}.{extension}");
        if (overwrite || !File.Exists(path)) return path;
        for (var version = 2; ; version++)
        {
            path = Path.Combine(directory, $"{baseName}_v{version}.{extension}");
            if (!File.Exists(path)) return path;
        }
    }

    private static string Escape(string? value) => $"\"{(value ?? "").Replace("\"", "\"\"")}\"";
    private static string Format(DateTime? value) => value?.ToString("yyyy-MM-dd HH:mm") ?? "未设置";
    private static string Format(DateTime value) => value.ToString("yyyy-MM-dd HH:mm");
    private static string YesNo(bool value) => value ? "是" : "否";
}
