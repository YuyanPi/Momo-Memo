using System.Text.Json;
using System.Text.Json.Serialization;
using System.IO;

namespace MomoMemo;

/// <summary>
/// Keeps user data outside the replaceable application folder when a portable release is placed
/// under &lt;root&gt;\App.  For example, D:\MomoMemo\App\MomoMemo.exe stores data in D:\MomoMemo\Data.
/// </summary>
public static class AppStoragePaths
{
    public static string ApplicationDirectory { get; } = Path.GetFullPath(AppContext.BaseDirectory);
    public static string RootDirectory
    {
        get
        {
            var application = new DirectoryInfo(ApplicationDirectory);
            return application.Name.Equals("App", StringComparison.OrdinalIgnoreCase) && application.Parent is not null
                ? application.Parent.FullName
                : application.FullName;
        }
    }

    public static string DataDirectory => Path.Combine(RootDirectory, "Data");
    public static string ExportsDirectory => Path.Combine(RootDirectory, "Exports");
}

public sealed class StorageService
{
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string DataDirectory { get; } = AppStoragePaths.DataDirectory;
    public string DataPath => Path.Combine(DataDirectory, "momo-memo.json");

    public AppData Load()
    {
        Directory.CreateDirectory(DataDirectory);
        if (!File.Exists(DataPath)) return CreateDefault();

        try
        {
            var data = JsonSerializer.Deserialize<AppData>(File.ReadAllText(DataPath), _jsonOptions) ?? CreateDefault();
            Normalize(data);
            return data;
        }
        catch
        {
            var brokenPath = Path.Combine(DataDirectory, $"momo-memo.invalid-{DateTime.Now:yyyyMMdd-HHmmss}.json");
            File.Copy(DataPath, brokenPath, true);
            return CreateDefault();
        }
    }

    public void Save(AppData data)
    {
        Directory.CreateDirectory(DataDirectory);
        var temporaryPath = DataPath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(data, _jsonOptions));
        File.Move(temporaryPath, DataPath, true);
        Backup();
    }

    private AppData CreateDefault() => new();

    private static void Normalize(AppData data)
    {
        data.Projects ??= [];
        data.Tasks ??= [];
        data.Settings ??= new AppSettings();
        data.Projects.RemoveAll(x => x.Id == "inbox");

        var validProjects = data.Projects.Select(x => x.Id).ToHashSet();
        foreach (var task in data.Tasks)
        {
            if (task.Status == MemoTaskStatus.NotStarted) task.Status = MemoTaskStatus.InProgress;
            if (task.ProjectId == "inbox" || !validProjects.Contains(task.ProjectId)) task.ProjectId = "";
            if (task.ReminderRule == "BeforeDue")
            {
                task.ReminderRule = "None";
                task.BeforeDueReminderEnabled = true;
            }
            task.MustToday = false;
            task.IsLongTerm = false;
            if (task.Status == MemoTaskStatus.Completed && task.CompletedAt is null) task.CompletedAt = task.ModifiedAt;
            if (task.Status == MemoTaskStatus.Completed) task.EverCompleted = true;
            if (task.IsArchived) task.EverArchived = true;
        }
    }

    private void Backup()
    {
        var directory = Path.Combine(DataDirectory, "Backups");
        Directory.CreateDirectory(directory);
        File.Copy(DataPath, Path.Combine(directory, $"momo-memo-{DateTime.Now:yyyyMMdd-HHmmss-fff}.json"), true);
        foreach (var oldFile in Directory.GetFiles(directory, "momo-memo-*.json").OrderByDescending(File.GetCreationTimeUtc).Skip(7))
            File.Delete(oldFile);
    }
}
