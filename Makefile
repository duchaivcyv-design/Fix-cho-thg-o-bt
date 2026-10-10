export THEOS = /var/jb/var/mobile/theos
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64
TARGET = iphone:clang:latest:14.0
DEBUG = 0
FINALPACKAGE = 1
FOR_RELEASE = 1
STRIP = 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OptimizerX
OptimizerX_FILES = Tweak.xm
OptimizerX_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error=deprecated-declarations -Wno-everything
OptimizerX_FRAMEWORKS = Foundation UIKit IOKit
OptimizerX_LIBRARIES = substrate
OptimizerX_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Settings
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
