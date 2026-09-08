#import <Cocoa/Cocoa.h>

static NSString *MMDateString(NSDate *date) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [formatter stringFromDate:date ?: NSDate.date];
}

static NSString *MMDateTimeString(NSDate *date) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    return [formatter stringFromDate:date ?: NSDate.date];
}

static NSDate *MMDateFromString(NSString *value) {
    if (!value.length) return nil;
    for (NSString *format in @[@"yyyy-MM-dd HH:mm", @"yyyy-MM-dd"]) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.lenient = NO;
        formatter.dateFormat = format;
        NSDate *date = [formatter dateFromString:value];
        if (date) return date;
    }
    return nil;
}

static NSString *MMUUID(void) {
    return NSUUID.UUID.UUIDString;
}

static NSColor *MMColor(NSString *hex) {
    NSString *source = hex.length ? hex : @"#6B7280";
    NSString *clean = [source stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned value = 0x6B7280;
    [[NSScanner scannerWithString:clean] scanHexInt:&value];
    return [NSColor colorWithRed:((value >> 16) & 255) / 255.0
                           green:((value >> 8) & 255) / 255.0
                            blue:(value & 255) / 255.0 alpha:1];
}

static NSTextField *MMLabel(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = [NSColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static NSButton *MMButton(NSString *title, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:13];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

static NSString *MMDefaultExportDirectory(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [(documents ?: NSHomeDirectory()) stringByAppendingPathComponent:@"Momo Memo"];
}

@interface MMAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSPopUpButton *projectPopup;
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) NSStackView *taskStack;
@property(nonatomic, strong) NSTextField *summaryLabel;
@property(nonatomic, strong) NSButton *hideDoneButton;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTimer *reminderTimer;
@property(nonatomic, strong) NSMutableDictionary *store;
@property(nonatomic, copy) NSString *currentProjectId;
@property(nonatomic, copy) NSString *lastReminderKey;
@property(nonatomic, copy) NSString *lastAutoExportKey;
@property BOOL trayHighlighted;
@end

@implementation MMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self loadStore];
    [self buildWindow];
    [self buildStatusItem];
    [self render];
    self.reminderTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(__unused NSTimer *timer) {
        [self checkReminder];
        [self checkAutoExport];
    }];
    [self checkReminder];
    [self checkAutoExport];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (NSString *)dataDirectory {
    NSURL *url = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *path = [[url path] stringByAppendingPathComponent:@"Momo Memo"];
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

- (NSString *)dataPath {
    return [[self dataDirectory] stringByAppendingPathComponent:@"momo-memo.json"];
}

- (NSMutableDictionary *)defaultStore {
    return [@{
        @"projects": [@[
            [@{@"id": @"inbox", @"name": @"Inbox", @"color": @"#4F8EF7", @"allowRepeat": @YES, @"order": @0} mutableCopy]
        ] mutableCopy],
        @"tags": [NSMutableArray array],
        @"tasks": [NSMutableArray array],
        @"settings": [@{
            @"hideCompleted": @NO,
            @"remindersEnabled": @YES,
            @"reminderStartHour": @10,
            @"reminderEndHour": @18,
            @"reminderIntervalMinutes": @60,
            @"quietRanges": @"12:00-13:30\n18:00-09:00",
            @"workWeekMode": @"double",
            @"autoAlternateWeek": @YES,
            @"workWeekAnchor": MMDateString(NSDate.date),
            @"reminderMode": @"icon",
            @"exportDirectory": MMDefaultExportDirectory(),
            @"autoExport": @NO,
            @"autoExportFrequency": @"weekly",
            @"autoExportTime": @"18:30",
            @"autoExportFormat": @"both",
            @"exportOverwrite": @YES,
            @"lastAutoExportKey": @"",
            @"autoBackup": @YES
        } mutableCopy]
    } mutableCopy];
}

- (void)loadStore {
    NSData *data = [NSData dataWithContentsOfFile:[self dataPath]];
    if (data) {
        id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        if ([object isKindOfClass:NSDictionary.class]) self.store = object;
    }
    if (!self.store) self.store = [self defaultStore];
    if (![self.store[@"projects"] count]) self.store[@"projects"] = [self defaultStore][@"projects"];
    for (NSMutableDictionary *project in self.store[@"projects"]) {
        if ([project[@"id"] isEqualToString:@"inbox"] && [project[@"name"] isEqualToString:@"默认项目"]) project[@"name"] = @"Inbox";
    }
    if (!self.store[@"tags"]) self.store[@"tags"] = [NSMutableArray array];
    if (!self.store[@"tasks"]) self.store[@"tasks"] = [NSMutableArray array];
    if (!self.store[@"settings"]) self.store[@"settings"] = [self defaultStore][@"settings"];
    NSMutableDictionary *defaults = [self defaultStore][@"settings"];
    for (NSString *key in defaults) if (!self.store[@"settings"][key]) self.store[@"settings"][key] = defaults[key];
    for (NSMutableDictionary *task in self.store[@"tasks"]) [self migrateTask:task];
    self.currentProjectId = @"today";
}

- (void)migrateTask:(NSMutableDictionary *)task {
    BOOL completed = [task[@"completed"] boolValue];
    if (!task[@"status"]) task[@"status"] = completed ? @"completed" : @"notStarted";
    if (!task[@"priority"] || [task[@"priority"] isEqualToString:@"中"]) task[@"priority"] = @"P2";
    else if ([task[@"priority"] isEqualToString:@"高"]) task[@"priority"] = @"P1";
    else if ([task[@"priority"] isEqualToString:@"低"]) task[@"priority"] = @"P3";
    if (!task[@"createdAt"]) task[@"createdAt"] = MMDateTimeString(NSDate.date);
    if (!task[@"modifiedAt"]) task[@"modifiedAt"] = task[@"createdAt"];
    if (!task[@"completedAt"]) task[@"completedAt"] = completed ? (task[@"finishDate"] ?: @"") : @"";
    if (!task[@"archived"]) task[@"archived"] = @NO;
    if (!task[@"everArchived"]) task[@"everArchived"] = task[@"archived"];
    if (!task[@"archivedAt"]) task[@"archivedAt"] = @"";
    if (!task[@"mustToday"]) task[@"mustToday"] = @NO;
    if (!task[@"isLongTerm"]) task[@"isLongTerm"] = @NO;
    if (!task[@"reminderEnabled"]) task[@"reminderEnabled"] = @YES;
    if (!task[@"reminderRule"]) task[@"reminderRule"] = @"workHours";
    if (!task[@"snoozedUntil"]) task[@"snoozedUntil"] = @"";
}

- (void)saveStore {
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.store options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[self dataPath] atomically:YES];
    if ([self.store[@"settings"][@"autoBackup"] boolValue]) [self backupStore];
}

- (void)backupStore {
    NSString *backupDir = [[self dataDirectory] stringByAppendingPathComponent:@"Backups"];
    [NSFileManager.defaultManager createDirectoryAtPath:backupDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *target = [backupDir stringByAppendingPathComponent:[NSString stringWithFormat:@"momo-memo-%@.json", [formatter stringFromDate:NSDate.date]]];
    [NSFileManager.defaultManager copyItemAtPath:[self dataPath] toPath:target error:nil];
    NSArray *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:backupDir error:nil] sortedArrayUsingSelector:@selector(compare:)];
    if (files.count <= 7) return;
    for (NSUInteger i = 0; i < files.count - 7; i++) {
        [NSFileManager.defaultManager removeItemAtPath:[backupDir stringByAppendingPathComponent:files[i]] error:nil];
    }
}

- (NSDictionary *)projectById:(NSString *)projectId {
    for (NSDictionary *project in self.store[@"projects"]) {
        if ([project[@"id"] isEqualToString:projectId]) return project;
    }
    return [self.store[@"projects"] firstObject];
}

- (NSDictionary *)tagByName:(NSString *)name {
    for (NSDictionary *tag in self.store[@"tags"]) {
        if ([tag[@"name"] caseInsensitiveCompare:name] == NSOrderedSame) return tag;
    }
    return nil;
}

- (NSMutableDictionary *)taskById:(NSString *)taskId {
    for (NSMutableDictionary *task in self.store[@"tasks"]) {
        if ([task[@"id"] isEqualToString:taskId]) return task;
    }
    return nil;
}

- (BOOL)isTaskCompleted:(NSDictionary *)task {
    return [task[@"completed"] boolValue] || [task[@"status"] isEqualToString:@"completed"];
}

- (BOOL)isTaskOverdue:(NSDictionary *)task {
    if ([self isTaskCompleted:task] || [task[@"archived"] boolValue]) return NO;
    NSString *dueValue = task[@"dueDate"];
    NSDate *due = MMDateFromString(dueValue);
    if (!due) return NO;
    if (dueValue.length == 10) due = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:due options:0];
    return [NSDate.date compare:due] != NSOrderedAscending;
}

- (BOOL)isTaskDueToday:(NSDictionary *)task {
    NSString *today = MMDateString(NSDate.date);
    return [task[@"taskDate"] isEqualToString:today] || [task[@"dueDate"] hasPrefix:today] || [task[@"mustToday"] boolValue];
}

- (BOOL)isTaskWithinNextThreeDays:(NSDictionary *)task {
    NSString *value = [task[@"taskDate"] length] ? task[@"taskDate"] : ([task[@"startDate"] length] ? task[@"startDate"] : task[@"dueDate"]);
    NSDate *date = MMDateFromString(value);
    if (!date) return NO;
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *today = [calendar startOfDayForDate:NSDate.date];
    NSDate *end = [calendar dateByAddingUnit:NSCalendarUnitDay value:3 toDate:today options:0];
    return [date compare:today] != NSOrderedAscending && [date compare:end] == NSOrderedAscending;
}

- (NSString *)displayStatusForTask:(NSDictionary *)task {
    if ([self isTaskOverdue:task]) return @"已逾期";
    NSDictionary *names = @{@"notStarted": @"未开始", @"inProgress": @"进行中", @"paused": @"暂停", @"completed": @"已完成"};
    return names[task[@"status"]] ?: ([self isTaskCompleted:task] ? @"已完成" : @"未开始");
}

- (BOOL)taskVisible:(NSDictionary *)task {
    NSString *filter = self.currentProjectId ?: @"today";
    BOOL archived = [task[@"archived"] boolValue];
    BOOL completed = [self isTaskCompleted:task];
    if ([filter isEqualToString:@"archived"]) return archived;
    if (archived) return NO;
    if ([filter isEqualToString:@"today"] && (completed || (![self isTaskDueToday:task] && ![self isTaskOverdue:task]))) return NO;
    if ([filter isEqualToString:@"upcoming"] && (completed || ![self isTaskWithinNextThreeDays:task])) return NO;
    if ([filter isEqualToString:@"longterm"] && (completed || ![task[@"isLongTerm"] boolValue])) return NO;
    if ([filter isEqualToString:@"inbox"] && ![task[@"projectId"] isEqualToString:@"inbox"]) return NO;
    if ([filter isEqualToString:@"incomplete"] && completed) return NO;
    if ([filter isEqualToString:@"completed"] && !completed) return NO;
    if ([filter hasPrefix:@"project:"] && ![task[@"projectId"] isEqualToString:[filter substringFromIndex:8]]) return NO;
    if ([self.store[@"settings"][@"hideCompleted"] boolValue] && completed && ![filter isEqualToString:@"completed"]) return NO;
    return YES;
}

- (void)buildWindow {
    NSSize size = NSMakeSize(430, 620);
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Momo Memo";
    self.window.level = NSFloatingWindowLevel;
    self.window.opaque = NO;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.hasShadow = YES;
    self.window.movableByWindowBackground = YES;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSVisualEffectView *panel = [NSVisualEffectView new];
    panel.material = NSVisualEffectMaterialSidebar;
    panel.state = NSVisualEffectStateActive;
    panel.wantsLayer = YES;
    panel.layer.cornerRadius = 12;
    panel.layer.masksToBounds = YES;
    panel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = MMLabel(@"Momo Memo", 18, NSFontWeightSemibold);
    self.projectPopup = [NSPopUpButton new];
    self.projectPopup.target = self;
    self.projectPopup.action = @selector(projectChanged:);
    self.projectPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self reloadProjectPopup];

    NSButton *pin = MMButton(@"置顶", self, @selector(togglePin:));
    NSButton *hide = MMButton(@"隐藏", self, @selector(hideWindow));
    NSStackView *topButtons = [NSStackView stackViewWithViews:@[pin, hide]];
    topButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    topButtons.spacing = 6;
    topButtons.translatesAutoresizingMaskIntoConstraints = NO;

    self.summaryLabel = MMLabel(@"", 12, NSFontWeightRegular);
    self.summaryLabel.textColor = [NSColor secondaryLabelColor];

    self.hideDoneButton = [NSButton checkboxWithTitle:@"隐藏已完成" target:self action:@selector(toggleHideDone:)];
    self.hideDoneButton.state = [self.store[@"settings"][@"hideCompleted"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.hideDoneButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.taskStack = [NSStackView new];
    self.taskStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.taskStack.alignment = NSLayoutAttributeWidth;
    self.taskStack.spacing = 10;
    self.taskStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView = [NSScrollView new];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.documentView = self.taskStack;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *add = MMButton(@"+", self, @selector(addTask));
    add.font = [NSFont systemFontOfSize:20 weight:NSFontWeightMedium];
    NSButton *export = MMButton(@"导出", self, @selector(exportWeek));
    NSButton *stats = MMButton(@"统计", self, @selector(showStats));
    NSButton *settings = MMButton(@"设置", self, @selector(showSettings));
    NSStackView *bottom = [NSStackView stackViewWithViews:@[add, export, stats, settings]];
    bottom.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottom.distribution = NSStackViewDistributionFillEqually;
    bottom.spacing = 8;
    bottom.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    [content addSubview:panel];
    for (NSView *view in @[title, self.projectPopup, topButtons, self.summaryLabel, self.hideDoneButton, self.scrollView, bottom]) {
        [panel addSubview:view];
    }
    self.window.contentView = content;
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [panel.topAnchor constraintEqualToAnchor:content.topAnchor],
        [panel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [title.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:18],
        [title.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16],
        [topButtons.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-14],
        [topButtons.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [self.projectPopup.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [self.projectPopup.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [self.projectPopup.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [self.summaryLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:18],
        [self.summaryLabel.topAnchor constraintEqualToAnchor:self.projectPopup.bottomAnchor constant:12],
        [self.hideDoneButton.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-18],
        [self.hideDoneButton.centerYAnchor constraintEqualToAnchor:self.summaryLabel.centerYAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:14],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-14],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.summaryLabel.bottomAnchor constant:10],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:bottom.topAnchor constant:-12],
        [self.taskStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-18],
        [bottom.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:14],
        [bottom.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-14],
        [bottom.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-14],
        [bottom.heightAnchor constraintEqualToConstant:34]
    ]];
    NSRect visible = NSScreen.mainScreen.visibleFrame;
    [self.window setFrameOrigin:NSMakePoint(NSMaxX(visible) - size.width - 24, NSMaxY(visible) - size.height - 40)];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)buildStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"Momo";
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:@"显示 Momo Memo" action:@selector(showWindow) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"快速添加任务" action:@selector(quickAddFromTray) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出" action:@selector(terminate:) keyEquivalent:@""];
    self.statusItem.menu = menu;
}

- (void)reloadProjectPopup {
    [self.projectPopup removeAllItems];
    NSArray *views = @[
        @[@"今日", @"today"], @[@"未来三天", @"upcoming"], @[@"长期任务", @"longterm"],
        @[@"Inbox", @"inbox"], @[@"未完成", @"incomplete"], @[@"全部任务", @"all"], @[@"已完成", @"completed"], @[@"归档", @"archived"]
    ];
    for (NSArray *view in views) {
        [self.projectPopup addItemWithTitle:view[0]];
        self.projectPopup.lastItem.representedObject = view[1];
    }
    [[self.projectPopup menu] addItem:[NSMenuItem separatorItem]];
    for (NSDictionary *project in self.store[@"projects"]) {
        [self.projectPopup addItemWithTitle:[NSString stringWithFormat:@"项目 · %@", project[@"name"]]];
        self.projectPopup.lastItem.representedObject = [@"project:" stringByAppendingString:project[@"id"]];
    }
    for (NSMenuItem *item in self.projectPopup.itemArray) {
        if ([item.representedObject isEqual:self.currentProjectId]) {
            [self.projectPopup selectItem:item];
            break;
        }
    }
}

- (NSArray *)sortedTasks {
    NSArray *tasks = [self.store[@"tasks"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) {
        return [self taskVisible:task];
    }]];
    return [tasks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([self.currentProjectId isEqualToString:@"today"]) {
            BOOL oa = [self isTaskOverdue:a], ob = [self isTaskOverdue:b];
            if (oa != ob) return oa ? NSOrderedAscending : NSOrderedDescending;
            NSInteger ba = [a[@"priority"] isEqualToString:@"P0"] ? 1 : ([a[@"mustToday"] boolValue] ? 2 : 3);
            NSInteger bb = [b[@"priority"] isEqualToString:@"P0"] ? 1 : ([b[@"mustToday"] boolValue] ? 2 : 3);
            if (ba != bb) return ba < bb ? NSOrderedAscending : NSOrderedDescending;
            BOOL ma = [a[@"mustToday"] boolValue], mb = [b[@"mustToday"] boolValue];
            if (ma != mb) return ma ? NSOrderedAscending : NSOrderedDescending;
            NSInteger pa = [[a[@"priority"] substringFromIndex:1] integerValue];
            NSInteger pb = [[b[@"priority"] substringFromIndex:1] integerValue];
            if (pa != pb) return pa < pb ? NSOrderedAscending : NSOrderedDescending;
        }
        BOOL pa = [a[@"pinned"] boolValue], pb = [b[@"pinned"] boolValue];
        if (pa != pb) return pa ? NSOrderedAscending : NSOrderedDescending;
        if ([self.currentProjectId isEqualToString:@"all"] || [self.currentProjectId isEqualToString:@"completed"] || [self.currentProjectId isEqualToString:@"archived"]) {
            NSComparisonResult project = [(a[@"projectId"] ?: @"") compare:(b[@"projectId"] ?: @"")];
            if (project != NSOrderedSame) return project;
        }
        NSString *da = a[@"taskDate"] ?: @"";
        NSString *db = b[@"taskDate"] ?: @"";
        NSComparisonResult date = [da compare:db];
        if (date != NSOrderedSame) return date;
        return [a[@"title"] compare:b[@"title"]];
    }];
}

- (void)render {
    for (NSView *view in self.taskStack.arrangedSubviews.copy) {
        [self.taskStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray *tasks = [self sortedTasks];
    NSInteger done = 0, overdue = 0;
    for (NSDictionary *task in tasks) {
        if ([self isTaskCompleted:task]) done++;
        if ([self isTaskOverdue:task]) overdue++;
    }
    self.summaryLabel.stringValue = [NSString stringWithFormat:@"共 %ld · 完成 %ld · 未完成 %ld · 逾期 %ld", (long)tasks.count, (long)done, (long)(tasks.count - done), (long)overdue];
    if (!tasks.count) {
        NSTextField *empty = MMLabel(@"今天先写下一件小事。", 15, NSFontWeightRegular);
        empty.alignment = NSTextAlignmentCenter;
        empty.textColor = [NSColor secondaryLabelColor];
        [self.taskStack addArrangedSubview:empty];
        return;
    }
    NSString *lastProject = nil;
    for (NSDictionary *task in tasks) {
        if (([self.currentProjectId isEqualToString:@"all"] || [self.currentProjectId isEqualToString:@"completed"] || [self.currentProjectId isEqualToString:@"archived"]) && ![lastProject isEqualToString:task[@"projectId"]]) {
            NSDictionary *project = [self projectById:task[@"projectId"]];
            NSTextField *header = MMLabel(project[@"name"] ?: @"未分组", 13, NSFontWeightSemibold);
            header.textColor = MMColor(project[@"color"]);
            [self.taskStack addArrangedSubview:header];
            lastProject = task[@"projectId"];
        }
        [self.taskStack addArrangedSubview:[self taskCard:task]];
    }
}

- (NSView *)taskCard:(NSDictionary *)task {
    NSBox *box = [NSBox new];
    box.boxType = NSBoxCustom;
    box.cornerRadius = 8;
    box.borderWidth = 0;
    box.fillColor = [NSColor colorWithWhite:1 alpha:.60];
    box.translatesAutoresizingMaskIntoConstraints = NO;

    NSDictionary *project = [self projectById:task[@"projectId"]];
    NSView *bar = [NSView new];
    bar.wantsLayer = YES;
    bar.layer.backgroundColor = MMColor(task[@"color"] ?: project[@"color"]).CGColor;
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *check = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleTaskDone:)];
    check.identifier = task[@"id"];
    check.state = [task[@"completed"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    check.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = MMLabel(task[@"title"], 14, [task[@"pinned"] boolValue] ? NSFontWeightSemibold : NSFontWeightRegular);
    if ([task[@"completed"] boolValue]) title.textColor = [NSColor tertiaryLabelColor];
    NSString *date = [task[@"startDate"] length] ? task[@"startDate"] : ([task[@"taskDate"] length] ? task[@"taskDate"] : @"未安排");
    NSString *end = task[@"finishDate"];
    NSString *dateText = end.length && ![end isEqualToString:date] ? [NSString stringWithFormat:@"%@ 至 %@", date, end] : date;
    NSMutableArray *meta = [NSMutableArray arrayWithObjects:[self displayStatusForTask:task], dateText, task[@"priority"] ?: @"P2", nil];
    if ([task[@"dueDate"] length]) [meta addObject:[NSString stringWithFormat:@"截止 %@", task[@"dueDate"]]];
    if ([task[@"mustToday"] boolValue]) [meta addObject:@"今天必须完成"];
    if ([task[@"isLongTerm"] boolValue]) [meta addObject:@"长期"];
    if ([task[@"snoozedUntil"] length]) [meta addObject:[NSString stringWithFormat:@"延后至 %@", task[@"snoozedUntil"]]];
    if ([task[@"repeat"] length] && ![task[@"repeat"] isEqualToString:@"无"]) [meta addObject:[NSString stringWithFormat:@"重复 %@", task[@"repeat"]]];
    NSTextField *detail = MMLabel([meta componentsJoinedByString:@"  ·  "], 11, NSFontWeightRegular);
    detail.textColor = [NSColor secondaryLabelColor];

    NSString *tagsText = [task[@"tags"] count] ? [NSString stringWithFormat:@"#%@", [task[@"tags"] componentsJoinedByString:@"  #"]] : @"";
    NSTextField *tags = MMLabel(tagsText, 11, NSFontWeightRegular);
    tags.textColor = [NSColor secondaryLabelColor];

    NSMutableArray *subLines = [NSMutableArray array];
    for (NSDictionary *sub in task[@"subtasks"] ?: @[]) {
        [subLines addObject:[NSString stringWithFormat:@"%@ %@", [sub[@"done"] boolValue] ? @"[x]" : @"[ ]", sub[@"title"] ?: @""]];
    }
    NSTextField *subs = MMLabel([subLines componentsJoinedByString:@"\n"], 11, NSFontWeightRegular);
    subs.textColor = [NSColor secondaryLabelColor];
    subs.hidden = !subLines.count;

    NSButton *pin = MMButton([task[@"pinned"] boolValue] ? @"取消置顶" : @"置顶", self, @selector(toggleTaskPinned:));
    pin.identifier = task[@"id"];
    NSButton *edit = MMButton(@"编辑", self, @selector(editTask:));
    edit.identifier = task[@"id"];
    NSButton *snooze = MMButton(@"稍后", self, @selector(snoozeTask:));
    snooze.identifier = task[@"id"];
    snooze.hidden = [self isTaskCompleted:task] || [task[@"archived"] boolValue];
    NSButton *archive = MMButton([task[@"archived"] boolValue] ? @"恢复" : @"归档", self, @selector(toggleTaskArchived:));
    archive.identifier = task[@"id"];
    NSButton *del = MMButton(@"删除", self, @selector(deleteTask:));
    del.identifier = task[@"id"];
    del.hidden = [self isTaskCompleted:task] || [task[@"everArchived"] boolValue];
    NSStackView *actions = [NSStackView stackViewWithViews:@[pin, edit, snooze, archive, del]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 6;
    actions.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *texts = [NSStackView stackViewWithViews:@[title, detail, tags, subs, actions]];
    texts.orientation = NSUserInterfaceLayoutOrientationVertical;
    texts.alignment = NSLayoutAttributeLeading;
    texts.spacing = 5;
    texts.translatesAutoresizingMaskIntoConstraints = NO;

    [box addSubview:bar];
    [box addSubview:check];
    [box addSubview:texts];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [bar.topAnchor constraintEqualToAnchor:box.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
        [bar.widthAnchor constraintEqualToConstant:5],
        [check.leadingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:10],
        [check.topAnchor constraintEqualToAnchor:box.topAnchor constant:12],
        [texts.leadingAnchor constraintEqualToAnchor:check.trailingAnchor constant:4],
        [texts.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],
        [texts.topAnchor constraintEqualToAnchor:box.topAnchor constant:12],
        [texts.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-12]
    ]];
    return box;
}

- (NSStackView *)formWithViews:(NSArray<NSView *> *)views {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    stack.alignment = NSLayoutAttributeWidth;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack.widthAnchor constraintEqualToConstant:360].active = YES;
    return stack;
}

- (NSView *)scrollableFormWithViews:(NSArray<NSView *> *)views height:(CGFloat)height {
    NSStackView *stack = [self formWithViews:views];
    [stack layoutSubtreeIfNeeded];
    CGFloat contentHeight = MAX(height, stack.fittingSize.height);
    stack.translatesAutoresizingMaskIntoConstraints = YES;
    stack.frame = NSMakeRect(0, 0, 360, contentHeight);
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 380, height)];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = stack;
    return scroll;
}

- (NSTextField *)field:(NSString *)value placeholder:(NSString *)placeholder {
    NSTextField *field = [NSTextField textFieldWithString:value ?: @""];
    field.placeholderString = placeholder;
    return field;
}

- (NSTextField *)labelForField:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    return label;
}

- (BOOL)validateDateValue:(NSString *)value fieldName:(NSString *)fieldName {
    if (!value.length || MMDateFromString(value)) return YES;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"%@格式不正确", fieldName];
    alert.informativeText = @"请使用 yyyy-MM-dd 或 yyyy-MM-dd HH:mm。";
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
    return NO;
}

- (void)addTask {
    [self editTaskObject:nil quick:NO];
}

- (NSString *)projectIdForNewTask {
    return [self.currentProjectId hasPrefix:@"project:"] ? [self.currentProjectId substringFromIndex:8] : @"inbox";
}

- (void)quickAddFromTray {
    [self showWindow];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"快速添加任务";
    NSTextField *title = [self field:@"" placeholder:@"任务标题"];
    alert.accessoryView = title;
    [alert addButtonWithTitle:@"添加"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn || !title.stringValue.length) return;
    NSString *projectId = [self projectIdForNewTask];
    NSMutableDictionary *task = [@{
        @"id": MMUUID(),
        @"title": title.stringValue,
        @"desc": @"",
        @"projectId": projectId,
        @"tags": [NSMutableArray array],
        @"subtasks": [NSMutableArray array],
        @"startDate": @"",
        @"finishDate": @"",
        @"dueDate": @"",
        @"taskDate": @"",
        @"priority": @"P2",
        @"status": @"notStarted",
        @"completed": @NO,
        @"pinned": @NO,
        @"repeat": @"无",
        @"mustToday": @NO,
        @"isLongTerm": @NO,
        @"archived": @NO,
        @"everArchived": @NO,
        @"archivedAt": @"",
        @"createdAt": MMDateTimeString(NSDate.date),
        @"modifiedAt": MMDateTimeString(NSDate.date),
        @"completedAt": @"",
        @"reminderEnabled": @YES,
        @"reminderRule": @"workHours",
        @"snoozedUntil": @""
    } mutableCopy];
    [self.store[@"tasks"] addObject:task];
    [self saveStore];
    [self render];
}

- (void)editTask:(NSButton *)sender {
    [self editTaskObject:[self taskById:sender.identifier] quick:NO];
}

- (void)editTaskObject:(NSMutableDictionary *)task quick:(BOOL)quick {
    BOOL isNew = task == nil;
    NSDictionary *baseProject = [self projectById:[self projectIdForNewTask]];
    NSMutableDictionary *draft = task ? [task mutableCopy] : [@{
        @"id": MMUUID(),
        @"title": @"",
        @"desc": @"",
        @"projectId": baseProject[@"id"] ?: @"inbox",
        @"tags": [NSMutableArray array],
        @"subtasks": [NSMutableArray array],
        @"startDate": MMDateString(NSDate.date),
        @"finishDate": @"",
        @"dueDate": @"",
        @"taskDate": MMDateString(NSDate.date),
        @"priority": @"P2",
        @"status": @"notStarted",
        @"completed": @NO,
        @"pinned": @NO,
        @"repeat": @"无",
        @"color": @"",
        @"mustToday": @NO,
        @"isLongTerm": @NO,
        @"archived": @NO,
        @"everArchived": @NO,
        @"archivedAt": @"",
        @"createdAt": MMDateTimeString(NSDate.date),
        @"modifiedAt": MMDateTimeString(NSDate.date),
        @"completedAt": @"",
        @"reminderEnabled": @YES,
        @"reminderRule": @"workHours",
        @"snoozedUntil": @""
    } mutableCopy];

    NSTextField *title = [self field:draft[@"title"] placeholder:@"标题，必填"];
    NSTextField *desc = [self field:draft[@"desc"] placeholder:@"详细描述，可写简单 Markdown"];
    NSTextField *start = [self field:draft[@"startDate"] placeholder:@"开始时间 yyyy-MM-dd HH:mm"];
    NSTextField *finish = [self field:draft[@"finishDate"] placeholder:@"完成日期，可空"];
    NSTextField *due = [self field:draft[@"dueDate"] placeholder:@"截止时间 yyyy-MM-dd HH:mm，可空"];
    NSTextField *taskDate = [self field:draft[@"taskDate"] placeholder:@"任务日期 yyyy-MM-dd"];
    NSTextField *tags = [self field:[draft[@"tags"] componentsJoinedByString:@","] placeholder:@"标签，逗号分隔"];
    NSMutableArray *subTitles = [NSMutableArray array];
    for (NSDictionary *sub in draft[@"subtasks"] ?: @[]) [subTitles addObject:sub[@"title"] ?: @""];
    NSTextField *subs = [self field:[subTitles componentsJoinedByString:@","] placeholder:@"子任务，逗号分隔"];
    NSTextField *color = [self field:draft[@"color"] placeholder:@"任务颜色，可空，如 #EF4444"];

    NSPopUpButton *project = [NSPopUpButton new];
    for (NSDictionary *p in self.store[@"projects"]) {
        [project addItemWithTitle:p[@"name"]];
        project.lastItem.representedObject = p[@"id"];
        if ([p[@"id"] isEqualToString:draft[@"projectId"]]) [project selectItem:project.lastItem];
    }
    NSPopUpButton *priority = [NSPopUpButton new];
    [priority addItemsWithTitles:@[@"P0", @"P1", @"P2", @"P3"]];
    [priority selectItemWithTitle:draft[@"priority"] ?: @"P2"];
    NSPopUpButton *status = [NSPopUpButton new];
    NSArray *statusValues = @[@[@"未开始", @"notStarted"], @[@"进行中", @"inProgress"], @[@"暂停", @"paused"], @[@"已完成", @"completed"]];
    for (NSArray *item in statusValues) {
        [status addItemWithTitle:item[0]];
        status.lastItem.representedObject = item[1];
        if ([item[1] isEqualToString:draft[@"status"]]) [status selectItem:status.lastItem];
    }
    NSPopUpButton *repeat = [NSPopUpButton new];
    [repeat addItemsWithTitles:@[@"无", @"每日", @"每周", @"每月", @"自定义"]];
    [repeat selectItemWithTitle:draft[@"repeat"] ?: @"无"];
    NSPopUpButton *reminderRule = [NSPopUpButton new];
    NSArray *reminderRules = @[@[@"不提醒", @"none"], @[@"工作时间定时提醒", @"workHours"], @[@"每 30 分钟", @"every30"], @[@"每 1 小时", @"every60"], @[@"截止前 30 分钟", @"beforeDue"]];
    for (NSArray *item in reminderRules) {
        [reminderRule addItemWithTitle:item[0]];
        reminderRule.lastItem.representedObject = item[1];
        if ([item[1] isEqualToString:draft[@"reminderRule"]]) [reminderRule selectItem:reminderRule.lastItem];
    }
    NSButton *mustToday = [NSButton checkboxWithTitle:@"今天必须完成" target:nil action:nil];
    mustToday.state = [draft[@"mustToday"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSButton *longTerm = [NSButton checkboxWithTitle:@"长期任务" target:nil action:nil];
    longTerm.state = [draft[@"isLongTerm"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSButton *reminder = [NSButton checkboxWithTitle:@"参与提醒" target:nil action:nil];
    reminder.state = [draft[@"reminderEnabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    NSView *form = [self scrollableFormWithViews:@[
        [self labelForField:@"标题"], title,
        [self labelForField:@"所属项目"], project,
        [self labelForField:@"描述"], desc,
        [self labelForField:@"日期"], start, finish, due, taskDate,
        [self labelForField:@"状态与优先级"], status, priority, mustToday, longTerm,
        [self labelForField:@"提醒规则"], reminder, reminderRule,
        [self labelForField:@"标签与子任务"], tags, subs,
        [self labelForField:@"重复与颜色"], repeat, color
    ] height:500];
    NSAlert *alert = [NSAlert new];
    alert.messageText = isNew ? @"创建任务" : @"编辑任务";
    alert.informativeText = @"常用字段直接填；不需要的留空即可。";
    alert.accessoryView = form;
    [alert addButtonWithTitle:isNew ? @"创建" : @"保存"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    if (!title.stringValue.length) return;
    if (![self validateDateValue:start.stringValue fieldName:@"开始时间"] ||
        ![self validateDateValue:finish.stringValue fieldName:@"完成日期"] ||
        ![self validateDateValue:due.stringValue fieldName:@"截止时间"] ||
        ![self validateDateValue:taskDate.stringValue fieldName:@"任务日期"]) return;

    NSString *projectId = project.selectedItem.representedObject;
    NSDictionary *selectedProject = [self projectById:projectId];
    NSString *repeatValue = [selectedProject[@"allowRepeat"] boolValue] ? repeat.titleOfSelectedItem : @"无";
    NSMutableArray *tagList = [NSMutableArray array];
    for (NSString *part in [tags.stringValue componentsSeparatedByString:@","]) {
        NSString *name = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length) continue;
        [tagList addObject:name];
        if (![self tagByName:name]) [self.store[@"tags"] addObject:[@{@"id": MMUUID(), @"name": name, @"color": @"#9CA3AF"} mutableCopy]];
    }
    NSMutableArray *subList = [NSMutableArray array];
    for (NSString *part in [subs.stringValue componentsSeparatedByString:@","]) {
        NSString *name = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length) [subList addObject:[@{@"id": MMUUID(), @"title": name, @"done": @NO} mutableCopy]];
    }
    draft[@"title"] = title.stringValue;
    draft[@"desc"] = desc.stringValue;
    draft[@"projectId"] = projectId ?: @"inbox";
    draft[@"startDate"] = start.stringValue.length ? start.stringValue : MMDateString(NSDate.date);
    draft[@"finishDate"] = finish.stringValue ?: @"";
    draft[@"dueDate"] = due.stringValue ?: @"";
    draft[@"taskDate"] = taskDate.stringValue.length ? taskDate.stringValue : MMDateString(NSDate.date);
    draft[@"priority"] = priority.titleOfSelectedItem ?: @"P2";
    draft[@"status"] = status.selectedItem.representedObject ?: @"notStarted";
    draft[@"completed"] = @([draft[@"status"] isEqualToString:@"completed"]);
    if ([draft[@"completed"] boolValue] && ![draft[@"completedAt"] length]) draft[@"completedAt"] = MMDateTimeString(NSDate.date);
    if (![draft[@"completed"] boolValue]) draft[@"completedAt"] = @"";
    draft[@"mustToday"] = @(mustToday.state == NSControlStateValueOn);
    draft[@"isLongTerm"] = @(longTerm.state == NSControlStateValueOn);
    draft[@"reminderEnabled"] = @(reminder.state == NSControlStateValueOn);
    draft[@"reminderRule"] = reminderRule.selectedItem.representedObject ?: @"workHours";
    draft[@"tags"] = tagList;
    draft[@"subtasks"] = subList;
    draft[@"repeat"] = repeatValue ?: @"无";
    draft[@"color"] = color.stringValue ?: @"";
    draft[@"modifiedAt"] = MMDateTimeString(NSDate.date);
    if (isNew) [self.store[@"tasks"] addObject:draft];
    else [task setDictionary:draft];
    [self saveStore];
    [self reloadProjectPopup];
    [self render];
}

- (void)deleteTask:(NSButton *)sender {
    NSMutableDictionary *task = [self taskById:sender.identifier];
    if (!task) return;
    if ([self isTaskCompleted:task] || [task[@"everArchived"] boolValue]) {
        NSAlert *protected = [NSAlert new];
        protected.messageText = @"历史任务不能删除";
        protected.informativeText = @"已完成或曾归档的任务会永久保留，但仍允许编辑与恢复显示。";
        [protected addButtonWithTitle:@"好"];
        [protected runModal];
        return;
    }
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"确认删除任务？";
    alert.informativeText = @"删除后不会进入回收站，但自动备份中仍可能保留旧数据。";
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self.store[@"tasks"] removeObject:task];
    [self saveStore];
    [self render];
}

- (void)toggleTaskDone:(NSButton *)sender {
    NSMutableDictionary *task = [self taskById:sender.identifier];
    if (!task) return;
    BOOL done = sender.state == NSControlStateValueOn;
    task[@"completed"] = @(done);
    task[@"status"] = done ? @"completed" : @"notStarted";
    task[@"completedAt"] = done ? MMDateTimeString(NSDate.date) : @"";
    task[@"modifiedAt"] = MMDateTimeString(NSDate.date);
    if (done && ![task[@"finishDate"] length]) task[@"finishDate"] = MMDateString(NSDate.date);
    [self saveStore];
    [self render];
}

- (void)toggleTaskArchived:(NSButton *)sender {
    NSMutableDictionary *task = [self taskById:sender.identifier];
    if (!task) return;
    BOOL archived = ![task[@"archived"] boolValue];
    task[@"archived"] = @(archived);
    if (archived) task[@"everArchived"] = @YES;
    task[@"archivedAt"] = archived ? MMDateTimeString(NSDate.date) : @"";
    task[@"modifiedAt"] = MMDateTimeString(NSDate.date);
    [self saveStore];
    [self render];
}

- (void)snoozeTask:(NSButton *)sender {
    NSMutableDictionary *task = [self taskById:sender.identifier];
    if (!task || [self isTaskCompleted:task]) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"稍后提醒";
    [alert addButtonWithTitle:@"30 分钟后"];
    [alert addButtonWithTitle:@"1 小时后"];
    [alert addButtonWithTitle:@"明天 10:00"];
    [alert addButtonWithTitle:@"取消"];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn + 3) return;
    NSDate *date = nil;
    if (response == NSAlertFirstButtonReturn) date = [NSDate dateWithTimeIntervalSinceNow:30 * 60];
    else if (response == NSAlertSecondButtonReturn) date = [NSDate dateWithTimeIntervalSinceNow:60 * 60];
    else {
        NSDate *tomorrow = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:NSDate.date options:0];
        NSDateComponents *parts = [NSCalendar.currentCalendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:tomorrow];
        parts.hour = 10;
        date = [NSCalendar.currentCalendar dateFromComponents:parts];
    }
    task[@"snoozedUntil"] = MMDateTimeString(date);
    task[@"modifiedAt"] = MMDateTimeString(NSDate.date);
    [self saveStore];
    [self render];
}

- (void)toggleTaskPinned:(NSButton *)sender {
    NSMutableDictionary *task = [self taskById:sender.identifier];
    task[@"pinned"] = @(![task[@"pinned"] boolValue]);
    [self saveStore];
    [self render];
}

- (void)projectChanged:(NSPopUpButton *)sender {
    self.currentProjectId = sender.selectedItem.representedObject ?: @"all";
    [self render];
}

- (void)toggleHideDone:(NSButton *)sender {
    self.store[@"settings"][@"hideCompleted"] = @(sender.state == NSControlStateValueOn);
    [self saveStore];
    [self render];
}

- (void)togglePin:(NSButton *)sender {
    BOOL floating = self.window.level != NSFloatingWindowLevel;
    self.window.level = floating ? NSFloatingWindowLevel : NSNormalWindowLevel;
    sender.title = floating ? @"置顶" : @"取消置顶";
}

- (void)showWindow {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)hideWindow {
    [self.window orderOut:nil];
}

- (NSArray *)tasksInCurrentWeek {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *now = NSDate.date;
    NSDate *start = nil;
    [calendar rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&start interval:nil forDate:now];
    NSDate *end = [calendar dateByAddingUnit:NSCalendarUnitDay value:7 toDate:start options:0];
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *task in self.store[@"tasks"]) {
        NSDate *date = MMDateFromString(task[@"taskDate"]);
        if (!date) continue;
        if ([date compare:start] != NSOrderedAscending && [date compare:end] == NSOrderedAscending) [result addObject:task];
    }
    return result;
}

- (void)exportWeek {
    NSAlert *rangeChoice = [NSAlert new];
    rangeChoice.messageText = @"选择导出范围";
    [rangeChoice addButtonWithTitle:@"本周"];
    [rangeChoice addButtonWithTitle:@"全部历史"];
    [rangeChoice addButtonWithTitle:@"取消"];
    NSModalResponse rangeResponse = [rangeChoice runModal];
    if (rangeResponse == NSAlertThirdButtonReturn) return;
    BOOL allHistory = rangeResponse == NSAlertSecondButtonReturn;
    NSArray *tasks = allHistory ? [self.store[@"tasks"] copy] : [self tasksInCurrentWeek];

    NSAlert *formatChoice = [NSAlert new];
    formatChoice.messageText = @"选择导出格式";
    [formatChoice addButtonWithTitle:@"Markdown"];
    [formatChoice addButtonWithTitle:@"CSV"];
    [formatChoice addButtonWithTitle:@"取消"];
    NSModalResponse formatResponse = [formatChoice runModal];
    if (formatResponse == NSAlertThirdButtonReturn) return;
    BOOL markdown = formatResponse == NSAlertFirstButtonReturn;
    NSString *ext = markdown ? @"md" : @"csv";
    NSString *baseName = [self exportBaseNameForAllHistory:allHistory];
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@.%@", baseName, ext];
    panel.directoryURL = [NSURL fileURLWithPath:self.store[@"settings"][@"exportDirectory"] ?: NSHomeDirectory()];
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *content = markdown ? [self markdownExportForTasks:tasks allHistory:allHistory] : [self csvExportForTasks:tasks];
    NSError *error = nil;
    if (![content writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error]) [self showError:@"导出失败" error:error];
}

- (NSString *)exportBaseNameForAllHistory:(BOOL)allHistory {
    if (allHistory) return [NSString stringWithFormat:@"momo-memo_all_%@", MMDateString(NSDate.date)];
    NSDate *start = nil;
    [NSCalendar.currentCalendar rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&start interval:nil forDate:NSDate.date];
    NSDate *end = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:6 toDate:start options:0];
    return [NSString stringWithFormat:@"momo-memo_%@_to_%@", MMDateString(start), MMDateString(end)];
}

- (NSString *)markdownExportForTasks:(NSArray *)tasks allHistory:(BOOL)allHistory {
    NSInteger done = 0, overdue = 0;
    for (NSDictionary *task in tasks) {
        if ([self isTaskCompleted:task]) done++;
        if ([self isTaskOverdue:task]) overdue++;
    }
    NSMutableString *out = [NSMutableString stringWithString:@"# Momo Memo 工作记录\n\n"];
    [out appendFormat:@"导出时间：%@\n\n", MMDateTimeString(NSDate.date)];
    [out appendFormat:@"时间范围：%@\n\n---\n\n## 工作概览\n\n", allHistory ? @"全部历史" : @"本周"];
    [out appendFormat:@"- 任务总数：%ld\n- 已完成：%ld\n- 未完成：%ld\n- 已逾期：%ld\n- 完成率：%ld%%\n\n---\n\n# 项目\n\n",
        (long)tasks.count, (long)done, (long)(tasks.count - done), (long)overdue, (long)(done * 100 / MAX(tasks.count, 1))];
    NSArray *statuses = @[@"已逾期", @"进行中", @"暂停", @"未开始", @"已完成"];
    for (NSDictionary *project in self.store[@"projects"]) {
        NSArray *projectTasks = [tasks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) {
            return [task[@"projectId"] isEqualToString:project[@"id"]];
        }]];
        if (!projectTasks.count) continue;
        [out appendFormat:@"## %@\n\n", project[@"name"] ?: @"未分类"];
        for (NSString *status in statuses) {
            NSArray *statusTasks = [projectTasks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) {
                return [[self displayStatusForTask:task] isEqualToString:status];
            }]];
            if (!statusTasks.count) continue;
            [out appendFormat:@"### %@\n\n", status];
            NSArray *sorted = [statusTasks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [(a[@"priority"] ?: @"P2") compare:(b[@"priority"] ?: @"P2")];
            }];
            for (NSDictionary *task in sorted) {
                [out appendFormat:@"- %@ [%@] %@（开始：%@；截止：%@）\n",
                    [self isTaskCompleted:task] ? @"[x]" : @"[ ]", task[@"priority"] ?: @"P2", task[@"title"] ?: @"",
                    task[@"startDate"] ?: @"未设置", [task[@"dueDate"] length] ? task[@"dueDate"] : @"未设置"];
            }
            [out appendString:@"\n"];
        }
    }
    NSArray *longTasks = [tasks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) {
        return [task[@"isLongTerm"] boolValue];
    }]];
    if (longTasks.count) {
        [out appendString:@"# 长期任务\n\n"];
        for (NSDictionary *task in longTasks) [out appendFormat:@"- [%@] %@\n", task[@"priority"] ?: @"P2", task[@"title"] ?: @""];
        [out appendString:@"\n"];
    }
    return out;
}

- (NSString *)csvEscape:(NSString *)value {
    NSString *v = [value ?: @"" stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    return [NSString stringWithFormat:@"\"%@\"", v];
}

- (NSString *)csvExportForTasks:(NSArray *)tasks {
    NSMutableString *out = [NSMutableString stringWithString:@"任务 ID,任务名称,描述,项目,状态,优先级,开始时间,截止时间,创建时间,完成时间,修改时间,是否长期任务,是否逾期,是否归档\n"];
    for (NSDictionary *task in tasks) {
        NSDictionary *project = [self projectById:task[@"projectId"]];
        [out appendFormat:@"%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@\n",
            [self csvEscape:task[@"id"]],
            [self csvEscape:task[@"title"]],
            [self csvEscape:task[@"desc"]],
            [self csvEscape:project[@"name"]],
            [self csvEscape:[self displayStatusForTask:task]],
            [self csvEscape:task[@"priority"]],
            [self csvEscape:task[@"startDate"]],
            [self csvEscape:task[@"dueDate"]],
            [self csvEscape:task[@"createdAt"]],
            [self csvEscape:task[@"completedAt"]],
            [self csvEscape:task[@"modifiedAt"]],
            [self csvEscape:[task[@"isLongTerm"] boolValue] ? @"是" : @"否"],
            [self csvEscape:[self isTaskOverdue:task] ? @"是" : @"否"],
            [self csvEscape:[task[@"archived"] boolValue] ? @"是" : @"否"]];
    }
    return out;
}

- (void)showError:(NSString *)title error:(NSError *)error {
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = error.localizedDescription ?: @"未知错误";
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
}

- (void)showStats {
    NSArray *tasks = [self tasksInCurrentWeek];
    NSInteger done = 0, overdue = 0;
    NSMutableString *projects = [NSMutableString string];
    NSMutableString *priorities = [NSMutableString string];
    for (NSDictionary *task in tasks) {
        if ([self isTaskCompleted:task]) done++;
        if ([self isTaskOverdue:task]) overdue++;
    }
    for (NSDictionary *project in self.store[@"projects"]) {
        NSInteger total = 0, projectDone = 0;
        for (NSDictionary *task in tasks) {
            if (![task[@"projectId"] isEqualToString:project[@"id"]]) continue;
            total++;
            if ([self isTaskCompleted:task]) projectDone++;
        }
        if (total) [projects appendFormat:@"%@：%ld/%ld（%ld%%）\n", project[@"name"], (long)projectDone, (long)total, (long)(projectDone * 100 / MAX(total, 1))];
    }
    for (NSString *priority in @[@"P0", @"P1", @"P2", @"P3"]) {
        NSInteger total = 0, priorityDone = 0;
        for (NSDictionary *task in tasks) {
            if (![task[@"priority"] isEqualToString:priority]) continue;
            total++;
            if ([self isTaskCompleted:task]) priorityDone++;
        }
        if (total) [priorities appendFormat:@"%@：%ld/%ld（%ld%%）\n", priority, (long)priorityDone, (long)total, (long)(priorityDone * 100 / MAX(total, 1))];
    }
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"本周统计";
    alert.informativeText = [NSString stringWithFormat:@"总任务：%ld\n已完成：%ld\n未完成：%ld\n逾期：%ld\n完成率：%ld%%\n\n项目统计\n%@\n优先级统计\n%@",
        (long)tasks.count, (long)done, (long)(tasks.count - done), (long)overdue, (long)(done * 100 / MAX(tasks.count, 1)),
        projects.length ? projects : @"暂无项目任务\n", priorities.length ? priorities : @"暂无优先级数据\n"];
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
}

- (void)showSettings {
    NSMutableArray *projectLines = [NSMutableArray array];
    for (NSDictionary *p in self.store[@"projects"]) {
        [projectLines addObject:[NSString stringWithFormat:@"%@,%@,%@", p[@"name"], p[@"color"], [p[@"allowRepeat"] boolValue] ? @"repeat" : @"norepeat"]];
    }
    NSMutableArray *tagLines = [NSMutableArray array];
    for (NSDictionary *t in self.store[@"tags"]) [tagLines addObject:[NSString stringWithFormat:@"%@,%@", t[@"name"], t[@"color"]]];
    NSTextField *projects = [self field:[projectLines componentsJoinedByString:@"\n"] placeholder:@"项目名,#颜色,repeat/norepeat"];
    NSTextField *tags = [self field:[tagLines componentsJoinedByString:@"\n"] placeholder:@"标签名,#颜色"];
    NSTextField *hours = [self field:[NSString stringWithFormat:@"%@-%@", self.store[@"settings"][@"reminderStartHour"], self.store[@"settings"][@"reminderEndHour"]] placeholder:@"提醒整点，如 10-18"];
    NSTextField *interval = [self field:[self.store[@"settings"][@"reminderIntervalMinutes"] stringValue] placeholder:@"提醒间隔分钟，如 30/60/120"];
    NSTextField *quiet = [self field:self.store[@"settings"][@"quietRanges"] placeholder:@"免打扰时段，每行一个，如 12:00-13:30"];
    NSTextField *exportDir = [self field:self.store[@"settings"][@"exportDirectory"] placeholder:@"默认导出目录"];
    NSPopUpButton *workWeek = [NSPopUpButton new];
    [workWeek addItemsWithTitles:@[@"双休周", @"单休周"]];
    [workWeek selectItemAtIndex:[self.store[@"settings"][@"workWeekMode"] isEqualToString:@"single"] ? 1 : 0];
    NSButton *autoAlternate = [NSButton checkboxWithTitle:@"下周自动切换单双休" target:nil action:nil];
    autoAlternate.state = [self.store[@"settings"][@"autoAlternateWeek"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSPopUpButton *reminderMode = [NSPopUpButton new];
    NSArray *reminderModes = @[@"icon", @"notification", @"desktop", @"iconSound", @"notificationSound", @"desktopSound"];
    [reminderMode addItemsWithTitles:@[@"仅图标状态", @"系统通知", @"桌面提示", @"图标状态 + 声音", @"系统通知 + 声音", @"桌面提示 + 声音"]];
    NSString *savedReminderMode = self.store[@"settings"][@"reminderMode"] ?: @"icon";
    NSUInteger savedModeIndex = [reminderModes indexOfObject:savedReminderMode];
    NSInteger reminderModeIndex = savedModeIndex == NSNotFound ? 0 : (NSInteger)savedModeIndex;
    [reminderMode selectItemAtIndex:reminderModeIndex];
    NSButton *autoExport = [NSButton checkboxWithTitle:@"开启自动导出" target:nil action:nil];
    autoExport.state = [self.store[@"settings"][@"autoExport"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSPopUpButton *exportFrequency = [NSPopUpButton new];
    [exportFrequency addItemsWithTitles:@[@"每天", @"每周", @"每月"]];
    NSString *savedFrequency = self.store[@"settings"][@"autoExportFrequency"] ?: @"weekly";
    [exportFrequency selectItemAtIndex:[savedFrequency isEqualToString:@"daily"] ? 0 : ([savedFrequency isEqualToString:@"monthly"] ? 2 : 1)];
    NSTextField *exportTime = [self field:self.store[@"settings"][@"autoExportTime"] placeholder:@"自动导出时间 HH:mm"];
    NSPopUpButton *exportFormat = [NSPopUpButton new];
    [exportFormat addItemsWithTitles:@[@"Markdown", @"CSV", @"Markdown + CSV"]];
    NSString *savedFormat = self.store[@"settings"][@"autoExportFormat"] ?: @"both";
    [exportFormat selectItemAtIndex:[savedFormat isEqualToString:@"markdown"] ? 0 : ([savedFormat isEqualToString:@"csv"] ? 1 : 2)];
    NSButton *overwrite = [NSButton checkboxWithTitle:@"同一范围覆盖原文件" target:nil action:nil];
    overwrite.state = [self.store[@"settings"][@"exportOverwrite"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSButton *reminders = [NSButton checkboxWithTitle:@"开启提醒" target:nil action:nil];
    reminders.state = [self.store[@"settings"][@"remindersEnabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSButton *backup = [NSButton checkboxWithTitle:@"退出/保存时自动备份，保留最近 7 份" target:nil action:nil];
    backup.state = [self.store[@"settings"][@"autoBackup"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    NSView *form = [self scrollableFormWithViews:@[
        [self labelForField:@"项目（每行：名称,#颜色,repeat/norepeat）"], projects,
        [self labelForField:@"标签（每行：名称,#颜色）"], tags,
        [self labelForField:@"提醒"], reminders, hours, interval, reminderMode,
        [self labelForField:@"本周工作制度"], workWeek, autoAlternate,
        [self labelForField:@"免打扰"], quiet,
        [self labelForField:@"自动导出"], autoExport, exportFrequency, exportTime, exportFormat, overwrite,
        [self labelForField:@"导出路径与备份"], exportDir, backup
    ] height:500];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"设置";
    alert.informativeText = @"保持简单：项目和标签按行编辑即可。";
    alert.accessoryView = form;
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSMutableArray *newProjects = [NSMutableArray array];
    NSArray *existingProjects = [self.store[@"projects"] copy];
    NSInteger order = 0;
    for (NSString *line in [projects.stringValue componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray *parts = [line componentsSeparatedByString:@","];
        NSString *name = parts.count > 0 ? [parts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        if (!name.length) continue;
        NSInteger currentOrder = order++;
        NSString *projectId = currentOrder == 0 ? @"inbox" : nil;
        for (NSDictionary *existing in existingProjects) {
            if ([existing[@"name"] isEqualToString:name]) { projectId = existing[@"id"]; break; }
        }
        if (!projectId && currentOrder < (NSInteger)existingProjects.count) projectId = existingProjects[currentOrder][@"id"];
        [newProjects addObject:[@{
            @"id": projectId ?: MMUUID(),
            @"name": name,
            @"color": parts.count > 1 ? parts[1] : @"#4F8EF7",
            @"allowRepeat": @(!(parts.count > 2 && [parts[2] containsString:@"no"])),
            @"order": @(currentOrder)
        } mutableCopy]];
    }
    if (newProjects.count) {
        self.store[@"projects"] = newProjects;
        NSMutableSet *validProjectIds = [NSMutableSet set];
        for (NSDictionary *project in newProjects) [validProjectIds addObject:project[@"id"]];
        for (NSMutableDictionary *task in self.store[@"tasks"]) {
            if (![validProjectIds containsObject:task[@"projectId"]]) task[@"projectId"] = @"inbox";
        }
    }
    NSMutableArray *newTags = [NSMutableArray array];
    for (NSString *line in [tags.stringValue componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray *parts = [line componentsSeparatedByString:@","];
        NSString *name = parts.count > 0 ? [parts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        if (name.length) [newTags addObject:[@{@"id": MMUUID(), @"name": name, @"color": parts.count > 1 ? parts[1] : @"#9CA3AF"} mutableCopy]];
    }
    self.store[@"tags"] = newTags;
    NSArray *hourParts = [hours.stringValue componentsSeparatedByString:@"-"];
    if (hourParts.count == 2) {
        self.store[@"settings"][@"reminderStartHour"] = @([hourParts[0] integerValue]);
        self.store[@"settings"][@"reminderEndHour"] = @([hourParts[1] integerValue]);
    }
    self.store[@"settings"][@"reminderIntervalMinutes"] = @(MAX(30, interval.integerValue));
    self.store[@"settings"][@"quietRanges"] = quiet.stringValue ?: @"";
    self.store[@"settings"][@"workWeekMode"] = workWeek.indexOfSelectedItem == 1 ? @"single" : @"double";
    self.store[@"settings"][@"autoAlternateWeek"] = @(autoAlternate.state == NSControlStateValueOn);
    self.store[@"settings"][@"workWeekAnchor"] = MMDateString(NSDate.date);
    self.store[@"settings"][@"reminderMode"] = reminderModes[reminderMode.indexOfSelectedItem];
    self.store[@"settings"][@"exportDirectory"] = exportDir.stringValue.length ? exportDir.stringValue : NSHomeDirectory();
    self.store[@"settings"][@"autoExport"] = @(autoExport.state == NSControlStateValueOn);
    NSArray *frequencies = @[@"daily", @"weekly", @"monthly"];
    self.store[@"settings"][@"autoExportFrequency"] = frequencies[exportFrequency.indexOfSelectedItem];
    self.store[@"settings"][@"autoExportTime"] = exportTime.stringValue.length ? exportTime.stringValue : @"18:30";
    NSArray *formats = @[@"markdown", @"csv", @"both"];
    self.store[@"settings"][@"autoExportFormat"] = formats[exportFormat.indexOfSelectedItem];
    self.store[@"settings"][@"exportOverwrite"] = @(overwrite.state == NSControlStateValueOn);
    self.store[@"settings"][@"remindersEnabled"] = @(reminders.state == NSControlStateValueOn);
    self.store[@"settings"][@"autoBackup"] = @(backup.state == NSControlStateValueOn);
    if ([self.currentProjectId hasPrefix:@"project:"]) {
        NSString *selectedId = [self.currentProjectId substringFromIndex:8];
        BOOL exists = NO;
        for (NSDictionary *project in self.store[@"projects"]) if ([project[@"id"] isEqualToString:selectedId]) { exists = YES; break; }
        if (!exists) self.currentProjectId = @"all";
    }
    [self saveStore];
    [self reloadProjectPopup];
    [self render];
}

- (BOOL)isQuietNow {
    NSString *quiet = self.store[@"settings"][@"quietRanges"] ?: @"";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm";
    NSDate *nowDate = [formatter dateFromString:[formatter stringFromDate:NSDate.date]];
    for (NSString *line in [quiet componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray *parts = [line componentsSeparatedByString:@"-"];
        if (parts.count != 2) continue;
        NSDate *start = [formatter dateFromString:[parts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
        NSDate *end = [formatter dateFromString:[parts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
        if (!start || !end) continue;
        if ([start compare:end] == NSOrderedAscending) {
            if ([nowDate compare:start] != NSOrderedAscending && [nowDate compare:end] == NSOrderedAscending) return YES;
        } else {
            if ([nowDate compare:start] != NSOrderedAscending || [nowDate compare:end] == NSOrderedAscending) return YES;
        }
    }
    return NO;
}

- (NSString *)effectiveWorkWeekMode {
    NSString *mode = self.store[@"settings"][@"workWeekMode"] ?: @"double";
    if (![self.store[@"settings"][@"autoAlternateWeek"] boolValue]) return mode;
    NSDate *anchorDate = MMDateFromString(self.store[@"settings"][@"workWeekAnchor"]);
    if (!anchorDate) return mode;
    NSDate *anchorStart = nil, *nowStart = nil;
    [NSCalendar.currentCalendar rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&anchorStart interval:nil forDate:anchorDate];
    [NSCalendar.currentCalendar rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&nowStart interval:nil forDate:NSDate.date];
    NSInteger weeks = [[NSCalendar.currentCalendar components:NSCalendarUnitWeekOfYear fromDate:anchorStart toDate:nowStart options:0] weekOfYear];
    if (labs(weeks) % 2 == 0) return mode;
    return [mode isEqualToString:@"single"] ? @"double" : @"single";
}

- (BOOL)isWorkingDayNow {
    NSInteger weekday = [NSCalendar.currentCalendar component:NSCalendarUnitWeekday fromDate:NSDate.date];
    if (weekday == 1) return NO;
    if (weekday == 7 && [[self effectiveWorkWeekMode] isEqualToString:@"double"]) return NO;
    return YES;
}

- (void)deliverReminderForCount:(NSInteger)count {
    NSString *mode = self.store[@"settings"][@"reminderMode"] ?: @"icon";
    self.trayHighlighted = YES;
    self.statusItem.button.title = [NSString stringWithFormat:@"● Momo (%ld)", (long)count];
    NSApp.dockTile.badgeLabel = [NSString stringWithFormat:@"%ld", (long)count];
    if ([mode containsString:@"notification"]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSUserNotification *notification = [NSUserNotification new];
        notification.title = @"Momo Memo";
        notification.informativeText = [NSString stringWithFormat:@"还有 %ld 个今日或逾期任务未完成", (long)count];
        [NSUserNotificationCenter.defaultUserNotificationCenter deliverNotification:notification];
#pragma clang diagnostic pop
    }
    if ([mode containsString:@"desktop"]) [self showWindow];
    if ([mode containsString:@"Sound"] || [mode containsString:@"sound"]) [NSSound beep];
}

- (NSArray *)tasksForAutoExportFrequency:(NSString *)frequency {
    if ([frequency isEqualToString:@"weekly"]) return [self tasksInCurrentWeek];
    NSString *prefix = [frequency isEqualToString:@"monthly"] ? [MMDateString(NSDate.date) substringToIndex:7] : MMDateString(NSDate.date);
    return [self.store[@"tasks"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) {
        return [task[@"taskDate"] hasPrefix:prefix];
    }]];
}

- (NSString *)autoExportBaseNameForFrequency:(NSString *)frequency {
    NSString *today = MMDateString(NSDate.date);
    if ([frequency isEqualToString:@"daily"]) return [NSString stringWithFormat:@"momo-memo_%@_to_%@", today, today];
    if ([frequency isEqualToString:@"weekly"]) return [self exportBaseNameForAllHistory:NO];
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSRange days = [calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:NSDate.date];
    NSString *month = [today substringToIndex:7];
    return [NSString stringWithFormat:@"momo-memo_%@-01_to_%@-%02ld", month, month, (long)days.length];
}

- (NSString *)availableExportPathInDirectory:(NSString *)directory baseName:(NSString *)baseName extension:(NSString *)extension {
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", baseName, extension]];
    if ([self.store[@"settings"][@"exportOverwrite"] boolValue] || ![NSFileManager.defaultManager fileExistsAtPath:path]) return path;
    NSInteger version = 2;
    do {
        path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_v%ld.%@", baseName, (long)version++, extension]];
    } while ([NSFileManager.defaultManager fileExistsAtPath:path]);
    return path;
}

- (void)checkAutoExport {
    NSMutableDictionary *settings = self.store[@"settings"];
    if (![settings[@"autoExport"] boolValue]) return;
    NSDateFormatter *timeFormatter = [NSDateFormatter new];
    timeFormatter.dateFormat = @"HH:mm";
    if (![[timeFormatter stringFromDate:NSDate.date] isEqualToString:settings[@"autoExportTime"]]) return;
    NSString *frequency = settings[@"autoExportFrequency"] ?: @"weekly";
    NSInteger weekday = [NSCalendar.currentCalendar component:NSCalendarUnitWeekday fromDate:NSDate.date];
    NSRange days = [NSCalendar.currentCalendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:NSDate.date];
    NSInteger day = [NSCalendar.currentCalendar component:NSCalendarUnitDay fromDate:NSDate.date];
    if ([frequency isEqualToString:@"weekly"] && weekday != 6) return;
    if ([frequency isEqualToString:@"monthly"] && day != days.length) return;
    NSString *key = [NSString stringWithFormat:@"%@-%@", frequency, MMDateString(NSDate.date)];
    if ([settings[@"lastAutoExportKey"] isEqualToString:key]) return;
    NSString *directory = settings[@"exportDirectory"] ?: MMDefaultExportDirectory();
    NSError *directoryError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
        [self showError:@"自动导出失败" error:directoryError];
        return;
    }
    NSArray *tasks = [self tasksForAutoExportFrequency:frequency];
    NSString *baseName = [self autoExportBaseNameForFrequency:frequency];
    NSString *format = settings[@"autoExportFormat"] ?: @"both";
    NSError *writeError = nil;
    if (![format isEqualToString:@"csv"]) {
        NSString *path = [self availableExportPathInDirectory:directory baseName:baseName extension:@"md"];
        [[self markdownExportForTasks:tasks allHistory:NO] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    }
    if (!writeError && ![format isEqualToString:@"markdown"]) {
        NSString *path = [self availableExportPathInDirectory:directory baseName:baseName extension:@"csv"];
        [[self csvExportForTasks:tasks] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    }
    if (writeError) {
        [self showError:@"自动导出失败" error:writeError];
        return;
    }
    settings[@"lastAutoExportKey"] = key;
    [self saveStore];
}

- (void)checkReminder {
    if (![self.store[@"settings"][@"remindersEnabled"] boolValue] || [self isQuietNow] || ![self isWorkingDayNow]) {
        self.statusItem.button.title = @"Momo";
        NSApp.dockTile.badgeLabel = nil;
        self.trayHighlighted = NO;
        return;
    }
    NSDateComponents *components = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:NSDate.date];
    NSInteger start = [self.store[@"settings"][@"reminderStartHour"] integerValue];
    NSInteger end = [self.store[@"settings"][@"reminderEndHour"] integerValue];
    NSInteger interval = [self.store[@"settings"][@"reminderIntervalMinutes"] integerValue];
    if (components.hour < start || components.hour > end) {
        self.statusItem.button.title = @"Momo";
        NSApp.dockTile.badgeLabel = nil;
        self.trayHighlighted = NO;
        return;
    }
    NSInteger elapsedMinutes = (components.hour - start) * 60 + components.minute;
    NSString *reminderKey = [NSString stringWithFormat:@"%@-%02ld:%02ld", MMDateString(NSDate.date), (long)components.hour, (long)components.minute];
    if ([self.lastReminderKey isEqualToString:reminderKey]) return;
    NSInteger count = 0, outstanding = 0;
    for (NSDictionary *task in self.store[@"tasks"]) {
        if ([self isTaskCompleted:task] || [task[@"archived"] boolValue] || ![task[@"reminderEnabled"] boolValue]) continue;
        if (![self isTaskDueToday:task] && ![self isTaskOverdue:task]) continue;
        NSDate *snoozedUntil = MMDateFromString(task[@"snoozedUntil"]);
        if (snoozedUntil && [NSDate.date compare:snoozedUntil] == NSOrderedAscending) continue;
        NSString *rule = task[@"reminderRule"] ?: @"workHours";
        if ([rule isEqualToString:@"none"]) continue;
        outstanding++;
        if ([rule isEqualToString:@"workHours"] && elapsedMinutes % MAX(interval, 30) != 0) continue;
        if ([rule isEqualToString:@"every30"] && elapsedMinutes % 30 != 0) continue;
        if ([rule isEqualToString:@"every60"] && elapsedMinutes % 60 != 0) continue;
        if ([rule isEqualToString:@"beforeDue"]) {
            NSDate *due = MMDateFromString(task[@"dueDate"]);
            if (!due) continue;
            NSTimeInterval seconds = [due timeIntervalSinceDate:NSDate.date];
            if (seconds < 0 || seconds > 30 * 60) continue;
        }
        count++;
    }
    self.lastReminderKey = reminderKey;
    if (!count && !outstanding) {
        self.statusItem.button.title = @"Momo";
        NSApp.dockTile.badgeLabel = nil;
        self.trayHighlighted = NO;
        return;
    }
    if (!count) return;
    [self deliverReminderForCount:count];
}

@end

static MMAppDelegate *delegate;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        delegate = [MMAppDelegate new];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
