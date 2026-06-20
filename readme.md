# 音频频谱可视化器 (Audio Spectrum Visualizer)

高性能、跨平台、多语言实现的实时音频频谱分析工具。

---

## 项目愿景

> 想看到电脑播放的音乐"长什么样"

实时采集系统音频，进行高分辨率频谱分析，通过 GPU 加速渲染出流畅、炫酷的可视化效果。

---

## 技术架构

| 层级 | 语言 | 职责 |
|:---|:---|:---|
| 算法层 | C11 | 音频采集 (WASAPI)、FFT 数学计算 (kiss_fft) |
| 引擎层 | Rust | 线程调度、数据管线、状态管理，暴露 C ABI 给上层 |
| 界面层 | Dart (Flutter) | GPU 渲染 (Impeller)、GUI 控件、跨平台窗口 |

---

## 当前状态

- [x] 多语言链路验证通过
- [x] xmake + cargo 自动化构建
- [x] WASAPI Loopback 音频采集
- [x] FFT 频谱分析 (fft_processor.c)
- [x] dart:ffi 绑定 (Dart ↔ Rust 链路打通)
- [ ] Rust 引擎管线 (采集→FFT→输出)
- [ ] Flutter 频谱渲染
- [ ] 跨平台音频后端 (macOS/Linux)

---

## 构建 & 运行

### 1. 构建引擎

```powershell
# 自动使用 MinGW GCC（xmake.lua 已写死平台 + 工具链）
xmake build engine
```

产物：`rust_engine/target/x86_64-pc-windows-gnu/release/spectrum_engine.dll`

### 2. 启动 Flutter

```powershell
cd spectrum_ui
flutter run -d windows
```

> `flutter run` 为持续运行模式，支持 hot reload，按 `q` 退出。

---

## 性能目标

- 延迟: < 10ms
- 频率分辨率: 2.9 Hz (16K FFT)
- 刷新率: 200 FPS

---

## License
MIT / Apache-2.0 dual license

---