#import <Cocoa/Cocoa.h>

static NSString *MMDateString(NSDate *date) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [formatter stringFromDate:date ?: NSDate.date];
}

static NSDate *MMDateFromString(NSString *value) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd";
    return value.length ? [formatter dateFromString:value] : nil;
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
    }];
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
            [@{@"id": @"inbox", @"name": @"默认项目", @"color": @"#4F8EF7", @"allowRepeat": @YES, @"order": @0} mutableCopy]
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
            @"exportDirectory": MMDefaultExportDirectory(),
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
    if (!self.store[@"tags"]) self.store[@"tags"] = [NSMutableArray array];
    if (!self.store[@"tasks"]) self.store[@"tasks"] = [NSMutableArray array];
    if (!self.store[@"settings"]) self.store[@"settings"] = [self defaultStore][@"settings"];
    self.currentProjectId = @"all";
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

- (BOOL)taskVisible:(NSDictionary *)task {
    if (![self.currentProjectId isEqualToString:@"all"] && ![task[@"projectId"] isEqualToString:self.currentProjectId]) return NO;
    if ([self.store[@"settings"][@"hideCompleted"] boolValue] && [task[@"completed"] boolValue]) return NO;
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
    [self.projectPopup addItemWithTitle:@"全部任务"];
    self.projectPopup.lastItem.representedObject = @"all";
    for (NSDictionary *project in self.store[@"projects"]) {
        [self.projectPopup addItemWithTitle:project[@"name"]];
        self.projectPopup.lastItem.representedObject = project[@"id"];
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
        BOOL pa = [a[@"pinned"] boolValue], pb = [b[@"pinned"] boolValue];
        if (pa != pb) return pa ? NSOrderedAscending : NSOrderedDescending;
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
    NSInteger done = 0;
    for (NSDictionary *task in tasks) if ([task[@"completed"] boolValue]) done++;
    self.summaryLabel.stringValue = [NSString stringWithFormat:@"当前 %ld 项，已完成 %ld 项", (long)tasks.count, (long)done];
    if (!tasks.count) {
        NSTextField *empty = MMLabel(@"今天先写下一件小事。", 15, NSFontWeightRegular);
        empty.alignment = NSTextAlignmentCenter;
        empty.textColor = [NSColor secondaryLabelColor];
        [self.taskStack addArrangedSubview:empty];
        return;
    }
    NSString *lastProject = nil;
    for (NSDictionary *task in tasks) {
        if ([self.currentProjectId isEqualToString:@"all"] && ![lastProject isEqualToString:task[@"projectId"]]) {
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
    NSString *date = task[@"startDate"] ?: task[@"taskDate"] ?: MMDateString(NSDate.date);
    NSString *end = task[@"finishDate"];
    NSString *dateText = end.length && ![end isEqualToString:date] ? [NSString stringWithFormat:@"%@ 至 %@", date, end] : date;
    NSMutableArray *meta = [NSMutableArray arrayWithObjects:dateText, task[@"priority"] ?: @"中", nil];
    if ([task[@"dueDate"] length]) [meta addObject:[NSString stringWithFormat:@"截止 %@", task[@"dueDate"]]];
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
    NSButton *del = MMButton(@"删除", self, @selector(deleteTask:));
    del.identifier = task[@"id"];
    NSStackView *actions = [NSStackView stackViewWithViews:@[pin, edit, del]];
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

- (void)addTask {
    [self editTaskObject:nil quick:NO];
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
    NSString *projectId = [self.currentProjectId isEqualToString:@"all"] ? @"inbox" : self.currentProjectId;
    NSMutableDictionary *task = [@{
        @"id": MMUUID(),
        @"title": title.stringValue,
        @"desc": @"",
        @"projectId": projectId,
        @"tags": [NSMutableArray array],
        @"subtasks": [NSMutableArray array],
        @"startDate": MMDateString(NSDate.date),
        @"finishDate": @"",
        @"dueDate": @"",
        @"taskDate": MMDateString(NSDate.date),
        @"priority": @"中",
        @"completed": @NO,
        @"pinned": @NO,
        @"repeat": @"无"
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
    NSDictionary *baseProject = [self projectById:[self.currentProjectId isEqualToString:@"all"] ? @"inbox" : self.currentProjectId];
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
        @"priority": @"中",
        @"completed": @NO,
        @"pinned": @NO,
        @"repeat": @"无",
        @"color": @""
    } mutableCopy];

    NSTextField *title = [self field:draft[@"title"] placeholder:@"标题，必填"];
    NSTextField *desc = [self field:draft[@"desc"] placeholder:@"详细描述，可写简单 Markdown"];
    NSTextField *start = [self field:draft[@"startDate"] placeholder:@"开始日期 yyyy-MM-dd"];
    NSTextField *finish = [self field:draft[@"finishDate"] placeholder:@"完成日期，可空"];
    NSTextField *due = [self field:draft[@"dueDate"] placeholder:@"截止日期，可空"];
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
    [priority addItemsWithTitles:@[@"高", @"中", @"低"]];
    [priority selectItemWithTitle:draft[@"priority"] ?: @"中"];
    NSPopUpButton *repeat = [NSPopUpButton new];
    [repeat addItemsWithTitles:@[@"无", @"每日", @"每周", @"每月", @"自定义"]];
    [repeat selectItemWithTitle:draft[@"repeat"] ?: @"无"];

    NSStackView *form = [self formWithViews:@[
        [self labelForField:@"标题"], title,
        [self labelForField:@"所属项目"], project,
        [self labelForField:@"描述"], desc,
        [self labelForField:@"日期"], start, finish, due, taskDate,
        [self labelForField:@"优先级"], priority,
        [self labelForField:@"标签与子任务"], tags, subs,
        [self labelForField:@"重复与颜色"], repeat, color
    ]];
    NSAlert *alert = [NSAlert new];
    alert.messageText = isNew ? @"创建任务" : @"编辑任务";
    alert.informativeText = @"常用字段直接填；不需要的留空即可。";
    alert.accessoryView = form;
    [alert addButtonWithTitle:isNew ? @"创建" : @"保存"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    if (!title.stringValue.length) return;

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
    draft[@"priority"] = priority.titleOfSelectedItem ?: @"中";
    draft[@"tags"] = tagList;
    draft[@"subtasks"] = subList;
    draft[@"repeat"] = repeatValue ?: @"无";
    draft[@"color"] = color.stringValue ?: @"";
    if (isNew) [self.store[@"tasks"] addObject:draft];
    else [task setDictionary:draft];
    [self saveStore];
    [self reloadProjectPopup];
    [self render];
}

- (void)deleteTask:(NSButton *)sender {
    NSMutableDictionary *task = [self taskById:sender.identifier];
    if (!task) return;
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
    if (done && ![task[@"finishDate"] length]) task[@"finishDate"] = MMDateString(NSDate.date);
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
    NSAlert *choice = [NSAlert new];
    choice.messageText = @"导出本周任务";
    choice.informativeText = @"选择导出格式。";
    [choice addButtonWithTitle:@"Markdown"];
    [choice addButtonWithTitle:@"CSV"];
    [choice addButtonWithTitle:@"取消"];
    NSModalResponse response = [choice runModal];
    if (response == NSAlertThirdButtonReturn) return;
    BOOL markdown = response == NSAlertFirstButtonReturn;
    NSString *ext = markdown ? @"md" : @"csv";
    NSString *name = [NSString stringWithFormat:@"本周任务_%@.%@", MMDateString(NSDate.date), ext];
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = name;
    panel.directoryURL = [NSURL fileURLWithPath:self.store[@"settings"][@"exportDirectory"] ?: NSHomeDirectory()];
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *content = markdown ? [self markdownExport] : [self csvExport];
    [content writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (NSString *)markdownExport {
    NSMutableString *out = [NSMutableString stringWithFormat:@"# 本周任务 %@\n\n", MMDateString(NSDate.date)];
    NSArray *tasks = [[self tasksInCurrentWeek] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"taskDate"] compare:b[@"taskDate"]];
    }];
    NSString *lastDate = nil;
    for (NSDictionary *task in tasks) {
        NSString *date = task[@"taskDate"] ?: @"未设置日期";
        if (![date isEqualToString:lastDate]) {
            [out appendFormat:@"## %@\n\n", date];
            lastDate = date;
        }
        NSDictionary *project = [self projectById:task[@"projectId"]];
        NSString *range = [task[@"finishDate"] length] && ![task[@"finishDate"] isEqualToString:task[@"startDate"]]
            ? [NSString stringWithFormat:@"%@ 至 %@", task[@"startDate"], task[@"finishDate"]]
            : (task[@"startDate"] ?: date);
        [out appendFormat:@"- %@%@ | %@ | %@ | %@\n",
            [task[@"completed"] boolValue] ? @"[x] " : @"[ ] ",
            task[@"title"] ?: @"",
            range,
            project[@"name"] ?: @"",
            [task[@"tags"] componentsJoinedByString:@", "]];
    }
    return out;
}

- (NSString *)csvEscape:(NSString *)value {
    NSString *v = [value ?: @"" stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    return [NSString stringWithFormat:@"\"%@\"", v];
}

- (NSString *)csvExport {
    NSMutableString *out = [NSMutableString stringWithString:@"日期,标题,开始日期,完成日期,项目,标签,状态\n"];
    for (NSDictionary *task in [self tasksInCurrentWeek]) {
        NSDictionary *project = [self projectById:task[@"projectId"]];
        [out appendFormat:@"%@,%@,%@,%@,%@,%@,%@\n",
            [self csvEscape:task[@"taskDate"]],
            [self csvEscape:task[@"title"]],
            [self csvEscape:task[@"startDate"]],
            [self csvEscape:task[@"finishDate"]],
            [self csvEscape:project[@"name"]],
            [self csvEscape:[task[@"tags"] componentsJoinedByString:@";"]],
            [self csvEscape:[task[@"completed"] boolValue] ? @"已完成" : @"未完成"]];
    }
    return out;
}

- (void)showStats {
    NSArray *tasks = [self tasksInCurrentWeek];
    NSInteger done = 0;
    NSMutableString *projects = [NSMutableString string];
    for (NSDictionary *task in tasks) if ([task[@"completed"] boolValue]) done++;
    for (NSDictionary *project in self.store[@"projects"]) {
        NSInteger total = 0, projectDone = 0;
        for (NSDictionary *task in tasks) {
            if (![task[@"projectId"] isEqualToString:project[@"id"]]) continue;
            total++;
            if ([task[@"completed"] boolValue]) projectDone++;
        }
        if (total) [projects appendFormat:@"%@：%ld/%ld（%ld%%）\n", project[@"name"], (long)projectDone, (long)total, (long)(projectDone * 100 / MAX(total, 1))];
    }
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"本周统计";
    alert.informativeText = [NSString stringWithFormat:@"总任务：%ld\n已完成：%ld\n未完成：%ld\n\n%@", (long)tasks.count, (long)done, (long)(tasks.count - done), projects.length ? projects : @"暂无项目任务"];
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
    NSButton *reminders = [NSButton checkboxWithTitle:@"开启提醒" target:nil action:nil];
    reminders.state = [self.store[@"settings"][@"remindersEnabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSButton *backup = [NSButton checkboxWithTitle:@"退出/保存时自动备份，保留最近 7 份" target:nil action:nil];
    backup.state = [self.store[@"settings"][@"autoBackup"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    NSStackView *form = [self formWithViews:@[
        [self labelForField:@"项目（每行：名称,#颜色,repeat/norepeat）"], projects,
        [self labelForField:@"标签（每行：名称,#颜色）"], tags,
        [self labelForField:@"提醒"], reminders, hours, interval,
        [self labelForField:@"免打扰"], quiet,
        [self labelForField:@"导出与备份"], exportDir, backup
    ]];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"设置";
    alert.informativeText = @"保持简单：项目和标签按行编辑即可。";
    alert.accessoryView = form;
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSMutableArray *newProjects = [NSMutableArray array];
    NSInteger order = 0;
    for (NSString *line in [projects.stringValue componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray *parts = [line componentsSeparatedByString:@","];
        NSString *name = parts.count > 0 ? [parts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        if (!name.length) continue;
        NSInteger currentOrder = order++;
        [newProjects addObject:[@{
            @"id": currentOrder == 0 ? @"inbox" : MMUUID(),
            @"name": name,
            @"color": parts.count > 1 ? parts[1] : @"#4F8EF7",
            @"allowRepeat": @(!(parts.count > 2 && [parts[2] containsString:@"no"])),
            @"order": @(currentOrder)
        } mutableCopy]];
    }
    if (newProjects.count) self.store[@"projects"] = newProjects;
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
    self.store[@"settings"][@"exportDirectory"] = exportDir.stringValue.length ? exportDir.stringValue : NSHomeDirectory();
    self.store[@"settings"][@"remindersEnabled"] = @(reminders.state == NSControlStateValueOn);
    self.store[@"settings"][@"autoBackup"] = @(backup.state == NSControlStateValueOn);
    if (![self.currentProjectId isEqualToString:@"all"] && ![self projectById:self.currentProjectId]) self.currentProjectId = @"all";
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

- (void)checkReminder {
    if (![self.store[@"settings"][@"remindersEnabled"] boolValue] || [self isQuietNow]) {
        self.statusItem.button.title = @"Momo";
        return;
    }
    NSDateComponents *components = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:NSDate.date];
    NSInteger start = [self.store[@"settings"][@"reminderStartHour"] integerValue];
    NSInteger end = [self.store[@"settings"][@"reminderEndHour"] integerValue];
    NSInteger interval = [self.store[@"settings"][@"reminderIntervalMinutes"] integerValue];
    if (components.hour < start || components.hour > end || components.minute % MAX(interval, 30) != 0) return;
    BOOL hasToday = NO;
    NSString *today = MMDateString(NSDate.date);
    for (NSDictionary *task in self.store[@"tasks"]) {
        if (![task[@"completed"] boolValue] && [task[@"taskDate"] isEqualToString:today]) {
            hasToday = YES;
            break;
        }
    }
    if (!hasToday) return;
    self.trayHighlighted = !self.trayHighlighted;
    self.statusItem.button.title = self.trayHighlighted ? @"● Momo" : @"Momo";
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
