import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera scanner that returns the ID number found in a barcode/QR on the ID card.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  /// Pull the ID number (7–9 digits) out of whatever the barcode encodes.
  static String? extractId(String raw) {
    final runs = RegExp(r'\d{7,9}').allMatches(raw).map((m) => m.group(0)!).toList();
    if (runs.isEmpty) return null;
    return runs.first;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final id = b.rawValue == null ? null : extractId(b.rawValue!);
      if (id != null) {
        _done = true;
        Navigator.of(context).pop(id);
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan ID'),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _controller.toggleTorch()),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 280,
            height: 180,
            decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: Text('Point the camera at the barcode on the ID card',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
        ),
      ]),
    );
  }
}
