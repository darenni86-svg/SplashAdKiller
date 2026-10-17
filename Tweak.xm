//
//  Tweak.xm
//  SplashAdKiller
//

#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <StoreKit/StoreKit.h>
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
    if ([SADCore shouldBlockPresentation:viewControllerToPresent]) {
        if (completion) {
            completion();
        }
        return;
    }
    BOOL isAd = [SADCore shouldBlockViewController:viewControllerToPresent];
    %orig(viewControllerToPresent, isAd ? NO : flag, completion);
}

%end

%hook UINavigationController

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    BOOL isAd = [SADCore shouldBlockViewController:viewController];
    %orig(viewController, isAd ? NO : animated);
}

%end

%hook UIApplication

- (BOOL)openURL:(NSURL *)url {
    if ([SADCore shouldBlockAdJump]) {
        return NO;
    }
    return %orig;
}

- (void)openURL:(NSURL *)url
        options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey, id> *)options
completionHandler:(void (^)(BOOL success))completion {
    if ([SADCore shouldBlockAdJump]) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    %orig(url, options, completion);
}

%end

%hook SKStoreProductViewController

- (void)loadProductWithParameters:(NSDictionary *)parameters
                  completionBlock:(void (^)(BOOL, NSError *))block {
    if ([SADCore shouldBlockAdJump]) {
        if (block) {
            block(NO, nil);
        }
        return;
    }
    %orig(parameters, block);
}

%end

%hook CMMotionManager

- (void)startAccelerometerUpdates {
    if ([SADCore shouldBlockMotion]) {
        return;
    }
    %orig;
}

- (void)startAccelerometerUpdatesToQueue:(NSOperationQueue *)queue
                             withHandler:(CMAccelerometerHandler)handler {
    if ([SADCore shouldBlockMotion]) {
        return;
    }
    %orig(queue, handler);
}

- (void)startDeviceMotionUpdatesToQueue:(NSOperationQueue *)queue
                            withHandler:(CMDeviceMotionHandler)handler {
    if ([SADCore shouldBlockMotion]) {
        return;
    }
    %orig(queue, handler);
}

- (void)startGyroUpdatesToQueue:(NSOperationQueue *)queue
                    withHandler:(CMGyroHandler)handler {
    if ([SADCore shouldBlockMotion]) {
        return;
    }
    %orig(queue, handler);
}

%end

%hook UIAccelerometer

- (void)setDelegate:(id<UIAccelerometerDelegate>)delegate {
    if ([SADCore shouldBlockMotion]) {
        return;
    }
    %orig(delegate);
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
