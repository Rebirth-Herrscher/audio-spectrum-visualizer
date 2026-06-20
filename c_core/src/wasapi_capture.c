#include "wasapi_capture.h"

#include <windows.h>
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

// MSVC linker can't find these in import libraries — define them directly
const GUID CLSID_MMDeviceEnumerator = {0xBCDE0395,0xE52F,0x467C,{0x8E,0x3D,0xC4,0x57,0x92,0x91,0x69,0x2E}};
const GUID IID_IMMDeviceEnumerator  = {0xA95664D2,0x9614,0x4F35,{0xA7,0x46,0xDE,0x8D,0xB6,0x36,0x17,0xE6}};
const GUID IID_IAudioClient         = {0x1CB9AD4C,0xDBFA,0x4C32,{0xB1,0x78,0xC2,0xF5,0x68,0xA7,0x03,0xB2}};
const GUID IID_IAudioCaptureClient  = {0xC8ADBD64,0xE71E,0x48A0,{0xA4,0xDE,0x18,0x5C,0x39,0x5C,0xD3,0x17}};

/*
 * Windows 音频使用 100 纳秒为基本时间单位
 * 10,000,000 个单位 = 1 秒
 */
#define REFTIMES_PER_SEC      10000000 // 1秒的100纳秒单位数
#define REFTIMES_PER_MILLISEC 10000    // 1毫秒的100纳秒单位数

/*
 * wasapi_ctx 结构体：存储 WASAPI 采集所需的所有状态
 */
struct wasapi_ctx {
    /* COM 接口指针（8 字节对齐） */
    IMMDeviceEnumerator  *enumerator;
    IMMDevice            *device;
    IAudioClient         *audio_client;
    IAudioCaptureClient  *capture_client;
    WAVEFORMATEX         *wave_format;
    HANDLE                h_event;

    /* 配置参数 */
    uint32_t sample_rate;
    uint32_t channels;
    uint32_t buffer_frames;
    uint32_t _padding; // 显式填充，消除 struct 尾部对齐警告

    /* 错误信息缓冲区 */
    char error_msg[256];
};

/* ================================================================== */

static void set_error(wasapi_ctx_t *ctx, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    (void)vsnprintf(ctx->error_msg, sizeof(ctx->error_msg), fmt, args);
    va_end(args);
}

/* ================================================================== */

const char *wasapi_error(const wasapi_ctx_t *ctx) {
    return ctx ? ctx->error_msg : "null context";
}

/* ================================================================== */

int wasapi_create(wasapi_ctx_t **ctx, const wasapi_config_t *config) {
    *ctx = NULL;

    wasapi_ctx_t *cap = calloc(1, sizeof(wasapi_ctx_t));
    if (!cap) {
        return -1;
    }

    cap->sample_rate  = config->sample_rate;
    cap->channels     = config->channels;
    cap->buffer_frames = config->buffer_frames;

    HRESULT hres = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(hres)) {
        set_error(cap, "CoInitializeEx failed: 0x%08lX", (unsigned long)hres);
        free(cap);
        return -1;
    }

    hres = CoCreateInstance(
            &CLSID_MMDeviceEnumerator,
            NULL,
            CLSCTX_ALL,
            &IID_IMMDeviceEnumerator,
            (void **)&cap->enumerator);

    if (FAILED(hres)) {
        set_error(cap, "CoCreateInstance(MMDeviceEnumerator) failed: 0x%08lX",
                  (unsigned long)hres);
        CoUninitialize();
        free(cap);
        return -1;
    }

    *ctx = cap;
    return 0;
}

/* ================================================================== */

int wasapi_get_default_device(wasapi_ctx_t *ctx) {
    if (!ctx || !ctx->enumerator) {
        return -1;
    }

    HRESULT hres = ctx->enumerator->lpVtbl->GetDefaultAudioEndpoint(
            ctx->enumerator,
            eRender,
            eConsole,
            &ctx->device);

    if (FAILED(hres)) {
        set_error(ctx, "GetDefaultAudioEndpoint failed: 0x%08lX",
                  (unsigned long)hres);
        return -1;
    }

    return 0;
}

/* ================================================================== */

int wasapi_init_client(wasapi_ctx_t *ctx, bool loopback) {
    (void)loopback;
    if (!ctx || !ctx->device) {
        set_error(ctx, "Context or device not initialized");
        return -1;
    }

    HRESULT hres = ctx->device->lpVtbl->Activate(
            ctx->device,
            &IID_IAudioClient,
            CLSCTX_ALL,
            NULL,
            (void **)&ctx->audio_client);

    if (FAILED(hres)) {
        set_error(ctx, "Activate(IAudioClient) failed: 0x%08lX",
                  (unsigned long)hres);
        return -1;
    }

    WAVEFORMATEX *pFormat = NULL;
    hres = ctx->audio_client->lpVtbl->GetMixFormat(ctx->audio_client, &pFormat);
    if (FAILED(hres)) {
        set_error(ctx, "GetMixFormat failed: 0x%08lX", (unsigned long)hres);
        return -1;
    }

    ctx->wave_format = pFormat;

    // Update to actual format (may differ from requested)
    ctx->sample_rate = pFormat->nSamplesPerSec;
    ctx->channels    = pFormat->nChannels;

    REFERENCE_TIME hnsBufferDuration = 5LL * REFTIMES_PER_MILLISEC;
    REFERENCE_TIME hnsPeriodicity    = 0;

    DWORD streamFlags = AUDCLNT_STREAMFLAGS_LOOPBACK
                      | AUDCLNT_STREAMFLAGS_EVENTCALLBACK;

    hres = ctx->audio_client->lpVtbl->Initialize(
            ctx->audio_client,
            AUDCLNT_SHAREMODE_SHARED,
            streamFlags,
            hnsBufferDuration,
            hnsPeriodicity,
            ctx->wave_format,
            NULL);

    if (FAILED(hres)) {
        set_error(ctx, "IAudioClient::Initialize failed: 0x%08lX",
                  (unsigned long)hres);
        if (hres == AUDCLNT_E_DEVICE_IN_USE) {
            set_error(ctx, "Device in use (exclusive mode?)");
        } else if (hres == AUDCLNT_E_UNSUPPORTED_FORMAT) {
            set_error(ctx, "Unsupported format");
        }
        return -1;
    }

    // Create event for event-driven capture
    ctx->h_event = CreateEventEx(NULL, NULL, 0, EVENT_MODIFY_STATE | SYNCHRONIZE);
    if (!ctx->h_event) {
        set_error(ctx, "CreateEventEx failed");
        return -1;
    }
    hres = ctx->audio_client->lpVtbl->SetEventHandle(ctx->audio_client, ctx->h_event);
    if (FAILED(hres)) {
        set_error(ctx, "SetEventHandle failed: 0x%08lX", (unsigned long)hres);
        return -1;
    }

    hres = ctx->audio_client->lpVtbl->GetService(
            ctx->audio_client,
            &IID_IAudioCaptureClient,
            (void **)&ctx->capture_client);

    if (FAILED(hres)) {
        set_error(ctx, "GetService(IAudioCaptureClient) failed: 0x%08lX",
                  (unsigned long)hres);
        return -1;
    }

    return 0;
}

/* ================================================================== */

int wasapi_start(wasapi_ctx_t *ctx) {
    if (!ctx || !ctx->audio_client) {
        set_error(ctx, "Audio client not initialized");
        return -1;
    }

    HRESULT hres = ctx->audio_client->lpVtbl->Start(ctx->audio_client);
    if (FAILED(hres)) {
        set_error(ctx, "IAudioClient::Start failed: 0x%08lX", (unsigned long)hres);
        return -1;
    }

    return 0;
}

/* ================================================================== */

void wasapi_stop(wasapi_ctx_t *ctx) {
    if (ctx && ctx->audio_client) {
        ctx->audio_client->lpVtbl->Stop(ctx->audio_client);
    }
}

/* ================================================================== */

// Wait for audio data with timeout (event-driven). Returns 0 on timeout, >0 on data.
uint32_t wasapi_wait(wasapi_ctx_t *ctx, uint32_t timeout_ms) {
    if (!ctx || !ctx->h_event) return 0;
    DWORD ret = WaitForSingleObject(ctx->h_event, timeout_ms);
    return (ret == WAIT_OBJECT_0) ? 1 : 0;
}

/* ================================================================== */

uint32_t wasapi_read(wasapi_ctx_t *ctx, float *buffer, uint32_t frames) {
    if (!ctx || !ctx->capture_client || !buffer) {
        return 0;
    }

    uint32_t framesRead = 0;
    BYTE    *pData;
    UINT32   numFramesAvailable;
    DWORD    flags;

    // Process all available packets
    while (framesRead < frames) {
        HRESULT hres = ctx->capture_client->lpVtbl->GetBuffer(
                ctx->capture_client,
                &pData,
                &numFramesAvailable,
                &flags,
                NULL,
                NULL);

        if (hres == AUDCLNT_S_BUFFER_EMPTY || FAILED(hres)) {
            break;
        }

        UINT32 framesToCopy = numFramesAvailable;
        if (framesRead + framesToCopy > frames) {
            framesToCopy = frames - framesRead;
        }

        if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
            memset(buffer + (size_t)(framesRead * ctx->channels), 0,
                   (size_t)framesToCopy * ctx->channels * sizeof(float));
        } else if (pData) {
            memcpy(buffer + (size_t)(framesRead * ctx->channels),
                   pData,
                   (size_t)framesToCopy * ctx->channels * sizeof(float));
        }

        framesRead += framesToCopy;

        hres = ctx->capture_client->lpVtbl->ReleaseBuffer(
                ctx->capture_client,
                numFramesAvailable);
        if (FAILED(hres)) {
            break;
        }
    }

    return framesRead;
}

/* ================================================================== */

void wasapi_destroy(wasapi_ctx_t *ctx) {
    if (!ctx) {
        return;
    }

    if (ctx->audio_client) {
        ctx->audio_client->lpVtbl->Stop(ctx->audio_client);
    }

    if (ctx->capture_client) {
        ctx->capture_client->lpVtbl->Release(ctx->capture_client);
        ctx->capture_client = NULL;
    }

    if (ctx->wave_format) {
        CoTaskMemFree(ctx->wave_format);
        ctx->wave_format = NULL;
    }

    if (ctx->audio_client) {
        ctx->audio_client->lpVtbl->Release(ctx->audio_client);
        ctx->audio_client = NULL;
    }

    if (ctx->device) {
        ctx->device->lpVtbl->Release(ctx->device);
        ctx->device = NULL;
    }

    if (ctx->enumerator) {
        ctx->enumerator->lpVtbl->Release(ctx->enumerator);
        ctx->enumerator = NULL;
    }

    if (ctx->h_event) {
        CloseHandle(ctx->h_event);
        ctx->h_event = NULL;
    }

    free(ctx);
}
