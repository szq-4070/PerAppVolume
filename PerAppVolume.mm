#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern "C" {
    void pv_gain_process_stereo(
        float *samples,
        size_t frame_count,
        void *state
    );
}

__attribute__((constructor))
static void PerAppVolumeInitialize(void)
{
    NSLog(@"[PerAppVolume] =================================");
    NSLog(@"[PerAppVolume] PerAppVolume dylib loaded");
    NSLog(@"[PerAppVolume] Architecture: arm64/arm64e");
    NSLog(@"[PerAppVolume] Phase 2 build test");
    NSLog(@"[PerAppVolume] =================================");
}
