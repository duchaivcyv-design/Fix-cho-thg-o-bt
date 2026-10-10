# ─── Theos path ────────────────────────────────────────────────────────────
# Dùng ?= để KHÔNG ghi đè THEOS từ env.
# - Trên GitHub Actions: env đã set sẵn → dùng path CI.
# - Trên iPhone (không có env): fallback /var/jb/var/mobile/theos.
export THEOS           ?= /var/jb/var/mobile/theos
export THEOS_MAKE_PATH ?= $(THEOS)/makefiles

# ─── Cấu hình chung ────────────────────────────────────────────────────────
THEOS_PACKAGE_SCHEME = rootless
ARCHS        = arm64
TARGET       = iphone:clang:latest:14.0
DEBUG        = 0
FINALPACKAGE = 1
FOR_RELEASE  = 1
STRIP        = 0

include $(THEOS)/makefiles/common.mk

# ─── Tweak chính ───────────────────────────────────────────────────────────
TWEAK_NAME              = OptimizerX
OptimizerX_FILES        = Tweak.xm
OptimizerX_CFLAGS       = -fobjc-arc -Wno-deprecated-declarations -Wno-everything
OptimizerX_FRAMEWORKS   = Foundation UIKit IOKit
OptimizerX_LIBRARIES    = substrate
OptimizerX_LDFLAGS      = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

# ─── Subproject (PreferenceBundle) ─────────────────────────────────────────
SUBPROJECTS += Setting
include $(THEOS_MAKE_PATH)/aggregate.mk

# ─── Sau khi cài: respring ─────────────────────────────────────────────────
INSTALL_TARGET_PROCESSES = SpringBoard
