import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'engine_bridge.dart';

void main() { runApp(const MyApp()); }

enum SpectrumStyle { classic, mirror, bars, radar, radial }
enum ColorTheme { rainbow, fire, neon, ice }

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override Widget build(BuildContext c) => MaterialApp(title: 'Audio Spectrum', theme: ThemeData(brightness: Brightness.dark), home: const SpectrumPage());
}

class SpectrumPage extends StatefulWidget {
  const SpectrumPage({super.key});
  @override State<SpectrumPage> createState() => _SpectrumPageState();
}

class _SpectrumPageState extends State<SpectrumPage> {
  EngineBridge? _engine; bool _capturing = false; String _status = 'Initializing...';
  int _spectrumSize = 0; Float32List _spectrum = Float32List(0); Timer? _timer;
  final List<double> _smooth = []; double _smoothMax = 0.0;
  final List<double> _peaks = [];
  double _glow = 0.0;
  SpectrumStyle _style = SpectrumStyle.mirror;
  ColorTheme _theme = ColorTheme.rainbow;

  @override void initState() { super.initState(); unawaited(_initEngine()); }

  Future<void> _initEngine() async {
    try {
      _engine = EngineBridge();
      final v = fromCString(_engine!.engineVersion());
      setState(() => _status = 'Engine: $v');
      await Future<void>.delayed(const Duration(seconds: 1));
      _startCapture();
    } catch (e) { setState(() => _status = 'Error: $e'); }
  }

  void _startCapture() {
    if (_engine == null) return;
    const sr=48000, ch=2, bf=480, nf=16384, sp=512;
    final r = _engine!.engineStartCapture(sr,ch,bf,nf,sp);
    if (r != 0) { final e = _engine!.engineLastError(); setState(() => _status = 'Failed: ${e != nullptr ? fromCString(e) : "code $r"}'); return; }
    _spectrumSize = _engine!.engineGetSpectrumSize(); _spectrum = Float32List(_spectrumSize); _capturing = true;
    setState(() => _status = 'Capturing...');
    _timer = Timer.periodic(const Duration(milliseconds: 8), (_) { _readSpectrum(); });
  }

  void _readSpectrum() {
    if (_engine == null || !_capturing) return;
    try {
      final ptr = calloc<Float>(_spectrumSize);
      final useLinear = _style == SpectrumStyle.bars || _style == SpectrumStyle.radar || _style == SpectrumStyle.radial;
      final n = useLinear ? _engine!.engineReadSpectrumLinear(ptr, _spectrumSize) : _engine!.engineReadSpectrum(ptr, _spectrumSize);
      if (n > 0) {
        if (_smooth.length != n) { _smooth.clear(); for (var i=0;i<n;i++) { _smooth.add(0.0); } }
        for (var i=0;i<n;i++) { final v=ptr[i]; _spectrum[i]=v.isNaN||v.isInfinite?0.0:v; }
        final tMax = _findMax(_spectrum);
        if (tMax > 0) {
          if (_smoothMax <= 0) { _smoothMax = tMax; } else { _smoothMax += (tMax - _smoothMax) * 0.5; }
        }
        for (var i=0;i<n;i++) { final t=(_spectrum[i]/_smoothMax).clamp(0.0,1.0); final factor = t > _smooth[i] ? 0.25 : 0.5; _smooth[i]+=(t-_smooth[i])*factor; }
        // Total volume for background glow
        var sum = 0.0;
        for (var i=0;i<n;i++) { sum += _spectrum[i]; }
        final vol = (sum / n / (_smoothMax > 0 ? _smoothMax : 1.0)).clamp(0.0, 1.0);
        _glow += (vol - _glow) * 0.15;
      }
      calloc.free(ptr);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _stopCapture() {
    if (!_capturing) return;
    _timer?.cancel(); _timer=null;
    _engine?.engineStopCapture();
    _capturing=false; if (mounted) setState(()=>_status='Stopped');
  }

  void _showSettings() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(children: [
            const Text('样式：', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 12),
            DropdownButton<SpectrumStyle>(
              value: _style,
              items: const [
                DropdownMenuItem(value: SpectrumStyle.classic, child: Text('经典曲线')),
                DropdownMenuItem(value: SpectrumStyle.mirror, child: Text('镜像曲线')),
                DropdownMenuItem(value: SpectrumStyle.bars, child: Text('柱状图')),
                DropdownMenuItem(value: SpectrumStyle.radar, child: Text('圆形雷达')),
                DropdownMenuItem(value: SpectrumStyle.radial, child: Text('径向柱状')),
              ],
              onChanged: (s) { setState(() => _style = s!); setSheet(() {}); },
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('配色：', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 12),
            DropdownButton<ColorTheme>(
              value: _theme,
              items: const [
                DropdownMenuItem(value: ColorTheme.rainbow, child: Text('🌈 彩虹')),
                DropdownMenuItem(value: ColorTheme.fire, child: Text('🔥 火焰')),
                DropdownMenuItem(value: ColorTheme.neon, child: Text('💜 霓虹')),
                DropdownMenuItem(value: ColorTheme.ice, child: Text('❄️ 冰蓝')),
              ],
              onChanged: (t) { setState(() => _theme = t!); setSheet(() {}); },
            ),
          ]),
        ]),
      )),
    ));
  }

  double _findMax(Float32List d) { var m=0.0; for (final v in d) { if(v>m) m=v; } return m; }

  @override void dispose() { _stopCapture(); super.dispose(); }

  @override Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Spectrum'),
      actions: [
        IconButton(icon: const Icon(Icons.settings), tooltip: '设置', onPressed: () => _showSettings()),
        const SizedBox(width: 4),
        TextButton(onPressed: _capturing?_stopCapture:_startCapture, child: Text(_capturing?'Stop':'Start', style: const TextStyle(color: Colors.white))),
      ],
    ),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Text(_status, style: const TextStyle(fontSize:12,color:Colors.grey))),
      Expanded(child: _capturing ? Padding(padding: const EdgeInsets.symmetric(horizontal:8), child: CustomPaint(size: Size.infinite, painter: SpectrumPainter(_spectrum, _smooth, _smoothMax, _peaks, _style, _theme, _glow))) : const Center(child: Text('Press Start to begin', style: TextStyle(color:Colors.white54,fontSize:16)))),
    ]),
  );
}

class SpectrumPainter extends CustomPainter {
  final Float32List spectrum;
  final List<double> smooth;
  final double smoothMax;
  final List<double> _peaks;
  final SpectrumStyle _style;
  final ColorTheme _theme;
  final double _glow;
  final List<(Path, double)> _trails = [];
  final List<_Particle> _particles = [];
  SpectrumPainter(this.spectrum, this.smooth, this.smoothMax, this._peaks, this._style, this._theme, this._glow);

  static Color _lerpPalette(List<Color> pal, double t) {
    t = t.clamp(0.0, 1.0);
    final step = 1.0 / (pal.length - 1);
    final idx = (t / step).floor().clamp(0, pal.length - 2);
    final local = ((t - idx * step) / step).clamp(0.0, 1.0);
    return Color.lerp(pal[idx], pal[idx + 1], local)!;
  }

  static List<Color> _gradient(ColorTheme theme) => switch (theme) {
    ColorTheme.rainbow => [Colors.red, Colors.deepOrange, Colors.orange, Colors.yellow, Colors.lime, Colors.green, Colors.teal, Colors.cyan, Colors.blue, Colors.indigo, Colors.purple],
    ColorTheme.fire    => [Colors.yellow, Colors.yellowAccent, Colors.amber, Colors.orange, Colors.deepOrange, Colors.red, Colors.redAccent, Colors.deepOrange],
    ColorTheme.neon    => [Colors.purple, Colors.purpleAccent, Colors.deepPurpleAccent, Colors.pinkAccent, Colors.cyanAccent, Colors.lightGreenAccent, Colors.greenAccent],
    ColorTheme.ice     => [Colors.lightBlueAccent, Colors.cyanAccent, Colors.cyan, Colors.lightBlue, Colors.blue, Colors.indigo, Colors.blueGrey],
  };

  @override void paint(Canvas canvas, Size size) {
    if (spectrum.isEmpty || smooth.isEmpty || smooth.length != spectrum.length || smoothMax <= 0) return;
    if (_peaks.length != spectrum.length) { _peaks.clear(); for (var i=0;i<spectrum.length;i++) { _peaks.add(0.0); } }

    // ---- Background glow ----
    if (_style != SpectrumStyle.radar && _style != SpectrumStyle.radial && _glow > 0.01) {
      canvas.drawCircle(Offset(size.width/2, size.height), size.height * (_glow * 0.9 + 0.3),
        Paint()..shader=RadialGradient(colors: [
          _lerpPalette(_gradient(_theme), 0.0).withValues(alpha: _glow * 0.3),
          Colors.transparent,
        ]).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    }

    final bw = size.width / spectrum.length;
    final pal = _gradient(_theme);
    final path = Path(), fillPath = Path()..moveTo(0, size.height);

    if (_style == SpectrumStyle.radar) {
      _drawRadar(canvas, size, pal);
      // Still compute peaks for dots
      for (var i=0; i<spectrum.length; i++) {
        final t = smooth[i].clamp(0.0, 1.0);
        if (t > _peaks[i]) { _peaks[i] = t; } else { _peaks[i] *= 0.98; }
      }
      _drawBarPeaks(canvas, size, bw);
      return;
    }

    if (_style == SpectrumStyle.radial) {
      _drawRadial(canvas, size, pal);
      return;
    }

    for (var i=0; i<spectrum.length; i++) {
      final t = smooth[i].clamp(0.0, 1.0);
      final h = (t*size.height).clamp(1.0, size.height);
      final x = i*bw+bw/2, y = size.height-h;
      if (_style == SpectrumStyle.bars) {
        final barW = (bw*0.7).clamp(2.0, 8.0);
        final col = _lerpPalette(pal, i/spectrum.length);
        canvas.drawRect(Rect.fromLTWH(x-barW/2, y, barW, h), Paint()..color=col.withValues(alpha:0.8));
        canvas.drawRect(Rect.fromLTWH(x-barW/2, y, barW, 2.0), Paint()..color=Colors.white.withValues(alpha:0.6));
      } else {
        if (i==0) { path.moveTo(x,y); }
        else { final px=(i-1)*bw+bw/2, py=size.height-(smooth[i-1]*size.height).clamp(0.0,size.height), mx=(px+x)/2; path.quadraticBezierTo(px,py,mx,(py+y)/2); path.lineTo(x,y); }
        fillPath.lineTo(x, y);
      }
      if (t > _peaks[i]) { _peaks[i] = t; } else { _peaks[i] *= 0.98; }
    }

    if (_style != SpectrumStyle.bars) {
      fillPath..lineTo(size.width, size.height)..close();

      // ---- Trail effect (ghost of past frames) ----
      for (final (oldPath, age) in _trails) {
        final alpha = (0.12 * (1.0 - age)).clamp(0.0, 0.12);
        canvas.drawPath(oldPath, Paint()..color=Colors.white.withValues(alpha:alpha)..strokeWidth=2.5..style=PaintingStyle.stroke..maskFilter=const MaskFilter.blur(BlurStyle.normal,6));
        canvas.drawPath(oldPath, Paint()..color=Colors.white.withValues(alpha:alpha*2)..strokeWidth=1.2..style=PaintingStyle.stroke);
      }
      // Age trails, add current
      for (var i=_trails.length-1; i>=0; i--) {
        _trails[i] = (_trails[i].$1, _trails[i].$2 + 0.04);
        if (_trails[i].$2 >= 1.0) { _trails.removeAt(i); }
      }
      _trails.add((Path.from(path), 0.0));

      // ---- Main curve ----
      canvas.drawPath(fillPath, Paint()..shader=LinearGradient(begin:Alignment.centerLeft,end:Alignment.centerRight,colors:pal).createShader(Rect.fromLTWH(0,0,size.width,size.height))..style=PaintingStyle.fill);
      canvas.drawPath(path, Paint()..color=Colors.white.withValues(alpha:0.4)..strokeWidth=2.5..style=PaintingStyle.stroke..maskFilter=const MaskFilter.blur(BlurStyle.normal,6));
      canvas.drawPath(path, Paint()..color=Colors.white.withValues(alpha:0.8)..strokeWidth=1.2..style=PaintingStyle.stroke);

      if (_style == SpectrumStyle.mirror) {
        final mm = Matrix4.diagonal3Values(1, -1, 1); mm.setTranslationRaw(0, size.height, 0);
        canvas.drawPath(fillPath.transform(mm.storage), Paint()..shader=LinearGradient(
          begin:Alignment.topCenter, end:Alignment.bottomCenter,
          colors:[pal.first.withValues(alpha:0.15), Colors.transparent],
        ).createShader(Rect.fromLTWH(0,size.height,size.width,size.height*0.5))..style=PaintingStyle.fill);
        canvas.drawPath(path.transform(mm.storage), Paint()..color=Colors.white.withValues(alpha:0.15)..strokeWidth=1.5..style=PaintingStyle.stroke..maskFilter=const MaskFilter.blur(BlurStyle.normal,3));
      }
    }

    // Peak dots
    _drawBarPeaks(canvas, size, bw);

    // Particles
    if (_style != SpectrumStyle.radar && _style != SpectrumStyle.radial) {
      _updateParticles(size, bw);
      _drawParticles(canvas, size);
    }
  }

  void _updateParticles(Size size, double bw) {
    for (final p in _particles) { p.life -= 0.02; p.y -= p.speed; p.x += p.vx; }
    _particles.removeWhere((p) => p.life <= 0);
    for (var i=0; i<_peaks.length; i+=8) {
      if (_peaks[i] > 0.35 && (DateTime.now().millisecondsSinceEpoch % 2 == 0)) {
        _particles.add(_Particle(x:i*bw+bw/2, y:size.height-_peaks[i]*size.height,
          vx:(DateTime.now().microsecondsSinceEpoch%200-100)/150.0, speed:0.8+_peaks[i]*2.0, life:1.0));
      }
    }
    while (_particles.length > 120) { _particles.removeAt(0); }
  }

  void _drawParticles(Canvas canvas, Size size) {
    for (final p in _particles) {
      final col = _lerpPalette(_gradient(_theme), p.x / size.width * 0.4);
      canvas.drawCircle(Offset(p.x, p.y), 2.2,
        Paint()..color=col.withValues(alpha:p.life*0.6)..maskFilter=const MaskFilter.blur(BlurStyle.normal,2));
      canvas.drawCircle(Offset(p.x, p.y), 0.8,
        Paint()..color=Colors.white.withValues(alpha:p.life*0.9));
    }
  }

  void _drawBarPeaks(Canvas canvas, Size size, double bw) {
    for (var i=0; i<spectrum.length; i+=4) {
      final ph = (_peaks[i]*size.height).clamp(0.0, size.height);
      canvas.drawCircle(Offset(i*bw+bw/2, size.height-ph), 1.5,
        Paint()..color=Colors.white.withValues(alpha:_peaks[i].clamp(0.0,0.9))
        ..maskFilter=const MaskFilter.blur(BlurStyle.normal,2));
    }
  }

  void _drawRadar(Canvas canvas, Size size, List<Color> pal) {
    final cx = size.width/2, cy = size.height/2;
    final maxR = (cx < cy ? cx : cy) * 0.82;
    final n = spectrum.length;

    for (final r in [0.25, 0.5, 0.75]) {
      canvas.drawCircle(Offset(cx, cy), maxR*r,
        Paint()..color=Colors.white.withValues(alpha:0.06)..style=PaintingStyle.stroke);
    }
    canvas.drawLine(Offset(cx-maxR, cy), Offset(cx+maxR, cy), Paint()..color=Colors.white.withValues(alpha:0.04));
    canvas.drawLine(Offset(cx, cy-maxR), Offset(cx, cy+maxR), Paint()..color=Colors.white.withValues(alpha:0.04));

    final radarPath = Path();
    for (var i=0; i<n; i++) {
      final angle = (i/n - 0.25) * 2 * 3.1415926535;
      final t = smooth[i].clamp(0.0, 1.0);
      final r = maxR * (0.08 + t * 0.92);
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i==0) { radarPath.moveTo(x, y); } else { radarPath.lineTo(x, y); }
    }
    radarPath.close();

    final cols = <Color>[];
    for (var i=0; i<=n; i+=32) { cols.add(_lerpPalette(pal, i/n)); }
    if (cols.last != cols.first) { cols.add(cols.first); } // seamless wrap
    canvas.drawPath(radarPath, Paint()
      ..shader=SweepGradient(center:Alignment.center, colors:cols).createShader(Rect.fromCircle(center:Offset(cx,cy), radius:maxR))
      ..style=PaintingStyle.fill);
    canvas.drawPath(radarPath, Paint()..color=Colors.white.withValues(alpha:0.25)..strokeWidth=2..style=PaintingStyle.stroke..maskFilter=const MaskFilter.blur(BlurStyle.normal,4));
    canvas.drawPath(radarPath, Paint()..color=Colors.white.withValues(alpha:0.65)..strokeWidth=1..style=PaintingStyle.stroke);
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color=Colors.white.withValues(alpha:0.4));
  }

  void _drawRadial(Canvas canvas, Size size, List<Color> pal) {
    final cx = size.width/2, cy = size.height/2;
    final innerR = (cx < cy ? cx : cy) * 0.14;
    final maxBar = (cx < cy ? cx : cy) * 0.72;
    final n = spectrum.length;

    // Center circle
    canvas.drawCircle(Offset(cx, cy), innerR, Paint()..color=Colors.white.withValues(alpha:0.1));
    canvas.drawCircle(Offset(cx, cy), innerR, Paint()..color=Colors.white.withValues(alpha:0.3)..style=PaintingStyle.stroke..strokeWidth=1.5);

    for (var i=0; i<n; i+=2) {
      final angle = (i.toDouble()/n - 0.25) * 2 * 3.1415926535;
      final t = smooth[i].clamp(0.0, 1.0);
      final barH = maxBar * t;
      if (barH < 1.5) continue;
      final x1 = cx + innerR * math.cos(angle);
      final y1 = cy + innerR * math.sin(angle);
      final x2 = cx + (innerR + barH) * math.cos(angle);
      final y2 = cy + (innerR + barH) * math.sin(angle);
      final col = _lerpPalette(pal, i/n);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), Paint()..color=col.withValues(alpha:0.8)..strokeWidth=2.5..strokeCap=StrokeCap.round);
      canvas.drawLine(Offset(x2-1, y2-1), Offset(x2+1, y2+1), Paint()..color=Colors.white.withValues(alpha:0.5)..strokeWidth=1.5..strokeCap=StrokeCap.round);
    }
  }

  @override bool shouldRepaint(covariant SpectrumPainter o) => true;
}

class _Particle { double x, y, vx, speed, life; _Particle({required this.x, required this.y, required this.vx, required this.speed, required this.life}); }
