# 音频频谱可视化器 (Audio Spectrum Visualizer)

实时音频频谱分析工具 —— 采集系统音频，FFT 频谱分析，GPU 渲染。

---

## 技术架构

| 层级 | 语言 | 职责 |
|:---|:---|:---|
| 算法层 | C11 | WASAPI Loopback 采集、kiss_fft 实数 FFT |
| 引擎层 | Rust | 事件驱动采集线程、滑动窗 FFT 管线、Arc 无锁共享 |
| 界面层 | Dart (Flutter) | Canvas 渲染、彩虹渐变、峰值保持、60-120fps |

---

## 特性

- WASAPI 事件驱动采集（5ms buffer，~200Hz 事件频率）
- 16384 点实数 FFT + Hann 窗（2.93 Hz 分辨率）
- 对数频率映射 + 高斯平滑
- 滑动窗 FFT（每次采集都更新频谱）
- 峰值保持下落 + 彩虹渐变填充
- Arc + AtomicPtr 无锁线程间数据共享

---

## 构建 & 运行

### 环境要求

- Visual Studio 2022+ (MSVC 工具链)
- LLVM/Clang (clang-cl)
- Rust (x86_64-pc-windows-msvc target)
- Flutter 3.x

### 构建引擎

```powershell
xmake build engine
```

产物：`rust_engine/target/x86_64-pc-windows-msvc/release/spectrum_engine.dll`

### 启动

```powershell
cd spectrum_ui
flutter run -d windows
```

---

## 性能指标

| 指标 | 数值 |
|:---|:---|
| 频率分辨率 | 2.93 Hz (16384-pt FFT @ 48kHz) |
| WASAPI buffer | 5ms |
| FFT 更新率 | ~200 Hz（事件驱动） |
| 渲染帧率 | 60-120 fps（Dart 定时器可调） |
| 端到端延迟 | < 15ms |

---

## License

MIT / Apache-2.0 dual license
