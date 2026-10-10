BUNDLE_NAME = OptimizerX

# ─── Nguồn & vị trí cài ────────────────────────────────────────────────────
OptimizerX_FILES              = RootListController.m
OptimizerX_INSTALL_PATH       = /Library/PreferenceBundles

# ─── Frameworks ────────────────────────────────────────────────────────────
OptimizerX_FRAMEWORKS         = UIKit
OptimizerX_PRIVATE_FRAMEWORKS = Preferences

# ─── Compile flags ─────────────────────────────────────────────────────────
OptimizerX_CFLAGS             = -fobjc-arc \
                                -Wno-deprecated-declarations \
                                -Wno-everything

# ─── Resources ─────────────────────────────────────────────────────────────
# Root.plist nằm trong Resources/ → chỉ dùng RESOURCE_DIRS.
# KHÔNG khai báo thêm RESOURCE_FILES (sẽ copy trùng).
# Info.plist PHẢI ở Setting/Info.plist (root subproject) — bundle.mk tự copy.
OptimizerX_RESOURCE_DIRS      = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

# ─── entry.plist → PreferenceLoader (để hiện icon trong Settings) ──────────
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/$(BUNDLE_NAME).plist$(ECHO_END)
