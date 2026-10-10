# ─── Đường dẫn Theos rootless (Dopamine/Sileo) ─────────────────────────────
export THEOS = /var/jb/var/mobile/theos
export THEOS_MAKE_PATH = $(THEOS)/makefiles

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
OptimizerX_CFLAGS       = -fobjc-arc -Wno-deprecated-declarations \
                          -Wno-error=deprecated-declarations -Wno-everything
OptimizerX_FRAMEWORKS   = Foundation UIKit IOKit
OptimizerX_LIBRARIES    = substrate
OptimizerX_LDFLAGS      = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

# ─── Subproject (PreferenceBundle) ─────────────────────────────────────────
# Tên thư mục thật là "Setting" (số ít) — sửa từ "Settings" → "Setting"
SUBPROJECTS += Setting
include $(THEOS_MAKE_PATH)/aggregate.mk

# ─── Stage entry plist cho PreferenceLoader ────────────────────────────────
# File OptimizerX.plist ở root cần được copy vào /Library/PreferenceLoader/Preferences/
# để iOS hiện icon trong Settings. Không cần copy thủ công vì rootless Theos
# đã tự prefix THEOS_STAGING_DIR.
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp OptimizerX.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/OptimizerX.plist$(ECHO_END)

# ─── Sau khi cài: respring ─────────────────────────────────────────────────
INSTALL_TARGET_PROCESSES = SpringBoard
