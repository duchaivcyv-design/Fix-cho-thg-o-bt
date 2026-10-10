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

// Các key bắt buộc phải lưu dạng int (vì PSSliderCell trả float)
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

// ── Live info helpers ───────────────────────────────────────────────────────
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
        // [ĐÃ SỬA]: Bỏ retain để tuân thủ ARC
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

#pragma mark - Ghi mọi thay đổi vào plist + notify tweak

// [ĐÃ SỬA]: Selector chuẩn của PSListController là specifier:, không phải forSpecifier:
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id stored = value;

    // PSSliderCell / PSSegmentedCell có thể trả NSNumber float → ép int cho key số
    if (key && [intKeys() containsObject:key]) {
        if ([value respondsToSelector:@selector(intValue)])
            stored = @([value intValue]);
    }

    // currentMode: clamp 0..3
    if ([key isEqualToString:@"currentMode"]) {
        int m = [stored intValue];
        if (m < 0) m = 0;
        if (m > 3) m = 3;
        stored = @(m);
    }

    // Ngưỡng nhiệt: clamp 35..60
    if ([key isEqualToString:@"tempThreshold"]) {
        int t = [stored intValue];
        if (t < 35) t = 35;
        if (t > 60) t = 60;
        stored = @(t);
    }
    // Ngưỡng pin: clamp 5..50
    if ([key isEqualToString:@"batteryThreshold"]) {
        int b = [stored intValue];
        if (b < 5)  b = 5;
        if (b > 50) b = 50;
        stored = @(b);
    }
    // Chu kỳ dọn: clamp 600..7200
    if ([key isEqualToString:@"autoCleanInterval"]) {
        int s = [stored intValue];
        if (s < 600)  s = 600;
        if (s > 7200) s = 7200;
        stored = @(s);
    }

    // [ĐÃ SỬA]: Gọi super với đúng selector
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

    // Cập nhật dòng "Trạng thái" nếu có
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

#pragma mark - Live Info cell (tùy chọn, an toàn nếu plist không có)

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
    [self reloadSpecifiers];

    // [ĐÃ SỬA]: Đăng ký dispatch với biến token hợp lệ, tránh đăng ký lặp
    if (!_isNotifyRegistered) {
        notify_register_dispatch(NOTIFY_NAME, &_notifyToken, dispatch_get_main_queue(),
                                 ^(int token) {
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

    // [ĐÃ SỬA]: Hủy token khi thoát trang cài đặt
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
