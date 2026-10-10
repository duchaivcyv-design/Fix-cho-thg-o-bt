include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OptimizerX
OptimizerX_FILES = RootListController.mm
OptimizerX_INSTALL_PATH = /Library/PreferenceBundles
OptimizerX_FRAMEWORKS = UIKit
OptimizerX_PRIVATE_FRAMEWORKS = Preferences
OptimizerX_RESOURCE_FILES = Root.plist

include $(THEOS_MAKE_PATH)/bundle.mk

# RootHide/Theos already applies the package prefix to THEOS_STAGING_DIR.
# Do not prepend THEOS_PACKAGE_INSTALL_PREFIX again or this creates /var/jb/var/jb.
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)$(OptimizerX_INSTALL_PATH)/$(BUNDLE_NAME).bundle$(ECHO_END)
	$(ECHO_NOTHING)cp Info.plist $(THEOS_STAGING_DIR)$(OptimizerX_INSTALL_PATH)/$(BUNDLE_NAME).bundle/Info.plist$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/OptimizerX.plist$(ECHO_END)
