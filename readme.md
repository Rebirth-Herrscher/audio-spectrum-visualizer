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
| 算法层 | C11 | 音频采集、FFT计算 |
| 引擎层 | Rust | 资源管理、GPU计算、Python绑定 |
| 界面层 | Python | GUI、配置管理、显示 |

---

## 当前状态

- [x] 多语言链路验证通过
- [x] 自动化构建系统
- [ ] WASAPI 音频采集
- [ ] FFT 频谱分析
- [ ] GPU 加速渲染
- [ ] Dear ImGui 界面

---

## 构建指南

```powershell
py -3.11 -m pip install numpy dearpygui moderngl glfw pybind11-stubgen
xmake f -c -y
xmake build linktest
xmake run linktest
```

---

## 性能目标

- 延迟: < 10ms
- 频率分辨率: 2.9 Hz (16K FFT)
- 刷新率: 200 FPS

---

## License
MIT / Apache-2.0 dual license

---