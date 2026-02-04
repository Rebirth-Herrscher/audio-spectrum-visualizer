set_project("audio-spectrum-visualizer")
set_version("0.1.0")
set_languages("c11")

add_rules("mode.debug", "mode.release")
set_defaultarchs("x64")

-- 指定 Python 路径
local python = "D:/programming_languages/Python3_11_9/python.exe"
print("Using Python: " .. python)

includes("c_core")

target("linktest")
    set_kind("phony")
    add_deps("c_test")
    
    on_build(function (target)
        local mode = is_mode("debug") and "debug" or "release"
        local c_lib_dir = path.absolute(path.join("build", "windows", "x64", mode))
        
        local envs = os.getenvs()
        envs.LIB = c_lib_dir
        
        -- 构建 Rust
        os.execv("cargo", {
            "build",
            "--manifest-path", "rust_engine/Cargo.toml",
            "--" .. mode
        }, {envs = envs})
        
        -- 复制 DLL
        local src = path.join("rust_engine", "target", mode, "spectrum_engine.dll")
        os.cp(src, "python_ui/spectrum_engine.pyd")
        
        -- 自动生成 .pyi stub
        print("Generating Python stub...")
        local envs_stub = os.getenvs()
        envs_stub.PYTHONPATH = path.absolute("python_ui")
        os.execv(python, {"-m", "pybind11_stubgen", "spectrum_engine", "-o", "python_ui"}, {envs = envs_stub})
        
        print("Built: python_ui/spectrum_engine.pyd + .pyi")
    end)
    
    on_run(function (target)
        os.execv(python, {"test.py"}, {curdir = "python_ui"})
    end)

target("release")
    set_kind("phony")
    set_default(true)
    add_deps("c_core")
    
    on_build(function (target)
        local mode = is_mode("debug") and "debug" or "release"
        local c_lib_dir = path.absolute(path.join("build", "windows", "x64", mode))
        
        local envs = os.getenvs()
        envs.LIB = c_lib_dir
        
        os.execv("cargo", {
            "build",
            "--manifest-path", "rust_engine/Cargo.toml",
            "--" .. mode
        }, {envs = envs})
        
        local src = path.join("rust_engine", "target", mode, "spectrum_engine.dll")
        os.cp(src, "python_ui/spectrum_engine.pyd")
        
        -- 自动生成 .pyi stub
        print("Generating Python stub...")
        local envs_stub = os.getenvs()
        envs_stub.PYTHONPATH = path.absolute("python_ui")
        os.execv(python, {"-m", "pybind11_stubgen", "spectrum_engine", "-o", "python_ui"}, {envs = envs_stub})
        
        print("Built: python_ui/spectrum_engine.pyd + .pyi")
    end)