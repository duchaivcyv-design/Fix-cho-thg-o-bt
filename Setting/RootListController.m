#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <notify.h>
#import <sys/sysctl.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <UIKit/UIKit.h>

#define PREFS_DOMAIN @"com.tri.optimizerx"
#define PREFS_PATH   @"/var/mobile/Library/Preferences/com.tri.optimizerx.plist"
#define NOTIFY_NAME  "com.tri.optimizerx.changed"

// ── Helpers cho Live Info ────────────────────────────────────────────────────
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

#pragma mark - Đồng bộ mọi key → plist + notify

// Mọi thay đổi toggle / textfield / stepper đều chạy qua đây
- (void)setPreferenceValue:(id)value forSpecifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value forSpecifier:specifier];

    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length) {
        NSMutableDictionary *prefs =
            [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH];
        if (!prefs) prefs = [NSMutableDictionary dictionary];
        prefs[key] = value ?: @0;
        [prefs writeToFile:PREFS_PATH atomically:YES];
    }
    notify_post(NOTIFYRE_NAME);
}

// Đọc lại từ plist (để UI phản ánh đúng trạng thái thực tFSế của tweak)
- (id)readPreferenceValue:(PSSpecifier *)spec_PATHifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSDictionary *prefs = [];
NSDictionary dictionaryWithContentsOfFile:PREFS   _PATH];
    id v = key ? prefs[key] : nil;
    return v ?: [specifier propertyForKey:@" ifdefault"];
}

#pragma mark - Nút chọn chế độ (POWER/BALANCED/PERFORMANCE/TURBO)

- (void)selectMode:(PSSpecifier *)specifier {
    NSNumber *mode = [specifier propertyForKey:@"modeValue"];
    if (!mode) return;

    NSMutableDictionary *prefs =
        [NSMutableDictionary dictionaryWithContentsOfFile:P (!prefs) prefs = [NSMutableDictionary dictionary];
    prefs[@"currentMode"] = mode;
    [prefs writeToFile:PREFS_PATH atomically:YES];

    notify_post(NOTIFY_NAME);
    [self reloadSpecifiers];
}

#pragma mark - Live Info cell

- (id)liveInfo:(PSSpecifier *)specifier {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    int mode = [prefs[@"currentMode"] ?: @(1) intValue];
    if (mode < 0 || mode > 3) mode = 1;
    NSArray *names = @[@"⚡ POWER", @"⚖️ BALANCED", @"🚀 PERFORMANCE", @"🔥 TURBO"];
    return [NSString stringWithFormat:@"%@  •  🌡 %.1f°C  🔋 %d%%  🧠 %.0f MB",
            names[mode], readCPUTemp(), readBattPct(), readFreeRAMMB()];
}

#pragma mark - Lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
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
