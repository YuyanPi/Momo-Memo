using System.Windows;
using System.Windows.Controls;
using WpfMessageBox = System.Windows.MessageBox;

namespace MomoMemo;

public partial class NaturalLanguageTaskWindow : Window
{
    private readonly IReadOnlyList<ProjectItem> _projects;
    private readonly string _currentProjectId;
    private readonly AppSettings _settings;
    private readonly NaturalLanguageTaskParser _parser = new();
    public MemoTask? CreatedTask { get; private set; }

    public NaturalLanguageTaskWindow(IReadOnlyList<ProjectItem> projects, string currentProjectId, AppSettings settings)
    {
        InitializeComponent();
        _projects = projects;
        _currentProjectId = currentProjectId;
        _settings = settings;
        ProjectBox.ItemsSource = new[] { new ProjectItem { Id = "", Name = "未分类" } }.Concat(projects.Where(x => x.IsActive)).ToList();
        PriorityBox.ItemsSource = new[] { "P0", "P1", "P2", "P3" };
        DueHourBox.ItemsSource = Enumerable.Range(0, 24).Select(x => x.ToString("00")).ToList();
        DueMinuteBox.ItemsSource = Enumerable.Range(0, 60).Select(x => x.ToString("00")).ToList();
        WorkHoursReminderBox.IsChecked = settings.DefaultWorkHoursReminderEnabled;
        BeforeDueReminderBox.Content = $"截止前 {settings.BeforeDueReminderMinutes} 分钟提醒一次";
        BeforeDueReminderBox.IsChecked = settings.DefaultBeforeDueReminderEnabled;
        ReminderBox.IsChecked = settings.DefaultWorkHoursReminderEnabled || settings.DefaultBeforeDueReminderEnabled;
        RawTextBox.Focus();
    }

    private void Parse_Click(object sender, RoutedEventArgs e)
    {
        var result = _parser.Parse(RawTextBox.Text, _projects, _currentProjectId, DateTime.Now);
        TitleBox.Text = result.Title;
        ProjectBox.SelectedValue = result.ProjectId;
        PriorityBox.SelectedItem = result.Priority;
        ReminderBox.IsChecked = result.ReminderEnabled;
        NoDueBox.IsChecked = result.DueAt is null;
        DueDatePicker.SelectedDate = result.DueAt?.Date;
        DueHourBox.SelectedItem = (result.DueAt?.Hour ?? 18).ToString("00");
        DueMinuteBox.SelectedItem = (result.DueAt?.Minute ?? 0).ToString("00");
        WarningText.Text = string.Join("\n", result.Warnings);
        ConfirmButton.IsEnabled = result.Title.Length > 0;
    }

    private void NoDue_Changed(object sender, RoutedEventArgs e)
    {
        var enabled = NoDueBox.IsChecked != true;
        DueDatePicker.IsEnabled = DueHourBox.IsEnabled = DueMinuteBox.IsEnabled = enabled;
    }

    private void AddDescription_Changed(object sender, RoutedEventArgs e)
    {
        DescriptionBox.IsEnabled = AddDescriptionBox.IsChecked == true;
        if (!DescriptionBox.IsEnabled) DescriptionBox.Clear();
    }

    private void TitleBox_TextChanged(object sender, TextChangedEventArgs e) => ConfirmButton.IsEnabled = TitleBox.Text.Trim().Length > 0;

    private void Confirm_Click(object sender, RoutedEventArgs e)
    {
        var title = TitleBox.Text.Trim();
        if (title.Length == 0)
        {
            WpfMessageBox.Show("请补充任务内容。", "无法添加", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        DateTime? due = null;
        if (NoDueBox.IsChecked != true)
        {
            if (DueDatePicker.SelectedDate is not DateTime date)
            {
                WpfMessageBox.Show("请设置截止日期或选择不设置截止时间。", "无法添加", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            due = date.Date.AddHours(int.Parse(DueHourBox.SelectedItem?.ToString() ?? "18")).AddMinutes(int.Parse(DueMinuteBox.SelectedItem?.ToString() ?? "00"));
        }
        CreatedTask = new MemoTask
        {
            Title = title,
            Description = AddDescriptionBox.IsChecked == true ? DescriptionBox.Text.Trim() : "",
            ProjectId = ProjectBox.SelectedValue?.ToString() ?? "",
            Priority = PriorityBox.SelectedItem?.ToString() ?? "P2",
            DueAt = due,
            ReminderEnabled = ReminderBox.IsChecked == true,
            ReminderRule = WorkHoursReminderBox.IsChecked == true ? "WorkHours" : "None",
            BeforeDueReminderEnabled = BeforeDueReminderBox.IsChecked == true,
            CreatedAt = DateTime.Now,
            ModifiedAt = DateTime.Now
        };
        DialogResult = true;
    }
}
