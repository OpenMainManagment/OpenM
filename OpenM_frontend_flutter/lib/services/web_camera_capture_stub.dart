import 'dart:typed_data';

import 'package:flutter/material.dart';

class WebCameraCaptureResult {
  const WebCameraCaptureResult({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

class CameraPermissionDeniedException implements Exception {
  const CameraPermissionDeniedException();
}

Future<WebCameraCaptureResult?> captureImageFromWebCamera(
  BuildContext context,
) async {
  return null;
}
