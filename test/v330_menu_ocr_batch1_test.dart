import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/screens/diet/menu_ocr_lab_screen.dart';
import 'package:lifelog/services/menu_ocr_service.dart';
import 'package:lifelog/theme/app_theme.dart';

class _FakeTextRecognizer implements TextRecognizer {
  final Future<RecognizedText> Function(InputImage input) onProcess;
  bool closed = false;

  _FakeTextRecognizer(this.onProcess);

  @override
  String get id => 'fake-recognizer';

  @override
  TextRecognitionScript get script => TextRecognitionScript.latin;

  @override
  Future<RecognizedText> processImage(InputImage inputImage) => onProcess(inputImage);

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  group('v3.3.5 MenuOcrService file-path capture pipeline', () {
    test('processFilePath parses Vietnamese diacritics & deletes temp file when deleteAfter=true',
        () async {
      final tmp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}lifelog_ocr_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmp.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
      expect(await tmp.exists(), isTrue);

      String? capturedPath;
      final fake = _FakeTextRecognizer((input) async {
        capturedPath = input.filePath;
        return RecognizedText(
          text: '  Phở bò tái chín · 65.000đ\nBún chả Hà Nội · 55.000đ  ',
          blocks: [
            TextBlock(
              text: '  Phở bò tái chín · 65.000đ ',
              lines: [
                TextLine(
                  text: 'Phở bò tái chín · 65.000đ',
                  elements: const [],
                  boundingBox: const Rect.fromLTWH(10, 20, 200, 30),
                  recognizedLanguages: const ['vi'],
                  cornerPoints: const [],
                  confidence: 0.98,
                  angle: 0,
                ),
              ],
              boundingBox: const Rect.fromLTWH(10, 20, 200, 30),
              recognizedLanguages: const ['vi'],
              cornerPoints: const [],
            ),
            TextBlock(
              text: '   ',
              lines: const [],
              boundingBox: Rect.zero,
              recognizedLanguages: const [],
              cornerPoints: const [],
            ),
          ],
        );
      });

      final service = MenuOcrService(recognizer: fake);
      final res = await service.processFilePath(
        tmp.path,
        source: 'stream',
        deleteAfter: true,
      );

      expect(capturedPath, tmp.path);
      expect(res.source, 'stream');
      expect(res.blocks.length, 1);
      expect(res.blocks.first.text, 'Phở bò tái chín · 65.000đ');
      expect(res.fullText, contains('Bún chả Hà Nội'));
      expect(await tmp.exists(), isFalse);

      await service.dispose();
      expect(fake.closed, isTrue);
    });

    test('processFilePath preserves gallery file when deleteAfter=false & cleans up on error when deleteAfter=true',
        () async {
      final keepFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}lifelog_ocr_keep_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      final errFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}lifelog_ocr_err_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await keepFile.writeAsBytes([1, 2, 3]);
      await errFile.writeAsBytes([4, 5, 6]);

      try {
        final okService = MenuOcrService(
          recognizer: _FakeTextRecognizer(
            (_) async => RecognizedText(text: 'Cơm tấm', blocks: const []),
          ),
        );
        final res = await okService.processFilePath(
          keepFile.path,
          source: 'gallery',
          deleteAfter: false,
        );
        expect(res.fullText, 'Cơm tấm');
        expect(await keepFile.exists(), isTrue);

        final failService = MenuOcrService(
          recognizer: _FakeTextRecognizer(
            (_) async => throw StateError('mock recognizer failure'),
          ),
        );
        await expectLater(
          failService.processFilePath(
            errFile.path,
            source: 'stream',
            deleteAfter: true,
          ),
          throwsStateError,
        );
        expect(await errFile.exists(), isFalse);
      } finally {
        if (await keepFile.exists()) await keepFile.delete();
        if (await errFile.exists()) await errFile.delete();
      }
    });
  });

  group('v3.3.0 Batch 1 MenuOcrLabScreen widget verification', () {
    testWidgets('displays recognized Vietnamese menu blocks (Phở bò / Bún chả) & toggles freeze',
        (tester) async {
      const mockResult = MenuOcrFrameResult(
        blocks: [
          OcrTextItem(
            text: 'Phở bò tái chín · 65.000đ',
            boundingBox: Rect.fromLTWH(24, 80, 320, 44),
            lines: ['Phở bò tái chín · 65.000đ'],
          ),
          OcrTextItem(
            text: 'Bún chả Hà Nội · 55.000đ',
            boundingBox: Rect.fromLTWH(24, 140, 310, 44),
            lines: ['Bún chả Hà Nội · 55.000đ'],
          ),
        ],
        fullText: 'Phở bò tái chín · 65.000đ\nBún chả Hà Nội · 55.000đ',
        elapsedMs: 54,
        imageSize: Size(720, 1280),
        source: 'stream',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MenuOcrLabScreen(
            disableCameraForTest: true,
            initialResultForTest: mockResult,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('menu_ocr_status_pill')), findsOneWidget);
      expect(find.text('实时 · 54 ms · 2 块'), findsOneWidget);
      expect(find.text('Phở bò tái chín · 65.000đ'), findsOneWidget);
      expect(find.text('Bún chả Hà Nội · 55.000đ'), findsOneWidget);

      // 点击「定格画面」后切换状态胶囊为「已定格 · 2 块」
      await tester.tap(find.byKey(const ValueKey('menu_ocr_pause_btn')));
      await tester.pump();
      expect(find.text('已定格 · 2 块'), findsOneWidget);
      expect(find.text('继续实时'), findsOneWidget);
    });
  });

  group('v3.4.2 Local Menu OCR Noise Cleaning & Price Normalization', () {
    test('normalizeMenuPrices converts 50K / 50.000đ / 50,000 to integer VND without mangling 4K or decimals', () {
      expect(MenuOcrService.normalizeMenuPrices('Cà phê đen đá 45K'), 'Cà phê đen đá 45000đ');
      expect(MenuOcrService.normalizeMenuPrices('Bạc xỉu 50.000đ'), 'Bạc xỉu 50000đ');
      expect(MenuOcrService.normalizeMenuPrices('Trà đào cam sả 50,000'), 'Trà đào cam sả 50000đ');
      expect(MenuOcrService.normalizeMenuPrices('Phở bò 120.000 VND'), 'Phở bò 120000đ');
      expect(MenuOcrService.normalizeMenuPrices('48k'), '48000đ');
      // 4K monitor label & 1.250 decimal should not be converted
      expect(MenuOcrService.normalizeMenuPrices('4K display 1.250'), '4K display 1.250');
    });

    test('cleanMenuOcrWithStats strips browser tabs, URLs, UI keys, garbled text while keeping Vietnamese dishes & prices', () {
      const noisyRaw = '''
Gemini X
pngtree.com
https://example.com/menu?cid=123
FdetaiV2&cid=-Bpil9abc
insert
Tab
X 0TF-bilbilX GPT 62 Astra 1computer USe, X Lifelog EBAC
--
AB
CÀ PHÊ ĐEN ĐÁ
45K
Cà phê sữa đá · 50.000đ
Bạc xỉu 50,000
Hot Chocolate 48K
''';
      final stats = MenuOcrService.cleanMenuOcrWithStats(noisyRaw);
      expect(stats.droppedLines, greaterThanOrEqualTo(9));
      expect(stats.cleanedText, isNot(contains('Gemini')));
      expect(stats.cleanedText, isNot(contains('pngtree.com')));
      expect(stats.cleanedText, isNot(contains('cid=')));
      expect(stats.cleanedText, isNot(contains('insert')));
      expect(stats.cleanedText, isNot(contains('bilbil')));
      expect(stats.cleanedText, isNot(contains('Lifelog')));

      expect(stats.cleanedText, contains('CÀ PHÊ ĐEN ĐÁ'));
      expect(stats.cleanedText, contains('45000đ'));
      expect(stats.cleanedText, contains('Cà phê sữa đá · 50000đ'));
      expect(stats.cleanedText, contains('Bạc xỉu 50000đ'));
      expect(stats.cleanedText, contains('Hot Chocolate 48000đ'));
    });

    test('cleanMenuOcrWithStats falls back safely if every line looks like noise', () {
      final stats = MenuOcrService.cleanMenuOcrWithStats('AB\n--');
      expect(stats.cleanedText, isNotEmpty);
    });

    test('processCapturedFile deletes BOTH raw & compressed temp files on success and on error', () async {
      final ts = DateTime.now().microsecondsSinceEpoch;
      final rawOk = File('${Directory.systemTemp.path}${Platform.pathSeparator}lifelog_raw_ok_$ts.jpg');
      final cmpOk = File('${Directory.systemTemp.path}${Platform.pathSeparator}lifelog_cmp_ok_$ts.jpg');
      final rawErr = File('${Directory.systemTemp.path}${Platform.pathSeparator}lifelog_raw_err_$ts.jpg');
      final cmpErr = File('${Directory.systemTemp.path}${Platform.pathSeparator}lifelog_cmp_err_$ts.jpg');
      await rawOk.writeAsBytes(List<int>.filled(1024, 1));
      await rawErr.writeAsBytes(List<int>.filled(1024, 2));

      try {
        final okSvc = MenuOcrService(
          recognizer: _FakeTextRecognizer(
            (input) async {
              expect(input.filePath, cmpOk.path);
              // 原始大图在压缩后应已被提前删除
              expect(await rawOk.exists(), isFalse);
              return RecognizedText(text: 'Cà phê đen · 45K', blocks: const []);
            },
          ),
        );
        final out = await okSvc.processCapturedFile(
          rawOk.path,
          compressOverrideForTest: (_) async {
            await cmpOk.writeAsBytes(List<int>.filled(256, 3));
            return OcrImagePrepResult(
              path: cmpOk.path,
              width: 720,
              height: 1280,
              origWidth: 3000,
              origHeight: 4000,
              origBytes: 1500000,
              compressedBytes: 260000,
              compressed: true,
            );
          },
        );
        expect(out.result.fullText, 'Cà phê đen · 45K');
        expect(out.prep.summary(), '3000x4000(1464KB)->720x1280(253KB)');
        expect(await rawOk.exists(), isFalse);
        expect(await cmpOk.exists(), isFalse);

        final errSvc = MenuOcrService(
          recognizer: _FakeTextRecognizer((_) async => throw StateError('ocr error')),
        );
        await expectLater(
          errSvc.processCapturedFile(
            rawErr.path,
            compressOverrideForTest: (_) async {
              await cmpErr.writeAsBytes(List<int>.filled(200, 4));
              return OcrImagePrepResult(
                path: cmpErr.path,
                width: 720,
                height: 1280,
                origWidth: 3000,
                origHeight: 4000,
                origBytes: 1500000,
                compressedBytes: 200000,
                compressed: true,
              );
            },
          ),
          throwsStateError,
        );
        expect(await rawErr.exists(), isFalse);
        expect(await cmpErr.exists(), isFalse);
      } finally {
        for (final f in [rawOk, cmpOk, rawErr, cmpErr]) {
          if (await f.exists()) await f.delete();
        }
      }
    });
  });
}
