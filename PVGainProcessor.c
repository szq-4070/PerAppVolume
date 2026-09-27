#include "PVGainProcessor.h"

#include <math.h>

static float pv_clampf(float value, float minimum, float maximum)
{
    if (value < minimum) {
        return minimum;
    }

    if (value > maximum) {
        return maximum;
    }

    return value;
}

float pv_clamp_gain(float gain)
{
    return pv_clampf(gain, 0.0f, 2.0f);
}

float pv_soft_limit(float x)
{
    /*
     * Soft saturation.
     *
     * This is intentionally conservative for Phase 2.
     * The final DSP chain will use a proper limiter.
     */

    if (x > 1.0f) {
        return 1.0f;
    }

    if (x < -1.0f) {
        return -1.0f;
    }

    return x;
}

void pv_gain_process_stereo(
    float *samples,
    size_t frame_count,
    PVGainState *state
)
{
    if (samples == NULL || state == NULL) {
        return;
    }

    float master = pv_clamp_gain(state->master_gain);
    float left = pv_clamp_gain(state->left_gain);
    float right = pv_clamp_gain(state->right_gain);

    if (!state->independent_stereo) {
        left = master;
        right = master;
    }

    for (size_t frame = 0; frame < frame_count; frame++) {
        size_t index = frame * 2;

        samples[index] =
            pv_soft_limit(samples[index] * left);

        samples[index + 1] =
            pv_soft_limit(samples[index + 1] * right);
    }
}
