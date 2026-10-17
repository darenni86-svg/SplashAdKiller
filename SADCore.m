//
//  SADCore.m
//  SplashAdKiller
//

#import "SADCore.h"
#import <QuartzCore/QuartzCore.h>
#import <os/log.h>

static NSString *const SADPreferencesDomain = @"com.dsh.splashadkiller";

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
        // cfprefsd 偶尔会缓存旧值，直接读文件做一次兜底。
        NSString *path = [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:
                                                                      [SADPreferencesDomain stringByAppendingPathExtension:@"plist"]];
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

/// 去掉大小写、下划线、横线、空格，只保留字母数字，方便做包含匹配。
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
            // 通用拼接
            @"splashad", @"adsplash", @"splashadvert",
            @"launchad", @"adlaunch", @"launchadvert",
            @"openscreenad", @"openingscreenad", @"openingad",
            @"bootad", @"startupad", @"welcomead",
            // 国内常见广告 SDK
            @"busplash", @"gdtsplash", @"kssplash", @"sigsplash",
            @"mtgsplash", @"hwsplash", @"misplash", @"panglesplash",
        ];
    });
    return keywords;
}

static NSArray<NSString *> *SADExcludedKeywords(void) {
    static NSArray<NSString *> *keywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 这些词出现在类名里时，一般不是「开屏广告界面」，误杀会弄坏 App。
        keywords = @[
            @"config", @"manager", @"request", @"loader", @"cache",
            @"report", @"tracker", @"helper", @"adapter", @"delegate",
            @"model", @"monitor", @"setting", @"preference", @"network",
            @"parser", @"service", @"controllerconfig",
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

    // 兜底：同时出现 splash 与 ad 的类名。
    if ([normalized containsString:@"splash"] && [normalized containsString:@"ad"]) {
        return YES;
    }

    return NO;
}

static BOOL SADNameMatches(NSString *className, SADConfig *config) {
    if (className.length == 0) {
        return NO;
    }
    // 扫描时每一帧都会查很多次，按类名缓存结果（类名重复度极高）。
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

static BOOL SADNameIsExcluded(NSString *className) {
    NSString *normalized = SADNormalized(className);
    for (NSString *keyword in SADExcludedKeywords()) {
        if ([normalized containsString:keyword]) {
            return YES;
        }
    }
    return NO;
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
    if ([lowercase containsString:@"跳过此广告"] || [lowercase containsString:@"跳过广告"]) {
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

#pragma mark - SADCore

@interface SADCore ()

@property (nonatomic, strong, readwrite) SADConfig *config;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, assign) CFTimeInterval deadline;
@property (nonatomic, assign) CFTimeInterval startedAt;
@property (nonatomic, assign) NSInteger clickCount;
@property (nonatomic, strong) NSHashTable<UIControl *> *clickedControls;
@property (nonatomic, strong) NSHashTable<UIView *> *maskedViews;

- (void)stopMonitoring;

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
    // 系统 App 不做处理，避免影响 SpringBoard / 设置等。
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
                        if (!core.config.hotStart) {
                            return;
                        }
                        if (core.timer != nil) {
                            return;
                        }
                        // 热启动的开屏广告通常只会停留几秒。
                        [core beginMonitoringWithWindow:MIN(6.0, core.config.launchWindow)
                                                 reason:@"foreground"];
                    }];

    [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        [[SADCore shared] stopMonitoring];
                    }];
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
    [self.clickedControls removeAllObjects];
    [self.maskedViews removeAllObjects];

    self.timer = [NSTimer timerWithTimeInterval:0.12
                                         target:self
                                       selector:@selector(handleTick)
                                       userInfo:nil
                                        repeats:YES];
    self.timer.tolerance = 0.03;
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];

    SADLog(@"开始监听 (%@, %.0f 秒)", reason, window);
}

- (void)stopMonitoring {
    if (self.timer == nil) {
        return;
    }
    [self.timer invalidate];
    self.timer = nil;
    SADLog(@"停止监听");
}

- (void)handleTick {
    if (!self.config.enabled) {
        [self stopMonitoring];
        return;
    }
    if (CACurrentMediaTime() > self.deadline) {
        [self stopMonitoring];
        return;
    }
    @try {
        [self scanVisibleWindows];
    } @catch (NSException *exception) {
        SADLog(@"扫描异常: %@", exception.reason);
    }
}

#pragma mark 扫描

- (void)scanVisibleWindows {
    UIApplication *application = [UIApplication sharedApplication];
    if (application == nil) {
        return;
    }

    NSInteger budget = 1500;
    for (UIWindow *window in application.windows) {
        if (budget <= 0) {
            break;
        }
        if (window.hidden || window.alpha < 0.02) {
            continue;
        }
        // 键盘等超高层级窗口不扫；普通层级、状态栏层级、Alert 层级都扫。
        if (window.windowLevel > UIWindowLevelAlert) {
            continue;
        }

        [self scanTopViewControllerInWindow:window];
        [self scanViewTree:window budget:&budget];
    }
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
    if (self.config.autoSkip && [view isKindOfClass:[UIControl class]]) {
        [self considerControl:(UIControl *)view];
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

    NSString *text = SADTextFromControl(control);
    if (!SADIsSkipText(text)) {
        return;
    }

    BOOL insideAdContainer = SADViewIsInsideAdContainer(control, self.config);
    BOOL inSkipZone = [self isControlInSkipZone:control];
    BOOL earlyStage = (CACurrentMediaTime() - self.startedAt) < 8.0;
    BOOL weakMatch = !insideAdContainer && inSkipZone && earlyStage;

    if (!insideAdContainer && !weakMatch) {
        return;
    }

    [self.clickedControls addObject:control];
    self.clickCount += 1;

    NSString *preview = text.length > 40 ? [text substringToIndex:40] : text;
    SADLog(@"点击跳过: %@ (%@)", preview, NSStringFromClass(control.class));

    dispatch_async(dispatch_get_main_queue(), ^{
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
}

/// 「跳过」通常位于屏幕右上角。
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

    CGFloat totalArea = view.bounds.size.width * view.bounds.size.height;
    if (totalArea <= 0) {
        return;
    }

    for (UIView *subview in view.subviews) {
        CGFloat area = subview.bounds.size.width * subview.bounds.size.height;
        if (area < totalArea * 0.4) {
            continue;
        }
        if ([subview isKindOfClass:[UIControl class]]) {
            continue;
        }
        // 不要把带「跳过」按钮的容器一起隐藏掉。
        if (SADContainsSkipControl(subview, 0)) {
            continue;
        }
        subview.alpha = 0.0;
        SADLog(@"遮挡广告画面: %@", NSStringFromClass(subview.class));
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
    return YES;
}

+ (void)dismissBlockedViewController:(UIViewController *)viewController {
    if (viewController == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (viewController.isBeingDismissed || viewController.isBeingPresented) {
            return;
        }

        UIWindow *window = viewController.viewIfLoaded.window;
        if (window != nil && window.rootViewController == viewController) {
            return;
        }

        SADLog(@"关闭开屏广告控制器: %@", NSStringFromClass(viewController.class));

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

@end
