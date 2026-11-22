import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ai_service.dart';

/// AR 浮层单个菜品标签在取景框内的定位结果（最多渲染前 5 项，超出部分折叠进 ModalBottomSheet）
class MenuArOverlayAnchor {
  final MenuDishItem dish;
  final double left;
  final double top;
  final double maxWidth;
  final bool matchedBox;

  const MenuArOverlayAnchor({
    required this.dish,
    required this.left,
    required this.top,
    required this.maxWidth,
    required this.matchedBox,
  });
}

/// 单帧抓拍图压缩前后的诊断信息（长边 <= 1280px, JPEG Q80）
class OcrImagePrepResult {
  final String path;
  final int width;
  final int height;
  final int origWidth;
  final int origHeight;
  final int origBytes;
  final int compressedBytes;
  final bool compressed;

  const OcrImagePrepResult({
    required this.path,
    required this.width,
    required this.height,
    required this.origWidth,
    required this.origHeight,
    required this.origBytes,
    required this.compressedBytes,
    required this.compressed,
  });

  String summary() {
    final dim = (width > 0 && height > 0) ? '${width}x$height' : 'orig';
    final origDim = (origWidth > 0 && origHeight > 0) ? '${origWidth}x$origHeight' : '?';
    if (compressed) {
      return '$origDim(${origBytes ~/ 1024}KB)->$dim(${compressedBytes ~/ 1024}KB)';
    }
    return '$dim(${compressedBytes ~/ 1024}KB)';
  }
}

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
  static const MethodChannel _nativeChannel = MethodChannel('com.lifelog/reminders');
  final TextRecognizer _recognizer;

  MenuOcrService({TextRecognizer? recognizer})
      : _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  /// 将相机拍出的高分辨率原图（部分机型忽略 medium 预设直接吐 1.5MB+ 全分辨率图）
  /// 在原生后台线程按长边 <= [maxEdge]px + JPEG quality=[quality] 压缩至 ~200–350KB，
  /// 大幅降低 ML Kit 解码峰值内存（从 ~96MB 降至 ~4MB）与存储占用。
  static Future<OcrImagePrepResult> compressImageForOcr(
    String rawPath, {
    int maxEdge = 1280,
    int quality = 80,
  }) async {
    final rawFile = File(rawPath);
    final rawBytes = rawFile.existsSync() ? rawFile.lengthSync() : 0;
    if (Platform.isAndroid) {
      try {
        final res = await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
          'compressImageForOcr',
          <String, Object>{
            'path': rawPath,
            'maxEdge': maxEdge,
            'quality': quality,
          },
        );
        if (res != null && res['path'] is String) {
          return OcrImagePrepResult(
            path: res['path'] as String,
            width: (res['width'] as num?)?.toInt() ?? 0,
            height: (res['height'] as num?)?.toInt() ?? 0,
            origWidth: (res['origWidth'] as num?)?.toInt() ?? 0,
            origHeight: (res['origHeight'] as num?)?.toInt() ?? 0,
            origBytes: (res['origBytes'] as num?)?.toInt() ?? rawBytes,
            compressedBytes: (res['compressedBytes'] as num?)?.toInt() ?? rawBytes,
            compressed: res['compressed'] == true,
          );
        }
      } catch (_) {}
    }
    return OcrImagePrepResult(
      path: rawPath,
      width: 0,
      height: 0,
      origWidth: 0,
      origHeight: 0,
      origBytes: rawBytes,
      compressedBytes: rawBytes,
      compressed: false,
    );
  }

  /// 抓拍文件专用通道：先压图（长边 <= 1280px, JPEG Q80）→ 立刻删原始大图 → 喂 ML Kit → finally 删压缩图。
  /// 确保两份临时文件在正常和异常分支均 100% 彻底清理。
  Future<({MenuOcrFrameResult result, OcrImagePrepResult prep})> processCapturedFile(
    String rawPath, {
    String source = 'stream',
    int maxEdge = 1280,
    int quality = 80,
    Future<OcrImagePrepResult> Function(String path)? compressOverrideForTest,
  }) async {
    OcrImagePrepResult? prep;
    try {
      prep = compressOverrideForTest != null
          ? await compressOverrideForTest(rawPath)
          : await compressImageForOcr(rawPath, maxEdge: maxEdge, quality: quality);

      // 压缩产生新文件后立刻删除原始 1.5MB 大图，避免两份临时文件同时驻留磁盘
      if (prep.path != rawPath) {
        await _safeDeleteFile(rawPath);
      }

      final input = InputImage.fromFilePath(prep.path);
      final res = await processInputImage(
        input,
        imageSize: Size(prep.width.toDouble(), prep.height.toDouble()),
        source: source,
      );
      return (result: res, prep: prep);
    } finally {
      await _safeDeleteFile(rawPath);
      if (prep != null && prep.path != rawPath) {
        await _safeDeleteFile(prep.path);
      }
    }
  }

  static Future<void> _safeDeleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
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

  // ── v3.4.2 本地菜单 OCR 噪音清洗与越南盾价格规范化（发 AI 前执行，省 Token 提准确率） ──

  static final RegExp _vietnameseDiacriticRe = RegExp(
    r'[àáảãạăằắẳẵặâầấẩẫậđèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵ]',
    caseSensitive: false,
  );

  static final RegExp _urlNoiseRe = RegExp(
    r'(https?://|www\.|\.(com|net|org|io|cn|html|htm|php|gov|edu)\b|%[0-9a-f]{2}|[?&](cid|id|utm_\w+|token|ref|v)=|\b[a-z0-9_]{2,}=\S+)',
    caseSensitive: false,
  );

  static final RegExp _browserBrandNoiseRe = RegExp(
    r'\b(gemini|chatgpt|gpt|lifelog|bilbil\w*|bilibili|pngtree|localhost|chrome|firefox|safari|deepseek|openai|github|youtube)\b',
    caseSensitive: false,
  );

  static final RegExp _garbledMixedAlnumRe = RegExp(
    r'(?:\b\d+[a-z]{3,}\b|\b[a-z]{2,}\d+[a-z]+\b|\b\d+[A-Z]{2,}-[a-zA-Z]+\b|\b[A-Z][a-z]+[A-Z]\d+\b)',
  );

  static final RegExp _priceThousandSepRe = RegExp(
    r'(?<!\d)(\d{1,3})[.,](\d{3})(?:\s*(đ|₫|d|vnd))?(?!\d)',
    caseSensitive: false,
  );

  static final RegExp _priceKRe = RegExp(
    r'(?<![a-zA-Z0-9])(\d{1,3})\s*[kK](?![a-zA-Z0-9])',
  );

  static final RegExp _normalizedPriceRe = RegExp(r'\b\d{4,7}đ\b');

  static final RegExp _hasAlphaNumRe = RegExp(
    r'[a-zA-Z0-9àáảãạăằắẳẵặâầấẩẫậđèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵ]',
    caseSensitive: false,
  );

  static final RegExp _standaloneXRe = RegExp(r'(?:^|\s)[xX×](?:\s|$)');

  static const Set<String> _uiNoiseSingleWords = {
    'insert',
    'delete',
    'del',
    'home',
    'end',
    'pgup',
    'pgdn',
    'tab',
    'shift',
    'ctrl',
    'alt',
    'esc',
    'enter',
    'backspace',
    'caps',
    'capslock',
    'numlock',
    'prtsc',
    'pause',
    'fn',
    'win',
    'cmd',
    'file',
    'edit',
    'view',
    'help',
    'tools',
    'window',
    'search',
    'settings',
    'bookmark',
    'bookmarks',
    'history',
    'downloads',
    'extensions',
    'close',
    'cancel',
    'ok',
    'back',
    'next',
    'share',
    'copy',
    'paste',
    'gemini',
    'chatgpt',
    'chrome',
    'edge',
    'firefox',
    'safari',
    'localhost',
    'lifelog',
    'bilibili',
    'youtube',
    'google',
    'github',
  };

  /// 将菜单中的越南盾常见价格写法规范化为整数 + `đ`（如 `50K` / `50.000đ` / `50,000` → `50000đ`），
  /// 降低大模型换算与千分位误判概率。
  static String normalizeMenuPrices(String text) {
    var out = text.replaceAllMapped(_priceThousandSepRe, (m) {
      final thousands = int.tryParse(m.group(1)!) ?? 0;
      final rest = m.group(2)!;
      final suffix = m.group(3);
      // 有明确货币后缀（đ/₫/d/vnd）或 >= 5,000 才按越南盾价格规范化，避免误改 1.250 等小数
      if (suffix != null || thousands >= 5) {
        return '${thousands * 1000 + int.parse(rest)}đ';
      }
      return m.group(0)!;
    });
    out = out.replaceAllMapped(_priceKRe, (m) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      // 过滤 1K/2K/4K 显示器分辨率字样，仅把 5K..999K 规范为越南盾整数
      if (n >= 5 && n <= 999) {
        return '${n * 1000}đ';
      }
      return m.group(0)!;
    });
    return out;
  }

  /// 本地清洗 OCR 菜单原文并统计丢弃噪音行数：
  /// 1) 过滤 URL/域名/查询串片段（http/.com/.html/%2F/cid= 等）
  /// 2) 过滤极短行（<3 字符）及纯符号行（短价格如 50K 除外）
  /// 3) 过滤键盘/浏览器 UI 噪音词、标签页关闭符 `X` 及乱码字母数字串
  /// 4) 规范化 `50K` / `50.000đ` / `50,000` 为整数越南盾，优先保留越南语变音符与价格行
  static ({String cleanedText, int rawLines, int keptLines, int droppedLines})
      cleanMenuOcrWithStats(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return (cleanedText: '', rawLines: 0, keptLines: 0, droppedLines: 0);
    }

    final rawLines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final kept = <String>[];
    for (final rawLine in rawLines) {
      // ① URL / 查询串 / 域名直接剔除
      if (_urlNoiseRe.hasMatch(rawLine)) continue;

      // 浏览器/电脑屏幕杂词直接剔除
      if (_browserBrandNoiseRe.hasMatch(rawLine)) continue;

      // 多处独立 "X" 浏览器标签页关闭按钮特征（如 "X 0TF-bilbilX ... X Lifelog EBAC"）
      if (_standaloneXRe.allMatches(rawLine).length >= 2) continue;

      // 先做价格规范化，避免 50K 被误判为短行或混合字母数字
      final normalized = normalizeMenuPrices(rawLine);
      final hasVn = _vietnameseDiacriticRe.hasMatch(normalized);
      final hasPrice = _normalizedPriceRe.hasMatch(normalized);

      // ② 极短行或纯符号行过滤（有价格的短行如 50000đ 保留）
      if (!hasPrice && (normalized.length < 3 || !_hasAlphaNumRe.hasMatch(normalized))) {
        continue;
      }

      // ③ 明显键盘/UI 单词过滤
      final lower = normalized.toLowerCase();
      if (_uiNoiseSingleWords.contains(lower)) continue;

      // 以独立 " X" 结尾的浏览器标签页（且不含越南语和价格）
      if (!hasVn && !hasPrice && RegExp(r'\s+[xX×]$').hasMatch(normalized)) {
        continue;
      }

      // 乱码字母数字混排（非越南语且非价格行）
      if (!hasVn && !hasPrice && _garbledMixedAlnumRe.hasMatch(normalized)) {
        continue;
      }

      kept.add(normalized);
    }

    // 兜底：若极端情况下全部被误滤，则回退规范化后的原文本避免空请求
    if (kept.isEmpty) {
      final fallback = normalizeMenuPrices(trimmed);
      return (
        cleanedText: fallback,
        rawLines: rawLines.length,
        keptLines: rawLines.length,
        droppedLines: 0,
      );
    }

    return (
      cleanedText: kept.join('\n'),
      rawLines: rawLines.length,
      keptLines: kept.length,
      droppedLines: rawLines.length - kept.length,
    );
  }

  /// 便捷接口：返回清洗与价格规范化后的菜单文本
  static String cleanMenuOcrTextForAi(String rawText) =>
      cleanMenuOcrWithStats(rawText).cleanedText;

  // ── v3.6.0 AR 浮层坐标映射、越南语变音符归一与 1.5s 画面稳定度检测 ──

  static const Map<String, String> _vnFoldMap = {
    'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
    'đ': 'd',
    'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
    'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
    'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
    'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
  };

  /// 折叠越南语声调与变音字母为 ASCII 小写基底，用于 OCR 框模糊匹配与稳定度对比
  static String foldVietnameseToAscii(String input) {
    final lower = input.toLowerCase();
    final sb = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      sb.write(_vnFoldMap[ch] ?? ch);
    }
    return sb.toString();
  }

  /// 计算两帧 OCR 文本的词集 Jaccard 相似度（0.0 ~ 1.0），用于判定画面是否稳定 >= 1.5 秒
  static double computeOcrTextSimilarity(String a, String b) {
    Set<String> tokenize(String s) {
      final cleaned = foldVietnameseToAscii(cleanMenuOcrTextForAi(s));
      return cleaned
          .split(RegExp(r'[^a-z0-9]+'))
          .where((t) => t.length >= 2)
          .toSet();
    }

    final setA = tokenize(a);
    final setB = tokenize(b);
    if (setA.isEmpty || setB.isEmpty) return 0.0;
    final inter = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union == 0 ? 0.0 : inter / union;
  }

  /// 将 AI 翻译出的菜品列表映射为取景框内的 Positioned AR 浮层坐标（最多返回 [maxOverlayCount] = 5 项）
  static List<MenuArOverlayAnchor> computeArOverlayAnchors({
    required List<MenuDishItem> dishes,
    required List<OcrTextItem> blocks,
    required Size imageSize,
    required Size viewSize,
    int maxOverlayCount = 5,
  }) {
    if (dishes.isEmpty || viewSize.width <= 0 || viewSize.height <= 0) {
      return const [];
    }

    // 推断原始图像尺寸（若未传则由 OCR 边界框包络推断，兜底 720x1280）
    var imgW = imageSize.width;
    var imgH = imageSize.height;
    if (imgW <= 1 || imgH <= 1) {
      var maxR = 720.0;
      var maxB = 1280.0;
      for (final b in blocks) {
        if (b.boundingBox.right > maxR) maxR = b.boundingBox.right * 1.05;
        if (b.boundingBox.bottom > maxB) maxB = b.boundingBox.bottom * 1.05;
      }
      imgW = maxR;
      imgH = maxB;
    }

    final scaleX = viewSize.width / imgW;
    final scaleY = viewSize.height / imgH;
    final minTop = 40.0;
    final maxTop = math.max(minTop, viewSize.height - 46.0);
    final tagMaxW = math.min(240.0, math.max(130.0, viewSize.width - 20.0));

    final foldedBlocks = <({OcrTextItem block, String folded, List<String> words})>[
      for (final b in blocks)
        (
          block: b,
          folded: foldVietnameseToAscii(b.text),
          words: foldVietnameseToAscii(b.text)
              .split(RegExp(r'[^a-z0-9]+'))
              .where((w) => w.length >= 2)
              .toList(),
        ),
    ];

    final limit = math.min(dishes.length, maxOverlayCount);
    final usedBlockIndices = <int>{};
    final placedTops = <double>[];
    final anchors = <MenuArOverlayAnchor>[];

    for (var i = 0; i < limit; i++) {
      final dish = dishes[i];
      final dishFolded = foldVietnameseToAscii(dish.vn).trim();
      final dishWords = dishFolded
          .split(RegExp(r'[^a-z0-9]+'))
          .where((w) => w.length >= 2)
          .toList();

      int? bestIdx;
      var bestScore = 0.0;
      for (var bIdx = 0; bIdx < foldedBlocks.length; bIdx++) {
        final fb = foldedBlocks[bIdx];
        if (fb.folded.isEmpty) continue;
        var score = 0.0;
        if (dishFolded.isNotEmpty && fb.folded.contains(dishFolded)) {
          score = 10.0;
        } else if (dishWords.isNotEmpty) {
          var hits = 0;
          for (final w in dishWords) {
            if (fb.words.contains(w) || fb.folded.contains(w)) hits++;
          }
          score = hits / dishWords.length;
        }
        if (usedBlockIndices.contains(bIdx)) {
          score *= 0.4;
        }
        if (score > bestScore && score >= 0.45) {
          bestScore = score;
          bestIdx = bIdx;
        }
      }

      double rawLeft;
      double rawTop;
      final bool matched;
      if (bestIdx != null) {
        usedBlockIndices.add(bestIdx);
        final rect = foldedBlocks[bestIdx].block.boundingBox;
        rawLeft = rect.left * scaleX;
        rawTop = rect.top * scaleY;
        matched = true;
      } else {
        rawLeft = 12.0;
        final span = math.max(1.0, maxTop - minTop);
        rawTop = minTop + (span * (i + 0.5) / (limit + 0.5));
        matched = false;
      }

      var left = rawLeft.clamp(8.0, math.max(8.0, viewSize.width - tagMaxW - 8.0)).toDouble();
      var top = rawTop.clamp(minTop, maxTop).toDouble();

      // 垂直防重叠避让（间距 >= 32px）
      for (var attempt = 0; attempt < 6; attempt++) {
        final conflict = placedTops.any((t) => (t - top).abs() < 32.0);
        if (!conflict) break;
        top += 34.0;
        if (top > maxTop) {
          top = minTop + (attempt * 17.0).clamp(0.0, maxTop - minTop).toDouble();
        }
      }
      placedTops.add(top);

      anchors.add(
        MenuArOverlayAnchor(
          dish: dish,
          left: left,
          top: top,
          maxWidth: tagMaxW,
          matchedBox: matched,
        ),
      );
    }

    return anchors;
  }
}
