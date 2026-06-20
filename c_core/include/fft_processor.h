// fft_processor.h
#pragma once

#include "kiss_fftr.h"
#include <stdbool.h>
#include <stdint.h>


#ifdef __cplusplus
extern "C" {
#endif

typedef struct fft_plan fft_plan_t;

fft_plan_t *fft_create(uint32_t nfft);
void fft_destroy(fft_plan_t *plan);
void fft_execute(const fft_plan_t *plan, const float *input, kiss_fft_cpx *output);
void fft_magnitude(const kiss_fft_cpx *fft_output, float *magnitude, uint32_t nfft);

uint32_t *log_map_create(uint32_t nfft, uint32_t screen_points, float sample_rate);
void log_map_destroy(uint32_t *map);
void log_map_apply(const float *fft_magnitude, const uint32_t *map, float *output, uint32_t screen_points);

#ifdef __cplusplus
}
#endif