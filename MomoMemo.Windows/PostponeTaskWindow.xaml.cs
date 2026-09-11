using System.Windows;

namespace MomoMemo;

public partial class PostponeTaskWindow : Window
{
    public DateTime? DueAt { get; private set; }

    public PostponeTaskWindow(DateTime? currentDue)
    {
        InitializeComponent();
        var value = currentDue is { } due && due > DateTime.Now ? due : DateTime.Today.AddDays(1).AddHours(18);
        DatePicker.SelectedDate = value.Date;
        HourBox.ItemsSource = Enumerable.Range(0, 24).Select(x => x.ToString("00")).ToList();
        MinuteBox.ItemsSource = Enumerable.Range(0, 60).Select(x => x.ToString("00")).ToList();
        HourBox.SelectedItem = value.Hour.ToString("00");
        MinuteBox.SelectedItem = value.Minute.ToString("00");
    }

    private void Confirm_Click(object sender, RoutedEventArgs e)
    {
        if (DatePicker.SelectedDate is not DateTime date) return;
        DueAt = date.Date.AddHours(int.Parse(HourBox.SelectedItem?.ToString() ?? "18")).AddMinutes(int.Parse(MinuteBox.SelectedItem?.ToString() ?? "00"));
        DialogResult = true;
    }
}
