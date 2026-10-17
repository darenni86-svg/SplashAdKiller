//
//  SADCore.h
//  SplashAdKiller
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SADConfig : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL autoSkip;
@property (nonatomic, assign) BOOL blockControllers;
@property (nonatomic, assign) BOOL maskAdContent;
@property (nonatomic, assign) BOOL hotStart;
@property (nonatomic, assign) BOOL verboseLog;
/// 启动窗口内禁用加速度计 / 陀螺仪，防止「摇一摇」广告。
@property (nonatomic, assign) BOOL blockShake;
/// 广告出现后拦截跳转（openURL / App Store / Safari）。
@property (nonatomic, assign) BOOL blockAdJump;
/// 把诊断信息写进 /var/mobile/Library/Preferences/com.dsh.splashadkiller.plist 的 DiagnosticLog。
@property (nonatomic, assign) BOOL logToFile;
/// 对 diagnosticBundles 里的 App：启动结束后把诊断日志复制到剪贴板并提示。
@property (nonatomic, assign) BOOL copyDiagnostics;
@property (nonatomic, copy) NSArray<NSString *> *diagnosticBundles;
@property (nonatomic, assign) NSTimeInterval launchWindow;
@property (nonatomic, copy) NSArray<NSString *> *extraKeywords;
@property (nonatomic, copy) NSArray<NSString *> *disabledBundles;
@property (nonatomic, copy) NSArray<NSString *> *enabledBundles;

+ (instancetype)loadFromPreferences;

@end

@interface SADCore : NSObject

@property (nonatomic, strong, readonly) SADConfig *config;

+ (instancetype)shared;

+ (BOOL)isEligibleProcess;
+ (void)install;

+ (BOOL)shouldBlockViewController:(nullable UIViewController *)viewController;
+ (BOOL)shouldBlockPresentation:(nullable UIViewController *)viewController;
+ (void)dismissBlockedViewController:(UIViewController *)viewController;

+ (BOOL)shouldBlockMotion;
+ (BOOL)shouldBlockAdJump;
+ (void)noteAdDetected;

- (void)beginMonitoringWithWindow:(NSTimeInterval)window reason:(NSString *)reason;

@end

NS_ASSUME_NONNULL_END
