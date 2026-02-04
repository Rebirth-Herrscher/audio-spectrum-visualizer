-- xmake.lua

set_project("audio-spectrum-visualizer")
set_version("0.1.0")
set_languages("c11")

add_rules("mode.debug", "mode.release")
set_defaultarchs("x64")

includes("c_core")

-- 测试目标
target("linktest")
    set_kind("phony")
    add_deps("c_test")
    
    -- 内联 Rust 构建逻辑，不用函数
    on_build(function (target)
        local mode = is_mode("debug") and "debug" or "release"
        local c_lib_dir = path.absolute(path.join("build", mode))
        
        local envs = os.getenvs()
        envs.LIB = c_lib_dir
        
        os.execv("cargo", {
            "build",
            "--manifest-path", "rust_engine/Cargo.toml",
            "--" .. mode
        }, {envs = envs})
        
        local src = path.join("rust_engine", "target", mode, "spectrum_engine.dll")
        os.cp(src, "python_ui/spectrum_engine.pyd")
        print("Built: python_ui/spectrum_engine.pyd")
    end)
    
    on_run(function (target)
    -- 1：使用绝对路径
    local test_py = path.join(os.projectdir(), "python_ui", "test.py")
    os.exec("python " .. test_py)
    
    -- 2：先 cd 再执行
    -- local old_dir = os.cd("python_ui")
    -- os.exec("python test.py")
    -- os.cd(old_dir)
    end)

-- 发布目标
target("release")
    set_kind("phony")
    set_default(true)
    add_deps("c_core")
    
    on_build(function (target)
        local mode = is_mode("debug") and "debug" or "release"
        local c_lib_dir = path.absolute(path.join("build", mode))
        
        local envs = os.getenvs()
        envs.LIB = c_lib_dir
        
        os.execv("cargo", {
            "build",
            "--manifest-path", "rust_engine/Cargo.toml",
            "--" .. mode
        }, {envs = envs})
        
        local src = path.join("rust_engine", "target", mode, "spectrum_engine.dll")
        os.cp(src, "python_ui/spectrum_engine.pyd")
        print("Built: python_ui/spectrum_engine.pyd")
    end)