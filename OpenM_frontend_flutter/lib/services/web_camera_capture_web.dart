import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

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
  html.MediaStream? mediaStream;
  try {
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      return null;
    }
    mediaStream = await mediaDevices.getUserMedia({
      'video': {'facingMode': 'environment'},
      'audio': false,
    });
  } on html.DomException catch (error) {
    if (error.name == 'NotAllowedError' || error.name == 'SecurityError') {
      throw const CameraPermissionDeniedException();
    }
    return null;
  }

  final videoElement = html.VideoElement()
    ..autoplay = true
    ..muted = true
    ..setAttribute('playsinline', 'true')
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.objectFit = 'cover'
    ..srcObject = mediaStream;

  final viewType =
      'web-camera-preview-${DateTime.now().microsecondsSinceEpoch}';
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int _) => videoElement,
  );

  final previewReadyNotifier = ValueNotifier<bool>(false);
  StreamSubscription<html.Event>? loadedMetadataSub;
  StreamSubscription<html.Event>? canPlaySub;

  void updatePreviewReady() {
    previewReadyNotifier.value =
        videoElement.videoWidth > 0 && videoElement.videoHeight > 0;
  }

  loadedMetadataSub = videoElement.onLoadedMetadata.listen((_) {
    updatePreviewReady();
  });
  canPlaySub = videoElement.onCanPlay.listen((_) {
    updatePreviewReady();
  });

  Future<void> waitForVideoReady() async {
    if (videoElement.videoWidth > 0 && videoElement.videoHeight > 0) {
      return;
    }
    try {
      await videoElement.onLoadedMetadata.first.timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      // Keep going; capture will still guard against zero-sized frames.
    }
  }

  Future<void> stopStream() async {
    mediaStream?.getTracks().forEach((track) => track.stop());
  }

  try {
    await videoElement.play();
    await waitForVideoReady();
    updatePreviewReady();

    final result = await showDialog<WebCameraCaptureResult?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var capturing = false;
        String? captureError;

        Future<Uint8List?> captureFrameBytes() async {
          try {
            if (videoElement.videoWidth <= 0 || videoElement.videoHeight <= 0) {
              await waitForVideoReady();
              await Future<void>.delayed(const Duration(milliseconds: 120));
            }

            final width = videoElement.videoWidth;
            final height = videoElement.videoHeight;
            if (width <= 0 || height <= 0) {
              return null;
            }

            final canvas = html.CanvasElement(width: width, height: height);
            final ctx = canvas.context2D;
            ctx.drawImageScaled(
              videoElement,
              0,
              0,
              width.toDouble(),
              height.toDouble(),
            );

            final blob = await canvas.toBlob('image/jpeg', 0.9);

            final reader = html.FileReader();
            final completer = Completer<Uint8List?>();
            reader.onLoad.listen((_) {
              final data = reader.result;
              if (data is ByteBuffer) {
                completer.complete(Uint8List.view(data));
              } else {
                completer.complete(null);
              }
            });
            reader.onError.listen((_) => completer.complete(null));
            reader.readAsArrayBuffer(blob);
            return completer.future;
          } catch (_) {
            return null;
          }
        }

        return StatefulBuilder(
          builder: (context, setState) => ValueListenableBuilder<bool>(
            valueListenable: previewReadyNotifier,
            builder: (context, previewReady, _) {
              return AlertDialog(
                title: const Text('Take business card photo'),
                content: SizedBox(
                  width: 420,
                  height: 320,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: HtmlElementView(viewType: viewType),
                      ),
                      if (!previewReady)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black38,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      if (captureError != null)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            color: Colors.black87,
                            child: Text(
                              captureError!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: capturing
                        ? null
                        : () => Navigator.of(dialogContext).pop(null),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: capturing || !previewReady
                        ? null
                        : () async {
                            setState(() {
                              capturing = true;
                              captureError = null;
                            });

                            final bytes = await captureFrameBytes();
                            if (!dialogContext.mounted) {
                              return;
                            }
                            if (bytes == null) {
                              setState(() {
                                capturing = false;
                                captureError =
                                    'Could not capture image. Keep the card in frame and try again.';
                              });
                              return;
                            }

                            Navigator.of(dialogContext).pop(
                              WebCameraCaptureResult(
                                bytes: bytes,
                                fileName:
                                    'business_card_${DateTime.now().millisecondsSinceEpoch}.jpg',
                              ),
                            );
                          },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(capturing ? 'Capturing...' : 'Capture'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    return result;
  } catch (_) {
    return null;
  } finally {
    await loadedMetadataSub.cancel();
    await canPlaySub.cancel();
    previewReadyNotifier.dispose();
    await stopStream();
  }
}
