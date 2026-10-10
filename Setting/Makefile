BUNDLE_NAME = OptimizerX
OptimizerX_FILES = RootListController.m
OptimizerX_INSTALL_PATH = /Library/PreferenceBundles
OptimizerX_FRAMEWORKS = UIKit
OptimizerX_PRIVATE_FRAMEWORKS = Preferences

# Khai báo resources bằng biến chuẩn của Theos
OptimizerX_RESOURCE_DIRS = Resources
OptimizerX_RESOURCE_FILES = Resources/Root.plist

include $(THEOS_MAKE_PATH)/bundle.mk

# entry.plist thuộc PreferenceLoader, KHÔNG nằm trong bundle
# -> stage riêng vào /Library/PreferenceLoader/Preferences
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/$(BUNDLE_NAME).plist$(ECHO_END)
