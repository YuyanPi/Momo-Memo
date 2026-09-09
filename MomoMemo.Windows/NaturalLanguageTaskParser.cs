using System.Globalization;
using System.Text.RegularExpressions;

namespace MomoMemo;

public sealed record NaturalLanguageTaskParseResult(
    string OriginalText,
    string Title,
    string ProjectId,
    string? MentionedProject,
    DateTime? StartAt,
    DateTime? DueAt,
    string Priority,
    bool ReminderEnabled,
    IReadOnlyList<string> Warnings);

/// <summary>
/// Parses deliberately small, predictable Chinese task expressions locally.  It never guesses a
/// project: ambiguous or unknown references are returned as an unclassified task for review.
/// </summary>
public sealed class NaturalLanguageTaskParser
{
    private static readonly Regex ExplicitDate = new(@"(?<year>20\d{2})[年/-](?<month>\d{1,2})[月/-](?<day>\d{1,2})日?", RegexOptions.Compiled);
    private static readonly Regex MonthDay = new(@"(?<month>\d{1,2})月(?<day>\d{1,2})日?", RegexOptions.Compiled);
    private static readonly Regex Weekday = new(@"(?:下周|下星期)(?<day>[一二三四五六日天])", RegexOptions.Compiled);
    private static readonly Regex TimeRange = new(@"(?<start>(?:上午|早上|中午|下午|晚上)?\s*\d{1,2}(?::\d{2}|点(?:\d{1,2}分?)?)?)\s*(?:到|至|—|－|-)\s*(?<end>(?:上午|早上|中午|下午|晚上)?\s*\d{1,2}(?::\d{2}|点(?:\d{1,2}分?)?)?)", RegexOptions.Compiled);
    private static readonly Regex Time = new(@"(?<period>上午|早上|中午|下午|晚上)?\s*(?<hour>\d{1,2})(?::(?<colonMinute>\d{2})|点(?<pointMinute>\d{1,2})?分?)", RegexOptions.Compiled);
    private static readonly Regex Code = new(@"^[A-Za-z]+\d+[A-Za-z\d-]*$", RegexOptions.Compiled);

    public NaturalLanguageTaskParseResult Parse(string text, IReadOnlyList<ProjectItem> projects, string currentProjectId, DateTime now)
    {
        var original = text.Trim();
        var warnings = new List<string>();
        var project = MatchProject(original, projects, out var mentionedProject, out var projectWarning);
        if (projectWarning is not null) warnings.Add(projectWarning);

        var (date, datePattern) = ParseDate(original, now);
        var timeRange = TimeRange.Match(original);
        DateTime? start = null;
        DateTime? due = null;
        var timePatterns = new List<string>();
        if (timeRange.Success)
        {
            var rangeDate = date ?? now.Date;
            start = WithTime(rangeDate, ParseTime(timeRange.Groups["start"].Value));
            due = WithTime(rangeDate, ParseTime(timeRange.Groups["end"].Value));
            timePatterns.Add(timeRange.Value);
        }
        else
        {
            var singleTime = Time.Match(original);
            if (singleTime.Success)
            {
                var time = ParseTime(singleTime.Value);
                var value = WithTime(date ?? now.Date, time);
                if (Regex.IsMatch(original, @"(?:开始|从)\s*" + Regex.Escape(singleTime.Value))) start = value;
                else due = value;
                timePatterns.Add(singleTime.Value);
            }
            else if (date is not null)
            {
                due = date.Value.Date.AddHours(18);
            }
        }

        if (start is not null && due is not null && due < start)
        {
            warnings.Add("截止时间早于开始时间，请在确认时修正。");
        }
        if (date is null && timePatterns.Count == 0)
        {
            warnings.Add("未识别到日期或时间，截止时间留空。");
        }

        var priority = ParsePriority(original);
        var reminderEnabled = !Regex.IsMatch(original, @"(?:不要提醒|无需提醒)");
        var projectId = project?.Id ?? (mentionedProject is null ? currentProjectId : "");
        var title = CleanupTitle(original, project, mentionedProject, datePattern, timePatterns);
        if (title.Length == 0) warnings.Add("未识别到任务内容，请补充任务名称。");

        return new NaturalLanguageTaskParseResult(original, title, projectId, mentionedProject, start, due, priority, reminderEnabled, warnings);
    }

    private static ProjectItem? MatchProject(string text, IReadOnlyList<ProjectItem> projects, out string? mentioned, out string? warning)
    {
        mentioned = null;
        warning = null;
        var active = projects.Where(x => x.IsActive).ToList();
        var exact = active.Where(x => text.Contains(x.Name, StringComparison.OrdinalIgnoreCase)).OrderByDescending(x => x.Name.Length).ToList();
        if (exact.Count == 1)
        {
            mentioned = exact[0].Name;
            return exact[0];
        }
        if (exact.Count > 1)
        {
            mentioned = exact[0].Name;
            warning = "识别到多个项目名称，任务将保存至未分类。";
            return null;
        }

        var codeMatches = active.Select(project => new { Project = project, Token = project.Name.Split([' ', '　', '-', '_'], StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "" })
            .Where(x => Code.IsMatch(x.Token) && text.Contains(x.Token, StringComparison.OrdinalIgnoreCase)).ToList();
        if (codeMatches.Count == 1)
        {
            mentioned = codeMatches[0].Token;
            return codeMatches[0].Project;
        }
        var explicitProject = Regex.Match(text, @"(?<project>[A-Za-z][A-Za-z0-9-]*)项目");
        if (explicitProject.Success)
        {
            mentioned = explicitProject.Groups["project"].Value;
            warning = codeMatches.Count > 1 ? "项目编号匹配到多个项目，任务将保存至未分类。" : $"未识别到项目 {mentioned}，任务将保存至未分类。";
        }
        return null;
    }

    private static (DateTime? Date, string? Pattern) ParseDate(string text, DateTime now)
    {
        var explicitDate = ExplicitDate.Match(text);
        if (explicitDate.Success && DateTime.TryParseExact(explicitDate.Value.Replace('年', '-').Replace('月', '-').Replace("日", ""), "yyyy-M-d", CultureInfo.InvariantCulture, DateTimeStyles.None, out var fullDate)) return (fullDate.Date, explicitDate.Value);
        var monthDay = MonthDay.Match(text);
        if (monthDay.Success && int.TryParse(monthDay.Groups["month"].Value, out var month) && int.TryParse(monthDay.Groups["day"].Value, out var day))
        {
            try { return (new DateTime(now.Year, month, day), monthDay.Value); } catch (ArgumentOutOfRangeException) { }
        }
        if (text.Contains("后天")) return (now.Date.AddDays(2), "后天");
        if (text.Contains("明天")) return (now.Date.AddDays(1), "明天");
        if (text.Contains("今天") || text.Contains("今晚")) return (now.Date, text.Contains("今晚") ? "今晚" : "今天");
        var weekday = Weekday.Match(text);
        if (weekday.Success)
        {
            var desired = "一二三四五六日天".IndexOf(weekday.Groups["day"].Value[0]);
            if (desired == 7) desired = 6;
            var nextMonday = now.Date.AddDays(7 + ((int)DayOfWeek.Monday - (int)now.DayOfWeek + 7) % 7);
            return (nextMonday.AddDays(desired), weekday.Value);
        }
        return (null, null);
    }

    private static TimeSpan ParseTime(string value)
    {
        var match = Time.Match(value);
        var hour = int.Parse(match.Groups["hour"].Value);
        var minuteText = match.Groups["colonMinute"].Success ? match.Groups["colonMinute"].Value : match.Groups["pointMinute"].Value;
        var minute = minuteText.Length == 0 ? 0 : int.Parse(minuteText);
        var period = match.Groups["period"].Value;
        if ((period is "下午" or "晚上") && hour < 12) hour += 12;
        if (period == "中午" && hour < 11) hour += 12;
        return new TimeSpan(Math.Min(hour, 23), Math.Min(minute, 59), 0);
    }

    private static DateTime WithTime(DateTime date, TimeSpan time) => date.Date.Add(time);

    private static string ParsePriority(string text) => Regex.Match(text, @"\bP(?<level>[0-3])\b", RegexOptions.IgnoreCase) is { Success: true } match
        ? $"P{match.Groups["level"].Value}"
        : text.Contains("紧急") ? "P0" : text.Contains("重要") ? "P1" : "P2";

    private static string CleanupTitle(string text, ProjectItem? project, string? mentionedProject, string? datePattern, IEnumerable<string> timePatterns)
    {
        var title = text;
        if (mentionedProject is not null) title = title.Replace(mentionedProject + "项目", "", StringComparison.OrdinalIgnoreCase).Replace(mentionedProject, "", StringComparison.OrdinalIgnoreCase);
        if (project is not null) title = title.Replace(project.Name, "", StringComparison.OrdinalIgnoreCase);
        if (datePattern is not null) title = title.Replace(datePattern, "");
        foreach (var pattern in timePatterns) title = title.Replace(pattern, "");
        title = Regex.Replace(title, @"(?:今天|明天|后天|下周|下星期)[一二三四五六日天]?|(?:要|需|请)?完成|(?:开始|从)|(?:不要提醒|无需提醒)|\bP[0-3]\b|紧急|重要", "", RegexOptions.IgnoreCase);
        return title.Trim(' ', '，', '。', '：', ':', '的');
    }
}
