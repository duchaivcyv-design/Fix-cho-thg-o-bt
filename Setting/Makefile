include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OptimizerX

OptimizerX_FILES              = RootListController.m
OptimizerX_INSTALL_PATH       = /Library/PreferenceBundles
OptimizerX_FRAMEWORKS         = UIKit
OptimizerX_PRIVATE_FRAMEWORKS = Preferences
OptimizerX_CFLAGS             = -fobjc-arc -Wno-deprecated-declarations -Wno-everything

# Quét toàn bộ tài nguyên (Root.plist, icon, ngôn ngữ) trong thư mục Resources
OptimizerX_RESOURCE_DIRS      = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

# Tự động nạp entry.plist vào đúng thư mục PreferenceLoader (hỗ trợ tự chuyển đường dẫn cả Rootful lẫn Rootless /var/jb)
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/$(BUNDLE_NAME).plist$(ECHO_END)
