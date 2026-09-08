using System.Text.Json;
using System.Text.Json.Serialization;
using System.IO;

namespace MomoMemo;

public sealed class StorageService
{
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string DataDirectory { get; } = Path.Combine(AppContext.BaseDirectory, "Data");
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

    private AppData CreateDefault() => new()
    {
        Projects =
        [
            new ProjectItem { Id = "inbox", Name = "Inbox", Color = "#6C63FF" }
        ]
    };

    private static void Normalize(AppData data)
    {
        data.Projects ??= [];
        data.Tasks ??= [];
        data.Settings ??= new AppSettings();
        if (data.Projects.All(x => x.Id != "inbox"))
            data.Projects.Insert(0, new ProjectItem { Id = "inbox", Name = "Inbox" });

        var validProjects = data.Projects.Select(x => x.Id).ToHashSet();
        foreach (var task in data.Tasks)
        {
            if (!validProjects.Contains(task.ProjectId)) task.ProjectId = "inbox";
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
