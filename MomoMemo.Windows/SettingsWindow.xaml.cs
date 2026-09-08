using System.Windows;
using System.IO;
using Forms = System.Windows.Forms;
using WpfMessageBox = System.Windows.MessageBox;
using WpfButton = System.Windows.Controls.Button;
using WpfStackPanel = System.Windows.Controls.StackPanel;
using WpfTextBlock = System.Windows.Controls.TextBlock;

namespace MomoMemo;

public partial class SettingsWindow : Window
{
    private sealed record Option(string Id, string Title);
    private readonly AppData _data;
    private readonly List<(System.Windows.Controls.ComboBox Start, System.Windows.Controls.ComboBox End)> _quietRows = [];
    private readonly Option[] _reminderModes =
    [
        new("Icon", "仅图标状态"), new("Notification", "系统通知"), new("Desktop", "桌面提示"),
        new("IconSound", "图标状态 + 声音"), new("NotificationSound", "系统通知 + 声音"), new("DesktopSound", "桌面提示 + 声音")
    ];

    public SettingsWindow(AppData data)
    {
        InitializeComponent();
        _data = data;
        var timeOptions = Enumerable.Range(0, 24).SelectMany(hour => new[] { 0, 15, 30, 45 }
            .Select(minute => $"{hour:00}:{minute:00}")).ToList();
        WorkStartBox.ItemsSource = WorkEndBox.ItemsSource = ExportTimeBox.ItemsSource = timeOptions;
        RemindersEnabledBox.IsChecked = data.Settings.RemindersEnabled;
        WorkStartBox.SelectedItem = $"{data.Settings.WorkStart:hh\\:mm}";
        WorkEndBox.SelectedItem = $"{data.Settings.WorkEnd:hh\\:mm}";
        IntervalBox.Text = data.Settings.ReminderIntervalMinutes.ToString();
        ReminderModeBox.ItemsSource = _reminderModes;
        ReminderModeBox.SelectedValue = data.Settings.ReminderMode;
        foreach (var range in data.Settings.QuietRanges.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)) AddQuietRow(range);
        WorkWeekBox.ItemsSource = new[] { "双休周", "单休周" };
        WorkWeekBox.SelectedIndex = data.Settings.CurrentWeekMode == WorkWeekMode.SingleRest ? 1 : 0;
        AutoAlternateBox.IsChecked = data.Settings.AutoAlternateWeek;
        AutoExportWeeklyBox.IsChecked = data.Settings.AutoExportWeekly;
        AutoExportMonthlyBox.IsChecked = data.Settings.AutoExportMonthly;
        ExportTimeBox.SelectedItem = $"{data.Settings.AutoExportTime:hh\\:mm}";
        FormatBox.ItemsSource = new[] { "Markdown", "CSV", "Markdown + CSV" };
        FormatBox.SelectedIndex = data.Settings.AutoExportFormat == "Markdown" ? 0 : data.Settings.AutoExportFormat == "Csv" ? 1 : 2;
        OverwriteBox.IsChecked = data.Settings.ExportOverwrite;
        ExportDirectoryBox.Text = data.Settings.ExportDirectory;
    }

    private void AddQuiet_Click(object sender, RoutedEventArgs e) => AddQuietRow(null);

    private void AddQuietRow(string? range)
    {
        var options = Enumerable.Range(0, 24).SelectMany(hour => new[] { 0, 15, 30, 45 }.Select(minute => $"{hour:00}:{minute:00}")).ToList();
        var start = new System.Windows.Controls.ComboBox { ItemsSource = options, Width = 92, Margin = new Thickness(0, 2, 6, 2) };
        var end = new System.Windows.Controls.ComboBox { ItemsSource = options, Width = 92, Margin = new Thickness(0, 2, 6, 2) };
        var remove = new WpfButton { Content = "删除", Padding = new Thickness(7, 3, 7, 3) };
        var row = new WpfStackPanel { Orientation = System.Windows.Controls.Orientation.Horizontal };
        row.Children.Add(new WpfTextBlock { Text = "从", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0) });
        row.Children.Add(start); row.Children.Add(new WpfTextBlock { Text = "到", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0) }); row.Children.Add(end); row.Children.Add(remove);
        remove.Click += (_, _) => { QuietRowsPanel.Children.Remove(row); _quietRows.RemoveAll(x => x.Start == start); };
        QuietRowsPanel.Children.Add(row); _quietRows.Add((start, end));
        var parts = range?.Split('-', StringSplitOptions.TrimEntries);
        start.SelectedItem = parts?.ElementAtOrDefault(0) ?? "12:00"; end.SelectedItem = parts?.ElementAtOrDefault(1) ?? "13:30";
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
        if (!TimeSpan.TryParse(WorkStartBox.SelectedItem?.ToString(), out var workStart) || !TimeSpan.TryParse(WorkEndBox.SelectedItem?.ToString(), out var workEnd) ||
            !TimeSpan.TryParse(ExportTimeBox.SelectedItem?.ToString(), out var exportTime) || workStart >= workEnd)
        {
            WpfMessageBox.Show("请检查工作时间和导出时间，格式应为 HH:mm，且结束时间晚于开始时间。", "设置格式不正确", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!int.TryParse(IntervalBox.Text, out var interval) || interval < 30)
        {
            WpfMessageBox.Show("提醒间隔不能少于 30 分钟。", "设置格式不正确", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var settings = _data.Settings;
        settings.RemindersEnabled = RemindersEnabledBox.IsChecked == true;
        settings.WorkStart = workStart;
        settings.WorkEnd = workEnd;
        settings.ReminderIntervalMinutes = interval;
        settings.ReminderMode = ReminderModeBox.SelectedValue?.ToString() ?? "Icon";
        settings.QuietRanges = string.Join("\n", _quietRows.Select(x => $"{x.Start.SelectedItem}-{x.End.SelectedItem}"));
        var newWeekMode = WorkWeekBox.SelectedIndex == 1 ? WorkWeekMode.SingleRest : WorkWeekMode.DoubleRest;
        var newAutoAlternate = AutoAlternateBox.IsChecked == true;
        if (settings.CurrentWeekMode != newWeekMode || (!settings.AutoAlternateWeek && newAutoAlternate)) settings.WorkWeekAnchor = DateTime.Today;
        settings.CurrentWeekMode = newWeekMode;
        settings.AutoAlternateWeek = newAutoAlternate;
        settings.AutoExportWeekly = AutoExportWeeklyBox.IsChecked == true;
        settings.AutoExportMonthly = AutoExportMonthlyBox.IsChecked == true;
        settings.AutoExportTime = exportTime;
        settings.AutoExportFormat = FormatBox.SelectedIndex == 0 ? "Markdown" : FormatBox.SelectedIndex == 1 ? "Csv" : "Both";
        settings.ExportOverwrite = OverwriteBox.IsChecked == true;
        settings.ExportDirectory = string.IsNullOrWhiteSpace(ExportDirectoryBox.Text)
            ? Path.Combine(AppContext.BaseDirectory, "Exports")
            : ExportDirectoryBox.Text.Trim();
        DialogResult = true;
    }
}
