// 用于测试多语言链路是否通畅
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// 简单加法，验证 C -> Rust -> Python 链路
int c_add(int a, int b);

// 返回版本字符串
const char *c_version(void);

#ifdef __cplusplus
}
#endif