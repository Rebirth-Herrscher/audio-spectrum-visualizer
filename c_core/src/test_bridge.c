// 用于测试多语言链路是否通畅
#include "test_bridge.h"

int c_add(int a, int b) {
    return a + b;
}

const char *c_version(void) {
    return "C_Core_v0.1.0";
}
