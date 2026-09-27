TARGET := iphone:clang:latest:16.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME := PerAppVolume

PerAppVolume_FILES := \
    PVGainProcessor.c \
    PerAppVolume.mm

PerAppVolume_CFLAGS := \
    -fobjc-arc \
    -O2

PerAppVolume_CCFLAGS := \
    -std=c++17

PerAppVolume_FRAMEWORKS := \
    Foundation \
    UIKit \
    AVFoundation

PerAppVolume_INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS_MAKE_PATH)/library.mk
