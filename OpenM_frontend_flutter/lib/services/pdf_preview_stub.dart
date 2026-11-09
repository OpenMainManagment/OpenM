import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showPdfPreview(BuildContext context, Uint8List bytes) async {
  final uri = Uri.dataFromBytes(bytes, mimeType: 'application/pdf');
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched) {
    throw Exception('Could not open the PDF.');
  }
}
