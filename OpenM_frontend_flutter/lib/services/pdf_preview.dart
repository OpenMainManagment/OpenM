import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'pdf_preview_stub.dart'
    if (dart.library.html) 'pdf_preview_web.dart'
    as implementation;

Future<void> showPdfPreview(BuildContext context, List<int> bytes) {
  return implementation.showPdfPreview(context, Uint8List.fromList(bytes));
}
