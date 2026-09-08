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
    public string Color { get; set; } = "#6C63FF";
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.Now;
}

public sealed class MemoTask
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public string ProjectId { get; set; } = "inbox";
    public MemoTaskStatus Status { get; set; } = MemoTaskStatus.NotStarted;
    public string Priority { get; set; } = "P2";
    public DateTime? StartAt { get; set; }
    public DateTime? DueAt { get; set; }
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
    public DateTime? SnoozedUntil { get; set; }

    [JsonIgnore] public bool IsCompleted => Status == MemoTaskStatus.Completed;
    [JsonIgnore] public bool CanDelete => !EverCompleted && !EverArchived;
    [JsonIgnore] public bool CanSnooze => !IsCompleted && !IsArchived;
    [JsonIgnore] public bool IsOverdue => !IsCompleted && !IsArchived && DueAt is not null && DueAt < DateTime.Now;
    [JsonIgnore] public string StatusText => IsOverdue ? "已逾期" : Status switch
    {
        MemoTaskStatus.NotStarted => "未开始",
        MemoTaskStatus.InProgress => "进行中",
        MemoTaskStatus.Paused => "暂停",
        _ => "已完成"
    };
    [JsonIgnore] public string TimeText => $"{(StartAt is null ? "未安排" : StartAt.Value.ToString("MM-dd HH:mm"))}  ·  {(DueAt is null ? "无截止" : $"截止 {DueAt:MM-dd HH:mm}")}";
    [JsonIgnore] public string FlagsText => string.Join("  ", new[]
    {
        MustToday ? "📌 今天必须完成" : "",
        IsLongTerm ? "📚 长期" : "",
        SnoozedUntil > DateTime.Now ? $"⏰ {SnoozedUntil:MM-dd HH:mm}" : ""
    }.Where(x => x.Length > 0));
}

public sealed class AppSettings
{
    public TimeSpan WorkStart { get; set; } = new(10, 0, 0);
    public TimeSpan WorkEnd { get; set; } = new(18, 0, 0);
    public int ReminderIntervalMinutes { get; set; } = 60;
    public string QuietRanges { get; set; } = "12:00-13:30";
    public WorkWeekMode CurrentWeekMode { get; set; } = WorkWeekMode.DoubleRest;
    public bool AutoAlternateWeek { get; set; } = true;
    public DateTime WorkWeekAnchor { get; set; } = DateTime.Today;
    public string ReminderMode { get; set; } = "Icon";
    public bool RemindersEnabled { get; set; } = true;
    public bool AutoExportEnabled { get; set; }
    public string AutoExportFrequency { get; set; } = "Weekly";
    public TimeSpan AutoExportTime { get; set; } = new(18, 30, 0);
    public string AutoExportFormat { get; set; } = "Both";
    public string ExportDirectory { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Momo Memo");
    public bool ExportOverwrite { get; set; } = true;
    public string LastAutoExportKey { get; set; } = "";
}

public sealed class AppData
{
    public int SchemaVersion { get; set; } = 1;
    public List<ProjectItem> Projects { get; set; } = [];
    public List<MemoTask> Tasks { get; set; } = [];
    public AppSettings Settings { get; set; } = new();
}
