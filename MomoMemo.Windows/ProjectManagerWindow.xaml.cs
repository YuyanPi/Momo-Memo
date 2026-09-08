using System.Windows;
using WpfMessageBox = System.Windows.MessageBox;

namespace MomoMemo;

public partial class ProjectManagerWindow : Window
{
    private static readonly string[] Palette = ["#C9826A", "#6F9B95", "#8C7AA8", "#C39A4B", "#7795B7", "#B87B91"];
    private readonly AppData _data;
    private readonly ProjectItem? _project;

    public ProjectManagerWindow(AppData data, ProjectItem? project = null)
    {
        InitializeComponent();
        _data = data;
        _project = project;
        if (project is not null)
        {
            Title = "编辑项目";
            NameBox.Text = project.Name;
            DescriptionBox.Text = project.Description;
            StartDatePicker.SelectedDate = project.StartDate;
            DueDatePicker.SelectedDate = project.DueDate;
        }
        NameBox.Focus();
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var name = NameBox.Text.Trim();
        if (name.Length == 0)
        {
            WpfMessageBox.Show("项目名称不能为空。", "无法保存", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (_data.Projects.Any(x => x != _project && x.Name.Equals(name, StringComparison.OrdinalIgnoreCase)))
        {
            WpfMessageBox.Show("项目名称已经存在。", "无法保存", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var project = _project ?? new ProjectItem { Color = Palette[_data.Projects.Count % Palette.Length] };
        if (_project is null) _data.Projects.Add(project);
        project.Name = name;
        project.Description = DescriptionBox.Text.Trim();
        project.StartDate = StartDatePicker.SelectedDate;
        project.DueDate = DueDatePicker.SelectedDate;
        DialogResult = true;
    }
}
