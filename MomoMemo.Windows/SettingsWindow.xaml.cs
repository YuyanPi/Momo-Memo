using System.Windows;
using System.IO;
using Forms = System.Windows.Forms;
using WpfMessageBox = System.Windows.MessageBox;

namespace MomoMemo;

public partial class SettingsWindow : Window
{
    private sealed record Option(string Id, string Title);
    private readonly AppData _data;
    private readonly Option[] _reminderModes =
    [
        new("Icon", "仅图标状态"), new("Notification", "系统通知"), new("Desktop", "桌面提示"),
        new("IconSound", "图标状态 + 声音"), new("NotificationSound", "系统通知 + 声音"), new("DesktopSound", "桌面提示 + 声音")
    ];

    public SettingsWindow(AppData data)
    {
        InitializeComponent();
        _data = data;
        ProjectsBox.Text = string.Join(Environment.NewLine, data.Projects.Select(x => $"{x.Name}|{x.Color}"));
        RemindersEnabledBox.IsChecked = data.Settings.RemindersEnabled;
        WorkStartBox.Text = $"{data.Settings.WorkStart:hh\\:mm}";
        WorkEndBox.Text = $"{data.Settings.WorkEnd:hh\\:mm}";
        IntervalBox.Text = data.Settings.ReminderIntervalMinutes.ToString();
        ReminderModeBox.ItemsSource = _reminderModes;
        ReminderModeBox.SelectedValue = data.Settings.ReminderMode;
        QuietBox.Text = data.Settings.QuietRanges;
        WorkWeekBox.ItemsSource = new[] { "双休周", "单休周" };
        WorkWeekBox.SelectedIndex = data.Settings.CurrentWeekMode == WorkWeekMode.SingleRest ? 1 : 0;
        AutoAlternateBox.IsChecked = data.Settings.AutoAlternateWeek;
        AutoExportBox.IsChecked = data.Settings.AutoExportEnabled;
        FrequencyBox.ItemsSource = new[] { "每天", "每周", "每月" };
        FrequencyBox.SelectedIndex = data.Settings.AutoExportFrequency == "Daily" ? 0 : data.Settings.AutoExportFrequency == "Monthly" ? 2 : 1;
        ExportTimeBox.Text = $"{data.Settings.AutoExportTime:hh\\:mm}";
        FormatBox.ItemsSource = new[] { "Markdown", "CSV", "Markdown + CSV" };
        FormatBox.SelectedIndex = data.Settings.AutoExportFormat == "Markdown" ? 0 : data.Settings.AutoExportFormat == "Csv" ? 1 : 2;
        OverwriteBox.IsChecked = data.Settings.ExportOverwrite;
        ExportDirectoryBox.Text = data.Settings.ExportDirectory;
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new Forms.FolderBrowserDialog
        {
            SelectedPath = ExportDirectoryBox.Text,
            Description = "选择 Momo Memo 导出目录",
            UseDescriptionForTitle = true
        };
        if (dialog.ShowDialog() == Forms.DialogResult.OK) ExportDirectoryBox.Text = dialog.SelectedPath;
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (!TimeSpan.TryParse(WorkStartBox.Text, out var workStart) || !TimeSpan.TryParse(WorkEndBox.Text, out var workEnd) ||
            !TimeSpan.TryParse(ExportTimeBox.Text, out var exportTime) || workStart >= workEnd)
        {
            WpfMessageBox.Show("请检查工作时间和导出时间，格式应为 HH:mm，且结束时间晚于开始时间。", "设置格式不正确", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!int.TryParse(IntervalBox.Text, out var interval) || interval < 30)
        {
            WpfMessageBox.Show("提醒间隔不能少于 30 分钟。", "设置格式不正确", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var projectLines = ProjectsBox.Text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (projectLines.Length == 0)
        {
            WpfMessageBox.Show("至少需要保留 Inbox 项目。", "项目不能为空", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var updatedProjects = new List<ProjectItem>();
        for (var index = 0; index < projectLines.Length; index++)
        {
            var parts = projectLines[index].TrimEnd('\r').Split('|', 2, StringSplitOptions.TrimEntries);
            if (parts[0].Length == 0) continue;
            var existing = _data.Projects.FirstOrDefault(x => x.Name.Equals(parts[0], StringComparison.OrdinalIgnoreCase))
                           ?? _data.Projects.ElementAtOrDefault(index);
            updatedProjects.Add(new ProjectItem
            {
                Id = index == 0 ? "inbox" : existing?.Id ?? Guid.NewGuid().ToString("N"),
                Name = index == 0 ? "Inbox" : parts[0],
                Color = parts.Length > 1 && parts[1].StartsWith('#') ? parts[1] : "#6C63FF",
                Description = existing?.Description ?? "",
                CreatedAt = existing?.CreatedAt ?? DateTime.Now
            });
        }
        var validIds = updatedProjects.Select(x => x.Id).ToHashSet();
        foreach (var task in _data.Tasks.Where(x => !validIds.Contains(x.ProjectId))) task.ProjectId = "inbox";
        _data.Projects = updatedProjects;

        var settings = _data.Settings;
        settings.RemindersEnabled = RemindersEnabledBox.IsChecked == true;
        settings.WorkStart = workStart;
        settings.WorkEnd = workEnd;
        settings.ReminderIntervalMinutes = interval;
        settings.ReminderMode = ReminderModeBox.SelectedValue?.ToString() ?? "Icon";
        settings.QuietRanges = QuietBox.Text.Trim();
        var newWeekMode = WorkWeekBox.SelectedIndex == 1 ? WorkWeekMode.SingleRest : WorkWeekMode.DoubleRest;
        var newAutoAlternate = AutoAlternateBox.IsChecked == true;
        if (settings.CurrentWeekMode != newWeekMode || (!settings.AutoAlternateWeek && newAutoAlternate)) settings.WorkWeekAnchor = DateTime.Today;
        settings.CurrentWeekMode = newWeekMode;
        settings.AutoAlternateWeek = newAutoAlternate;
        settings.AutoExportEnabled = AutoExportBox.IsChecked == true;
        settings.AutoExportFrequency = FrequencyBox.SelectedIndex == 0 ? "Daily" : FrequencyBox.SelectedIndex == 2 ? "Monthly" : "Weekly";
        settings.AutoExportTime = exportTime;
        settings.AutoExportFormat = FormatBox.SelectedIndex == 0 ? "Markdown" : FormatBox.SelectedIndex == 1 ? "Csv" : "Both";
        settings.ExportOverwrite = OverwriteBox.IsChecked == true;
        settings.ExportDirectory = string.IsNullOrWhiteSpace(ExportDirectoryBox.Text)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Momo Memo")
            : ExportDirectoryBox.Text.Trim();
        DialogResult = true;
    }
}
