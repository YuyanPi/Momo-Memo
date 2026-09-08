using System.Globalization;
using System.Windows;
using WpfMessageBox = System.Windows.MessageBox;

namespace MomoMemo;

public partial class TaskEditorWindow : Window
{
    private sealed record Option(string Id, string Title);
    private readonly MemoTask _task;

    public TaskEditorWindow(MemoTask task, IReadOnlyList<ProjectItem> projects)
    {
        InitializeComponent();
        _task = task;
        ProjectBox.ItemsSource = projects.Where(x => x.IsActive).ToList();
        StatusBox.ItemsSource = new[] { "未开始", "进行中", "暂停", "已完成" };
        PriorityBox.ItemsSource = new[] { "P0", "P1", "P2", "P3" };
        ReminderRuleBox.ItemsSource = new[]
        {
            new Option("None", "不提醒"), new Option("WorkHours", "工作时间定时提醒"),
            new Option("Every30", "每 30 分钟"), new Option("Every60", "每 1 小时"),
            new Option("BeforeDue", "截止前 30 分钟")
        };

        TitleBox.Text = task.Title;
        DescriptionBox.Text = task.Description;
        ProjectBox.SelectedValue = task.ProjectId;
        StatusBox.SelectedIndex = (int)task.Status;
        PriorityBox.SelectedItem = task.Priority;
        StartBox.Text = Format(task.StartAt);
        DueBox.Text = Format(task.DueAt);
        MustTodayBox.IsChecked = task.MustToday;
        LongTermBox.IsChecked = task.IsLongTerm;
        ReminderEnabledBox.IsChecked = task.ReminderEnabled;
        ReminderRuleBox.SelectedValue = task.ReminderRule;
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var title = TitleBox.Text.Trim();
        if (title.Length == 0)
        {
            WpfMessageBox.Show("任务名称不能为空。", "无法保存", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!TryDate(StartBox.Text, false, out var start) || !TryDate(DueBox.Text, true, out var due))
        {
            WpfMessageBox.Show("时间格式应为 yyyy-MM-dd 或 yyyy-MM-dd HH:mm，也可以留空。", "时间格式不正确", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (start is not null && due is not null && due < start)
        {
            WpfMessageBox.Show("截止时间不能早于开始时间。", "时间范围不正确", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var wasCompleted = _task.IsCompleted;
        _task.Title = title;
        _task.Description = DescriptionBox.Text.Trim();
        _task.ProjectId = ProjectBox.SelectedValue?.ToString() ?? "inbox";
        _task.Status = (MemoTaskStatus)Math.Max(0, StatusBox.SelectedIndex);
        _task.Priority = PriorityBox.SelectedItem?.ToString() ?? "P2";
        _task.StartAt = start;
        _task.DueAt = due;
        _task.MustToday = MustTodayBox.IsChecked == true;
        _task.IsLongTerm = LongTermBox.IsChecked == true;
        _task.ReminderEnabled = ReminderEnabledBox.IsChecked == true;
        _task.ReminderRule = ReminderRuleBox.SelectedValue?.ToString() ?? "WorkHours";
        _task.ModifiedAt = DateTime.Now;
        if (_task.IsCompleted)
        {
            if (!wasCompleted) _task.CompletedAt ??= DateTime.Now;
            _task.EverCompleted = true;
        }
        DialogResult = true;
    }

    private static string Format(DateTime? value) => value?.ToString("yyyy-MM-dd HH:mm") ?? "";

    private static bool TryDate(string value, bool endOfDayForDateOnly, out DateTime? date)
    {
        date = null;
        if (string.IsNullOrWhiteSpace(value)) return true;
        var formats = new[] { "yyyy-MM-dd HH:mm", "yyyy-MM-dd" };
        if (!DateTime.TryParseExact(value.Trim(), formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed)) return false;
        date = endOfDayForDateOnly && value.Trim().Length == 10 ? parsed.Date.AddDays(1).AddTicks(-1) : parsed;
        return true;
    }
}
