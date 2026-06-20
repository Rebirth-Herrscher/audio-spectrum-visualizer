set_project("audio-spectrum-visualizer")
set_version("0.1.0")
set_languages("c11")

-- 目标平台 Windows，clang-cl 编译器 + MSVC 后端
set_plat("windows")
set_arch("x64")
set_toolchains("clang-cl")

-- 每次构建自动更新 compile_commands.json
add_rules("plugin.compile_commands.autoupdate")

add_rules("mode.debug", "mode.release")

includes("c_core")

target("engine")
    set_kind("phony")
    set_default(true)
    add_deps("c_core")

    on_build( function (target)
        local mode = "release"
        if is_mode("debug") then mode = "debug" end

        local envs = os.getenvs()
        envs.LIB = path.absolute(path.join("build", "windows", "x64", mode))

        -- 构建 Rust DLL（内部静态链接 C 库），使用 MSVC target
        os.execv("cargo", {
            "build",
            "--manifest-path",
            "rust_engine/Cargo.toml",
            "--target",
            "x86_64-pc-windows-msvc",
            "--" .. mode
        }, { envs = envs })

        print("Built: rust_engine/target/x86_64-pc-windows-msvc/" .. mode .. "/spectrum_engine.dll")
    end)

    on_clean( function (target)
        os.execv("cargo", {
            "clean",
            "--manifest-path",
            "rust_engine/Cargo.toml",
            "--target",
            "x86_64-pc-windows-msvc"
        })
    end)
