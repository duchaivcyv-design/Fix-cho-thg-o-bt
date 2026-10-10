BUNDLE_NAME = OptimizerX

OptimizerX_FILES              = RootListController.m
OptimizerX_INSTALL_PATH       = /Library/PreferenceBundles
OptimizerX_FRAMEWORKS         = UIKit
OptimizerX_PRIVATE_FRAMEWORKS = Preferences
OptimizerX_CFLAGS             = -fobjc-arc -Wno-deprecated-declarations -Wno-everything

# Chỉ dùng RESOURCE_DIRS — KHÔNG khai báo RESOURCE_FILES nữa
OptimizerX_RESOURCE_DIRS      = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/$(BUNDLE_NAME).plist$(ECHO_END)
