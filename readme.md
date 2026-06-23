# 音频频谱可视化器 (Audio Spectrum Visualizer)

实时音频频谱可视化工具 —— 采集系统音频，FFT 频谱分析，Flutter Canvas 渲染。

---

## 技术架构

| 层级 | 技术 |
|:---|:---|
| 引擎 | Rust — `windows` crate WASAPI 采集, `realfft` FFT, `arc-swap` 无锁快照 |
| 界面 | Dart (Flutter) — Canvas 渲染, 5 种样式 x 4 套配色, 拖尾/光晕/粒子 |

---

## 特性

- WASAPI Loopback 事件驱动（5ms buffer, pull-until-empty）
- 16384 点实数 FFT + Hann 窗 + 对数映射 + 三点加权平滑
- Fixed-hop 滑动窗 FFT（hop=8192, 50% overlap）
- `arc-swap` 无锁频谱发布机制
- Flutter UI: 经典曲线 / 镜像曲线 / 柱状图 / 圆形雷达 / 径向柱状
- 4 套配色: 彩虹 / 火焰 / 霓虹 / 冰蓝
- 背景光晕 + 峰值粒子

---

## 构建 & 运行

### 环境

- Rust 1.85+ (MSVC target, edition 2024)
- Flutter (Dart 3.11+, Windows desktop)

### 构建引擎

```powershell
cd rust_engine
cargo build --release
```

### 启动

```powershell
cd spectrum_ui
flutter run -d windows
```

---

## 依赖

### Rust (`rust_engine/Cargo.toml`)

| 库 | 用途 |
|:---|:---|
| [realfft](https://crates.io/crates/realfft) | 实数 FFT |
| [arc-swap](https://crates.io/crates/arc-swap) | 无锁 Arc 原子交换 |
| [windows](https://crates.io/crates/windows) | WASAPI COM 接口 |

### Dart (`spectrum_ui/pubspec.yaml`)

| 库 | 用途 |
|:---|:---|
| [ffi](https://pub.dev/packages/ffi) | FFI 绑定 |

---

## License

MIT OR Apache-2.0，详见 [LICENSE-MIT](LICENSE-MIT) 与 [LICENSE-APACHE](LICENSE-APACHE)。
