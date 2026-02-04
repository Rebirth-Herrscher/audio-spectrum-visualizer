import spectrum_engine as se

print("=" * 40)
print("多语言链路测试")
print("=" * 40)

# 测试 1: 纯 Rust
result = se.rust_pure(5)
print(f"1. 纯 Rust: rust_pure(5) = {result}")
assert result == 25, "Rust 计算错误"

# 测试 2: Rust -> C -> Rust -> Python
result = se.rust_add(3, 4)
print(f"2. C 链路: rust_add(3, 4) = {result}")
assert result == 7, "C 加法错误"

# 测试 3: C 字符串返回
version = se.rust_version()
print(f"3. C 版本: {version}")
assert "C_Core" in version, "C 版本字符串错误"

print("=" * 40)
print("所有测试通过！多语言链路已打通")
print("=" * 40)