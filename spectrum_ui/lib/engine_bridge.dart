import 'dart:ffi';
import 'dart:io';

/// FFI 绑定：加载 spectrum_engine.dll 并提供类型安全的 Dart 接口
class EngineBridge {
  static EngineBridge? _instance;
  late final DynamicLibrary _dylib;

  // ---- 单例 ----
  factory EngineBridge() {
    _instance ??= EngineBridge._internal();
    return _instance!;
  }

  EngineBridge._internal() {
    _dylib = _loadDll();
    _bindFunctions();
  }

  // ---- DLL 加载 ----
  static DynamicLibrary _loadDll() {
    final exeDir = Platform.resolvedExecutable;
    final exeParent = Directory(exeDir).parent.path;

    final candidates = <String>[
      // flutter run CWD (spectrum_ui/)
      '../rust_engine/target/release/spectrum_engine.dll',
      '../rust_engine/target/debug/spectrum_engine.dll',
      // 与 exe 同目录（双击运行 / 发布）
      '$exeParent\\spectrum_engine.dll',
      // 项目根 CWD
      'rust_engine/target/release/spectrum_engine.dll',
    ];

    for (final path in candidates) {
      try {
        final dylib = DynamicLibrary.open(path);
        stderr.writeln('[EngineBridge] loaded: $path');
        return dylib;
      } catch (_) {}
    }

    stderr.writeln('[EngineBridge] tried: ${candidates.join(", ")}');
    throw Exception(
      'Cannot find spectrum_engine.dll.\n'
      'Make sure you ran: cargo build --release --manifest-path rust_engine/Cargo.toml\n'
      'Tried:\n${candidates.map((p) => "  - $p").join("\n")}',
    );
  }

  // ---- 函数指针 ----
  late final EngineVersionFunc engineVersion;
  // Pipeline
  late final EngineStartCaptureFunc engineStartCapture;
  late final EngineStopCaptureFunc engineStopCapture;
  late final EngineReadSpectrumFunc engineReadSpectrum;
  late final EngineReadSpectrumFunc engineReadSpectrumLinear;
  late final EngineGetSpectrumSizeFunc engineGetSpectrumSize;
  late final EngineGetSampleRateFunc engineGetSampleRate;
  late final EngineLastErrorFunc engineLastError;

  void _bindFunctions() {
    engineVersion = _dylib.lookupFunction<EngineVersionNative, EngineVersionFunc>('engine_version');

    engineStartCapture = _dylib.lookupFunction<EngineStartCaptureNative, EngineStartCaptureFunc>('engine_start_capture');
    engineStopCapture = _dylib.lookupFunction<EngineStopCaptureNative, EngineStopCaptureFunc>('engine_stop_capture');
    engineReadSpectrum = _dylib.lookupFunction<EngineReadSpectrumNative, EngineReadSpectrumFunc>('engine_read_spectrum');
    engineReadSpectrumLinear = _dylib.lookupFunction<EngineReadSpectrumNative, EngineReadSpectrumFunc>('engine_read_spectrum_linear');
    engineGetSpectrumSize = _dylib.lookupFunction<EngineGetSpectrumSizeNative, EngineGetSpectrumSizeFunc>('engine_get_spectrum_size');
    engineGetSampleRate = _dylib.lookupFunction<EngineGetSampleRateNative, EngineGetSampleRateFunc>('engine_get_sample_rate');
    engineLastError = _dylib.lookupFunction<EngineLastErrorNative, EngineLastErrorFunc>('engine_last_error');
  }
}

// ---- C 字符串 ----

String fromCString(Pointer<Int8> ptr) {
  final units = <int>[];
  var i = 0;
  while (ptr[i] != 0) {
    units.add(ptr[i]);
    i++;
  }
  return String.fromCharCodes(units);
}

// ---- FFI 类型定义 ----

typedef EngineVersionNative = Pointer<Int8> Function();
typedef EngineVersionFunc = Pointer<Int8> Function();

// Pipeline

typedef EngineStartCaptureNative = Int32 Function(Uint32 nfft, Uint32 screenPoints);
typedef EngineStartCaptureFunc = int Function(int nfft, int screenPoints);

typedef EngineStopCaptureNative = Void Function();
typedef EngineStopCaptureFunc = void Function();

typedef EngineReadSpectrumNative = Int32 Function(Pointer<Float> buffer, Int32 len);
typedef EngineReadSpectrumFunc = int Function(Pointer<Float> buffer, int len);

typedef EngineGetSpectrumSizeNative = Int32 Function();
typedef EngineGetSpectrumSizeFunc = int Function();

typedef EngineGetSampleRateNative = Int32 Function();
typedef EngineGetSampleRateFunc = int Function();

typedef EngineLastErrorNative = Pointer<Int8> Function();
typedef EngineLastErrorFunc = Pointer<Int8> Function();
