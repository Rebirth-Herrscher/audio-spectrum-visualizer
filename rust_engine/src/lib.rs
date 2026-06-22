// spectrum_engine — minimal stable: pull-until-empty + fixed-hop FFT
use arc_swap::ArcSwapOption;
use realfft::RealFftPlanner;
use std::ffi::CStr;
use std::panic::catch_unwind;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use windows::Win32::Foundation::{HANDLE, WAIT_OBJECT_0};
use windows::Win32::Media::Audio::*;
use windows::core::GUID;
use windows::Win32::System::Com::*;
use windows::Win32::System::Threading::{
    CREATE_EVENT, CREATE_EVENT_INITIAL_SET, CreateEventExW, EVENT_MODIFY_STATE,
    SYNCHRONIZATION_SYNCHRONIZE, WaitForSingleObject,
};

const REFTIMES_PER_MILLISEC: i64 = 10000;

static RUNNING: AtomicBool = AtomicBool::new(false);
static THREAD_DONE: AtomicBool = AtomicBool::new(true);
static SPECTRUM: ArcSwapOption<(Vec<f32>, Vec<f32>)> = ArcSwapOption::const_empty();
static SPECTRUM_LEN: AtomicU32 = AtomicU32::new(0);
static SAMPLE_RATE: AtomicU32 = AtomicU32::new(48000);
static LAST_ERROR: std::sync::Mutex<String> = std::sync::Mutex::new(String::new());

fn publish(log: Vec<f32>, lin: Vec<f32>) {
    SPECTRUM.store(Some(std::sync::Arc::new((log, lin))));
}
fn set_error(msg: &str) {
    *LAST_ERROR.lock().unwrap() = msg.to_string();
}

fn read_sp(b: *mut f32, l: i32, linear: bool) -> i32 {
    let Some(ref a) = *SPECTRUM.load() else {
        return 0;
    };
    let src = if linear { &a.1 } else { &a.0 };
    let n = (src.len() as i32).min(l);
    unsafe {
        std::ptr::copy_nonoverlapping(src.as_ptr(), b, n as usize);
    }
    n
}

struct RingBuf {
    buf: Vec<f32>,
    w: usize,
    r: usize,
}
impl RingBuf {
    fn new(cap: usize) -> Self {
        Self {
            buf: vec![0.0f32; cap],
            w: 0,
            r: 0,
        }
    }
    fn push(&mut self, v: f32) {
        let i = self.w % self.buf.len();
        self.buf[i] = v;
        self.w += 1;
    }
    fn fill_zero(&mut self, n: usize) {
        for _ in 0..n {
            self.push(0.0);
        }
    }
    fn avail(&self) -> usize {
        self.w.saturating_sub(self.r)
    }
    fn skip(&mut self, n: usize) {
        self.r = (self.r + n).min(self.w);
    }
    fn peek_window(&self, off: usize, n: usize, out: &mut [f32]) {
        let m = self.buf.len();
        let s = self.r + off;
        for i in 0..n {
            out[i] = self.buf[(s + i) % m];
        }
    }
}

fn build_log_map(nfft: usize, sp: usize, sr: f32) -> Vec<usize> {
    let nb = nfft / 2 + 1;
    // 终点取 nyquist 与人耳上限 20kHz 的较小值, 高采样率下聚焦可听范围
    let ny = (sr / 2.0).min(20000.0);
    let lm = (20.0f32).ln();
    let lx = ny.ln();
    let iv = 1.0 / (sp - 1) as f32;
    (0..sp)
        .map(|i| {
            let f = (lm + i as f32 * iv * (lx - lm)).exp();
            ((f / ny * (nb - 1) as f32).round() as usize).min(nb - 1)
        })
        .collect()
}

#[unsafe(no_mangle)]
pub extern "C" fn engine_version() -> *const std::os::raw::c_char {
    static V: &CStr = c"spectrum_engine_v0.5.0";
    V.as_ptr()
}
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_spectrum_size() -> i32 {
    SPECTRUM_LEN.load(Ordering::Acquire) as i32
}
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_sample_rate() -> i32 {
    SAMPLE_RATE.load(Ordering::Acquire) as i32
}
#[unsafe(no_mangle)]
pub extern "C" fn engine_last_error() -> *const std::os::raw::c_char {
    let err = LAST_ERROR.lock().unwrap();
    if err.is_empty() {
        std::ptr::null()
    } else {
        std::ffi::CString::new(err.as_str()).unwrap().into_raw()
    }
}

struct WasapiCtx {
    ac: IAudioClient,
    cc: IAudioCaptureClient,
    ch: u16,
    sr: u32,
    _hev: HANDLE,
}
impl Drop for WasapiCtx {
    fn drop(&mut self) {
        unsafe {
            self.ac.Stop().ok();
        }
    }
}

fn wasapi_init(ms: u32) -> Option<WasapiCtx> {
    let en: IMMDeviceEnumerator =
        unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }.ok()?;
    let dv = unsafe { en.GetDefaultAudioEndpoint(eRender, eConsole) }.ok()?;
    let ac: IAudioClient = unsafe { dv.Activate::<IAudioClient>(CLSCTX_ALL, None) }.ok()?;
    let pf = unsafe { ac.GetMixFormat() }.ok()?;
    let ch = unsafe { (&*pf).nChannels };
    let sr = unsafe { (&*pf).nSamplesPerSec };
    // Shared mode mix format 应为 IEEE float 32-bit
    // 可能是 WAVE_FORMAT_IEEE_FLOAT(3) 直接格式, 或 WAVE_FORMAT_EXTENSIBLE(0xFFFE) + IEEE_FLOAT SubFormat
    let tag = unsafe { (&*pf).wFormatTag };
    let bits = unsafe { (&*pf).wBitsPerSample };
    const IEEE_FLOAT_SUBTYPE: GUID = GUID::from_values(
        0x00000003,
        0x0000,
        0x0010,
        [0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71],
    );
    let is_float = match tag {
        3 => true,
        0xFFFE => {
            // WAVEFORMATEXTENSIBLE 是 packed, 字段须用 read_unaligned 读取
            let ext = pf as *const WAVEFORMATEXTENSIBLE;
            let sub = unsafe { std::ptr::addr_of!((*ext).SubFormat).read_unaligned() };
            sub == IEEE_FLOAT_SUBTYPE
        }
        _ => false,
    };
    if !is_float || bits != 32 {
        set_error("unsupported mix format: need IEEE float 32-bit");
        return None;
    }
    unsafe {
        ac.Initialize(
            AUDCLNT_SHAREMODE_SHARED,
            AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
            (ms as i64) * REFTIMES_PER_MILLISEC,
            0,
            &*pf,
            None,
        )
    }
    .ok()?;
    let he = unsafe {
        CreateEventExW(
            None,
            None,
            CREATE_EVENT(CREATE_EVENT_INITIAL_SET.0),
            EVENT_MODIFY_STATE.0 | SYNCHRONIZATION_SYNCHRONIZE.0,
        )
    }
    .ok()?;
    unsafe { ac.SetEventHandle(he) }.ok()?;
    let cc: IAudioCaptureClient = unsafe { ac.GetService::<IAudioCaptureClient>() }.ok()?;
    unsafe { ac.Start() }.ok()?;
    Some(WasapiCtx {
        ac,
        cc,
        ch,
        sr,
        _hev: he,
    })
}

fn pull(ctx: &WasapiCtx, ring: &mut RingBuf) {
    let ch = ctx.ch as usize;
    loop {
        let mut d: *mut u8 = std::ptr::null_mut();
        let mut nf = 0u32;
        let mut fl = 0u32;
        if unsafe { ctx.cc.GetBuffer(&mut d, &mut nf, &mut fl, None, None) }.is_err() {
            break;
        }
        if nf == 0 {
            let _ = unsafe { ctx.cc.ReleaseBuffer(0) };
            break;
        }
        if fl & 1 != 0 {
            ring.fill_zero(nf as usize);
        } else if !d.is_null() {
            let src = unsafe { std::slice::from_raw_parts(d as *const f32, nf as usize * ch) };
            for fr in src.chunks_exact(ch) {
                ring.push(fr.iter().sum::<f32>() / ch as f32);
            }
        }
        let _ = unsafe { ctx.cc.ReleaseBuffer(nf) };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn engine_start_capture(nfft: u32, sp: u32) -> i32 {
    if RUNNING.load(Ordering::Acquire) || !THREAD_DONE.load(Ordering::Acquire) {
        return -1;
    }
    SPECTRUM_LEN.store(sp, Ordering::Release);
    THREAD_DONE.store(false, Ordering::Release);
    RUNNING.store(true, Ordering::Release);
    let hop = nfft / 2;

    let _ = std::thread::Builder::new()
        .stack_size(2 * 1024 * 1024)
        .spawn(move || {
            let _ = catch_unwind(move || {
                if unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) }.is_err() {
                    set_error("COM init failed");
                    RUNNING.store(false, Ordering::Release);
                    THREAD_DONE.store(true, Ordering::Release);
                    return;
                }
                let ctx = match wasapi_init(5) {
                    Some(c) => c,
                    None => {
                        if LAST_ERROR.lock().unwrap().is_empty() {
                            set_error("WASAPI init failed");
                        }
                        unsafe {
                            CoUninitialize();
                        }
                        RUNNING.store(false, Ordering::Release);
                        THREAD_DONE.store(true, Ordering::Release);
                        return;
                    }
                };
                let hev = ctx._hev;
                let real_sr = ctx.sr;
                SAMPLE_RATE.store(real_sr, Ordering::Release);
                let mut planner = RealFftPlanner::<f32>::new();
                let r2c = planner.plan_fft_forward(nfft as usize);
                let lm = build_log_map(nfft as usize, sp as usize, real_sr as f32);
                let win: Vec<f32> = (0..nfft as usize)
                    .map(|i| {
                        0.5 * (1.0
                            - (2.0 * std::f32::consts::PI * i as f32 / (nfft - 1) as f32).cos())
                    })
                    .collect();
                let nb = nfft as usize / 2 + 1;
                let mut ring = RingBuf::new((nfft * 4) as usize);
                let mut fin = r2c.make_input_vec();
                let mut fout = r2c.make_output_vec();
                let mut mag = vec![0.0f32; nb];
                let mut slog = vec![0.0f32; sp as usize];
                let mut slin = vec![0.0f32; sp as usize];
                while RUNNING.load(Ordering::Acquire) {
                    if unsafe { WaitForSingleObject(hev, 32) } == WAIT_OBJECT_0 {
                        pull(&ctx, &mut ring);
                    } else {
                        ring.fill_zero(hop as usize);
                    }
                    while ring.avail() >= hop as usize {
                        let a = ring.avail();
                        ring.peek_window(a.saturating_sub(nfft as usize), nfft as usize, &mut fin);
                        for i in 0..nfft as usize {
                            fin[i] *= win[i];
                        }
                        r2c.process(&mut fin, &mut fout).unwrap();
                        for i in 0..nb {
                            mag[i] = (fout[i].re * fout[i].re + fout[i].im * fout[i].im).sqrt();
                        }
                        mag[0] = 0.0;
                        for i in 0..sp as usize {
                            slog[i] = mag[lm[i]];
                        }
                        let t = slog.clone();
                        for i in 1..sp as usize - 1 {
                            slog[i] = t[i - 1] * 0.25 + t[i] * 0.5 + t[i + 1] * 0.25;
                        }
                        let nb2 = nfft as usize / 2 + 1;
                        for i in 0..sp as usize {
                            slin[i] =
                                mag[((i as f32 / sp as f32 * nb2 as f32) as usize).min(nb2 - 1)];
                        }
                        publish(slog.clone(), slin.clone());
                        ring.skip(hop as usize);
                    }
                }
                unsafe {
                    windows::Win32::Foundation::CloseHandle(hev).ok();
                    CoUninitialize();
                }
            });
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
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn engine_read_spectrum(b: *mut f32, l: i32) -> i32 {
    if !RUNNING.load(Ordering::Acquire) {
        return -1;
    }
    read_sp(b, l, false)
}
#[unsafe(no_mangle)]
pub extern "C" fn engine_read_spectrum_linear(b: *mut f32, l: i32) -> i32 {
    if !RUNNING.load(Ordering::Acquire) {
        return -1;
    }
    read_sp(b, l, true)
}
