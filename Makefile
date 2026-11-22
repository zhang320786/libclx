# rootHide / Dopamine-roothide 必须用 roothide scheme（不是 rootless）
# 若你的 Theos 没有 roothide scheme，改用 rootless（仅适用于 Dopamine 常规版）
THEOS_PACKAGE_SCHEME = roothide

TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = WeCom
INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
FINALPACKAGE = 1
STRIP = 1
DEBUG = 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = libclx

libclx_FILES = \
	Tweak.xm \
	CLXGuard.xm \
	CLXShared.m \
	CLXStore.m \
	CLXSession.m \
	CLXPanelController.m \
	CLXMapController.m

libclx_CFLAGS = -fobjc-arc -O2 -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable
libclx_FRAMEWORKS = Foundation UIKit CoreLocation MapKit CoreTelephony SystemConfiguration
libclx_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 WeCom 2>/dev/null || true"
