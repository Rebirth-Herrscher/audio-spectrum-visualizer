#include "fft_processor.h"
#include "kiss_fftr.h"
#include <math.h>
#include <stdlib.h>

/*
 * fft_plan wraps a kiss_fftr (real-optimized FFT) configuration.
 * Input:  nfft real samples.
 * Output: nfft/2+1 complex bins (only positive frequencies).
 */
struct fft_plan {
    kiss_fftr_cfg cfg;
    uint32_t nfft;
    uint32_t _padding;
};

/* ------------------------------------------------------------------ */

fft_plan_t *fft_create(uint32_t nfft) {
    fft_plan_t *plan = calloc(1, sizeof(fft_plan_t));
    if (!plan) {
        return NULL;
    }

    plan->nfft = nfft;
    plan->cfg = kiss_fftr_alloc((int)nfft, 0, NULL, NULL);
    if (!plan->cfg) {
        free(plan);
        return NULL;
    }
    return plan;
}

void fft_destroy(fft_plan_t *plan) {
    if (!plan) {
        return;
    }
    kiss_fftr_free(plan->cfg);
    free(plan);
}

void fft_execute(const fft_plan_t *plan, const float *input, kiss_fft_cpx *output) {
    if (!plan || !input || !output) {
        return;
    }
    kiss_fftr(plan->cfg, input, output);
}

/*
 * fft_magnitude — convert complex FFT output to magnitude spectrum.
 *   fft_output: nfft/2+1 complex bins (from kiss_fftr)
 *   magnitude:  nfft/2+1 floats, |bin| = sqrt(re^2 + im^2)
 */
void fft_magnitude(const kiss_fft_cpx *fft_output, float *magnitude, uint32_t nfft) {
    uint32_t nbins = (nfft / 2) + 1;
    for (uint32_t i = 0; i < nbins; i++) {
        float re = fft_output[i].r;
        float im = fft_output[i].i;
        magnitude[i] = sqrtf((re * re) + (im * im));
    }
}

/* ================================================================== */
/*  Log-frequency mapping — remap linear FFT bins to log scale         */
/*  to match human pitch perception.                                   */
/* ================================================================== */

/*
 * log_map_create — build a mapping table.
 *   nfft:          FFT size (e.g. 16384)
 *   screen_points: horizontal pixel count
 *   sample_rate:   sample rate in Hz
 * Returns an array of length screen_points where map[i] = FFT bin index.
 */
uint32_t *log_map_create(uint32_t nfft, uint32_t screen_points, float sample_rate) {
    uint32_t *map = malloc(screen_points * sizeof(uint32_t));
    if (!map) {
        return NULL;
    }

    uint32_t nbins = (nfft / 2) + 1;
    float nyquist = sample_rate / 2.0F;
    float log_min = log10f(20.0F);
    float log_max = log10f(nyquist);
    float inv_n = 1.0F / (float)(screen_points - 1);

    for (uint32_t i = 0; i < screen_points; i++) {
        float freq = powf(10.0F, log_min + ((float)i * inv_n * (log_max - log_min)));
        uint32_t bin = (uint32_t)((freq / nyquist * (float)(nbins - 1)) + 0.5F);
        if (bin >= nbins) {
            bin = nbins - 1;
        }
        map[i] = bin;
    }
    return map;
}

void log_map_destroy(uint32_t *map) {
    free(map);
}

/*
 * log_map_apply — extract log-spaced magnitudes from linear spectrum.
 *   fft_magnitude: linear magnitude array (nbins)
 *   map:           mapping table from log_map_create
 *   output:        result array (screen_points)
 */
void log_map_apply(const float *fft_magnitude, const uint32_t *map,
                   float *output, uint32_t screen_points) {
    for (uint32_t i = 0; i < screen_points; i++) {
        output[i] = fft_magnitude[map[i]];
    }
}
