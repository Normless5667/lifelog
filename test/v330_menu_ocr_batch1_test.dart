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
}
