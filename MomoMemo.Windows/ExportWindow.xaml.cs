using System.Windows;
using Forms = System.Windows.Forms;
using WpfMessageBox = System.Windows.MessageBox;

namespace MomoMemo;

public partial class ExportWindow : Window
{
    public bool IsMonthly => RangeBox.SelectedIndex == 1;
    public bool ExportMarkdown => MarkdownBox.IsChecked == true;
    public bool ExportCsv => CsvBox.IsChecked == true;
    public string Directory => DirectoryBox.Text.Trim();
    public bool Overwrite => OverwriteBox.IsChecked == true;

    public ExportWindow(AppSettings settings)
    {
        InitializeComponent();
        RangeBox.ItemsSource = new[] { "本周", "本月" };
        RangeBox.SelectedIndex = 0;
        MarkdownBox.IsChecked = settings.AutoExportFormat is "Markdown" or "Both";
        CsvBox.IsChecked = settings.AutoExportFormat is "Csv" or "Both";
        DirectoryBox.Text = settings.ExportDirectory;
        OverwriteBox.IsChecked = settings.ExportOverwrite;
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new Forms.FolderBrowserDialog { SelectedPath = DirectoryBox.Text, Description = "选择导出目录", UseDescriptionForTitle = true };
        if (dialog.ShowDialog() == Forms.DialogResult.OK) DirectoryBox.Text = dialog.SelectedPath;
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        if (!ExportMarkdown && !ExportCsv)
        {
            WpfMessageBox.Show("请至少选择一种导出格式。", "无法导出", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (Directory.Length == 0)
        {
            WpfMessageBox.Show("请选择导出目录。", "无法导出", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        DialogResult = true;
    }
}
