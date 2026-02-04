use std::path::Path;

fn main() {
    let profile = std::env::var("PROFILE").unwrap(); // debug 或 release

    let xmake_lib_dir = format!("../build/windows/x64/{}", profile);

    let test_lib = format!("{}/c_test.lib", xmake_lib_dir);
    let core_lib = format!("{}/c_core.lib", xmake_lib_dir);

    let (lib_name, lib_path) = if Path::new(&test_lib).exists() {
        ("c_test", xmake_lib_dir)
    } else if Path::new(&core_lib).exists() {
        ("c_core", xmake_lib_dir)
    } else {
        // 备用：尝试旧路径
        let old_path = format!("../build/{}", profile);
        let old_test = format!("{}/c_test.lib", old_path);
        let old_core = format!("{}/c_core.lib", old_path);

        if Path::new(&old_test).exists() {
            ("c_test", old_path)
        } else if Path::new(&old_core).exists() {
            ("c_core", old_path)
        } else {
            panic!("No C library found! Tried: {} and {}", test_lib, old_path);
        }
    };

    println!("cargo:rustc-link-lib=static={}", lib_name);
    println!("cargo:rustc-link-search=native={}", lib_path);

    println!("cargo:rerun-if-changed=../c_core/include");
}
