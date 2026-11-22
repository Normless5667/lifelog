import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 单块 OCR 识别文本与边界框（为后续 Batch 2/3 AI 解析与 AR 浮层坐标映射预留）
class OcrTextItem {
  final String text;
  final Rect boundingBox;
  final List<String> lines;

  const OcrTextItem({
    required this.text,
    required this.boundingBox,
    this.lines = const [],
  });
}

/// 单帧端侧 OCR 识别结果
class MenuOcrFrameResult {
  final List<OcrTextItem> blocks;
  final String fullText;
  final int elapsedMs;
  final Size imageSize;
  final String source; // 'stream' | 'photo' | 'gallery'

  const MenuOcrFrameResult({
    required this.blocks,
    required this.fullText,
    required this.elapsedMs,
    required this.imageSize,
    required this.source,
  });

  bool get isEmpty => blocks.isEmpty && fullText.trim().isEmpty;
}

/// 端侧菜单 OCR 服务（基于 Google ML Kit TextRecognitionScript.latin）：
/// - ML Kit v2 中越南语 vi 为正式受支持语言，与英语共用 latin 识别器，零额外语言包配置
/// - 支持实时 CameraImage 流（Android NV21 零拷贝快路径 + YUV420 兜底转换）与高清拍照/相册文件识别
class MenuOcrService {
  final TextRecognizer _recognizer;

  MenuOcrService({TextRecognizer? recognizer})
      : _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  static const Map<DeviceOrientation, int> _deviceOrientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// 计算 Android 帧旋转角度（严格遵循 ML Kit 官方公式）
  static int computeAndroidRotationDegrees({
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required CameraLensDirection lensDirection,
  }) {
    final comp = _deviceOrientations[deviceOrientation] ?? 0;
    if (lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + comp) % 360;
    }
    return (sensorOrientation - comp + 360) % 360;
  }

  /// 将 Android 3-plane YUV_420_888 字节流安全转换为标准单平面 NV21。
  /// 规避 camera_android_camerax 0.6.x 在 ImageFormatGroup.nv21 下的内部异常，全机型通用。
  static Uint8List convertYuv420ToNv21({
    required int width,
    required int height,
    required Uint8List yBytes,
    required int yRowStride,
    required Uint8List uBytes,
    required Uint8List vBytes,
    required int uvRowStride,
    required int uvPixelStride,
    int? vRowStride,
    int? vPixelStride,
  }) {
    final ySize = width * height;
    final uvHeight = height ~/ 2;
    final uvWidth = width ~/ 2;
    final out = Uint8List(ySize + uvWidth * uvHeight * 2);

    // 复制 Y 平面（无 padding 时整块拷贝，有 stride padding 时逐行去尾）
    if (yRowStride == width && yBytes.length >= ySize) {
      out.setRange(0, ySize, yBytes, 0);
    } else {
      var dst = 0;
      for (var row = 0; row < height; row++) {
        final srcStart = row * yRowStride;
        final copyLen = (srcStart + width <= yBytes.length)
            ? width
            : (yBytes.length - srcStart).clamp(0, width);
        if (copyLen > 0) {
          out.setRange(dst, dst + copyLen, yBytes, srcStart);
        }
        dst += width;
      }
    }

    // 交错写入 V/U 平面（NV21 = YYYYYYYY VUVU）
    final effVRowStride = vRowStride ?? uvRowStride;
    final effVPixelStride = vPixelStride ?? uvPixelStride;
    var dst = ySize;
    for (var row = 0; row < uvHeight; row++) {
      final uRowOffset = row * uvRowStride;
      final vRowOffset = row * effVRowStride;
      for (var col = 0; col < uvWidth; col++) {
        final vIdx = vRowOffset + col * effVPixelStride;
        final uIdx = uRowOffset + col * uvPixelStride;
        out[dst++] = vIdx < vBytes.length ? vBytes[vIdx] : 128;
        out[dst++] = uIdx < uBytes.length ? uBytes[uIdx] : 128;
      }
    }
    return out;
  }

  /// 将 CameraImage 转换为 ML Kit InputImage（Android 统一优先安全 YUV420→NV21，兼容单平面 NV21；iOS 用 BGRA8888）
  static InputImage? buildInputImageFromCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) {
    if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) return null;

    final int rotationDeg;
    if (Platform.isIOS) {
      rotationDeg = camera.sensorOrientation;
    } else {
      rotationDeg = computeAndroidRotationDegrees(
        sensorOrientation: camera.sensorOrientation,
        deviceOrientation: deviceOrientation,
        lensDirection: camera.lensDirection,
      );
    }
    final rotation = InputImageRotationValue.fromRawValue(rotationDeg) ??
        InputImageRotation.rotation0deg;

    final size = Size(image.width.toDouble(), image.height.toDouble());

    if (Platform.isIOS) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // Android 3-plane YUV_420_888（最稳妥通用路径：主动转为紧凑 NV21 再交给 ML Kit）
    if (image.planes.length >= 3) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final nv21 = convertYuv420ToNv21(
        width: image.width,
        height: image.height,
        yBytes: yPlane.bytes,
        yRowStride: yPlane.bytesPerRow,
        uBytes: uPlane.bytes,
        vBytes: vPlane.bytes,
        uvRowStride: uPlane.bytesPerRow,
        uvPixelStride: uPlane.bytesPerPixel ?? 1,
        vRowStride: vPlane.bytesPerRow,
        vPixelStride: vPlane.bytesPerPixel ?? (uPlane.bytesPerPixel ?? 1),
      );
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    // Android 单平面 NV21 兜底
    if (image.planes.length == 1) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    return null;
  }

  /// 对单帧 InputImage 执行端侧 OCR 并返回文本块、边界框与耗时
  Future<MenuOcrFrameResult> processInputImage(
    InputImage inputImage, {
    required Size imageSize,
    required String source,
  }) async {
    final sw = Stopwatch()..start();
    final recognized = await _recognizer.processImage(inputImage);
    sw.stop();

    final items = <OcrTextItem>[];
    for (final b in recognized.blocks) {
      final text = b.text.trim();
      if (text.isEmpty) continue;
      final lines = [
        for (final line in b.lines)
          if (line.text.trim().isNotEmpty) line.text.trim(),
      ];
      items.add(OcrTextItem(
        text: text,
        boundingBox: b.boundingBox,
        lines: lines,
      ));
    }

    return MenuOcrFrameResult(
      blocks: items,
      fullText: recognized.text.trim(),
      elapsedMs: sw.elapsedMilliseconds,
      imageSize: imageSize,
      source: source,
    );
  }

  /// 对本地高清照片 / 相册图片执行端侧 OCR（零旋转歧义，最适合验收小字越南语变音符）
  Future<MenuOcrFrameResult> processFilePath(
    String filePath, {
    String source = 'photo',
  }) async {
    final input = InputImage.fromFilePath(filePath);
    return processInputImage(
      input,
      imageSize: Size.zero,
      source: source,
    );
  }

  Future<void> dispose() async {
    await _recognizer.close();
  }
}
