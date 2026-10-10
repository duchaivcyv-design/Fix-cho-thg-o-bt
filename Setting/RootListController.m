#import "RootListController.h"
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <sys/sysctl.h>
#import <mach/mach.h>
#import <mach/mach_host.h>

#define PREFS_PATH_ROOTLESS @"/var/jb/var/mobile/Library/Preferences/com.tri.optimizerx.plist"
#define PREFS_PATH_ROOTFUL  @"/var/mobile/Library/Preferences/com.tri.optimizerx.plist"
#define NOTIFY_NAME         "com.tri.optimizerx.changed"

static NSString *getPrefsPath(void) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
        return PREFS_PATH_ROOTLESS;
    }
    return PREFS_PATH_ROOTFUL;
}

static NSSet *intKeys(void) {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[@"currentMode",
                                   @"batteryThreshold",
                                   @"tempThreshold",
                                   @"autoCleanInterval"]];
    });
    return s;
}

static float readCPUTemp(void) {
    int level = 0; size_t sz = sizeof(level);
    if (sysctlbyname("machdep.xcpm.cpu_thermal_level", &level, &sz, NULL, 0) == 0)
        return 30.0f + level * 0.5f;
    return -1.0f;
}

static int readBattPct(void) {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    return (int)([UIDevice currentDevice].batteryLevel * 100);
}

static float readFreeRAMMB(void) {
    mach_port_t host = mach_host_self();
    vm_size_t pg = 0; host_page_size(host, &pg);
    vm_statistics64_data_t st;
    mach_msg_type_number_t c = HOST_VM_INFO64_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&st, &c) == KERN_SUCCESS)
        return st.free_count * pg / 1048576.0f;
    return -1.0f;
}

@implementation RootListController {
    NSTimer *_liveTimer;
    int _notifyToken;
    BOOL _isNotifyRegistered;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self updateModeCellTitle];
    }
    return _specifiers;
}

// Cập nhật tên hiển thị ngoài menu tương ứng chế độ đang chạy
- (void)updateModeCellTitle {
    PSSpecifier *spec = [self specifierForID:@"currentModeCell"];
    if (spec) {
        NSString *path = getPrefsPath();
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
        int mode = [prefs[@"currentMode"] ?: @(1) intValue];
        NSArray *names = @[@"🍃 Tiết kiệm", @"⚖️ Cân bằng", @"⚡ Hiệu năng", @"🔥 Turbo"];
        NSString *name = (mode >= 0 && mode < (int)names.count) ? names[mode] : @"⚖️ Cân bằng";
        NSString *display = [NSString stringWithFormat:@"🎯 Chế độ: %@", name];
        spec.name = display;
        [spec setProperty:display forKey:@"label"];
    }
}

#pragma mark - Popup Menu chọn chế độ

- (void)showModeMenu:(PSSpecifier *)specifier {
    NSString *path = getPrefsPath();
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    int currentMode = [prefs[@"currentMode"] ?: @(1) intValue];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎯 CHỌN CHẾ ĐỘ HIỆU NĂNG"
                                                                   message:@"Cấu hình sẽ được kích hoạt tức thì không cần Respring:"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *modes = @[
        @"🍃 Tiết kiệm (15Hz - 60Hz)",
        @"⚖️ Cân bằng (Ổn định pin)",
        @"⚡ Hiệu năng (Mượt mà)",
        @"🔥 Turbo (Tối đa phần cứng)"
    ];

    for (int i = 0; i < (int)modes.count; i++) {
        int targetMode = i;
        NSString *title = modes[i];
        if (targetMode == currentMode) {
            title = [NSString stringWithFormat:@"✓ %@", title];
        }

        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull act) {
            [self selectMode:targetMode];
        }];
        [alert addAction:action];
    }

    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Đóng"
                                                     style:UIAlertActionStyleCancel
                                                   handler:nil];
    [alert addAction:cancel];

    // Chống crash trên iPad khi mở ActionSheet
    if (alert.popoverPresentationController) {
        UIView *sourceView = self.view;
        if ([self respondsToSelector:@selector(cachedCellForSpecifier:)]) {
            UITableViewCell *cell = [(id)self cachedCellForSpecifier:specifier];
            if (cell) sourceView = cell;
        }
        alert.popoverPresentationController.sourceView = sourceView;
        alert.popoverPresentationController.sourceRect = sourceView.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectMode:(int)mode {
    NSString *path = getPrefsPath();
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    prefs[@"currentMode"] = @(mode);
    [prefs writeToFile:path atomically:YES];

    notify_post(NOTIFY_NAME);

    [self updateModeCellTitle];
    PSSpecifier *modeCell = [self specifierForID:@"currentModeCell"];
    if (modeCell) [self reloadSpecifier:modeCell animated:YES];

    PSSpecifier *live = [self specifierForID:@"liveInfoCell"];
    if (live) [self reloadSpecifier:live animated:NO];
}

#pragma mark - Ghi mọi thay đổi vào plist + notify tweak

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id stored = value;

    if (key && [intKeys() containsObject:key]) {
        if ([value respondsToSelector:@selector(intValue)])
            stored = @([value intValue]);
    }

    if ([key isEqualToString:@"tempThreshold"]) {
        int t = [stored intValue];
        if (t < 35) t = 35;
        if (t > 60) t = 60;
        stored = @(t);
    }
    if ([key isEqualToString:@"batteryThreshold"]) {
        int b = [stored intValue];
        if (b < 5)  b = 5;
        if (b > 50) b = 50;
        stored = @(b);
    }
    if ([key isEqualToString:@"autoCleanInterval"]) {
        int s = [stored intValue];
        if (s < 600)  s = 600;
        if (s > 7200) s = 7200;
        stored = @(s);
    }

    [super setPreferenceValue:stored specifier:specifier];

    if (key.length) {
        NSString *path = getPrefsPath();
        NSString *dir = [path stringByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }

        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:path];
        if (!prefs) prefs = [NSMutableDictionary dictionary];
        prefs[key] = stored ?: @0;
        [prefs writeToFile:path atomically:YES];
    }
    notify_post(NOTIFY_NAME);

    PSSpecifier *live = [self specifierForID:@"liveInfoCell"];
    if (live) [self reloadSpecifier:live animated:NO];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *path = getPrefsPath();
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    id v = key ? prefs[key] : nil;
    if (v) return v;
    return [specifier propertyForKey:@"default"];
}

- (id)liveInfo:(PSSpecifier *)specifier {
    NSString *path = getPrefsPath();
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    int mode = [prefs[@"currentMode"] ?: @(1) intValue];
    if (mode < 0 || mode > 3) mode = 1;
    NSArray *names = @[@"Tiết kiệm", @"Cân bằng", @"Hiệu năng", @"Turbo"];
    return [NSString stringWithFormat:@"%@ • %.1f°C • %d%% • %.0f MB",
            names[mode], readCPUTemp(), readBattPct(), readFreeRAMMB()];
}

#pragma mark - Lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateModeCellTitle];
    [self reloadSpecifiers];

    if (!_isNotifyRegistered) {
        notify_register_dispatch(NOTIFY_NAME, &_notifyToken, dispatch_get_main_queue(),
                                 ^(int token) {
            [self updateModeCellTitle];
            [self reloadSpecifiers];
        });
        _isNotifyRegistered = YES;
    }

    if (!_liveTimer) {
        _liveTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(refreshLive)
                                                    userInfo:nil
                                                     repeats:YES];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_liveTimer invalidate];
    _liveTimer = nil;

    if (_isNotifyRegistered) {
        notify_cancel(_notifyToken);
        _isNotifyRegistered = NO;
    }
}

- (void)refreshLive {
    PSSpecifier *sp = [self specifierForID:@"liveInfoCell"];
    if (sp) [self reloadSpecifier:sp animated:NO];
}

@end
