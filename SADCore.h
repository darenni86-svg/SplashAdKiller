//
//  SADCore.h
//  SplashAdKiller
//
//  通用开屏广告跳过引擎。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SADConfig : NSObject

/// 总开关。
@property (nonatomic, assign) BOOL enabled;
/// 自动点击「跳过 / Skip」。
@property (nonatomic, assign) BOOL autoSkip;
/// 拦截、立即关闭开屏广告控制器。
@property (nonatomic, assign) BOOL blockControllers;
/// 把广告画面（大图 / 视频）透明化。
@property (nonatomic, assign) BOOL maskAdContent;
/// 从后台回到前台时，也监听一小段时间（热启动开屏广告）。
@property (nonatomic, assign) BOOL hotStart;
/// 输出调试日志（os_log，subsystem 为 com.dsh.splashadkiller）。
@property (nonatomic, assign) BOOL verboseLog;
/// 启动后监听多少秒，默认 12 秒。
@property (nonatomic, assign) NSTimeInterval launchWindow;
/// 额外的类名关键词（例如某个 App 自己的开屏广告类名）。
@property (nonatomic, copy) NSArray<NSString *> *extraKeywords;
/// 完全不生效的 App（Bundle ID）。
@property (nonatomic, copy) NSArray<NSString *> *disabledBundles;
/// 不为空时，只对这些 App 生效（Bundle ID）。
@property (nonatomic, copy) NSArray<NSString *> *enabledBundles;

+ (instancetype)loadFromPreferences;

@end

@interface SADCore : NSObject

@property (nonatomic, strong, readonly) SADConfig *config;

+ (instancetype)shared;

/// 当前进程是不是一个可以处理的第三方 App 进程。
+ (BOOL)isEligibleProcess;

/// 注册通知、开始等待 App 启动。
+ (void)install;

/// 这个控制器看起来是不是开屏广告。
+ (BOOL)shouldBlockViewController:(nullable UIViewController *)viewController;

/// 关闭一个被判定为开屏广告的控制器。
+ (void)dismissBlockedViewController:(UIViewController *)viewController;

/// 开始一段监听窗口。
- (void)beginMonitoringWithWindow:(NSTimeInterval)window reason:(NSString *)reason;

@end

NS_ASSUME_NONNULL_END
