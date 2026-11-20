include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = CFCheatHook

CFCheatHook_FILES = cheat_hook.m
CFCheatHook_FRAMEWORKS = Foundation
CFCheatHook_CFLAGS = -fobjc-arc -Wno-unused-variable

include $(THEOS_MAKE_PATH)/library.mk
