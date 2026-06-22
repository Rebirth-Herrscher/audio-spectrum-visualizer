-- 主库：完整编译（排除测试文件）
target("c_core")
    set_kind("static")
    
    add_includedirs("include", "third_party/kiss_fft")
    add_files("src/*.c|test_*.c", "third_party/kiss_fft/*.c")
    
    if is_plat("windows") then
        add_syslinks("ole32", "oleaut32", "winmm")
        add_defines("UNICODE", "_UNICODE")
    end
    
    if is_mode("release") then
        set_optimize("fastest")
        add_cflags("-mavx2", "-ffast-math")
    end