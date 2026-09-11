using System.Windows;
using WpfMessageBox = System.Windows.MessageBox;

namespace MomoMemo;

public partial class TaskEditorWindow : Window
{
    private sealed record Option(string Id, string Title);
    private sealed record StatusOption(string Id, string Title);
    private readonly MemoTask _task;
    private readonly AppSettings _settings;

    public TaskEditorWindow(MemoTask task, IReadOnlyList<ProjectItem> projects, AppSettings settings)
    {
        InitializeComponent();
        _task = task;
        _settings = settings;
        ProjectBox.ItemsSource = new[] { new ProjectItem { Id = "", Name = "未分类" } }
            .Concat(projects.Where(x => x.IsActive)).ToList();
        StatusBox.ItemsSource = StatusOptionsFor(task);
        PriorityBox.ItemsSource = new[] { "P0", "P1", "P2", "P3" };
        ReminderRuleBox.ItemsSource = new[]
        {
            new Option("None", "不启用工作时间提醒"), new Option("WorkHours", "工作时间定时提醒"),
            new Option("Every30", "每 30 分钟"), new Option("Every60", "每 1 小时")
        };
        var hours = Enumerable.Range(0, 24).Select(x => x.ToString("00")).ToList();
        var minutes = Enumerable.Range(0, 60).Select(x => x.ToString("00")).ToList();
        StartHourBox.ItemsSource = DueHourBox.ItemsSource = hours;
        StartMinuteBox.ItemsSource = DueMinuteBox.ItemsSource = minutes;

        TitleBox.Text = task.Title;
        DescriptionBox.Text = task.Description;
        ProjectBox.SelectedValue = task.ProjectId;
        StatusBox.SelectedValue = CurrentStatusId(task);
        PriorityBox.SelectedItem = task.Priority;
        SetDateTime(StartDatePicker, StartHourBox, StartMinuteBox, task.StartAt, 9, 0);
        SetDateTime(DueDatePicker, DueHourBox, DueMinuteBox, task.DueAt, 18, 0);
        LongTermBox.IsChecked = task.IsLongTerm;
        ReminderEnabledBox.IsChecked = task.ReminderEnabled;
        ReminderRuleBox.SelectedValue = task.ReminderRule;
        BeforeDueReminderEnabledBox.Content = $"截止前 {_settings.BeforeDueReminderMinutes} 分钟提醒一次";
        BeforeDueReminderEnabledBox.IsChecked = task.BeforeDueReminderEnabled;

        if (task.IsCompleted) SetDatesEditable(false);
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var title = TitleBox.Text.Trim();
        if (title.Length == 0)
        {
            WpfMessageBox.Show("任务名称不能为空。", "无法保存", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var wasCompleted = _task.IsCompleted;
        var previousDue = _task.DueAt;
        var start = wasCompleted ? _task.StartAt : GetDateTime(StartDatePicker, StartHourBox, StartMinuteBox);
        var due = wasCompleted ? previousDue : GetDateTime(DueDatePicker, DueHourBox, DueMinuteBox);
        if (start is not null && due < start)
        {
            WpfMessageBox.Show("截止时间不能早于开始时间。", "时间范围不正确", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        _task.Title = title;
        _task.Description = DescriptionBox.Text.Trim();
        _task.ProjectId = ProjectBox.SelectedValue?.ToString() ?? "";
        _task.Status = StatusFor(StatusBox.SelectedValue?.ToString());
        _task.Priority = PriorityBox.SelectedItem?.ToString() ?? "P2";
        _task.StartAt = start;
        _task.DueAt = due;
        _task.MustToday = false;
        _task.IsLongTerm = LongTermBox.IsChecked == true;
        _task.ReminderEnabled = ReminderEnabledBox.IsChecked == true;
        _task.ReminderRule = ReminderRuleBox.SelectedValue?.ToString() ?? "WorkHours";
        _task.BeforeDueReminderEnabled = BeforeDueReminderEnabledBox.IsChecked == true;
        if (previousDue != due) _task.BeforeDueReminderFor = null;
        _task.ModifiedAt = DateTime.Now;
        if (_task.IsCompleted)
        {
            if (!wasCompleted) _task.CompletedAt ??= DateTime.Now;
        }
        else _task.CompletedAt = null;
        DialogResult = true;
    }

    private static void SetDateTime(System.Windows.Controls.DatePicker picker, System.Windows.Controls.ComboBox hourBox,
        System.Windows.Controls.ComboBox minuteBox, DateTime? value, int defaultHour, int defaultMinute)
    {
        picker.SelectedDate = value?.Date;
        hourBox.SelectedItem = (value?.Hour ?? defaultHour).ToString("00");
        minuteBox.SelectedItem = (value?.Minute ?? defaultMinute).ToString("00");
    }

    private static DateTime? GetDateTime(System.Windows.Controls.DatePicker picker, System.Windows.Controls.ComboBox hourBox,
        System.Windows.Controls.ComboBox minuteBox)
    {
        if (picker.SelectedDate is not DateTime date) return null;
        var hour = int.Parse(hourBox.SelectedItem?.ToString() ?? "00");
        var minute = int.Parse(minuteBox.SelectedItem?.ToString() ?? "00");
        return date.Date.AddHours(hour).AddMinutes(minute);
    }

    private void ClearStart_Click(object sender, RoutedEventArgs e) => StartDatePicker.SelectedDate = null;

    private void ClearDue_Click(object sender, RoutedEventArgs e) => DueDatePicker.SelectedDate = null;

    private void LongTerm_Changed(object sender, RoutedEventArgs e)
    {
        if (LongTermBox.IsChecked != true || _task.IsLongTerm) return;
        StartDatePicker.SelectedDate = null;
        DueDatePicker.SelectedDate = null;
        ReminderEnabledBox.IsChecked = false;
        ReminderRuleBox.SelectedValue = "None";
        BeforeDueReminderEnabledBox.IsChecked = false;
    }

    private void SetDatesEditable(bool enabled)
    {
        StartDatePicker.IsEnabled = StartHourBox.IsEnabled = StartMinuteBox.IsEnabled = DueDatePicker.IsEnabled = DueHourBox.IsEnabled = DueMinuteBox.IsEnabled = enabled;
        ClearStartButton.IsEnabled = ClearDueButton.IsEnabled = enabled;
    }

    private static IReadOnlyList<StatusOption> StatusOptionsFor(MemoTask task) => task.IsCompleted
        ? [new("completed", "已完成"), new("restore", "恢复任务")]
        : task.IsOverdue
            ? [new("overdue", "已逾期"), new("paused", "暂停"), new("completed", "已完成")]
            : task.Status == MemoTaskStatus.Paused
                ? [new("paused", "已暂停"), new("in-progress", "进行中"), new("completed", "已完成")]
                : [new("in-progress", "进行中"), new("paused", "暂停"), new("completed", "已完成")];

    private static string CurrentStatusId(MemoTask task) => task.IsCompleted ? "completed" : task.IsOverdue ? "overdue" : task.Status == MemoTaskStatus.Paused ? "paused" : "in-progress";

    private static MemoTaskStatus StatusFor(string? id) => id switch
    {
        "completed" => MemoTaskStatus.Completed,
        "paused" => MemoTaskStatus.Paused,
        _ => MemoTaskStatus.InProgress
    };
}
