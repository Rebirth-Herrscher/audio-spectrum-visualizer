import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

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
      '../rust_engine/target/x86_64-pc-windows-msvc/release/spectrum_engine.dll',
      '../rust_engine/target/x86_64-pc-windows-msvc/debug/spectrum_engine.dll',
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
      'Make sure you ran: xmake build engine\n'
      'Tried:\n${candidates.map((p) => "  - $p").join("\n")}',
    );
  }

  // ---- 函数指针 ----
  late final EngineVersionFunc engineVersion;

  late final EngineFftCreateFunc engineFftCreate;
  late final EngineFftDestroyFunc engineFftDestroy;
  late final EngineFftExecuteFunc engineFftExecute;
  late final EngineFftMagnitudeFunc engineFftMagnitude;

  late final EngineLogMapCreateFunc engineLogMapCreate;
  late final EngineLogMapDestroyFunc engineLogMapDestroy;
  late final EngineLogMapApplyFunc engineLogMapApply;

  // Pipeline
  late final EngineStartCaptureFunc engineStartCapture;
  late final EngineStopCaptureFunc engineStopCapture;
  late final EngineReadSpectrumFunc engineReadSpectrum;
  late final EngineGetSpectrumSizeFunc engineGetSpectrumSize;
  late final EngineGetSampleRateFunc engineGetSampleRate;
  late final EngineLastErrorFunc engineLastError;

  void _bindFunctions() {
    engineVersion = _dylib.lookupFunction<EngineVersionNative, EngineVersionFunc>('engine_version');

    engineFftCreate  = _dylib.lookupFunction<EngineFftCreateNative, EngineFftCreateFunc>('engine_fft_create');
    engineFftDestroy = _dylib.lookupFunction<EngineFftDestroyNative, EngineFftDestroyFunc>('engine_fft_destroy');
    engineFftExecute = _dylib.lookupFunction<EngineFftExecuteNative, EngineFftExecuteFunc>('engine_fft_execute');
    engineFftMagnitude = _dylib.lookupFunction<EngineFftMagnitudeNative, EngineFftMagnitudeFunc>('engine_fft_magnitude');

    engineLogMapCreate  = _dylib.lookupFunction<EngineLogMapCreateNative, EngineLogMapCreateFunc>('engine_log_map_create');
    engineLogMapDestroy = _dylib.lookupFunction<EngineLogMapDestroyNative, EngineLogMapDestroyFunc>('engine_log_map_destroy');
    engineLogMapApply   = _dylib.lookupFunction<EngineLogMapApplyNative, EngineLogMapApplyFunc>('engine_log_map_apply');

    engineStartCapture = _dylib.lookupFunction<EngineStartCaptureNative, EngineStartCaptureFunc>('engine_start_capture');
    engineStopCapture = _dylib.lookupFunction<EngineStopCaptureNative, EngineStopCaptureFunc>('engine_stop_capture');
    engineReadSpectrum = _dylib.lookupFunction<EngineReadSpectrumNative, EngineReadSpectrumFunc>('engine_read_spectrum');
    engineGetSpectrumSize = _dylib.lookupFunction<EngineGetSpectrumSizeNative, EngineGetSpectrumSizeFunc>('engine_get_spectrum_size');
    engineGetSampleRate = _dylib.lookupFunction<EngineGetSampleRateNative, EngineGetSampleRateFunc>('engine_get_sample_rate');
    engineLastError = _dylib.lookupFunction<EngineLastErrorNative, EngineLastErrorFunc>('engine_last_error');
  }
}

// ---- C 结构体 ----

/// 对应 C 的 kiss_fft_cpx { float r; float i; }
final class KissFftCpx extends Struct {
  @Float()
  external double r;
  @Float()
  external double i;
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

// ---- 内存辅助 ----

/// 分配 Float32 数组并写入数据，返回 native 指针（调用者负责 free）
Pointer<Float> toNativeFloat32(Float32List data) {
  final ptr = calloc<Float>(data.length);
  for (var i = 0; i < data.length; i++) {
    ptr[i] = data[i];
  }
  return ptr;
}

/// 将 native Float32 数组读回 Dart，释放 native 内存
Float32List fromNativeFloat32(Pointer<Float> ptr, int length) {
  final list = Float32List(length);
  for (var i = 0; i < length; i++) {
    list[i] = ptr[i];
  }
  calloc.free(ptr);
  return list;
}

// ---- FFI 类型定义 ----

typedef EngineVersionNative = Pointer<Int8> Function();
typedef EngineVersionFunc = Pointer<Int8> Function();

typedef EngineFftCreateNative = Pointer<Void> Function(Uint32 nfft);
typedef EngineFftCreateFunc = Pointer<Void> Function(int nfft);

typedef EngineFftDestroyNative = Void Function(Pointer<Void> plan);
typedef EngineFftDestroyFunc = void Function(Pointer<Void> plan);

typedef EngineFftExecuteNative = Void Function(Pointer<Void> plan, Pointer<Float> input, Pointer<KissFftCpx> output);
typedef EngineFftExecuteFunc = void Function(Pointer<Void> plan, Pointer<Float> input, Pointer<KissFftCpx> output);

typedef EngineFftMagnitudeNative = Void Function(Pointer<KissFftCpx> fftOutput, Pointer<Float> magnitude, Uint32 nfft);
typedef EngineFftMagnitudeFunc = void Function(Pointer<KissFftCpx> fftOutput, Pointer<Float> magnitude, int nfft);

typedef EngineLogMapCreateNative = Pointer<Uint32> Function(Uint32 nfft, Uint32 screenPoints, Float sampleRate);
typedef EngineLogMapCreateFunc = Pointer<Uint32> Function(int nfft, int screenPoints, double sampleRate);

typedef EngineLogMapDestroyNative = Void Function(Pointer<Uint32> map);
typedef EngineLogMapDestroyFunc = void Function(Pointer<Uint32> map);

typedef EngineLogMapApplyNative = Void Function(Pointer<Float> magnitude, Pointer<Uint32> map, Pointer<Float> output, Uint32 screenPoints);
typedef EngineLogMapApplyFunc = void Function(Pointer<Float> magnitude, Pointer<Uint32> map, Pointer<Float> output, int screenPoints);

// Pipeline

typedef EngineStartCaptureNative = Int32 Function(Uint32 sampleRate, Uint32 channels, Uint32 bufferFrames, Uint32 nfft, Uint32 screenPoints);
typedef EngineStartCaptureFunc = int Function(int sampleRate, int channels, int bufferFrames, int nfft, int screenPoints);

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
