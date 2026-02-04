// wasapi_capture.h
#pragma once

#include <stdbool.h>
#include <stdint.h>


#ifdef __cplusplus
extern "C" {
#endif

typedef struct wasapi_ctx wasapi_ctx_t;

typedef struct {
    uint32_t sample_rate;
    uint32_t buffer_frames;
    uint32_t channels;
} wasapi_config_t;

int wasapi_create(wasapi_ctx_t **ctx, const wasapi_config_t *config);
void wasapi_destroy(wasapi_ctx_t *ctx);
int wasapi_start(wasapi_ctx_t *ctx);
void wasapi_stop(wasapi_ctx_t *ctx);
uint32_t wasapi_read(wasapi_ctx_t *ctx, float *dst, uint32_t frames);
uint32_t wasapi_get_rate(const wasapi_ctx_t *ctx);
const char *wasapi_error(const wasapi_ctx_t *ctx);

#ifdef __cplusplus
}
#endif