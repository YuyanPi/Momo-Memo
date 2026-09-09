using System.Windows;
using WpfMessageBox = System.Windows.MessageBox;

namespace MomoMemo;

public partial class TaskEditorWindow : Window
{
    private sealed record Option(string Id, string Title);
    private readonly MemoTask _task;
    private readonly AppSettings _settings;

    public TaskEditorWindow(MemoTask task, IReadOnlyList<ProjectItem> projects, AppSettings settings)
    {
        InitializeComponent();
        _task = task;
        _settings = settings;
        ProjectBox.ItemsSource = new[] { new ProjectItem { Id = "", Name = "未分类" } }
            .Concat(projects.Where(x => x.IsActive)).ToList();
        StatusBox.ItemsSource = new[] { "进行中", "暂停", "已完成" };
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
        StatusBox.SelectedIndex = task.Status == MemoTaskStatus.Paused ? 1 : task.Status == MemoTaskStatus.Completed ? 2 : 0;
        PriorityBox.SelectedItem = task.Priority;
        SetDateTime(StartDatePicker, StartHourBox, StartMinuteBox, task.StartAt, 9, 0);
        SetDateTime(DueDatePicker, DueHourBox, DueMinuteBox, task.DueAt, 18, 0);
        DueDatePicker.SelectedDate ??= DateTime.Today;
        ReminderEnabledBox.IsChecked = task.ReminderEnabled;
        ReminderRuleBox.SelectedValue = task.ReminderRule;
        BeforeDueReminderEnabledBox.Content = $"截止前 {_settings.BeforeDueReminderMinutes} 分钟提醒一次";
        BeforeDueReminderEnabledBox.IsChecked = task.BeforeDueReminderEnabled;
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var title = TitleBox.Text.Trim();
        if (title.Length == 0)
        {
            WpfMessageBox.Show("任务名称不能为空。", "无法保存", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var start = GetDateTime(StartDatePicker, StartHourBox, StartMinuteBox);
        var due = GetDateTime(DueDatePicker, DueHourBox, DueMinuteBox) ?? DateTime.Today.AddHours(18);
        if (start is not null && due < start)
        {
            WpfMessageBox.Show("截止时间不能早于开始时间。", "时间范围不正确", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var wasCompleted = _task.IsCompleted;
        var previousDue = _task.DueAt;
        _task.Title = title;
        _task.Description = DescriptionBox.Text.Trim();
        _task.ProjectId = ProjectBox.SelectedValue?.ToString() ?? "";
        _task.Status = StatusBox.SelectedIndex == 1 ? MemoTaskStatus.Paused : StatusBox.SelectedIndex == 2 ? MemoTaskStatus.Completed : MemoTaskStatus.InProgress;
        _task.Priority = PriorityBox.SelectedItem?.ToString() ?? "P2";
        _task.StartAt = start;
        _task.DueAt = due;
        _task.MustToday = false;
        _task.IsLongTerm = false;
        _task.ReminderEnabled = ReminderEnabledBox.IsChecked == true;
        _task.ReminderRule = ReminderRuleBox.SelectedValue?.ToString() ?? "WorkHours";
        _task.BeforeDueReminderEnabled = BeforeDueReminderEnabledBox.IsChecked == true;
        if (previousDue != due) _task.BeforeDueReminderFor = null;
        _task.ModifiedAt = DateTime.Now;
        if (_task.IsCompleted)
        {
            if (!wasCompleted) _task.CompletedAt ??= DateTime.Now;
            _task.EverCompleted = true;
        }
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
}
