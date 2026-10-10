#import "RootListController.h"
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <sys/sysctl.h>
#import <mach/mach.h>
#import <mach/mach_host.h>

#define PREFS_PATH   @"/var/mobile/Library/Preferences/com.tri.optimizerx.plist"
#define NOTIFY_NAME  "com.tri.optimizerx.changed"

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

@interface RootListController : PSListController
@end

@implementation RootListController {
    NSTimer *_liveTimer;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] retain];
    }
    return _specifiers;
}

#pragma mark - Ghi mọi thay đổi vào plist + notify tweak

- (void)setPreferenceValue:(id)value forSpecifier:(PSSpecifier *)specifier {
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

    [super setPreferenceValue:stored forSpecifier:specifier];

    if (key.length) {
        NSMutableDictionary *prefs =
            [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH];
        if (!prefs) prefs = [NSMutableDictionary dictionary];
        prefs[key] = stored ?: @0;
        [prefs writeToFile:PREFS_PATH atomically:YES];
    }
    notify_post(NOTIFY_NAME);

    // Cập nhật dòng "Trạng thái" nếu có
    PSSpecifier *live = [self specifierForID:@"liveInfoCell"];
    if (live) [self reloadSpecifier:live animated:NO];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    id v = key ? prefs[key] : nil;
    if (v) return v;
    return [specifier propertyForKey:@"default"];
}

#pragma mark - Live Info cell (tùy chọn, an toàn nếu plist không có)

- (id)liveInfo:(PSSpecifier *)specifier {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
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

    // Lắng nghe thay đổi từ phía tweak (Battery Guard / Thermal tự đổi mode)
    notify_register_dispatch(NOTIFY_NAME, NULL, dispatch_get_main_queue(),
                             ^(int token) {
        [self reloadSpecifiers];
    });

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
}

- (void)refreshLive {
    PSSpecifier *sp = [self specifierForID:@"liveInfoCell"];
    if (sp) [self reloadSpecifier:sp animated:NO];
}

@end
