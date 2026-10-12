import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import 'id_parser.dart';

/// Reads the ID number off a Kenyan ID card with the camera — printed text on the front,
/// the MRZ on the back, or a barcode/QR — entirely on the phone (works offline).
/// Pops with the confirmed ID number, or null if the operator backs out.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _CamState { starting, live, denied, unavailable }

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cam;
  _CamState _state = _CamState.starting;
  bool _torch = false;
  bool _busy = false; // a frame is being processed
  bool _confirming = false; // confirm sheet is open
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  String _hint = 'Point at the front (ID number) or the back (MRZ) of the card';

  final _text = TextRecognizer(script: TextRecognitionScript.latin);
  final _barcodes = BarcodeScanner(formats: [
    BarcodeFormat.qrCode,
    BarcodeFormat.pdf417,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.dataMatrix,
  ]);
  final _stable = StableReading(needed: 2);
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _sweep.dispose();
    _stopCamera();
    _text.close();
    _barcodes.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed && _cam == null && _state != _CamState.denied) {
      _start();
    }
  }

  Future<void> _start() async {
    setState(() => _state = _CamState.starting);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _state = _CamState.unavailable);
        return;
      }
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final cam = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );
      await cam.initialize();
      await cam.setFocusMode(FocusMode.auto).catchError((_) {});
      if (!mounted) {
        await cam.dispose();
        return;
      }
      _cam = cam;
      setState(() => _state = _CamState.live);
      await cam.startImageStream(_onFrame);
    } on CameraException catch (e) {
      final denied = e.code.startsWith('CameraAccessDenied') || e.code == 'CameraAccessRestricted';
      if (mounted) setState(() => _state = denied ? _CamState.denied : _CamState.unavailable);
    }
  }

  Future<void> _stopCamera() async {
    final cam = _cam;
    _cam = null;
    if (cam == null) return;
    try {
      if (cam.value.isStreamingImages) await cam.stopImageStream();
    } catch (_) {}
    await cam.dispose();
  }

  /// Throttled to ~3 frames a second; one frame in flight at a time.
  Future<void> _onFrame(CameraImage image) async {
    final now = DateTime.now();
    if (_busy || _confirming || now.difference(_lastFrame).inMilliseconds < 320) return;
    _busy = true;
    _lastFrame = now;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final found = await _read(input);
      final stable = _stable.add(found);
      if (!mounted) return;
      if (found.isNotEmpty && stable == null) {
        setState(() => _hint = 'Hold steady…');
      } else if (found.isEmpty && _hint == 'Hold steady…') {
        setState(() => _hint = 'Move closer so the ID number fills the frame');
      }
      if (stable != null) await _confirm(stable);
    } catch (e) {
      debugPrint('scan frame failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// Text + barcode recognition on one image → ranked ID candidates.
  Future<List<IdCandidate>> _read(InputImage input) async {
    final results = await Future.wait([_text.processImage(input), _barcodes.processImage(input)]);
    final text = results[0] as RecognizedText;
    final codes = results[1] as List<Barcode>;
    return rank([
      ...candidatesFromText(text.text),
      for (final b in codes)
        if (b.rawValue != null) ...candidatesFromBarcode(b.rawValue!),
    ]);
  }

  InputImage? _toInputImage(CameraImage image) {
    final cam = _cam;
    if (cam == null) return null;
    final rotation = InputImageRotationValue.fromRawValue(cam.description.sensorOrientation);
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null || image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _fromPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null || !mounted) return;
    setState(() => _hint = 'Reading the photo…');
    final found = await _read(InputImage.fromFilePath(picked.path));
    if (!mounted) return;
    if (found.isEmpty) {
      setState(() => _hint = 'No ID number found in that photo. Try a closer, sharper picture.');
      return;
    }
    await _confirm(found);
  }

  Future<void> _confirm(List<IdCandidate> found) async {
    _confirming = true;
    HapticFeedback.mediumImpact();
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => ConfirmIdSheet(candidates: found),
    );
    if (!mounted) return;
    if (id != null) {
      Navigator.of(context).pop(id);
      return;
    }
    _stable.reset();
    _confirming = false;
    setState(() => _hint = 'Point at the front (ID number) or the back (MRZ) of the card');
  }

  Future<void> _toggleTorch() async {
    final cam = _cam;
    if (cam == null) return;
    try {
      await cam.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          if (_state == _CamState.live && _cam != null) _preview(_cam!) else _placeholder(),
          if (_state == _CamState.live) _Overlay(sweep: _sweep),
          _topBar(),
          _bottomPanel(),
        ]),
      ),
    );
  }

  Widget _preview(CameraController cam) {
    final size = cam.value.previewSize;
    if (size == null) return const SizedBox();
    // Cover the screen without stretching (preview size is reported landscape).
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: size.height, height: size.width, child: CameraPreview(cam)),
      ),
    );
  }

  Widget _placeholder() {
    final msg = switch (_state) {
      _CamState.starting => null,
      _CamState.denied =>
        'Camera access is off for this app. Allow it in your phone\'s Settings, or use a photo or type the ID.',
      _CamState.unavailable => 'No camera available. Use a photo of the ID or type the number.',
      _CamState.live => null,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: msg == null
            ? const CircularProgressIndicator(color: Colors.white)
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
                const SizedBox(height: 16),
                Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ]),
      ),
    );
  }

  Widget _topBar() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            _RoundButton(icon: Icons.close, tooltip: 'Close', onTap: () => Navigator.of(context).pop()),
            const Expanded(
              child: Text('Scan ID card',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            _RoundButton(
              icon: _torch ? Icons.flash_on : Icons.flash_off,
              tooltip: 'Torch',
              onTap: _state == _CamState.live ? _toggleTorch : null,
            ),
          ]),
        ),
      );

  Widget _bottomPanel() => Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Icon(Icons.badge_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_hint, style: const TextStyle(color: Colors.white, fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('From photo'),
                    onPressed: _confirming ? null : _fromPhoto,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                    icon: const Icon(Icons.keyboard_outlined),
                    label: const Text('Type ID'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );
}

/// Card-shaped window with a sweeping brand-gradient line.
class _Overlay extends StatelessWidget {
  final Animation<double> sweep;
  const _Overlay({required this.sweep});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth * .86;
      final h = w / 1.586; // ID-1 card ratio
      return Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _MaskPainter(Size(w, h)))),
        Center(
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white, width: 2.2)),
            child: AnimatedBuilder(
              animation: sweep,
              builder: (_, __) => Align(
                alignment: Alignment(0, sweep.value * 2 - 1),
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: brandGradient,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [BoxShadow(color: AppColors.magenta.withValues(alpha: .6), blurRadius: 12)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

/// Darkens everything except a centred, rounded card-sized window.
class _MaskPainter extends CustomPainter {
  final Size window;
  _MaskPainter(this.window);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
        Rect.fromCenter(center: size.center(Offset.zero), width: window.width, height: window.height),
        const Radius.circular(18));
    final mask = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole));
    canvas.drawPath(mask, Paint()..color = Colors.black54);
  }

  @override
  bool shouldRepaint(_MaskPainter old) => old.window != window;
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _RoundButton({required this.icon, required this.tooltip, this.onTap});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
        icon: Icon(icon),
      );
}

/// Shows what was read and lets the operator confirm, pick another reading, or rescan.
class ConfirmIdSheet extends StatefulWidget {
  final List<IdCandidate> candidates;
  const ConfirmIdSheet({super.key, required this.candidates});
  @override
  State<ConfirmIdSheet> createState() => _ConfirmIdSheetState();
}

class _ConfirmIdSheetState extends State<ConfirmIdSheet> {
  late IdCandidate _picked = widget.candidates.first;

  @override
  Widget build(BuildContext context) {
    final others = widget.candidates.where((c) => c.value != _picked.value).take(3).toList();
    final sure = _picked.score >= IdCandidate.confident;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Icon(sure ? Icons.verified : Icons.help_outline, color: sure ? AppColors.teal : AppColors.amber),
            const SizedBox(width: 8),
            Text(sure ? 'ID number read' : 'Is this the ID number?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Text(_spaced(_picked.value),
                  key: const Key('scanned-id'),
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.purpleDark)),
              const SizedBox(height: 4),
              Text(_picked.note, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Other numbers on the card', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in others)
                ActionChip(
                  label: Text(c.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                  avatar: const Icon(Icons.swap_horiz, size: 18),
                  onPressed: () => setState(() => _picked = c),
                ),
            ]),
          ],
          const SizedBox(height: 18),
          FilledButton(
            key: const Key('use-scanned-id'),
            onPressed: () => Navigator.pop(context, _picked.value),
            child: const Text('Use this ID'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Scan again')),
        ]),
      ),
    );
  }

  static String _spaced(String v) => v.length == 8 ? '${v.substring(0, 4)} ${v.substring(4)}' : v;
}

/// Exposed for the on-device integration test: runs the same recognition on an image file.
@visibleForTesting
Future<List<IdCandidate>> readIdFromImageFile(String path) async {
  final text = TextRecognizer(script: TextRecognitionScript.latin);
  final codes = BarcodeScanner();
  try {
    final input = InputImage.fromFilePath(path);
    final t = await text.processImage(input);
    final b = await codes.processImage(input);
    return rank([
      ...candidatesFromText(t.text),
      for (final c in b)
        if (c.rawValue != null) ...candidatesFromBarcode(c.rawValue!),
    ]);
  } finally {
    await text.close();
    await codes.close();
  }
}
