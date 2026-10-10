include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OptimizerX

OptimizerX_FILES              = RootListController.m
OptimizerX_INSTALL_PATH       = /Library/PreferenceBundles
OptimizerX_FRAMEWORKS         = UIKit
OptimizerX_LDFLAGS            = -undefined dynamic_lookup
OptimizerX_CFLAGS             = -fobjc-arc -Wno-deprecated-declarations -Wno-everything

# Quét toàn bộ tài nguyên (Root.plist, icon...) trong thư mục Resources
OptimizerX_RESOURCE_DIRS      = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

# Chép entry.plist vào PreferenceLoader để hiện menu trong Cài đặt
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/$(BUNDLE_NAME).plist$(ECHO_END)
