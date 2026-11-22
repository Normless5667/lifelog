import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

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
  File? _liveTempBmpFile;

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
    final uvHeight = (height + 1) ~/ 2;
    final uvWidth = (width + 1) ~/ 2;
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
      if (plane.bytes.length <= image.width * image.height) return null;
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

  /// 纯 Y 亮度平面转 RGBA 灰度位图（供 InputImage.fromBitmap 兜底通道使用）：
  /// - 仅依赖 Android 全机型必有的 planes[0] 亮度平面，彻底绕开 NV21/YUV 格式兼容问题
  /// - 长边 > maxEdge 时自动整数抽稀，兼顾越南语变音符清晰度与低耗时
  static ({Uint8List rgba, int width, int height}) convertYPlaneToRgbaBitmap({
    required int width,
    required int height,
    required Uint8List yBytes,
    required int yRowStride,
    int maxEdge = 1280,
  }) {
    final longEdge = width > height ? width : height;
    final step = longEdge > maxEdge ? ((longEdge + 959) ~/ 960) : 1;
    final outW = (width + step - 1) ~/ step;
    final outH = (height + step - 1) ~/ step;
    final rgba = Uint8List(outW * outH * 4);
    var dst = 0;
    for (var y = 0; y < height; y += step) {
      final rowOff = y * yRowStride;
      for (var x = 0; x < width; x += step) {
        final idx = rowOff + x;
        final lum = idx < yBytes.length ? yBytes[idx] : 0;
        rgba[dst++] = lum;
        rgba[dst++] = lum;
        rgba[dst++] = lum;
        rgba[dst++] = 255;
      }
    }
    return (rgba: rgba, width: outW, height: outH);
  }

  /// 使用 Y 亮度平面构造 Android `InputImage.fromBitmap`（当部分机型 NV21 `fromBytes` 报 `InputImageConverterError` 时自动无缝接管）
  static InputImage? buildBitmapInputImageFromCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) {
    if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) return null;
    final yPlane = image.planes.first;
    final rotationDeg = Platform.isIOS
        ? camera.sensorOrientation
        : computeAndroidRotationDegrees(
            sensorOrientation: camera.sensorOrientation,
            deviceOrientation: deviceOrientation,
            lensDirection: camera.lensDirection,
          );
    final bmp = convertYPlaneToRgbaBitmap(
      width: image.width,
      height: image.height,
      yBytes: yPlane.bytes,
      yRowStride: yPlane.bytesPerRow,
    );
    return InputImage.fromBitmap(
      bitmap: bmp.rgba,
      width: bmp.width,
      height: bmp.height,
      rotation: rotationDeg,
    );
  }

  /// 将 CameraImage 的 Y 亮度平面编码为标准 8-bit 灰度正立 BMP（自底向上，4 字节行对齐，含 256 色灰度调色板）：
  /// - 供 `InputImage.fromFilePath` 直接读取，彻底绕开 google_mlkit_commons 1.0.3 中
  ///   `fromBytes` (NV21) 与 `fromBitmap` (raw RGBA) 的 `InputImageConverterError` 兼容性问题
  /// - 同步完成 0/90/180/270 顺时针旋转，输出坐标即正立图像坐标
  static ({Uint8List bmpBytes, int width, int height})
      encodeYPlaneToUprightGrayscaleBmp({
    required int width,
    required int height,
    required Uint8List yBytes,
    required int yRowStride,
    required int rotationDeg,
    int maxEdge = 1280,
  }) {
    final longEdge = width > height ? width : height;
    final step = longEdge > maxEdge ? ((longEdge + 959) ~/ 960) : 1;
    final sw = (width + step - 1) ~/ step;
    final sh = (height + step - 1) ~/ step;

    final rot = ((rotationDeg % 360) + 360) % 360;
    final swap = rot == 90 || rot == 270;
    final outW = swap ? sh : sw;
    final outH = swap ? sw : sh;

    final rowStride = (outW + 3) & ~3;
    const headerSize = 14 + 40;
    const paletteSize = 256 * 4;
    const pixelOffset = headerSize + paletteSize; // 1078
    final pixelDataSize = rowStride * outH;
    final fileSize = pixelOffset + pixelDataSize;

    final out = Uint8List(fileSize);
    final bd = ByteData.sublistView(out);

    // BITMAPFILEHEADER (14 bytes)
    out[0] = 0x42; // 'B'
    out[1] = 0x4D; // 'M'
    bd.setUint32(2, fileSize, Endian.little);
    bd.setUint32(6, 0, Endian.little);
    bd.setUint32(10, pixelOffset, Endian.little);

    // BITMAPINFOHEADER (40 bytes)
    bd.setUint32(14, 40, Endian.little);
    bd.setInt32(18, outW, Endian.little);
    bd.setInt32(22, outH, Endian.little); // 正数 = 标准自底向上，全版本 Android 兼容
    bd.setUint16(26, 1, Endian.little); // biPlanes
    bd.setUint16(28, 8, Endian.little); // biBitCount = 8-bit grayscale
    bd.setUint32(30, 0, Endian.little); // BI_RGB
    bd.setUint32(34, pixelDataSize, Endian.little);
    bd.setInt32(38, 2835, Endian.little);
    bd.setInt32(42, 2835, Endian.little);
    bd.setUint32(46, 256, Endian.little);
    bd.setUint32(50, 256, Endian.little);

    // 256 色灰度调色板 (B, G, R, 0)
    var pOff = headerSize;
    for (var i = 0; i < 256; i++) {
      out[pOff++] = i;
      out[pOff++] = i;
      out[pOff++] = i;
      out[pOff++] = 0;
    }

    // 旋转并写入像素（BMP 自底向上：outY=0 存在最后一行）
    for (var outY = 0; outY < outH; outY++) {
      final bmpRow = outH - 1 - outY;
      final dstRowOff = pixelOffset + bmpRow * rowStride;
      for (var outX = 0; outX < outW; outX++) {
        final int sx;
        final int sy;
        switch (rot) {
          case 90:
            sx = outY;
            sy = sh - 1 - outX;
            break;
          case 180:
            sx = sw - 1 - outX;
            sy = sh - 1 - outY;
            break;
          case 270:
            sx = sw - 1 - outY;
            sy = outX;
            break;
          default:
            sx = outX;
            sy = outY;
            break;
        }
        final srcIdx = (sy * step) * yRowStride + (sx * step);
        out[dstRowOff + outX] = srcIdx < yBytes.length ? yBytes[srcIdx] : 0;
      }
    }

    return (bmpBytes: out, width: outW, height: outH);
  }

  /// 对实时相机帧执行 OCR：
  /// - Android 走「Y 平面正立灰度 BMP → 复用临时文件 → InputImage.fromFilePath」通用路径，
  ///   彻底规避 google_mlkit_commons 1.0.3 的 InputImageConverterError 且免去大字节数组跨 Channel 拷贝
  /// - iOS 走标准 BGRA8888 `InputImage.fromBytes`
  Future<MenuOcrFrameResult?> processCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) {
      return null;
    }
    if (Platform.isIOS) {
      final input = buildInputImageFromCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: deviceOrientation,
      );
      if (input == null) return null;
      return processInputImage(
        input,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        source: 'stream',
      );
    }

    final sw = Stopwatch()..start();
    final rotationDeg = computeAndroidRotationDegrees(
      sensorOrientation: camera.sensorOrientation,
      deviceOrientation: deviceOrientation,
      lensDirection: camera.lensDirection,
    );
    final yPlane = image.planes.first;
    final encoded = encodeYPlaneToUprightGrayscaleBmp(
      width: image.width,
      height: image.height,
      yBytes: yPlane.bytes,
      yRowStride: yPlane.bytesPerRow,
      rotationDeg: rotationDeg,
    );

    _liveTempBmpFile ??= File(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}lifelog_ocr_live.bmp',
    );
    await _liveTempBmpFile!.writeAsBytes(encoded.bmpBytes, flush: false);

    final input = InputImage.fromFilePath(_liveTempBmpFile!.path);
    final recognized = await _recognizer.processImage(input);
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
      imageSize: Size(encoded.width.toDouble(), encoded.height.toDouble()),
      source: 'stream',
    );
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
    final f = _liveTempBmpFile;
    _liveTempBmpFile = null;
    if (f != null) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
