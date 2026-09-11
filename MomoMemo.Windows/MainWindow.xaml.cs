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
    private sealed record ViewOption(string Id, string Title, string Color, int ReminderCount)
    {
        public bool HasReminder => ReminderCount > 0;
    }

    private readonly StorageService _storage = new();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMinutes(1) };
    private readonly DispatcherTimer _quickAddFeedbackTimer = new() { Interval = TimeSpan.FromSeconds(5) };
    private readonly Forms.NotifyIcon _tray = new();
    private AppData _data = new();
    private string _currentView = "none";
    private string _lastReminderKey = "";
    private readonly HashSet<string> _unreadReminderTaskIds = [];

    public MainWindow()
    {
        InitializeComponent();
        _quickAddFeedbackTimer.Tick += (_, _) =>
        {
            QuickAddFeedbackText.Text = "";
            _quickAddFeedbackTimer.Stop();
        };
        ViewsList.PreviewMouseRightButtonDown += Projects_RightClick;
        Loaded += MainWindow_Loaded;
        Closing += (_, _) => { _storage.Save(_data); _tray.Dispose(); };
    }

    private void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        _data = _storage.Load();
        _currentView = _data.Settings.LastSelectedProjectId;
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
            new("unclassified", "未分类任务", "#B7A99B", ReminderCountForView("unclassified"))
        };
        foreach (var project in _data.Projects.Where(x => x.IsActive && !x.IsHidden))
            views.Add(new($"project:{project.Id}", project.Name, project.Color, ReminderCountForView($"project:{project.Id}")));
        var hiddenCount = _data.Projects.Count(x => x.IsActive && x.IsHidden);
        if (hiddenCount > 0)
            views.Add(new("hidden", $"隐藏项目（{hiddenCount}）", "#B7A99B", ReminderCountForView("hidden")));
        if (!views.Any(x => x.Id == _currentView)) _currentView = "unclassified";
        ViewsList.ItemsSource = views;
        ViewsList.SelectedItem = views.FirstOrDefault(x => x.Id == _currentView) ?? views[0];
    }

    private void BuildTray()
    {
        _tray.Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath ?? "") ?? System.Drawing.SystemIcons.Application;
        _tray.Text = "Momo Memo";
        _tray.Visible = true;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("显示 Momo Memo", null, (_, _) => Dispatcher.Invoke(ShowWindow));
        menu.Items.Add("新建任务", null, (_, _) => Dispatcher.Invoke(() => { ShowWindow(); AddTask_Click(this, new RoutedEventArgs()); }));
        menu.Items.Add("快速录入", null, (_, _) => Dispatcher.Invoke(() => { ShowWindow(); QuickAdd_Click(this, new RoutedEventArgs()); }));
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

    private void RefreshTasks()
    {
        var today = DateTime.Today;
        var tasks = SelectedTasks()
            .Where(x => !x.IsCompleted)
            .OrderBy(x => x.IsOverdue ? -1 : x.Priority switch { "P0" => 0, "P1" => 1, "P2" => 2, _ => 3 })
            .ThenBy(x => x.DueAt)
            .ToList();
        DecorateTasks(tasks);

        // The three unfinished buckets are intentionally mutually exclusive.  A task marked
        // long-term stays in the long-term bucket even when it has a date.
        var todayTasks = tasks.Where(x => !x.IsLongTerm && x.DueAt is not null && x.DueAt.Value.Date <= today).ToList();
        var weekStart = StartOfWeek(today);
        var weekEnd = weekStart.AddDays(6);
        var weekTasks = tasks.Where(x => !x.IsLongTerm && x.DueAt is not null && x.DueAt.Value.Date > today && x.DueAt.Value.Date <= weekEnd).ToList();
        var longTerm = tasks.Where(x => x.IsLongTerm || x.DueAt is null || x.DueAt.Value.Date > weekEnd).ToList();
        var completed = SelectedTasks().Where(x => x.IsCompleted).OrderByDescending(x => x.CompletedAt ?? x.ModifiedAt).ToList();
        DecorateTasks(completed);

        TodayTasks.ItemsSource = todayTasks;
        WeekTasks.ItemsSource = weekTasks;
        LongTermTasks.ItemsSource = longTerm;
        var weekStartForCompleted = StartOfWeek(today);
        CompletedTodayTasks.ItemsSource = completed.Where(x => (x.CompletedAt ?? x.ModifiedAt).Date == today).ToList();
        CompletedWeekTasks.ItemsSource = completed.Where(x => (x.CompletedAt ?? x.ModifiedAt).Date >= weekStartForCompleted && (x.CompletedAt ?? x.ModifiedAt).Date < today).ToList();
        CompletedEarlierTasks.ItemsSource = completed.Where(x => (x.CompletedAt ?? x.ModifiedAt).Date < weekStartForCompleted).ToList();
        CompletedExpander.Header = $"已完成任务（当前项目，{completed.Count}）";
        TodayCountText.Text = $"{todayTasks.Count} 项";
        WeekCountText.Text = $"{weekTasks.Count} 项";
        LongTermCountText.Text = $"{longTerm.Count} 项";
        var todayCompleted = SelectedTasks().Count(x => x.IsCompleted && (x.CompletedAt ?? x.ModifiedAt).Date == today);
        var weekCompleted = SelectedTasks().Count(x => x.IsCompleted && (x.CompletedAt ?? x.ModifiedAt).Date >= weekStart && (x.CompletedAt ?? x.ModifiedAt).Date <= weekEnd);
        SummaryText.Text = $"今天已完成 {todayCompleted} 项 · 本周已完成 {weekCompleted} 项 · 逾期 {tasks.Count(x => x.IsOverdue)} 项";
        ViewToggle_Changed(this, new RoutedEventArgs());
    }

    private IEnumerable<MemoTask> SelectedTasks() => _currentView switch
    {
        "none" or "unclassified" => _data.Tasks.Where(x => string.IsNullOrWhiteSpace(x.ProjectId)),
        _ when _currentView.StartsWith("project:") => _data.Tasks.Where(x => x.ProjectId == _currentView[8..]),
        "hidden" => Enumerable.Empty<MemoTask>(),
        _ => _data.Tasks
    };

    private int ReminderCountForView(string viewId)
    {
        return _data.Tasks.Count(task => _unreadReminderTaskIds.Contains(task.Id) && !task.IsCompleted && viewId switch
        {
            "unclassified" => string.IsNullOrWhiteSpace(task.ProjectId),
            "hidden" => _data.Projects.Any(project => project.IsHidden && project.Id == task.ProjectId),
            _ when viewId.StartsWith("project:") => task.ProjectId == viewId[8..],
            _ => false
        });
    }

    private void ViewsList_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is not DependencyObject source || ItemsControl.ContainerFromElement(ViewsList, source) is not ListBoxItem item || item.DataContext is not ViewOption view || view.ReminderCount == 0) return;
        // A badge means the reminder has not been viewed yet.  Move to the
        // clicked project before rebuilding the list so the selection remains
        // on that project after the badge is cleared.
        _currentView = view.Id;
        _data.Settings.LastSelectedProjectId = _currentView;
        MarkRemindersRead(view.Id);
        BuildViews();
        RefreshTasks();
    }

    private void MarkRemindersRead(string viewId)
    {
        foreach (var task in _data.Tasks.Where(task => _unreadReminderTaskIds.Contains(task.Id) && IsTaskInView(task, viewId)).ToList())
            _unreadReminderTaskIds.Remove(task.Id);
    }

    private bool IsTaskInView(MemoTask task, string viewId) => viewId switch
    {
        "unclassified" => string.IsNullOrWhiteSpace(task.ProjectId),
        "hidden" => _data.Projects.Any(project => project.IsHidden && project.Id == task.ProjectId),
        _ when viewId.StartsWith("project:") => task.ProjectId == viewId[8..],
        _ => false
    };

    private void DecorateTasks(IEnumerable<MemoTask> tasks)
    {
        var projects = _data.Projects.ToDictionary(x => x.Id);
        foreach (var task in tasks)
        {
            if (projects.TryGetValue(task.ProjectId, out var project))
            {
                task.ProjectName = project.Name;
                task.ProjectColor = project.Color;
            }
            else
            {
                task.ProjectName = "未分类";
                task.ProjectColor = "#B7A99B";
            }
        }
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
        _data.Settings.LastSelectedProjectId = _currentView;
        if (IsLoaded) RefreshTasks();
    }

    private void ViewToggle_Changed(object sender, RoutedEventArgs e)
    {
        if (TodayPanel is null || WeekPanel is null || LongTermPanel is null) return;
        TodayPanel.Visibility = TodayToggle.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        WeekPanel.Visibility = WeekToggle.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        LongTermPanel.Visibility = LongToggle.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
    }

    private void EditProjectMenu_Click(object sender, RoutedEventArgs e)
    {
        var project = SelectedProject();
        if (project is null) return;
        var dialog = new ProjectManagerWindow(_data, project) { Owner = this };
        if (dialog.ShowDialog() == true) SaveAndRefresh(true);
    }

    private void DeleteProjectMenu_Click(object sender, RoutedEventArgs e)
    {
        var project = SelectedProject();
        if (project is null) return;
        DeleteProject(project);
    }

    private void DeleteProject(ProjectItem project)
    {
        var count = _data.Tasks.Count(x => x.ProjectId == project.Id);
        var message = count == 0 ? $"删除项目“{project.Name}”吗？" : $"删除项目“{project.Name}”后，{count} 个任务将变为未分类。是否继续？";
        if (WpfMessageBox.Show(message, "删除项目", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        foreach (var task in _data.Tasks.Where(x => x.ProjectId == project.Id)) task.ProjectId = "";
        _data.Projects.Remove(project);
        _currentView = _data.Projects.FirstOrDefault(x => x.IsActive && !x.IsHidden)?.Id is { } id ? $"project:{id}" : "unclassified";
        SaveAndRefresh(true);
    }

    private ProjectItem? SelectedProject()
    {
        var view = ViewsList.SelectedItem as ViewOption;
        if (view?.Id.StartsWith("project:") == true) return _data.Projects.FirstOrDefault(x => x.Id == view.Id[8..]);
        return null;
    }

    private void Projects_RightClick(object? sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is not DependencyObject source) return;
        var item = ItemsControl.ContainerFromElement(ViewsList, source) as ListBoxItem;
        if (item?.DataContext is not ViewOption view || !(view.Id.StartsWith("project:") || view.Id == "hidden")) return;
        ViewsList.SelectedItem = view;
        var menu = new ContextMenu();
        if (view.Id == "hidden")
        {
            foreach (var hiddenProject in _data.Projects.Where(x => x.IsActive && x.IsHidden).ToList())
            {
                var projectMenu = new MenuItem { Header = hiddenProject.Name };
                var restore = new MenuItem { Header = "恢复显示" };
                restore.Click += (_, _) => { hiddenProject.IsHidden = false; _currentView = $"project:{hiddenProject.Id}"; SaveAndRefresh(true); };
                var deleteHidden = new MenuItem { Header = "删除项目" };
                deleteHidden.Click += (_, _) => DeleteProject(hiddenProject);
                projectMenu.Items.Add(restore); projectMenu.Items.Add(deleteHidden); menu.Items.Add(projectMenu);
            }
            item.ContextMenu = menu; menu.IsOpen = true; e.Handled = true; return;
        }
        var edit = new MenuItem { Header = "编辑项目" };
        edit.Click += EditProjectMenu_Click;
        var hide = new MenuItem { Header = "隐藏项目" };
        hide.Click += (_, _) => { var project = SelectedProject(); if (project is null) return; project.IsHidden = !project.IsHidden; _currentView = project.IsHidden ? "unclassified" : $"project:{project.Id}"; SaveAndRefresh(true); };
        var delete = new MenuItem { Header = "删除项目" };
        delete.Click += DeleteProjectMenu_Click;
        menu.Items.Add(edit);
        menu.Items.Add(hide);
        menu.Items.Add(delete);
        item.ContextMenu = menu;
        menu.IsOpen = true;
        e.Handled = true;
    }

    private System.Windows.Point _projectDragStart;
    private void Projects_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;
        if (_projectDragStart == default) _projectDragStart = e.GetPosition(ViewsList);
        var position = e.GetPosition(ViewsList);
        if (Math.Abs(position.X - _projectDragStart.X) < 8) return;
        if (e.OriginalSource is not DependencyObject source) return;
        var item = ItemsControl.ContainerFromElement(ViewsList, source) as ListBoxItem;
        if (item?.DataContext is ViewOption view && view.Id.StartsWith("project:"))
            DragDrop.DoDragDrop(item, view, System.Windows.DragDropEffects.Move);
        _projectDragStart = default;
    }

    private void Projects_DragOver(object sender, System.Windows.DragEventArgs e) => e.Effects = e.Data.GetDataPresent(typeof(ViewOption)) ? System.Windows.DragDropEffects.Move : System.Windows.DragDropEffects.None;

    private void Projects_Drop(object sender, System.Windows.DragEventArgs e)
    {
        if (e.Data.GetData(typeof(ViewOption)) is not ViewOption sourceView) return;
        var targetItem = ItemsControl.ContainerFromElement(ViewsList, (DependencyObject)e.OriginalSource) as ListBoxItem;
        if (targetItem?.DataContext is not ViewOption targetView || !targetView.Id.StartsWith("project:") || sourceView.Id == targetView.Id) return;
        var sourceId = sourceView.Id[8..];
        var targetId = targetView.Id[8..];
        var sourceIndex = _data.Projects.FindIndex(x => x.Id == sourceId);
        var targetIndex = _data.Projects.FindIndex(x => x.Id == targetId);
        if (sourceIndex < 0 || targetIndex < 0) return;
        (_data.Projects[sourceIndex], _data.Projects[targetIndex]) = (_data.Projects[targetIndex], _data.Projects[sourceIndex]);
        SaveAndRefresh(true);
    }

    private void AddTask_Click(object sender, RoutedEventArgs e)
    {
        var task = new MemoTask
        {
            ProjectId = _currentView.StartsWith("project:") ? _currentView[8..] : "",
            StartAt = DateTime.Now,
            ReminderEnabled = _data.Settings.DefaultWorkHoursReminderEnabled || _data.Settings.DefaultBeforeDueReminderEnabled,
            ReminderRule = _data.Settings.DefaultWorkHoursReminderEnabled ? "WorkHours" : "None",
            BeforeDueReminderEnabled = _data.Settings.DefaultBeforeDueReminderEnabled,
        };
        var editor = new TaskEditorWindow(task, _data.Projects, _data.Settings) { Owner = this };
        if (editor.ShowDialog() != true) return;
        _data.Tasks.Add(task);
        SaveAndRefresh();
    }

    private void QuickAdd_Click(object sender, RoutedEventArgs e)
    {
        var currentProjectId = _currentView.StartsWith("project:") ? _currentView[8..] : "";
        var dialog = new NaturalLanguageTaskWindow(_data.Projects, currentProjectId, _data.Settings) { Owner = this };
        if (dialog.ShowDialog() != true || dialog.CreatedTask is null) return;
        _data.Tasks.Add(dialog.CreatedTask);
        SaveAndRefresh();
        var projectName = _data.Projects.FirstOrDefault(x => x.Id == dialog.CreatedTask.ProjectId)?.Name ?? "未分类";
        var dueText = dialog.CreatedTask.DueAt is null ? "未设置截止时间" : $"截止 {dialog.CreatedTask.DueAt:MM-dd HH:mm}";
        QuickAddFeedbackText.Text = $"已添加至 {projectName} · {dueText}";
        _quickAddFeedbackTimer.Stop();
        _quickAddFeedbackTimer.Start();
    }

    private void EditTask_Click(object sender, RoutedEventArgs e)
    {
        EditTask((sender as FrameworkElement)?.Tag);
    }

    private void EditTaskMenu_Click(object sender, RoutedEventArgs e) => EditTask((sender as MenuItem)?.CommandParameter);

    private void EditTask(object? id)
    {
        var task = FindTask(id);
        if (task is null) return;
        var editor = new TaskEditorWindow(task, _data.Projects, _data.Settings) { Owner = this };
        if (editor.ShowDialog() == true) SaveAndRefresh();
    }

    private void Complete_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.CheckBox box || FindTask(box.Tag) is not { } task) return;
        task.Status = box.IsChecked == true ? MemoTaskStatus.Completed : MemoTaskStatus.InProgress;
        if (task.IsCompleted)
        {
            task.CompletedAt ??= DateTime.Now;
        }
        else task.CompletedAt = null;
        task.ModifiedAt = DateTime.Now;
        SaveAndRefresh();
    }

    private void StatusMenu_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button button || FindTask(button.Tag) is not { } task) return;
        var menu = new ContextMenu
        {
            PlacementTarget = button,
            Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom,
            Background = System.Windows.Media.Brushes.White,
            BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(226, 215, 204)),
            Padding = new Thickness(4)
        };
        void AddItem(string title, Action action)
        {
            var item = new MenuItem { Header = title, Padding = new Thickness(12, 6, 18, 6), FontSize = 12 };
            item.Click += (_, _) => action();
            menu.Items.Add(item);
        }

        if (task.IsCompleted)
        {
            AddItem("↩  恢复任务", () => UpdateTaskStatus(task, MemoTaskStatus.InProgress));
        }
        else if (task.IsOverdue)
        {
            AddItem("✓  标记为已完成", () => UpdateTaskStatus(task, MemoTaskStatus.Completed));
            menu.Items.Add(new Separator());
            AddItem("↪  顺延一天", () => PostponeOneDay(task));
            AddItem("📅  选择新的截止时间", () => ChooseNewDeadline(task));
            AddItem("Ⅱ  暂停", () => UpdateTaskStatus(task, MemoTaskStatus.Paused));
        }
        else if (task.Status == MemoTaskStatus.Paused)
        {
            AddItem("▶  继续任务", () => UpdateTaskStatus(task, MemoTaskStatus.InProgress));
            AddItem("✓  标记为已完成", () => UpdateTaskStatus(task, MemoTaskStatus.Completed));
        }
        else
        {
            AddItem("✓  标记为已完成", () => UpdateTaskStatus(task, MemoTaskStatus.Completed));
            AddItem("Ⅱ  暂停", () => UpdateTaskStatus(task, MemoTaskStatus.Paused));
        }
        menu.IsOpen = true;
    }

    private void RestoreTask_Click(object sender, RoutedEventArgs e)
    {
        if (FindTask((sender as FrameworkElement)?.Tag) is { } task) UpdateTaskStatus(task, MemoTaskStatus.InProgress);
    }

    private void UpdateTaskStatus(MemoTask task, MemoTaskStatus status)
    {
        if (task.Status == status) return;
        task.Status = status;
        if (status == MemoTaskStatus.Completed)
        {
            task.CompletedAt = DateTime.Now;
        }
        else task.CompletedAt = null;
        task.ModifiedAt = DateTime.Now;
        SaveAndRefresh();
    }

    private void PostponeOneDay(MemoTask task)
    {
        if (task.DueAt is null) return;
        task.DueAt = DateTime.Today.AddDays(1).Add(task.DueAt.Value.TimeOfDay);
        task.BeforeDueReminderFor = null;
        task.ModifiedAt = DateTime.Now;
        SaveAndRefresh();
    }

    private void ChooseNewDeadline(MemoTask task)
    {
        var dialog = new PostponeTaskWindow(task.DueAt) { Owner = this };
        if (dialog.ShowDialog() != true || dialog.DueAt is null) return;
        task.DueAt = dialog.DueAt;
        task.BeforeDueReminderFor = null;
        task.ModifiedAt = DateTime.Now;
        SaveAndRefresh();
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        DeleteTask((sender as FrameworkElement)?.Tag);
    }

    private void DeleteTaskMenu_Click(object sender, RoutedEventArgs e) => DeleteTask((sender as MenuItem)?.CommandParameter);

    private void DeleteTask(object? id)
    {
        var task = FindTask(id);
        if (task is null) return;
        if (task.IsCompleted)
        {
            WpfMessageBox.Show("请先恢复已完成的任务，再执行删除。", "不能删除", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (WpfMessageBox.Show($"确定真正删除“{task.Title}”吗？", "删除错误任务", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        _data.Tasks.Remove(task);
        SaveAndRefresh(true);
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

    private void Projects_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ProjectManagerWindow(_data) { Owner = this };
        if (dialog.ShowDialog() == true) SaveAndRefresh(true);
    }

    private void ShowStats_Click(object sender, RoutedEventArgs e)
    {
        var start = StartOfWeek(DateTime.Today);
        var hiddenProjectIds = _data.Projects.Where(p => p.IsHidden).Select(p => p.Id).ToHashSet();
        var tasks = _data.Tasks.Where(x => !hiddenProjectIds.Contains(x.ProjectId) && ((x.StartAt ?? x.CreatedAt) >= start && (x.StartAt ?? x.CreatedAt) < start.AddDays(7))).ToList();
        var done = tasks.Count(x => x.IsCompleted);
        var projects = _data.Projects.Where(p => !p.IsHidden).Select(p => $"{p.Name}：{tasks.Count(x => x.ProjectId == p.Id && x.IsCompleted)}/{tasks.Count(x => x.ProjectId == p.Id)}");
        var priorities = new[] { "P0", "P1", "P2", "P3" }.Select(p => $"{p}：{tasks.Count(x => x.Priority == p && x.IsCompleted)}/{tasks.Count(x => x.Priority == p)}");
        WpfMessageBox.Show($"总任务：{tasks.Count}\n已完成：{done}\n未完成：{tasks.Count - done}\n逾期：{tasks.Count(x => x.IsOverdue)}\n完成率：{(tasks.Count == 0 ? 0 : done * 100 / tasks.Count)}%\n\n项目统计\n{string.Join("\n", projects)}\n\n优先级统计\n{string.Join("\n", priorities)}", "本周统计");
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ExportWindow(_data.Settings) { Owner = this };
        if (dialog.ShowDialog() != true) return;
        var start = dialog.IsMonthly ? new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1) : StartOfWeek(DateTime.Today);
        var end = dialog.IsMonthly ? start.AddMonths(1).AddDays(-1) : start.AddDays(6);
        _data.Settings.ExportDirectory = dialog.Directory;
        _data.Settings.ExportOverwrite = dialog.Overwrite;
        try
        {
            ExportRange(start, end, dialog.ExportMarkdown, dialog.ExportCsv, dialog.Directory, dialog.Overwrite,
                "manual", dialog.IsMonthly ? "monthly" : "weekly");
            _storage.Save(_data);
            WpfMessageBox.Show($"已导出 {(dialog.IsMonthly ? "本月" : "本周")}工作记录。", "导出完成", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception exception)
        {
            WpfMessageBox.Show(exception.Message, "导出失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
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
        var candidates = _data.Tasks.Where(x => !x.IsCompleted && x.Status != MemoTaskStatus.Paused && x.ReminderEnabled && (x.ReminderRule != "None" || x.BeforeDueReminderEnabled) && (x.IsOverdue || x.MustToday || x.StartAt?.Date == now.Date || x.DueAt?.Date == now.Date) && !(x.SnoozedUntil > now)).ToList();
        var triggered = candidates.Where(x => IsWorkHoursReminderDue(x, elapsed, settings) || IsBeforeDueReminderDue(x, now, settings)).ToList();
        if (candidates.Count == 0) { ClearReminderState(); return; }
        if (triggered.Count == 0) return;
        foreach (var task in triggered.Where(x => IsBeforeDueReminderDue(x, now, settings))) task.BeforeDueReminderFor = task.DueAt;
        _storage.Save(_data);
        SetReminderState(triggered);
    }

    private static bool IsWorkHoursReminderDue(MemoTask task, int elapsed, AppSettings settings) => task.ReminderRule switch
    {
        "Every30" => elapsed % 30 == 0,
        "Every60" => elapsed % 60 == 0,
        "WorkHours" => elapsed % Math.Max(30, settings.ReminderIntervalMinutes) == 0,
        _ => false
    };

    private static bool IsBeforeDueReminderDue(MemoTask task, DateTime now, AppSettings settings) =>
        task.BeforeDueReminderEnabled && task.DueAt is not null && task.BeforeDueReminderFor != task.DueAt && task.DueAt > now && task.DueAt <= now.AddMinutes(settings.BeforeDueReminderMinutes);

    private void SetReminderState(IReadOnlyCollection<MemoTask> triggered)
    {
        foreach (var task in triggered) _unreadReminderTaskIds.Add(task.Id);
        BuildViews();
        var count = triggered.Count;
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
        if (!settings.AutoExportWeekly && !settings.AutoExportMonthly) return;
        if (now.ToString("HH:mm") != $"{settings.AutoExportTime:hh\\:mm}") return;
        if (settings.AutoExportWeekly && now.DayOfWeek == DayOfWeek.Friday)
        {
            var start = StartOfWeek(now.Date);
            var key = $"weekly-{start:yyyy-MM-dd}";
            if (settings.LastWeeklyAutoExportKey != key && TryAutoExport(start, start.AddDays(6), "weekly"))
                settings.LastWeeklyAutoExportKey = key;
        }
        if (settings.AutoExportMonthly && now.Date == new DateTime(now.Year, now.Month, 1).AddMonths(1).AddDays(-1))
        {
            var start = new DateTime(now.Year, now.Month, 1);
            var key = $"monthly-{start:yyyy-MM}";
            if (settings.LastMonthlyAutoExportKey != key && TryAutoExport(start, now.Date, "monthly"))
                settings.LastMonthlyAutoExportKey = key;
        }
        _storage.Save(_data);
    }

    private bool TryAutoExport(DateTime start, DateTime end, string period)
    {
        try
        {
            ExportRange(start, end, _data.Settings.AutoExportFormat is "Markdown" or "Both", _data.Settings.AutoExportFormat is "Csv" or "Both",
                _data.Settings.ExportDirectory, _data.Settings.ExportOverwrite, "auto", period);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private void ExportRange(DateTime start, DateTime end, bool markdown, bool csv, string directory, bool overwrite, string source, string period)
    {
        var tasks = _data.Tasks.Where(x =>
            (TaskDate(x).Date >= start.Date && TaskDate(x).Date <= end.Date) ||
            (x.IsCompleted && x.CompletedAt is not null && x.CompletedAt.Value.Date >= start.Date && x.CompletedAt.Value.Date <= end.Date)).ToList();
        var baseName = ExportService.BuildBaseName(start, end, source, period);
        var rangeText = $"{start:yyyy-MM-dd} ～ {end:yyyy-MM-dd}";
        if (markdown)
            File.WriteAllText(ExportService.AvailablePath(directory, baseName, "md", overwrite), ExportService.ExportMarkdown(tasks, _data.Projects, rangeText));
        if (csv)
            File.WriteAllText(ExportService.AvailablePath(directory, baseName, "csv", overwrite), ExportService.ExportCsv(tasks, _data.Projects));
    }

    private static DateTime TaskDate(MemoTask task) => task.StartAt ?? task.DueAt ?? task.CreatedAt;

    private static bool IsWithinNextThreeDays(DateTime? date, DateTime start, DateTime end) =>
        date is not null && date.Value.Date >= start && date.Value.Date < end;

    private static DateTime StartOfWeek(DateTime date)
    {
        var daysSinceMonday = ((int)date.DayOfWeek + 6) % 7;
        return date.Date.AddDays(-daysSinceMonday);
    }
}
