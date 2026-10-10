// ═══════════════════════════════════════════════════════════════════════════
// Tối ưu toàn hệ thống VAN TRUC IOS
// ═══════════════════════════════════════════════════════════════════════════
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <IOKit/IOKitLib.h>
#import <notify.h>
#import <objc/runtime.h>
#import <dirent.h>
#import <unistd.h>
#import <pthread.h>
#import <spawn.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <resolv.h>
#import <netdb.h>

extern char **environ;

// ═══ Wrapper thay thế system() vì iOS 16.5 block ═══
static int safe_system(const char *cmd) {
    if (!cmd) return -1;
    pid_t pid = fork();
    if (pid == 0) {
        execl("/bin/sh", "sh", "-c", cmd, NULL);
        _exit(127);
    }
    if (pid < 0) return -1;
    int status;
    waitpid(pid, &status, 0);
    return status;
}

#define PREFS_PATH   @"/var/mobile/Library/Preferences/com.tri.optimizerx.plist"
#define NOTIFY_NAME  "com.tri.optimizerx.changed"   // ✅ SYNC

// ═══ Helper lấy keyWindow không bị deprecated ═══
static UIWindow* getKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *win = [UIApplication sharedApplication].keyWindow;
    #pragma clang diagnostic pop
    return win;
}

// ═══════════════════════════════════════════════════════════════════════════
// PREFERENCES
// ═══════════════════════════════════════════════════════════════════════════
static NSMutableDictionary *gPrefs = nil;

static void loadPrefs() {
    gPrefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    if (!gPrefs) gPrefs = [NSMutableDictionary dictionary];
}
static id pref(NSString *key, id def) {
    id v = gPrefs[key];
    return v ?: def;
}
static void savePrefs() { [gPrefs writeToFile:PREFS_PATH atomically:YES]; }

// ✅ SYNC: helper clamp mode + đọc mode an toàn (tránh slider ghi float)
static int clampMode(id v) {
    int m = [v respondsToSelector:@selector(intValue)] ? [v intValue] : 1;
    if (m < 0) m = 0;
    if (m > 3) m = 3;
    return m;
}
static int currentMode(void) {
    return clampMode(pref(@"currentMode", @(1)));
}

// ✅ SYNC: khi tweak tự đổi mode → báo cho Preferences UI reload
static void setModeAndNotify(int m) {
    m = clampMode(@(m));
    gPrefs[@"currentMode"] = @(m);
    savePrefs();
    notify_post(NOTIFY_NAME);
}

// ═══════════════════════════════════════════════════════════════════════════
// HARDWARE INFO
// ═══════════════════════════════════════════════════════════════════════════
static float readCPUTemperature(void) {
    int thermalLevel = 0;
    size_t size = sizeof(thermalLevel);
    if (sysctlbyname("machdep.xcpm.cpu_thermal_level", &thermalLevel, &size, NULL, 0) == 0)
        return 30.0f + (thermalLevel * 0.5f);
    return -1;
}

static int readBatteryLevel(void) {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    return (int)([UIDevice currentDevice].batteryLevel * 100);
}

static float readFreeRAM(void) {
    mach_port_t host = mach_host_self();
    vm_size_t pageSize;
    host_page_size(host, &pageSize);
    vm_statistics64_data_t vmStats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vmStats, &count) == KERN_SUCCESS)
        return (vmStats.free_count * pageSize) / (1024.0 * 1024.0);
    return -1;
}

// ═══════════════════════════════════════════════════════════════════════════
// CLEANING
// ═══════════════════════════════════════════════════════════════════════════
static unsigned long long folderSize(NSString *path) {
    unsigned long long total = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *file in [fm contentsOfDirectoryAtPath:path error:nil]) {
        NSString *full = [path stringByAppendingPathComponent:file];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
        if (attrs) {
            if ([attrs[NSFileType] isEqualToString:NSFileTypeDirectory])
                total += folderSize(full);
            else
                total += [attrs[NSFileSize] unsignedLongLongValue];
        }
    }
    return total;
}

static unsigned long long cleanFolder(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return 0;
    unsigned long long freed = folderSize(path);
    for (NSString *file in [fm contentsOfDirectoryAtPath:path error:nil])
        [fm removeItemAtPath:[path stringByAppendingPathComponent:file] error:nil];
    return freed;
}

static unsigned long long cleanAllCache(void) {
    unsigned long long total = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appDir = @"/var/mobile/Containers/Data/Application";
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:appDir error:nil])
        total += cleanFolder([NSString stringWithFormat:@"%@/%@/Library/Caches", appDir, uuid]);
    total += cleanFolder(@"/var/mobile/Library/Logs/CrashReporter");
    total += cleanFolder(@"/var/jb/var/mobile/Library/Logs/CrashReporter");
    total += cleanFolder(@"/var/mobile/Library/Logs/DiagnosticReports");
    total += cleanFolder(@"/var/jb/var/log");
    total += cleanFolder(@"/tmp");
    total += cleanFolder(@"/var/tmp");
    total += cleanFolder(@"/var/mobile/tmp");
    total += cleanFolder(NSTemporaryDirectory());
    total += cleanFolder(@"/var/mobile/Library/Caches/com.apple.WebKit.Networking");
    total += cleanFolder(@"/var/mobile/Library/Caches/com.apple.WebKit.WebContent");
    total += cleanFolder(@"/var/mobile/Library/Caches/com.apple.mobilesafari");
    total += cleanFolder(@"/var/mobile/Library/Caches/GeoServices");
    return total;
}

// ═══════════════════════════════════════════════════════════════════════════
// KILL BACKGROUND
// ═══════════════════════════════════════════════════════════════════════════
static int killBackgroundApps(void) {
    NSArray *protectedApps = @[@"SpringBoard", @"backboardd", @"mediaserverd",
                               @"configd", @"UserEventAgent", @"launchd",
                               @"notificationd", @"wifid", @"CommCenter",
                               @"runningboardd", @"assertiond", @"apsd"];
    FILE *fp = popen("ps -A -o pid,comm", "r");
    if (!fp) return 0;
    char line[512];
    int killed = 0;
    while (fgets(line, sizeof(line), fp)) {
        NSString *s = [NSString stringWithUTF8String:line];
        BOOL skip = NO;
        for (NSString *p in protectedApps) if ([s containsString:p]) { skip = YES; break; }
        if (skip) continue;
        if ([s containsString:@"Containers/Bundle/Application"] ||
            [s containsString:@"/var/containers"]) {
            NSArray *parts = [s componentsSeparatedByString:@" "];
            if (parts.count > 0) {
                NSString *cmd = [NSString stringWithFormat:@"kill -9 %@ 2>/dev/null", parts[0]];
                safe_system([cmd UTF8String]);
                killed++;
            }
        }
    }
    pclose(fp);
    return killed;
}

// ═══════════════════════════════════════════════════════════════════════════
// NETWORK
// ═══════════════════════════════════════════════════════════════════════════
static void optimizeNetwork(void) {
    safe_system("/usr/bin/dscacheutil -flushcache 2>/dev/null");
    safe_system("/usr/bin/killall -HUP mDNSResponder 2>/dev/null");
    safe_system("echo 'nameserver 1.1.1.1' > /etc/resolv.conf 2>/dev/null");
    safe_system("echo 'nameserver 1.0.0.1' >> /etc/resolv.conf 2>/dev/null");
    safe_system("echo 'nameserver 8.8.8.8' >> /etc/resolv.conf 2>/dev/null");
    safe_system("sysctl -w net.inet.tcp.delayed_ack=0 2>/dev/null");
    safe_system("sysctl -w net.inet.tcp.mssdflt=1460 2>/dev/null");
    safe_system("sysctl -w net.inet.tcp.sendspace=262144 2>/dev/null");
    safe_system("sysctl -w net.inet.tcp.recvspace=262144 2>/dev/null");
    safe_system("killall -HUP configd 2>/dev/null");
    NSLog(@"[OptimizerX] Network optimized");
}

static void restoreNetwork(void) {
    safe_system("rm -f /etc/resolv.conf 2>/dev/null");
    safe_system("killall -HUP configd 2>/dev/null");
}

// ═══════════════════════════════════════════════════════════════════════════
// PERFORMANCE TUNING
// ═══════════════════════════════════════════════════════════════════════════

// ✅ SYNC: thêm smoothScroll
static void applySmoothTouch(void) {
    if ([pref(@"reduceMotion", @(YES)) boolValue]) {
        safe_system("defaults write com.apple.Accessibility ReduceMotionEnabled -bool YES 2>/dev/null");
    }
    if ([pref(@"fastAnimation", @(YES)) boolValue]) {
        UIWindow *win = getKeyWindow();
        if (win) win.layer.speed = 1.5f;
    }
    if ([pref(@"smoothScroll", @(YES)) boolValue]) {
        safe_system("defaults write -g NSAutoscrollEnabled -bool YES 2>/dev/null");
        safe_system("defaults write com.apple.UIKit UIScrollViewDecelerationRateFast -bool YES 2>/dev/null");
    }
    NSLog(@"[OptimizerX] Smooth touch applied");
}

static void restoreSmoothTouch(void) {
    UIWindowf *win = getKeyWindow();
    if (win) win.layer.speed = 1.0;
    safe_system("defaults write com.apple.Accessibility ReduceMotionEnabled -bool NO 2>/dev/null");
    safe_system("defaults delete -g NSAutoscrollEnabled 2>/dev/null");
    safe_system("defaults delete com.apple.UIKit UIScrollViewDecelerationRateFast 2>/dev/null");
    NSLog(@"[OptimizerX] Smooth touch restored");
}

static void disableBackgroundRefresh(void) {
    NSArray *bgDaemons = @[
        @"com.apple.siri.media-indexer", @"com.apple.photoanalysisd",
        @"com.apple.parsecd", @"com.apple.suggestd",
        @"com.apple.duetexpertd", @"com.apple.assistantd",
        @"com.apple.assistanced", @"com.apple.proactiveeventtrackerd",
        @"com.apple.spotlightknowledged.updater"
    ];
    for (NSString *d in bgDaemons)
        safe_system([[NSString stringWithFormat:@"launchctl stop %@ 2>/dev/null", d] UTF8String]);
    NSLog(@"[OptimizerX] Background daemons disabled");
}

static int gPreferredFPS = 60;
static void applyFPSLimit(int fps) {
    gPreferredFPS = fps;
    NSLog(@"[OptimizerX] FPS target = %d", fps);
}

static void applyCPUTuning(int mode) {
    mode = clampMode(@(mode));   // ✅ SYNC
    switch (mode) {
        case 0:
            safe_system("sysctl -w machdep.xcpm.cpu_thermal_level=8 2>/dev/null");
            safe_system("sysctl -w machdep.xcpm.gpu_thermal_level=8 2>/dev/null");
            safe_system("sysctl -w kern.thermal_throttle=2 2>/dev/null");
            applyFPSLimit(20);
            break;
        case 1:
            safe_system("sysctl -w machdep.xcpm.cpu_thermal_level=4 2>/dev/null");
            safe_system("sysctl -w machdep.xcpm.gpu_thermal_level=4 2>/dev/null");
            safe_system("sysctl -w kern.thermal_throttle=1 2>/dev/null");
            applyFPSLimit(30);
            break;
        case 2:
            safe_system("sysctl -w machdep.xcpm.cpu_thermal_level=2 2>/dev/null");
            safe_system("sysctl -w machdep.xcpm.gpu_thermal_level=2 2>/dev/null");
            safe_system("sysctl -w kern.thermal_throttle=0 2>/dev/null");
            applyFPSLimit(60);
            break;
        case 3:
            safe_system("sysctl -w machdep.xcpm.cpu_thermal_level=0 2>/dev/null");
            safe_system("sysctl -w machdep.xcpm.gpu_thermal_level=0 2>/dev/null");
            safe_system("sysctl -w kern.thermal_throttle=0 2>/dev/null");
            applyFPSLimit(60);
            break;
    }
    NSLog(@"[OptimizerX] CPU mode = %d, FPS = %d", mode, gPreferredFPS);
}

// ═══════════════════════════════════════════════════════════════════════════
// GUARDS
// ═══════════════════════════════════════════════════════════════════════════
static bool gBatteryGuardActive = false;
static int  gSavedMode = 1;
static time_t gLastAutoClean = 0;

static void checkThermalState(void) {
    if (![pref(@"thermalAction", @(YES)) boolValue]) return;
    NSProcessInfoThermalState state = [[NSProcessInfo processInfo] thermalState];
    float sysTemp = readCPUTemperature();
    if (state == NSProcessInfoThermalStateSerious ||
        state == NSProcessInfoThermalStateCritical ||
        sysTemp > 48.0f) {
        int cur = currentMode();
        if (cur != 0 && !gBatteryGuardActive) {
            gSavedMode = cur;
            setModeAndNotify(0);          // ✅ SYNC: báo UI
            applyCPUTuning(0);
            NSLog(@"[OptimizerX] Cool down → Power Save");
        }
    }
}

static void applyMode(int mode) {
    mode = clampMode(@(mode));            // ✅ SYNC

    applySmoothTouch();
    disableBackgroundRefresh();
    applyCPUTuning(mode);

    switch (mode) {
        case 0:
            NSLog(@"[OptimizerX] POWER SAVE — FPS 20, CPU low");
            break;
        case 1:
            NSLog(@"[OptimizerX] BALANCED — FPS 30");
            break;
        case 2:
            killBackgroundApps();
            cleanAllCache();
            safe_system("renice -10 -p $(pgrep -f SpringBoard) 2>/dev/null");
            NSLog(@"[OptimizerX] PERFORMANCE — FPS 60");
            break;
        case 3:
            killBackgroundApps();
            cleanAllCache();
            safe_system("renice -20 -p $(pgrep -f SpringBoard) 2>/dev/null");
            NSLog(@"[OptimizerX] TURBO — FPS 60, no throttle");
            break;
    }
    // Lưu lại nhưng KHÔNG notify (tránh vòng lặp notify từ notify handler)
    gPrefs[@"currentMode"] = @(mode);
    savePrefs();
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTO
// ═══════════════════════════════════════════════════════════════════════════
static void checkAutoClean(void) {
    if (![pref(@"autoClean", @(NO)) boolValue]) return;
    int interval = [pref(@"autoCleanInterval", @(3600)) intValue];
    if (interval < 60) interval = 60;     // an toàn nếu slider ghi sai
    if (time(NULL) - gLastAutoClean >= interval) {
        cleanAllCache();
        gLastAutoClean = time(NULL);
        NSLog(@"[OptimizerX] Auto clean done");
    }
}

static void checkBatteryGuard(void) {
    if (![pref(@"batteryGuard", @(YES)) boolValue]) return;
    int batt = readBatteryLevel();
    float temp = readCPUTemperature();
    int bTh = [pref(@"batteryThreshold", @(20)) intValue];
    int tTh = [pref(@"tempThreshold", @(45)) intValue];
    bool should = (batt > 0 && batt < bTh) || (temp > tTh);

    if (should && !gBatteryGuardActive) {
        gBatteryGuardActive = true;
        gSavedMode = currentMode();
        setModeAndNotify(0);              // ✅ SYNC: báo UI
        applyCPUTuning(0);
        NSLog(@"[OptimizerX] Battery Guard ON");
    } else if (!should && gBatteryGuardActive) {
        gBatteryGuardActive = false;
        setModeAndNotify(gSavedMode);     // ✅ SYNC: báo UI
        applyCPUTuning(gSavedMode);
        NSLog(@"[OptimizerX] Battery Guard OFF");
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// FPS TRACKER
// ═══════════════════════════════════════════════════════════════════════════
static int gFrameCount = 0;
static double gLastFPSTime = 0;
static int gCurrentFPS = 0;
static void tickFPS(void) {
    gFrameCount++;
    double now = CACurrentMediaTime();
    if (gLastFPSTime == 0) gLastFPSTime = now;
    if (now - gLastFPSTime >= 1.0) {
        gCurrentFPS = gFrameCount;
        gFrameCount = 0;
        gLastFPSTime = now;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HUD
// ═══════════════════════════════════════════════════════════════════════════
@interface OptHUD : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) CADisplayLink *link;
@end

@implementation OptHUD
+ (instancetype)shared {
    static OptHUD *hud;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ hud = [[OptHUD alloc] init]; });
    return hud;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(10, 120, 170, 105)];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    self.layer.cornerRadius = 10;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [UIColor colorWithRed:1 green:0.4 blue:0.1 alpha:0.8].CGColor;
    self.userInteractionEnabled = NO;
    _label = [[UILabel alloc] initWithFrame:self.bounds];
    _label.numberOfLines = 0;
    _label.textColor = [UIColor whiteColor];
    _label.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightBold];
    _label.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_label];
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateHUD)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    return self;
}
- (void)updateHUD {
    tickFPS();
    int mode = currentMode();                          // ✅ SYNC: clamp
    NSArray *names = @[@"⚡POWER", @"⚖️BAL", @"🚀PERF", @"🔥TURBO"]; // giữ style HUD ngắn
    _label.text = [NSString stringWithFormat:
        @"%@\n🌡 %.1f°C  📊 %d FPS\n🔋 %d%%  🧠 %.0fMB",
        names[mode], readCPUTemperature(), gCurrentFPS,
        readBatteryLevel(), readFreeRAM()];
}
- (void)show {
    UIWindow *win = getKeyWindow();
    if (win && !self.superview) [win addSubview:self];
}
- (void)hide { [self removeFromSuperview]; }
@end

// ═══════════════════════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════════════════════
__attribute__((constructor))
static void initOptimizerX(void) {
    loadPrefs();
    NSLog(@"[OptimizerX] Loaded");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        applyMode(currentMode());                      // ✅ SYNC
        if ([pref(@"optimizeNetwork", @(NO)) boolValue]) optimizeNetwork();
        if ([pref(@"showHUD", @(NO)) boolValue]) [[OptHUD shared] show];

        [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(NSTimer *t) {
            checkBatteryGuard();
            checkAutoClean();
            checkThermalState();
        }];
    });

    notify_register_dispatch(NOTIFY_NAME, NULL,               // ✅ SYNC hằng số
                             dispatch_get_main_queue(), ^(int token) {
        NSDictionary *old = [gPrefs copy];
        loadPrefs();

        // ✅ SYNC: nếu 3 toggle smooth thay đổi → restore khi tắt hết
        BOOL oldSmooth = [old[@"reduceMotion"] boolValue] ||
                         [old[@"fastAnimation"] boolValue] ||
                         [old[@"smoothScroll"] boolValue];
        BOOL newSmooth = [pref(@"reduceMotion", @(YES)) boolValue] ||
                         [pref(@"fastAnimation", @(YES)) boolValue] ||
                         [pref(@"smoothScroll", @(YES)) boolValue];
        if (oldSmooth && !newSmooth) restoreSmoothTouch();

        applyMode(currentMode());

        bool oldNet = [old[@"optimizeNetwork"] boolValue];
        bool newNet = [pref(@"optimizeNetwork", @(NO)) boolValue];
        if (oldNet != newNet) {
            if (newNet) optimizeNetwork();
            else        restoreNetwork();
        }

        if ([pref(@"showHUD", @(NO)) boolValue]) [[OptHUD shared] show];
        else                                     [[OptHUD shared] hide];
    });
}
