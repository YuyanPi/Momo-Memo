using System.Text.Json.Serialization;
using System.IO;

namespace MomoMemo;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum MemoTaskStatus
{
    NotStarted,
    InProgress,
    Paused,
    Completed
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum WorkWeekMode
{
    DoubleRest,
    SingleRest
}

public sealed class ProjectItem
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Name { get; set; } = "新项目";
    public string Description { get; set; } = "";
    public string Color { get; set; } = "#C9826A";
    public DateTime? StartDate { get; set; }
    public DateTime? DueDate { get; set; }
    public bool IsActive { get; set; } = true;
    public bool IsHidden { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.Now;
}

public sealed class MemoTask
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public string ProjectId { get; set; } = "";
    public MemoTaskStatus Status { get; set; } = MemoTaskStatus.InProgress;
    public string Priority { get; set; } = "P2";
    public DateTime? StartAt { get; set; }
    public DateTime? DueAt { get; set; } = DateTime.Today.AddHours(18);
    public DateTime CreatedAt { get; set; } = DateTime.Now;
    public DateTime ModifiedAt { get; set; } = DateTime.Now;
    public DateTime? CompletedAt { get; set; }
    public bool EverCompleted { get; set; }
    public bool MustToday { get; set; }
    public bool IsLongTerm { get; set; }
    public bool IsArchived { get; set; }
    public bool EverArchived { get; set; }
    public DateTime? ArchivedAt { get; set; }
    public bool ReminderEnabled { get; set; } = true;
    public string ReminderRule { get; set; } = "WorkHours";
    public bool BeforeDueReminderEnabled { get; set; }
    /// <summary>The deadline for which the one-time pre-deadline reminder has already been shown.</summary>
    public DateTime? BeforeDueReminderFor { get; set; }
    public DateTime? SnoozedUntil { get; set; }

    [JsonIgnore] public bool IsCompleted => Status == MemoTaskStatus.Completed;
    [JsonIgnore] public bool CanDelete => !EverCompleted && !EverArchived;
    [JsonIgnore] public bool CanSnooze => !IsCompleted && !IsArchived;
    [JsonIgnore] public bool HasDescription => !string.IsNullOrWhiteSpace(Description);
    [JsonIgnore] public string ProjectName { get; set; } = "未分类";
    [JsonIgnore] public string ProjectColor { get; set; } = "#B7A99B";
    [JsonIgnore] public bool IsOverdue => !IsCompleted && Status != MemoTaskStatus.Paused && !IsArchived && DueAt is not null && DueAt < DateTime.Now;
    [JsonIgnore] public string StatusText => IsOverdue ? "已逾期" : Status switch
    {
        MemoTaskStatus.NotStarted => "未开始",
        MemoTaskStatus.InProgress => "进行中",
        MemoTaskStatus.Paused => "暂停",
        _ => $"已完成 {CompletedAt?.ToString("MM-dd HH:mm") ?? ""}".TrimEnd()
    };
    [JsonIgnore] public string TimeText => $"{(StartAt is null ? "未安排" : StartAt.Value.ToString("MM-dd HH:mm"))}  ·  {(DueAt is null ? "无截止" : $"截止 {DueAt:MM-dd HH:mm}")}";
    [JsonIgnore] public string DueText => DueAt is null ? "截止：今天" : $"截止 {DueAt:MM-dd HH:mm}";
    [JsonIgnore] public string FlagsText => string.Join("  ", new[]
    {
        MustToday ? "📌 今天必须完成" : "",
        IsLongTerm ? "📚 长期" : "",
        SnoozedUntil > DateTime.Now ? $"⏰ {SnoozedUntil:MM-dd HH:mm}" : ""
    }.Where(x => x.Length > 0));
}

public sealed class AppSettings
{
    public TimeSpan WorkStart { get; set; } = new(9, 0, 0);
    public TimeSpan WorkEnd { get; set; } = new(18, 0, 0);
    public int ReminderIntervalMinutes { get; set; } = 60;
    public string QuietRanges { get; set; } = "12:00-13:30";
    public WorkWeekMode CurrentWeekMode { get; set; } = WorkWeekMode.DoubleRest;
    public bool AutoAlternateWeek { get; set; } = true;
    public DateTime WorkWeekAnchor { get; set; } = DateTime.Today;
    public string ReminderMode { get; set; } = "Icon";
    public bool RemindersEnabled { get; set; } = true;
    public bool DefaultWorkHoursReminderEnabled { get; set; } = true;
    public bool DefaultBeforeDueReminderEnabled { get; set; } = true;
    public int BeforeDueReminderMinutes { get; set; } = 30;
    public bool AutoExportWeekly { get; set; }
    public bool AutoExportMonthly { get; set; }
    public TimeSpan AutoExportTime { get; set; } = new(18, 30, 0);
    public string AutoExportFormat { get; set; } = "Both";
    public string ExportDirectory { get; set; } = AppStoragePaths.ExportsDirectory;
    public bool ExportOverwrite { get; set; } = true;
    public string LastWeeklyAutoExportKey { get; set; } = "";
    public string LastMonthlyAutoExportKey { get; set; } = "";
    public string LastSelectedProjectId { get; set; } = "all";
}

public sealed class AppData
{
    public int SchemaVersion { get; set; } = 1;
    public List<ProjectItem> Projects { get; set; } = [];
    public List<MemoTask> Tasks { get; set; } = [];
    public AppSettings Settings { get; set; } = new();
}
