import 'dart:io';
import 'dart:ui';

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
/// - 统一走标准 `InputImage.fromFilePath` 彩色原图通道（相机定时 `takePicture()` / 高清拍照 / 相册），
///   不做任何手写 YUV/NV21/BMP 格式转换，保留完整色彩对比度与越南语声调符号清晰度
class MenuOcrService {
  final TextRecognizer _recognizer;

  MenuOcrService({TextRecognizer? recognizer})
      : _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

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

  /// 对本地 JPEG/PNG 图像执行端侧 OCR（自动处理 EXIF 方向，零格式转换）：
  /// - [deleteAfter] 为 true 时（如相机定时抓帧 / 临时拍照），在 finally 中自动删除临时文件避免缓存堆积
  Future<MenuOcrFrameResult> processFilePath(
    String filePath, {
    String source = 'photo',
    bool deleteAfter = false,
  }) async {
    try {
      final input = InputImage.fromFilePath(filePath);
      return await processInputImage(
        input,
        imageSize: Size.zero,
        source: source,
      );
    } finally {
      if (deleteAfter) {
        try {
          final f = File(filePath);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<void> dispose() async {
    await _recognizer.close();
  }
}
