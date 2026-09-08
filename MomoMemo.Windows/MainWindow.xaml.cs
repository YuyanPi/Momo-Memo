using System.Collections.ObjectModel;
using System.IO;
using System.Media;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Shell;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using WpfMessageBox = System.Windows.MessageBox;

namespace MomoMemo;

public partial class MainWindow : Window
{
    private sealed record ViewOption(string Id, string Title);

    private readonly StorageService _storage = new();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMinutes(1) };
    private readonly Forms.NotifyIcon _tray = new();
    private AppData _data = new();
    private string _currentView = "today";
    private string _lastReminderKey = "";

    public MainWindow()
    {
        InitializeComponent();
        Loaded += MainWindow_Loaded;
        Closing += (_, _) => _tray.Dispose();
    }

    private void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        _data = _storage.Load();
        BuildViews();
        RefreshTasks();
        BuildTray();
        _timer.Tick += (_, _) => { CheckReminder(); CheckAutoExport(); };
        _timer.Start();
        CheckReminder();
        CheckAutoExport();
    }

    private void BuildViews()
    {
        var views = new ObservableCollection<ViewOption>
        {
            new("today", "今日"), new("upcoming", "未来三天"), new("longterm", "长期任务"),
            new("inbox", "Inbox"), new("incomplete", "未完成"), new("all", "全部任务"),
            new("completed", "已完成"), new("archived", "归档")
        };
        foreach (var project in _data.Projects.Where(x => x.IsActive))
            views.Add(new($"project:{project.Id}", $"项目 · {project.Name}"));
        ViewsList.ItemsSource = views;
        ViewsList.SelectedItem = views.FirstOrDefault(x => x.Id == _currentView) ?? views[0];
    }

    private void BuildTray()
    {
        _tray.Icon = System.Drawing.SystemIcons.Application;
        _tray.Text = "Momo Memo";
        _tray.Visible = true;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("显示 Momo Memo", null, (_, _) => Dispatcher.Invoke(ShowWindow));
        menu.Items.Add("快速添加到 Inbox", null, (_, _) => Dispatcher.Invoke(() => { ShowWindow(); QuickTitle.Focus(); }));
        menu.Items.Add("退出", null, (_, _) => Dispatcher.Invoke(Close));
        _tray.ContextMenuStrip = menu;
        _tray.DoubleClick += (_, _) => Dispatcher.Invoke(ShowWindow);
    }

    private void ShowWindow()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private IEnumerable<MemoTask> FilterTasks()
    {
        var now = DateTime.Now;
        var today = DateTime.Today;
        var end = today.AddDays(3);
        return _data.Tasks.Where(task => _currentView switch
        {
            "archived" => task.IsArchived,
            "today" => !task.IsArchived && !task.IsCompleted && (task.IsOverdue || task.MustToday || task.StartAt?.Date == today || task.DueAt?.Date == today),
            "upcoming" => !task.IsArchived && !task.IsCompleted && ((task.StartAt >= today && task.StartAt < end) || (task.DueAt >= now && task.DueAt < end)),
            "longterm" => !task.IsArchived && !task.IsCompleted && task.IsLongTerm,
            "inbox" => !task.IsArchived && task.ProjectId == "inbox",
            "incomplete" => !task.IsArchived && !task.IsCompleted,
            "completed" => !task.IsArchived && task.IsCompleted,
            "all" => !task.IsArchived,
            _ when _currentView.StartsWith("project:") => !task.IsArchived && task.ProjectId == _currentView[8..],
            _ => false
        });
    }

    private void RefreshTasks()
    {
        var tasks = FilterTasks()
            .OrderBy(x => x.IsOverdue ? 0 : x.Priority == "P0" ? 1 : x.MustToday ? 2 : 3)
            .ThenBy(x => x.Priority)
            .ThenBy(x => x.DueAt ?? DateTime.MaxValue)
            .ToList();
        TasksList.ItemsSource = null;
        TasksList.ItemsSource = tasks;
        var done = tasks.Count(x => x.IsCompleted);
        SummaryText.Text = $"共 {tasks.Count} 项 · 完成 {done} · 未完成 {tasks.Count - done} · 逾期 {tasks.Count(x => x.IsOverdue)}";
        PageTitle.Text = (ViewsList.SelectedItem as ViewOption)?.Title ?? "今日";
    }

    private void SaveAndRefresh(bool rebuildViews = false)
    {
        _storage.Save(_data);
        if (rebuildViews) BuildViews();
        RefreshTasks();
    }

    private MemoTask? FindTask(object? tag) => _data.Tasks.FirstOrDefault(x => x.Id == tag?.ToString());

    private void ViewsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ViewsList.SelectedItem is not ViewOption view) return;
        _currentView = view.Id;
        if (IsLoaded) RefreshTasks();
    }

    private void AddTask_Click(object sender, RoutedEventArgs e)
    {
        var task = new MemoTask
        {
            ProjectId = _currentView.StartsWith("project:") ? _currentView[8..] : "inbox",
            StartAt = _currentView == "today" ? DateTime.Now : null
        };
        var editor = new TaskEditorWindow(task, _data.Projects) { Owner = this };
        if (editor.ShowDialog() != true) return;
        _data.Tasks.Add(task);
        SaveAndRefresh();
    }

    private void EditTask_Click(object sender, RoutedEventArgs e)
    {
        var task = FindTask((sender as FrameworkElement)?.Tag);
        if (task is null) return;
        var editor = new TaskEditorWindow(task, _data.Projects) { Owner = this };
        if (editor.ShowDialog() == true) SaveAndRefresh();
    }

    private void Complete_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.CheckBox box || FindTask(box.Tag) is not { } task) return;
        task.Status = box.IsChecked == true ? MemoTaskStatus.Completed : MemoTaskStatus.NotStarted;
        if (task.IsCompleted)
        {
            task.CompletedAt ??= DateTime.Now;
            task.EverCompleted = true;
        }
        task.ModifiedAt = DateTime.Now;
        SaveAndRefresh();
    }

    private void QuickAdd_Click(object sender, RoutedEventArgs e) => QuickAdd();

    private void QuickTitle_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Enter) QuickAdd();
    }

    private void QuickAdd()
    {
        var title = QuickTitle.Text.Trim();
        if (title.Length == 0) return;
        _data.Tasks.Add(new MemoTask { Title = title, ProjectId = "inbox" });
        QuickTitle.Clear();
        _currentView = "inbox";
        BuildViews();
        SaveAndRefresh();
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        var task = FindTask((sender as FrameworkElement)?.Tag);
        if (task is null) return;
        if (task.EverCompleted || task.EverArchived)
        {
            WpfMessageBox.Show("曾完成或曾归档的任务属于永久记录，只能编辑或恢复显示。", "不能删除", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (WpfMessageBox.Show($"确定真正删除“{task.Title}”吗？", "删除错误任务", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        _data.Tasks.Remove(task);
        SaveAndRefresh();
    }

    private void Archive_Click(object sender, RoutedEventArgs e)
    {
        var task = FindTask((sender as FrameworkElement)?.Tag);
        if (task is null) return;
        task.IsArchived = !task.IsArchived;
        task.EverArchived = true;
        task.ArchivedAt = task.IsArchived ? DateTime.Now : task.ArchivedAt;
        task.ModifiedAt = DateTime.Now;
        SaveAndRefresh();
    }

    private void Snooze_Click(object sender, RoutedEventArgs e)
    {
        var task = FindTask((sender as FrameworkElement)?.Tag);
        if (task is null || task.IsCompleted) return;
        var result = WpfMessageBox.Show("选择“是”：30 分钟后；选择“否”：1 小时后；取消：不修改。", "稍后提醒", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (result == MessageBoxResult.Cancel) return;
        task.SnoozedUntil = DateTime.Now.AddMinutes(result == MessageBoxResult.Yes ? 30 : 60);
        task.ModifiedAt = DateTime.Now;
        SaveAndRefresh();
    }

    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SettingsWindow(_data) { Owner = this };
        if (dialog.ShowDialog() == true) SaveAndRefresh(true);
    }

    private void ShowStats_Click(object sender, RoutedEventArgs e)
    {
        var start = StartOfWeek(DateTime.Today);
        var tasks = _data.Tasks.Where(x => !x.IsArchived && ((x.StartAt ?? x.CreatedAt) >= start && (x.StartAt ?? x.CreatedAt) < start.AddDays(7))).ToList();
        var done = tasks.Count(x => x.IsCompleted);
        var projects = _data.Projects.Select(p => $"{p.Name}：{tasks.Count(x => x.ProjectId == p.Id && x.IsCompleted)}/{tasks.Count(x => x.ProjectId == p.Id)}");
        var priorities = new[] { "P0", "P1", "P2", "P3" }.Select(p => $"{p}：{tasks.Count(x => x.Priority == p && x.IsCompleted)}/{tasks.Count(x => x.Priority == p)}");
        WpfMessageBox.Show($"总任务：{tasks.Count}\n已完成：{done}\n未完成：{tasks.Count - done}\n逾期：{tasks.Count(x => x.IsOverdue)}\n完成率：{(tasks.Count == 0 ? 0 : done * 100 / tasks.Count)}%\n\n项目统计\n{string.Join("\n", projects)}\n\n优先级统计\n{string.Join("\n", priorities)}", "本周统计");
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        var all = WpfMessageBox.Show("导出全部历史？选择“否”则只导出本周。", "导出范围", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (all == MessageBoxResult.Cancel) return;
        var allHistory = all == MessageBoxResult.Yes;
        var start = StartOfWeek(DateTime.Today);
        var end = start.AddDays(6);
        var tasks = allHistory ? _data.Tasks.ToList() : _data.Tasks.Where(x => (x.StartAt ?? x.CreatedAt).Date >= start && (x.StartAt ?? x.CreatedAt).Date <= end).ToList();
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Filter = "Markdown (*.md)|*.md|CSV (*.csv)|*.csv",
            InitialDirectory = _data.Settings.ExportDirectory,
            FileName = allHistory ? ExportService.BuildAllBaseName() : ExportService.BuildBaseName(start, end)
        };
        if (dialog.ShowDialog(this) != true) return;
        File.WriteAllText(dialog.FileName, dialog.FilterIndex == 1
            ? ExportService.ExportMarkdown(tasks, _data.Projects, allHistory ? "全部历史" : $"{start:yyyy-MM-dd} ～ {end:yyyy-MM-dd}")
            : ExportService.ExportCsv(tasks, _data.Projects));
    }

    private void CheckReminder()
    {
        var settings = _data.Settings;
        var now = DateTime.Now;
        if (!settings.RemindersEnabled || !IsWorkingDay(now) || now.TimeOfDay < settings.WorkStart || now.TimeOfDay > settings.WorkEnd || IsQuiet(now.TimeOfDay))
        {
            ClearReminderState();
            return;
        }
        var key = now.ToString("yyyy-MM-dd HH:mm");
        if (_lastReminderKey == key) return;
        _lastReminderKey = key;
        var elapsed = (int)(now.TimeOfDay - settings.WorkStart).TotalMinutes;
        var candidates = _data.Tasks.Where(x => !x.IsCompleted && !x.IsArchived && x.ReminderEnabled && x.ReminderRule != "None" && (x.IsOverdue || x.MustToday || x.StartAt?.Date == now.Date || x.DueAt?.Date == now.Date) && !(x.SnoozedUntil > now)).ToList();
        var triggered = candidates.Where(x => x.ReminderRule switch
        {
            "Every30" => elapsed % 30 == 0,
            "Every60" => elapsed % 60 == 0,
            "BeforeDue" => x.DueAt is not null && x.DueAt >= now && x.DueAt <= now.AddMinutes(30),
            _ => elapsed % Math.Max(30, settings.ReminderIntervalMinutes) == 0
        }).ToList();
        if (candidates.Count == 0) { ClearReminderState(); return; }
        if (triggered.Count == 0) return;
        SetReminderState(triggered.Count);
    }

    private void SetReminderState(int count)
    {
        Title = $"● Momo Memo ({count})";
        _tray.Icon = System.Drawing.SystemIcons.Warning;
        _tray.Text = $"Momo Memo：{count} 个任务待处理";
        TaskbarState.ProgressState = TaskbarItemProgressState.Paused;
        TaskbarState.ProgressValue = 1;
        var mode = _data.Settings.ReminderMode;
        if (mode.Contains("Notification")) _tray.ShowBalloonTip(5000, "Momo Memo", $"还有 {count} 个今日或逾期任务未完成", Forms.ToolTipIcon.Info);
        if (mode.Contains("Desktop")) ShowWindow();
        if (mode.Contains("Sound")) SystemSounds.Asterisk.Play();
    }

    private void ClearReminderState()
    {
        Title = "Momo Memo";
        _tray.Icon = System.Drawing.SystemIcons.Application;
        _tray.Text = "Momo Memo";
        TaskbarState.ProgressState = TaskbarItemProgressState.None;
    }

    private bool IsWorkingDay(DateTime now)
    {
        if (now.DayOfWeek == DayOfWeek.Sunday) return false;
        var mode = _data.Settings.CurrentWeekMode;
        if (_data.Settings.AutoAlternateWeek)
        {
            var weeks = (int)((StartOfWeek(now.Date) - StartOfWeek(_data.Settings.WorkWeekAnchor.Date)).TotalDays / 7);
            if (Math.Abs(weeks) % 2 == 1) mode = mode == WorkWeekMode.DoubleRest ? WorkWeekMode.SingleRest : WorkWeekMode.DoubleRest;
        }
        return now.DayOfWeek != DayOfWeek.Saturday || mode == WorkWeekMode.SingleRest;
    }

    private bool IsQuiet(TimeSpan time)
    {
        foreach (var line in _data.Settings.QuietRanges.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var pair = line.Split('-', StringSplitOptions.TrimEntries);
            if (pair.Length != 2 || !TimeSpan.TryParse(pair[0], out var start) || !TimeSpan.TryParse(pair[1], out var end)) continue;
            if (start <= end ? time >= start && time < end : time >= start || time < end) return true;
        }
        return false;
    }

    private void CheckAutoExport()
    {
        var settings = _data.Settings;
        var now = DateTime.Now;
        if (!settings.AutoExportEnabled || now.ToString("HH:mm") != $"{settings.AutoExportTime:hh\\:mm}") return;
        if (settings.AutoExportFrequency == "Weekly" && now.DayOfWeek != DayOfWeek.Friday) return;
        if (settings.AutoExportFrequency == "Monthly" && now.Date != new DateTime(now.Year, now.Month, 1).AddMonths(1).AddDays(-1)) return;
        var key = $"{settings.AutoExportFrequency}-{now:yyyy-MM-dd}";
        if (settings.LastAutoExportKey == key) return;

        DateTime start, end;
        if (settings.AutoExportFrequency == "Daily") start = end = now.Date;
        else if (settings.AutoExportFrequency == "Monthly") { start = new(now.Year, now.Month, 1); end = start.AddMonths(1).AddDays(-1); }
        else { start = StartOfWeek(now.Date); end = start.AddDays(6); }
        var tasks = _data.Tasks.Where(x => (x.StartAt ?? x.CreatedAt).Date >= start && (x.StartAt ?? x.CreatedAt).Date <= end).ToList();
        var baseName = ExportService.BuildBaseName(start, end);
        if (settings.AutoExportFormat is "Markdown" or "Both")
            File.WriteAllText(ExportService.AvailablePath(settings.ExportDirectory, baseName, "md", settings.ExportOverwrite), ExportService.ExportMarkdown(tasks, _data.Projects, $"{start:yyyy-MM-dd} ～ {end:yyyy-MM-dd}"));
        if (settings.AutoExportFormat is "Csv" or "Both")
            File.WriteAllText(ExportService.AvailablePath(settings.ExportDirectory, baseName, "csv", settings.ExportOverwrite), ExportService.ExportCsv(tasks, _data.Projects));
        settings.LastAutoExportKey = key;
        _storage.Save(_data);
    }

    private static DateTime StartOfWeek(DateTime date)
    {
        var daysSinceMonday = ((int)date.DayOfWeek + 6) % 7;
        return date.Date.AddDays(-daysSinceMonday);
    }
}
