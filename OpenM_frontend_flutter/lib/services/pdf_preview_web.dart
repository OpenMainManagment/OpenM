import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Future<void> showPdfPreview(BuildContext context, Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  final viewType = 'pdf-preview-${DateTime.now().microsecondsSinceEpoch}';
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int _) => web.HTMLIFrameElement()
      ..src = objectUrl
      ..title = 'PDF preview'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%',
  );

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: size.width > 1200 ? 1152 : size.width - 48,
            height: size.height - 48,
            child: Column(
              children: [
                AppBar(
                  title: const Text('Offer PDF'),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      tooltip: 'Close PDF',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Expanded(child: HtmlElementView(viewType: viewType)),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    web.URL.revokeObjectURL(objectUrl);
  }
}
