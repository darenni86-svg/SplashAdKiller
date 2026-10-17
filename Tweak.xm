//
//  Tweak.xm
//  SplashAdKiller
//
//  只做三件事：
//  1. 开屏广告控制器一出现就关掉；
//  2. 广告控制器用无动画方式呈现，减少闪现；
//  3. 引擎负责自动点「跳过」与遮挡广告画面。
//

#import <UIKit/UIKit.h>
#import "SADCore.h"

%group SplashAdKillerHooks

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        if ([SADCore shouldBlockViewController:self]) {
            [SADCore dismissBlockedViewController:self];
        }
    } @catch (NSException *exception) {
        (void)exception;
    }
}

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    BOOL isAd = [SADCore shouldBlockViewController:viewControllerToPresent];
    // 广告控制器不播放入场动画：能少闪一帧是一帧。
    %orig(viewControllerToPresent, isAd ? NO : flag, completion);
}

%end

%hook UINavigationController

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    BOOL isAd = [SADCore shouldBlockViewController:viewController];
    %orig(viewController, isAd ? NO : animated);
}

%end

%end

%ctor {
    @autoreleasepool {
        if (![SADCore isEligibleProcess]) {
            return;
        }
        %init(SplashAdKillerHooks);
        [SADCore install];
    }
}
