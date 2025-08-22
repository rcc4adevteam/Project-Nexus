import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
// Required to parse the QR code JSON
import 'dart:convert';

class QRViewScreen extends StatefulWidget {
  const QRViewScreen({super.key});

  @override
  State<QRViewScreen> createState() => _QRViewScreenState();
}

class _QRViewScreenState extends State<QRViewScreen> {
  bool _isScanned = false; // prevent multiple scans

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Deployment QR"),
        actions: [
          // Cancel button to close scanner
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, null),
          )
        ],
      ),
      body: MobileScanner(
        onDetect: (barcodeCapture) {
          // Ignore if already scanned once
          if (_isScanned) return;
          _isScanned = true;

          final barcode = barcodeCapture.barcodes.first;
          if (barcode.rawValue == null) return;

          try {
            // Try parsing QR content as JSON
            final data = jsonDecode(barcode.rawValue!);

            if (data is Map && data.containsKey("deploymentCode")) {
              Navigator.pop(context, data["deploymentCode"]);
            } else {
              Navigator.pop(context, barcode.rawValue);
            }
          } catch (e) {
            // If not JSON, just return raw value
            Navigator.pop(context, barcode.rawValue);
          }
        },
      ),
    );
  }
}
