use pyo3::prelude::*;
use std::ffi::CStr;

// 声明 C 函数
extern "C" {
    fn c_add(a: i32, b: i32) -> i32;
    fn c_version() -> *const std::os::raw::c_char;
}

/// Rust 包装：调用 C 的加法
#[pyfunction]
fn rust_add(a: i32, b: i32) -> i32 {
    unsafe { c_add(a, b) }
}

/// Rust 包装：获取 C 的版本
#[pyfunction]
fn rust_version() -> String {
    unsafe {
        let ptr = c_version();
        CStr::from_ptr(ptr).to_string_lossy().into_owned()
    }
}

/// 纯 Rust 函数（不经过 C）
#[pyfunction]
fn rust_pure(x: i32) -> i32 {
    x * x
}

#[pymodule(name = "spectrum_engine")]
fn spectrum_engine(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(rust_add, m)?)?; // C -> Rust -> Python
    m.add_function(wrap_pyfunction!(rust_version, m)?)?; // C -> Rust -> Python
    m.add_function(wrap_pyfunction!(rust_pure, m)?)?; // Rust -> Python
    Ok(())
}
