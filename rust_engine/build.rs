use std::path::Path;

fn main() {
    let profile = std::env::var("PROFILE").unwrap();
    let other_profile = if profile == "debug" {
        "release"
    } else {
        "debug"
    };

    // 候选搜索路径（按优先级）
    let candidates: Vec<String> = vec![
        format!("../build/windows/x64/{}", profile), // 同模式优先
        format!("../build/windows/x64/{}", other_profile), // 回退到另一模式
        format!("../build/{}", profile),             // 旧路径
        format!("../build/{}", other_profile),       // 旧路径另一模式
    ];

    let lib_path = candidates
        .iter()
        .find(|dir| Path::new(&format!("{}/c_core.lib", dir)).exists());

    match lib_path {
        Some(path) => {
            println!("cargo:rustc-link-lib=static=c_core");
            println!("cargo:rustc-link-search=native={}", path);
        }
        None => panic!(
            "c_core.lib not found in any of: {:?}",
            candidates
                .iter()
                .map(|d| format!("{}/c_core.lib", d))
                .collect::<Vec<_>>()
        ),
    }

    // WASAPI COM dependencies
    println!("cargo:rustc-link-lib=ole32");
    println!("cargo:rustc-link-lib=oleaut32");
    println!("cargo:rustc-link-lib=winmm");
    println!("cargo:rustc-link-lib=mmdevapi");

    // Clang compiler-rt path (auto-detect, needed when linking clang-compiled C with MSVC)
    if let Ok(output) = std::process::Command::new("clang")
        .args(["-print-resource-dir"])
        .output()
    {
        let dir = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let libdir = std::path::Path::new(&dir).join("lib");
        println!("cargo:rustc-link-search=native={}", libdir.display());
    }

    println!("cargo:rerun-if-changed=../c_core/include");
}
