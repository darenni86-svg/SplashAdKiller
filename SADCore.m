//
//  SADCore.m
//  SplashAdKiller
//

#import "SADCore.h"
#import <QuartzCore/QuartzCore.h>
#import <os/log.h>

static NSString *const SADPreferencesDomain = @"com.dsh.splashadkiller";
static CFTimeInterval SADProcessStartTime = 0;
static UIWindow *SADBannerWindow = nil;

#pragma mark - 日志

static os_log_t SADLogHandle(void) {
    static os_log_t handle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = os_log_create("com.dsh.splashadkiller", "core");
    });
    return handle;
}

static void SADLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

static void SADLog(NSString *format, ...) {
    if (![SADCore shared].config.verboseLog) {
        return;
    }
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    os_log(SADLogHandle(), "[SAD] %{public}@", message);
}

static NSMutableString *SADDiagBuffer(void) {
    static NSMutableString *buffer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        buffer = [NSMutableString string];
    });
    return buffer;
}

static void SADClearDiag(void) {
    NSMutableString *buffer = SADDiagBuffer();
    @synchronized (buffer) {
        [buffer setString:@""];
    }
}

static void SADDiag(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

static void SADDiag(NSString *format, ...) {
    if (![SADCore shared].config.logToFile) {
        return;
    }
    if (SADProcessStartTime <= 0) {
        SADProcessStartTime = CACurrentMediaTime();
    }
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    NSMutableString *buffer = SADDiagBuffer();
    @synchronized (buffer) {
        [buffer appendFormat:@"%7.2f  %@\n", CACurrentMediaTime() - SADProcessStartTime, line];
    }
}

static void SADFlushDiag(void) {
    NSMutableString *buffer = SADDiagBuffer();
    NSString *text = nil;
    @synchronized (buffer) {
        text = [buffer copy];
    }
    if (text.length == 0) {
        return;
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:SADPreferencesDomain];
    [defaults setObject:text forKey:@"DiagnosticLog"];
    [defaults synchronize];
}

#pragma mark - 配置

static BOOL SADBoolValue(NSDictionary *preferences, NSString *key, BOOL fallback) {
    id value = preferences[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *lowercase = [(NSString *)value lowercaseString];
        return [lowercase isEqualToString:@"1"] ||
               [lowercase isEqualToString:@"true"] ||
               [lowercase isEqualToString:@"yes"] ||
               [lowercase isEqualToString:@"on"];
    }
    return fallback;
}

static double SADDoubleValue(NSDictionary *preferences, NSString *key, double fallback) {
    id value = preferences[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value doubleValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value doubleValue];
    }
    return fallback;
}

static NSArray<NSString *> *SADStringArrayValue(NSDictionary *preferences, NSString *key) {
    id value = preferences[key];
    NSMutableArray<NSString *> *result = [NSMutableArray array];

    if ([value isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)value) {
            if ([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0) {
                [result addObject:item];
            }
        }
        return result;
    }

    if ([value isKindOfClass:[NSString class]]) {
        NSCharacterSet *separators =
            [NSCharacterSet characterSetWithCharactersInString:@",，;；\n "];
        for (NSString *piece in [(NSString *)value componentsSeparatedByCharactersInSet:separators]) {
            NSString *trimmed =
                [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [result addObject:trimmed];
            }
        }
    }
    return result;
}

@implementation SADConfig

+ (instancetype)loadFromPreferences {
    SADConfig *config = [[SADConfig alloc] init];
    config.enabled = YES;
    config.autoSkip = YES;
    config.blockControllers = YES;
    config.maskAdContent = YES;
    config.hotStart = YES;
    config.verboseLog = NO;
    config.blockShake = YES;
    config.blockAdJump = YES;
    config.logToFile = YES;
    config.copyDiagnostics = YES;
    config.diagnosticBundles = @[@"com.tencent.live4iphone"];
    config.launchWindow = 12.0;
    config.extraKeywords = @[];
    config.disabledBundles = @[];
    config.enabledBundles = @[];

    NSDictionary *preferences = nil;

    CFPropertyListRef copied = CFPreferencesCopyMultiple(
        NULL, (__bridge CFStringRef)SADPreferencesDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (copied) {
        if (CFGetTypeID(copied) == CFDictionaryGetTypeID()) {
            preferences = (__bridge_transfer NSDictionary *)copied;
        } else {
            CFRelease(copied);
        }
    }

    if (preferences.count == 0) {
        NSString *path = [@"/var/mobile/Library/Preferences"
            stringByAppendingPathComponent:[SADPreferencesDomain stringByAppendingPathExtension:@"plist"]];
        NSDictionary *filePreferences = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([filePreferences isKindOfClass:[NSDictionary class]]) {
            preferences = filePreferences;
        }
    }

    if (![preferences isKindOfClass:[NSDictionary class]]) {
        preferences = @{};
    }

    config.enabled = SADBoolValue(preferences, @"Enabled", config.enabled);
    config.autoSkip = SADBoolValue(preferences, @"AutoSkip", config.autoSkip);
    config.blockControllers = SADBoolValue(preferences, @"BlockControllers", config.blockControllers);
    config.maskAdContent = SADBoolValue(preferences, @"MaskAdContent", config.maskAdContent);
    config.hotStart = SADBoolValue(preferences, @"HotStart", config.hotStart);
    config.verboseLog = SADBoolValue(preferences, @"VerboseLog", config.verboseLog);
    config.blockShake = SADBoolValue(preferences, @"BlockShake", config.blockShake);
    config.blockAdJump = SADBoolValue(preferences, @"BlockAdJump", config.blockAdJump);
    config.logToFile = SADBoolValue(preferences, @"LogToFile", config.logToFile);
    config.copyDiagnostics = SADBoolValue(preferences, @"CopyDiagnostics", config.copyDiagnostics);
    config.diagnosticBundles = SADStringArrayValue(preferences, @"DiagnosticBundles");
    if (config.diagnosticBundles.count == 0) {
        config.diagnosticBundles = @[@"com.tencent.live4iphone"];
    }
    config.launchWindow = SADDoubleValue(preferences, @"LaunchWindow", config.launchWindow);
    config.extraKeywords = SADStringArrayValue(preferences, @"ExtraKeywords");
    config.disabledBundles = SADStringArrayValue(preferences, @"DisabledBundles");
    config.enabledBundles = SADStringArrayValue(preferences, @"EnabledBundles");

    if (config.launchWindow < 3.0) {
        config.launchWindow = 3.0;
    }
    if (config.launchWindow > 30.0) {
        config.launchWindow = 30.0;
    }

    return config;
}

@end

#pragma mark - 类名匹配

static NSString *SADNormalized(NSString *text) {
    if (text.length == 0) {
        return @"";
    }
    NSMutableString *result = [NSMutableString stringWithCapacity:text.length];
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if (character >= 'A' && character <= 'Z') {
            character = (unichar)(character - 'A' + 'a');
        }
        if ((character >= 'a' && character <= 'z') || (character >= '0' && character <= '9')) {
            [result appendFormat:@"%C", character];
        }
    }
    return result;
}

static NSArray<NSString *> *SADBaseKeywords(void) {
    static NSArray<NSString *> *keywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keywords = @[
            @"splashad", @"adsplash", @"splashadvert",
            @"launchad", @"adlaunch", @"launchadvert",
            @"openscreenad", @"openingscreenad", @"openingad",
            @"bootad", @"startupad", @"welcomead",
            @"busplash", @"gdtsplash", @"kssplash", @"sigsplash",
            @"mtgsplash", @"hwsplash", @"misplash", @"panglesplash",
            // 腾讯系
            @"tadsplash", @"tadlaunch", @"tadvideo", @"gdtlaunch",
            @"qnlaunch", @"tvklaunch", @"qqlivead", @"qntvad", @"tencentad",
            // 酷狗系
            @"kugouad", @"kglaunch",
        ];
    });
    return keywords;
}

static NSArray<NSString *> *SADExcludedKeywords(void) {
    static NSArray<NSString *> *keywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keywords = @[
            @"config", @"manager", @"request", @"loader", @"cache",
            @"report", @"tracker", @"helper", @"adapter", @"delegate",
            @"model", @"monitor", @"setting", @"preference", @"network",
            @"parser", @"service",
        ];
    });
    return keywords;
}

static BOOL SADNameMatchesUncached(NSString *className, SADConfig *config) {
    if (className.length == 0) {
        return NO;
    }

    NSString *normalized = SADNormalized(className);
    if (normalized.length < 5) {
        return NO;
    }

    for (NSString *keyword in SADBaseKeywords()) {
        if ([normalized containsString:keyword]) {
            return YES;
        }
    }

    for (NSString *keyword in config.extraKeywords) {
        NSString *normalizedKeyword = SADNormalized(keyword);
        if (normalizedKeyword.length >= 3 && [normalized containsString:normalizedKeyword]) {
            return YES;
        }
    }

    if ([normalized containsString:@"splash"] && [normalized containsString:@"ad"]) {
        return YES;
    }

    return NO;
}

static BOOL SADNameMatches(NSString *className, SADConfig *config) {
    if (className.length == 0) {
        return NO;
    }
    if (![NSThread isMainThread]) {
        return SADNameMatchesUncached(className, config);
    }

    static NSMutableDictionary<NSString *, NSNumber *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });

    NSNumber *cached = cache[className];
    if (cached != nil) {
        return cached.boolValue;
    }

    BOOL matched = SADNameMatchesUncached(className, config);
    cache[className] = @(matched);
    return matched;
}

static BOOL SADNameIsExcluded(NSString *className) {    NSString *normalized = SADNormalized(className);
    for (NSString *keyword in SADExcludedKeywords()) {
        if ([normalized containsString:keyword]) {
            return YES;
        }
    }
    return NO;
}

static BOOL SADIsDiagnosticBundle(NSString *bundleIdentifier, NSArray<NSString *> *list) {
    if (bundleIdentifier.length == 0) {
        return NO;
    }
    if ([bundleIdentifier hasPrefix:@"com.tencent."]) {
        return YES;
    }
    return [list containsObject:bundleIdentifier];
}

#pragma mark - 文案与视图

static BOOL SADIsSkipText(NSString *text) {
    if (text.length == 0) {
        return NO;
    }
    NSString *lowercase = text.lowercaseString;
    if ([lowercase containsString:@"跳过"] || [lowercase containsString:@"跳過"]) {
        return YES;
    }
    if ([lowercase containsString:@"关闭广告"] || [lowercase containsString:@"關閉廣告"]) {
        return YES;
    }
    if ([lowercase containsString:@"skip"]) {
        return YES;
    }
    return NO;
}

static void SADAppendLabelText(UIView *view, NSMutableString *buffer, NSInteger depth) {
    if (depth > 3) {
        return;
    }
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length > 0) {
            [buffer appendString:label.text];
        }
    }
    for (UIView *subview in view.subviews) {
        SADAppendLabelText(subview, buffer, depth + 1);
    }
}

static NSString *SADTextFromControl(UIControl *control) {
    NSMutableString *buffer = [NSMutableString string];

    if ([control isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)control;
        NSString *title = [button titleForState:UIControlStateNormal];
        if (title.length > 0) {
            [buffer appendString:title];
        }
        NSString *currentTitle = [button titleForState:button.state];
        if (currentTitle.length > 0) {
            [buffer appendString:currentTitle];
        }
        if (button.titleLabel.text.length > 0) {
            [buffer appendString:button.titleLabel.text];
        }
        NSAttributedString *attributed = [button attributedTitleForState:UIControlStateNormal];
        if (attributed.string.length > 0) {
            [buffer appendString:attributed.string];
        }
    }

    if (control.accessibilityLabel.length > 0) {
        [buffer appendString:control.accessibilityLabel];
    }
    if (control.accessibilityIdentifier.length > 0) {
        [buffer appendString:control.accessibilityIdentifier];
    }

    SADAppendLabelText(control, buffer, 0);
    return buffer;
}

static UIControl *SADEnclosingControl(UIView *view) {
    UIView *current = view;
    NSInteger depth = 0;
    while (current && depth < 8) {
        if ([current isKindOfClass:[UIControl class]]) {
            return (UIControl *)current;
        }
        current = current.superview;
        depth++;
    }
    return nil;
}

static BOOL SADContainsSkipControl(UIView *view, NSInteger depth) {
    if (depth > 5) {
        return NO;
    }
    if ([view isKindOfClass:[UIControl class]] &&
        SADIsSkipText(SADTextFromControl((UIControl *)view))) {
        return YES;
    }
    for (UIView *subview in view.subviews) {
        if (SADContainsSkipControl(subview, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL SADViewIsInsideAdContainer(UIView *view, SADConfig *config) {
    UIView *current = view;
    NSInteger depth = 0;
    while (current && depth < 14) {
        if (SADNameMatches(NSStringFromClass(current.class), config)) {
            return YES;
        }
        current = current.superview;
        depth++;
    }
    return NO;
}

/// 有些 App 的「跳过」是 UILabel + UITapGestureRecognizer，只能直接触发手势的 target/action。
static BOOL SADTriggerTapGesture(UIView *view) {
    NSArray<UIGestureRecognizer *> *gestures = view.gestureRecognizers;
    if (gestures.count == 0 && view.superview != nil) {
        gestures = view.superview.gestureRecognizers;
    }

    for (UIGestureRecognizer *gesture in gestures) {
        if (![gesture isKindOfClass:[UITapGestureRecognizer class]]) {
            continue;
        }
        @try {
            NSArray *targets = [gesture valueForKey:@"_targets"];
            for (id container in targets) {
                id target = [container valueForKey:@"_target"];
                NSString *actionName = [container valueForKey:@"_action"];
                SEL action = NSSelectorFromString(actionName);
                if (target != nil && action != NULL && [target respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [target performSelector:action withObject:gesture];
#pragma clang diagnostic pop
                    return YES;
                }
            }
        } @catch (NSException *exception) {
            (void)exception;
        }
    }
    return NO;
}

static void SADPauseVideoLayer(UIView *view) {
    CALayer *layer = view.layer;
    if (layer == nil || ![NSStringFromClass(layer.class) containsString:@"AVPlayerLayer"]) {
        return;
    }
    @try {
        id player = [layer valueForKey:@"player"];
        if (player != nil && [player respondsToSelector:@selector(pause)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [player performSelector:@selector(pause)];
#pragma clang diagnostic pop
        }
    } @catch (NSException *exception) {
        (void)exception;
    }
}

#pragma mark - SADCore

@interface SADCore ()

@property (nonatomic, strong, readwrite) SADConfig *config;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, assign) CFTimeInterval deadline;
@property (nonatomic, assign) CFTimeInterval startedAt;
@property (nonatomic, assign) CFTimeInterval lastScan;
@property (nonatomic, assign) CFTimeInterval nextSnapshot;
@property (nonatomic, assign) NSInteger clickCount;
@property (nonatomic, assign) NSInteger tickSkipCandidates;
@property (nonatomic, assign) BOOL adDetected;
@property (nonatomic, strong) NSHashTable<UIView *> *clickedControls;
@property (nonatomic, strong) NSHashTable<UIView *> *maskedViews;

- (void)stopMonitoring;
- (void)deliverDiagnosticsIfNeeded;
- (void)showInjectionBannerIfNeeded;
- (UIViewController *)topViewController;

@end

@implementation SADCore

+ (instancetype)shared {
    static SADCore *core;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        core = [[SADCore alloc] init];
    });
    return core;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _config = [SADConfig loadFromPreferences];
        _clickedControls = [NSHashTable weakObjectsHashTable];
        _maskedViews = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

#pragma mark 生命周期

+ (BOOL)isEligibleProcess {
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    if (bundleIdentifier.length == 0) {
        return NO;
    }
    if ([bundleIdentifier hasPrefix:@"com.apple."]) {
        return NO;
    }
    if (NSClassFromString(@"UIApplication") == nil ||
        NSClassFromString(@"UIViewController") == nil) {
        return NO;
    }

    SADConfig *config = [SADCore shared].config;
    if (!config.enabled) {
        return NO;
    }
    if ([config.disabledBundles containsObject:bundleIdentifier]) {
        return NO;
    }
    if (config.enabledBundles.count > 0 &&
        ![config.enabledBundles containsObject:bundleIdentifier]) {
        return NO;
    }
    return YES;
}

+ (void)install {
    SADProcessStartTime = CACurrentMediaTime();
    if ([SADCore shared].config.logToFile) {
        SADClearDiag();
        SADDiag(@"process %@", [NSBundle mainBundle].bundleIdentifier);
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        SADCore *core = [SADCore shared];
                        [core beginMonitoringWithWindow:core.config.launchWindow reason:@"launch"];
                    }];

    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        SADCore *core = [SADCore shared];
                        if (!core.config.hotStart || core.timer != nil) {
                            return;
                        }
                        [core beginMonitoringWithWindow:MIN(6.0, core.config.launchWindow)
                                                 reason:@"foreground"];
                    }];

    [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        SADCore *core = [SADCore shared];
                        [core stopMonitoring];
                        SADFlushDiag();
                    }];

    [[SADCore shared] showInjectionBannerIfNeeded];
}

#pragma mark 监听

- (void)beginMonitoringWithWindow:(NSTimeInterval)window reason:(NSString *)reason {
    if (!self.config.enabled) {
        return;
    }
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self beginMonitoringWithWindow:window reason:reason];
        });
        return;
    }

    self.startedAt = CACurrentMediaTime();
    self.deadline = self.startedAt + MAX(window, 1.0);

    if (self.timer != nil) {
        SADLog(@"延长监听窗口 (%@)", reason);
        return;
    }

    self.clickCount = 0;
    self.tickSkipCandidates = 0;
    self.adDetected = NO;
    self.nextSnapshot = 0.8;
    self.lastScan = 0;
    [self.clickedControls removeAllObjects];
    [self.maskedViews removeAllObjects];

    self.timer = [NSTimer timerWithTimeInterval:0.1
                                         target:self
                                       selector:@selector(handleTick)
                                       userInfo:nil
                                        repeats:YES];
    self.timer.tolerance = 0.02;
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];

    SADDiag(@"monitor start (%@, %.0fs)", reason, window);
}

- (void)stopMonitoring {
    if (self.timer == nil) {
        return;
    }
    [self.timer invalidate];
    self.timer = nil;
    SADDiag(@"monitor stop clicks=%ld ad=%d", (long)self.clickCount, self.adDetected);
    SADFlushDiag();
    [self deliverDiagnosticsIfNeeded];
}

- (UIViewController *)topViewController {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    if (keyWindow == nil) {
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
    }
    UIViewController *controller = keyWindow.rootViewController;
    NSInteger depth = 0;
    while (controller.presentedViewController != nil && depth < 6) {
        controller = controller.presentedViewController;
        depth++;
    }
    return controller;
}

- (void)deliverDiagnosticsIfNeeded {
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    if (!SADIsDiagnosticBundle(bundleIdentifier, self.config.diagnosticBundles)) {
        return;
    }

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:SADPreferencesDomain];
    NSString *log = [defaults stringForKey:@"DiagnosticLog"];
    if (log.length > 0) {
        [UIPasteboard generalPasteboard].string = log;
    }

    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIViewController *top = [self topViewController];
        if (top == nil) {
            return;
        }
        NSString *message = log.length > 0
            ? [NSString stringWithFormat:@"日志已复制到剪贴板（%lu 字），直接粘贴发送就行。",
                                         (unsigned long)log.length]
            : @"没有生成日志：要么插件没注入，要么日志写入失败。请把这条提示截图发我。";
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:
                                    [NSString stringWithFormat:@"SAD 诊断 · %@", bundleIdentifier]
                                                message:message
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

- (void)showInjectionBannerIfNeeded {
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    if (!SADIsDiagnosticBundle(bundleIdentifier, self.config.diagnosticBundles)) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        window.windowLevel = UIWindowLevelAlert + 1;
        window.backgroundColor = [UIColor clearColor];
        window.rootViewController = [[UIViewController alloc] init];
        window.rootViewController.view.backgroundColor = [UIColor clearColor];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 54,
                                                                   window.bounds.size.width - 32, 36)];
        label.backgroundColor = [UIColor colorWithRed:0.85 green:0.10 blue:0.10 alpha:0.94];
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont boldSystemFontOfSize:12];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        label.layer.cornerRadius = 8;
        label.clipsToBounds = YES;
        label.text = [NSString stringWithFormat:@"SAD 已注入 %@", bundleIdentifier];

        [window.rootViewController.view addSubview:label];
        window.hidden = NO;
        SADBannerWindow = window;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            window.hidden = YES;
            SADBannerWindow = nil;
        });
    });
}

- (void)handleTick {
    if (!self.config.enabled) {
        [self stopMonitoring];
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (now > self.deadline) {
        [self stopMonitoring];
        return;
    }

    CFTimeInterval elapsed = now - self.startedAt;
    // 8 秒内什么都没发现，就没必要继续扫了，省得拖慢 App。
    if (elapsed > 8.0 && !self.adDetected && self.clickCount == 0) {
        [self stopMonitoring];
        return;
    }

    CFTimeInterval interval = elapsed < 2.5 ? 0.15 : 0.45;
    if (now - self.lastScan < interval) {
        return;
    }
    self.lastScan = now;

    self.tickSkipCandidates = 0;
    @try {
        [self scanVisibleWindows];
    } @catch (NSException *exception) {
        SADDiag(@"scan exception %@", exception.reason);
    }

    if (elapsed >= self.nextSnapshot) {
        SADDiag(@"t=%.1f top=%@ windows=%lu skip=%ld ad=%d",
                elapsed,
                [self topViewControllerName],
                (unsigned long)[UIApplication sharedApplication].windows.count,
                (long)self.tickSkipCandidates,
                self.adDetected);
        self.nextSnapshot = elapsed + 2.0;
    }
}

#pragma mark 扫描

- (void)scanVisibleWindows {
    UIApplication *application = [UIApplication sharedApplication];
    if (application == nil) {
        return;
    }

    CFTimeInterval elapsed = CACurrentMediaTime() - self.startedAt;
    NSInteger budget = elapsed < 2.5 ? 1400 : 500;

    for (UIWindow *window in application.windows) {
        if (budget <= 0) {
            break;
        }
        if (window.hidden || window.alpha < 0.02) {
            continue;
        }
        if (window.windowLevel > UIWindowLevelAlert) {
            continue;
        }

        [self scanTopViewControllerInWindow:window];
        [self scanViewTree:window budget:&budget];
    }
}

- (NSString *)topViewControllerName {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    if (keyWindow == nil) {
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
    }

    UIViewController *controller = keyWindow.rootViewController;
    NSInteger depth = 0;
    while (controller.presentedViewController != nil && depth < 6) {
        controller = controller.presentedViewController;
        depth++;
    }
    return controller != nil ? NSStringFromClass(controller.class) : @"(none)";
}

- (void)scanTopViewControllerInWindow:(UIWindow *)window {
    UIViewController *controller = window.rootViewController;
    NSInteger depth = 0;
    while (controller.presentedViewController && depth < 6) {
        controller = controller.presentedViewController;
        depth++;
    }
    if (controller == nil || controller == window.rootViewController) {
        return;
    }
    if ([SADCore shouldBlockViewController:controller]) {
        [SADCore dismissBlockedViewController:controller];
    }
}

- (void)scanViewTree:(UIView *)root budget:(NSInteger *)budget {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];

    while (stack.count > 0 && *budget > 0) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        (*budget)--;

        if (view.hidden || view.alpha < 0.02) {
            continue;
        }

        [self handleCandidateView:view];

        for (UIView *subview in view.subviews) {
            [stack addObject:subview];
        }
    }
}

- (void)handleCandidateView:(UIView *)view {
    if (self.config.autoSkip) {
        if ([view isKindOfClass:[UIControl class]]) {
            [self considerControl:(UIControl *)view];
        } else {
            [self considerAccessibilityView:view];
        }
    }
    if (self.config.maskAdContent) {
        [self maskAdContainerIfNeeded:view];
    }
}

- (void)considerControl:(UIControl *)control {
    if (self.clickCount >= 3) {
        return;
    }
    if ([self.clickedControls containsObject:control]) {
        return;
    }
    if (!control.isEnabled || control.hidden || control.alpha < 0.05) {
        return;
    }

    // 先用最便宜的方式判断，避免给每个控件都拼字符串。
    NSString *quick = control.accessibilityLabel;
    if (!SADIsSkipText(quick) && [control isKindOfClass:[UIButton class]]) {
        quick = [((UIButton *)control) titleForState:UIControlStateNormal];
    }

    if (!SADIsSkipText(quick)) {
        if (!SADViewIsInsideAdContainer(control, self.config)) {
            return;
        }
        quick = SADTextFromControl(control);
        if (!SADIsSkipText(quick)) {
            return;
        }
    }

    NSString *text = quick;

    self.tickSkipCandidates += 1;

    BOOL insideAdContainer = SADViewIsInsideAdContainer(control, self.config);
    BOOL inSkipZone = [self isControlInSkipZone:control];
    BOOL earlyStage = (CACurrentMediaTime() - self.startedAt) < 8.0;
    BOOL weakMatch = !insideAdContainer && inSkipZone && earlyStage;

    if (!insideAdContainer && !weakMatch) {
        return;
    }

    if (insideAdContainer) {
        [SADCore noteAdDetected];
    }

    [self.clickedControls addObject:control];
    self.clickCount += 1;

    SADDiag(@"click %@ text=%@ ad=%d",
            NSStringFromClass(control.class),
            text.length > 24 ? [text substringToIndex:24] : text,
            insideAdContainer);

    dispatch_async(dispatch_get_main_queue(), ^{
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
}

- (void)considerAccessibilityView:(UIView *)view {
    if (self.clickCount >= 3) {
        return;
    }

    // UILabel + 手势的「跳过」：直接触发手势的 target/action。
    if ([view isKindOfClass:[UILabel class]] && SADEnclosingControl(view) == nil) {
        UILabel *label = (UILabel *)view;
        if (SADIsSkipText(label.text) && ![self.clickedControls containsObject:view]) {
            self.tickSkipCandidates += 1;
            [self.clickedControls addObject:view];
            self.clickCount += 1;
            SADDiag(@"gesture tap %@ text=%@", NSStringFromClass(view.class), label.text);
            dispatch_async(dispatch_get_main_queue(), ^{
                SADTriggerTapGesture(view);
            });
            return;
        }
    }

    if (view.isAccessibilityElement == NO) {
        return;
    }
    if (view.accessibilityLabel.length == 0) {
        return;
    }
    if (!SADIsSkipText(view.accessibilityLabel)) {
        return;
    }
    if ([self.clickedControls containsObject:view]) {
        return;
    }
    if (SADEnclosingControl(view) != nil) {
        return;
    }

    self.tickSkipCandidates += 1;
    [self.clickedControls addObject:view];
    self.clickCount += 1;

    SADDiag(@"accessibilityActivate %@ label=%@",
            NSStringFromClass(view.class), view.accessibilityLabel);

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([view respondsToSelector:@selector(accessibilityActivate)]) {
            [view accessibilityActivate];
        }
    });
}

- (BOOL)isControlInSkipZone:(UIControl *)control {
    UIWindow *window = control.window;
    if (window == nil) {
        return NO;
    }
    CGRect frame = [control convertRect:control.bounds toView:window];
    CGSize size = window.bounds.size;
    if (size.width <= 0 || size.height <= 0 || CGRectIsEmpty(frame)) {
        return NO;
    }
    CGFloat centerX = CGRectGetMidX(frame);
    CGFloat centerY = CGRectGetMidY(frame);
    return centerY < size.height * 0.28 && centerX > size.width * 0.5;
}

- (void)maskAdContainerIfNeeded:(UIView *)view {
    if (view.bounds.size.width < 120 || view.bounds.size.height < 120) {
        return;
    }
    if (!SADNameMatches(NSStringFromClass(view.class), self.config)) {
        return;
    }
    if ([self.maskedViews containsObject:view]) {
        return;
    }
    [self.maskedViews addObject:view];
    [SADCore noteAdDetected];

    CGFloat totalArea = view.bounds.size.width * view.bounds.size.height;
    if (totalArea <= 0) {
        return;
    }

    SADDiag(@"mask %@", NSStringFromClass(view.class));

    for (UIView *subview in view.subviews) {
        CGFloat area = subview.bounds.size.width * subview.bounds.size.height;
        if (area < totalArea * 0.4) {
            continue;
        }
        if ([subview isKindOfClass:[UIControl class]]) {
            continue;
        }
        if (SADContainsSkipControl(subview, 0)) {
            continue;
        }
        SADPauseVideoLayer(subview);
        subview.alpha = 0.0;
    }
}

#pragma mark 控制器拦截

+ (BOOL)shouldBlockViewController:(UIViewController *)viewController {
    if (viewController == nil) {
        return NO;
    }
    SADConfig *config = [SADCore shared].config;
    if (!config.enabled || !config.blockControllers) {
        return NO;
    }
    if (![viewController isKindOfClass:[UIViewController class]]) {
        return NO;
    }

    NSString *className = NSStringFromClass(viewController.class);
    if (!SADNameMatches(className, config)) {
        return NO;
    }
    if (SADNameIsExcluded(className)) {
        return NO;
    }
    [SADCore noteAdDetected];
    return YES;
}

+ (BOOL)shouldBlockPresentation:(UIViewController *)viewController {
    if (viewController == nil) {
        return NO;
    }
    if (![SADCore shouldBlockAdJump]) {
        return NO;
    }
    NSString *className = NSStringFromClass(viewController.class);
    return [className containsString:@"SFSafariViewController"] ||
           [className containsString:@"SKStoreProductViewController"] ||
           [className containsString:@"ASWebAuthenticationSession"];
}

+ (void)dismissBlockedViewController:(UIViewController *)viewController {
    if (viewController == nil) {
        return;
    }
    [SADCore noteAdDetected];

    // 先让 App 自己的跳过逻辑有机会跑；0.6 秒后还在就强制关掉。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (viewController.isBeingDismissed || viewController.isBeingPresented) {
            return;
        }

        UIWindow *window = viewController.viewIfLoaded.window;
        if (window == nil) {
            return;
        }
        if (window.rootViewController == viewController) {
            return;
        }

        SADDiag(@"dismiss %@", NSStringFromClass(viewController.class));

        UINavigationController *navigationController = viewController.navigationController;
        if (navigationController != nil &&
            navigationController.viewControllers.lastObject == viewController &&
            navigationController.viewControllers.count > 1) {
            [navigationController popViewControllerAnimated:NO];
            return;
        }

        if (viewController.presentingViewController != nil) {
            [viewController dismissViewControllerAnimated:NO completion:nil];
        }
    });
}

#pragma mark 行为拦截

+ (BOOL)shouldBlockMotion {
    SADCore *core = [SADCore shared];
    if (!core.config.enabled || !core.config.blockShake) {
        return NO;
    }
    return core.timer != nil;
}

+ (BOOL)shouldBlockAdJump {
    SADCore *core = [SADCore shared];
    if (!core.config.enabled || !core.config.blockAdJump) {
        return NO;
    }
    return core.adDetected && core.timer != nil;
}

+ (void)noteAdDetected {
    SADCore *core = [SADCore shared];
    if (core.adDetected) {
        return;
    }
    core.adDetected = YES;
    SADDiag(@"ad context");
}

@end
