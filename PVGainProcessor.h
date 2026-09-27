#ifndef PV_GAIN_PROCESSOR_H
#define PV_GAIN_PROCESSOR_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float master_gain;
    float left_gain;
    float right_gain;

    int independent_stereo;

    float ramp_ms;
    float sample_rate;
} PVGainState;

void pv_gain_process_stereo(
    float *samples,
    size_t frame_count,
    PVGainState *state
);

float pv_clamp_gain(float gain);

float pv_soft_limit(float x);

#ifdef __cplusplus
}
#endif

#endif
