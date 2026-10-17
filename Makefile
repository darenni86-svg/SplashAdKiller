export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64 arm64e
export DEBUG = 0
export FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SplashAdKiller

SplashAdKiller_FILES = Tweak.xm SADCore.m
SplashAdKiller_CFLAGS = -fobjc-arc -Wall -Wno-unused-function -Wno-unused-parameter
SplashAdKiller_FRAMEWORKS = UIKit Foundation QuartzCore CoreMotion StoreKit

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard 2>/dev/null || true"
