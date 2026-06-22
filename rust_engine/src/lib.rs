// spectrum_engine — event-driven WASAPI + FFT pipeline
use std::ffi::CStr;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicPtr, AtomicU32, Ordering};
use std::thread;

#[allow(non_snake_case)]
unsafe extern "system" {
    fn CoInitializeEx(r: *mut std::ffi::c_void, c: u32) -> i32;
    fn CoUninitialize();
}
const COINIT_MULTITHREADED: u32 = 0x0;

#[repr(C)]
pub struct KissFftCpx {
    pub r: f32,
    pub i: f32,
}
impl Clone for KissFftCpx {
    fn clone(&self) -> Self {
        Self {
            r: self.r,
            i: self.i,
        }
    }
}
#[repr(C)]
pub struct WasapiConfig {
    pub sample_rate: u32,
    pub buffer_frames: u32,
    pub channels: u32,
}

unsafe extern "C" {
    fn wasapi_create(ctx: *mut *mut std::ffi::c_void, config: *const WasapiConfig) -> i32;
    fn wasapi_destroy(ctx: *mut std::ffi::c_void);
    fn wasapi_get_default_device(ctx: *mut std::ffi::c_void) -> i32;
    fn wasapi_init_client(ctx: *mut std::ffi::c_void, loopback: bool) -> i32;
    fn wasapi_start(ctx: *mut std::ffi::c_void) -> i32;
    fn wasapi_stop(ctx: *mut std::ffi::c_void);
    fn wasapi_wait(ctx: *mut std::ffi::c_void, timeout_ms: u32) -> u32;
    fn wasapi_read(ctx: *mut std::ffi::c_void, buffer: *mut f32, frames: u32) -> u32;
    fn fft_create(nfft: u32) -> *mut std::ffi::c_void;
    fn fft_destroy(plan: *mut std::ffi::c_void);
    fn fft_execute(plan: *const std::ffi::c_void, input: *const f32, output: *mut KissFftCpx);
    fn fft_magnitude(fft_output: *const KissFftCpx, magnitude: *mut f32, nfft: u32);
    fn log_map_create(nfft: u32, screen_points: u32, sample_rate: f32) -> *mut u32;
    fn log_map_destroy(map: *mut u32);
    fn log_map_apply(magnitude: *const f32, map: *const u32, output: *mut f32, screen_points: u32);
}

static RUNNING: AtomicBool = AtomicBool::new(false);
static THREAD_DONE: AtomicBool = AtomicBool::new(true);
static SPECTRUM_PTR: AtomicPtr<(Vec<f32>, Vec<f32>)> = AtomicPtr::new(std::ptr::null_mut());
static SPECTRUM_LEN: AtomicU32 = AtomicU32::new(0);

fn set_spectrum(log: Vec<f32>, lin: Vec<f32>) {
    let ptr = Arc::into_raw(Arc::new((log, lin))) as *mut (Vec<f32>, Vec<f32>);
    let old = SPECTRUM_PTR.swap(ptr, Ordering::Release);
    if !old.is_null() {
        unsafe {
            drop(Arc::from_raw(old));
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn engine_version() -> *const std::os::raw::c_char {
    static V: &CStr = c"spectrum_engine_v0.1.0";
    V.as_ptr()
}
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_spectrum_size() -> i32 {
    SPECTRUM_LEN.load(Ordering::Acquire) as i32
}
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_sample_rate() -> i32 {
    48000
}
#[unsafe(no_mangle)]
pub extern "C" fn engine_last_error() -> *const std::os::raw::c_char {
    std::ptr::null()
}

#[unsafe(no_mangle)]
pub extern "C" fn engine_start_capture(sr: u32, ch: u32, bf: u32, nfft: u32, sp: u32) -> i32 {
    if RUNNING.load(Ordering::Acquire) || !THREAD_DONE.load(Ordering::Acquire) {
        return -1;
    }
    SPECTRUM_LEN.store(sp, Ordering::Release);
    THREAD_DONE.store(false, Ordering::Release);
    RUNNING.store(true, Ordering::Release);
    let config = WasapiConfig {
        sample_rate: sr,
        buffer_frames: bf,
        channels: ch,
    };
    let _ = thread::Builder::new()
        .stack_size(2 * 1024 * 1024)
        .spawn(move || {
            unsafe {
                CoInitializeEx(std::ptr::null_mut(), COINIT_MULTITHREADED);
            }
            let mut ctx: *mut std::ffi::c_void = std::ptr::null_mut();
            unsafe {
                if wasapi_create(&mut ctx, &config) != 0
                    || wasapi_get_default_device(ctx) != 0
                    || wasapi_init_client(ctx, true) != 0
                    || wasapi_start(ctx) != 0
                {
                    if !ctx.is_null() {
                        wasapi_destroy(ctx);
                    }
                    CoUninitialize();
                    RUNNING.store(false, Ordering::Release);
                    THREAD_DONE.store(true, Ordering::Release);
                    return;
                }
            }
            let fft_plan = unsafe { fft_create(nfft) };
            let log_map = unsafe { log_map_create(nfft, sp, sr as f32) };
            if fft_plan.is_null() || log_map.is_null() {
                if !fft_plan.is_null() {
                    unsafe {
                        fft_destroy(fft_plan);
                    }
                }
                if !log_map.is_null() {
                    unsafe {
                        log_map_destroy(log_map);
                    }
                }
                unsafe {
                    wasapi_stop(ctx);
                    wasapi_destroy(ctx);
                    CoUninitialize();
                }
                RUNNING.store(false, Ordering::Release);
                THREAD_DONE.store(true, Ordering::Release);
                return;
            }
            let nb = (nfft / 2 + 1) as usize;
            let win: Vec<f32> = (0..nfft as usize)
                .map(|i| {
                    0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / (nfft - 1) as f32).cos())
                })
                .collect();
            let mut ring = vec![0.0f32; nfft as usize];
            let mut rp = 0usize;
            let mut fin = vec![0.0f32; nfft as usize];
            let mut fout = vec![KissFftCpx { r: 0.0, i: 0.0 }; nb];
            let mut mag = vec![0.0f32; nb];
            let mut spec = vec![0.0f32; sp as usize];
            let rf = 1024u32;
            let mut buf = vec![0.0f32; (rf * ch) as usize];
            while RUNNING.load(Ordering::Acquire) {
                unsafe {
                    wasapi_wait(ctx, 5);
                }
                let read = unsafe { wasapi_read(ctx, buf.as_mut_ptr(), rf) };
                if read > 0 {
                    for f in 0..read as usize {
                        if rp >= nfft as usize {
                            rp = 0;
                        }
                        let mut s = 0.0f32;
                        for c in 0..ch as usize {
                            s += buf[f * ch as usize + c];
                        }
                        ring[rp] = s / ch as f32;
                        rp += 1;
                    }
                } else {
                    let n = rf as usize;
                    if rp + n >= nfft as usize {
                        rp = 0;
                    }
                    ring[rp..rp + n].fill(0.0);
                    rp += n;
                }
                // Run FFT with sliding window on every iteration
                {
                    let pos = rp;
                    for i in 0..nfft as usize {
                        let idx = (pos.wrapping_sub(nfft as usize) + i).wrapping_rem(nfft as usize);
                        fin[i] = ring[idx] * win[i];
                    }
                    unsafe {
                        fft_execute(fft_plan, fin.as_ptr(), fout.as_mut_ptr());
                        fft_magnitude(fout.as_ptr(), mag.as_mut_ptr(), nfft);
                    }
                    mag[0] = 0.0;
                    unsafe {
                        log_map_apply(mag.as_ptr(), log_map, spec.as_mut_ptr(), sp);
                    }
                    // Frequency-domain Gaussian smoothing (3-point)
                    let prev = spec.to_vec();
                    for i in 1..sp as usize - 1 {
                        spec[i] = prev[i - 1] * 0.25 + prev[i] * 0.5 + prev[i + 1] * 0.25;
                    }
                    set_spectrum(
                        spec.clone(),
                        mag.iter().take(sp as usize).copied().collect(),
                    );
                }
                if rp >= nfft as usize {
                    rp = 0;
                }
            }
            unsafe {
                wasapi_stop(ctx);
                wasapi_destroy(ctx);
                CoUninitialize();
            }
            if !fft_plan.is_null() {
                unsafe {
                    fft_destroy(fft_plan);
                }
            }
            if !log_map.is_null() {
                unsafe {
                    log_map_destroy(log_map);
                }
            }
            THREAD_DONE.store(true, Ordering::Release);
        });
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn engine_stop_capture() {
    RUNNING.store(false, Ordering::Release);
    for _ in 0..100 {
        if THREAD_DONE.load(Ordering::Acquire) {
            break;
        }
        thread::sleep(std::time::Duration::from_millis(10));
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn engine_read_spectrum(buffer: *mut f32, len: i32) -> i32 {
    if !RUNNING.load(Ordering::Acquire) {
        return -1;
    }
    let ptr = SPECTRUM_PTR.load(Ordering::Acquire);
    if ptr.is_null() {
        return 0;
    }
    let arc = unsafe { Arc::from_raw(ptr) };
    let data = &(*arc).0;
    let n = (data.len() as i32).min(len);
    unsafe {
        std::ptr::copy_nonoverlapping(data.as_ptr(), buffer, n as usize);
    }
    let _ = Arc::into_raw(arc);
    n
}

#[unsafe(no_mangle)]
pub extern "C" fn engine_read_spectrum_linear(buffer: *mut f32, len: i32) -> i32 {
    if !RUNNING.load(Ordering::Acquire) {
        return -1;
    }
    let ptr = SPECTRUM_PTR.load(Ordering::Acquire);
    if ptr.is_null() {
        return 0;
    }
    let arc = unsafe { Arc::from_raw(ptr) };
    let data = &(*arc).1;
    let n = (data.len() as i32).min(len);
    unsafe {
        std::ptr::copy_nonoverlapping(data.as_ptr(), buffer, n as usize);
    }
    let _ = Arc::into_raw(arc);
    n
}
