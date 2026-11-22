import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/screens/diet/menu_ocr_lab_screen.dart';
import 'package:lifelog/services/menu_ocr_service.dart';
import 'package:lifelog/theme/app_theme.dart';

void main() {
  group('v3.3.0 Batch 1 MenuOcrService pure helpers', () {
    test('computeAndroidRotationDegrees computes back & front camera orientations accurately', () {
      expect(
        MenuOcrService.computeAndroidRotationDegrees(
          sensorOrientation: 90,
          deviceOrientation: DeviceOrientation.portraitUp,
          lensDirection: CameraLensDirection.back,
        ),
        90,
      );
      expect(
        MenuOcrService.computeAndroidRotationDegrees(
          sensorOrientation: 90,
          deviceOrientation: DeviceOrientation.landscapeLeft,
          lensDirection: CameraLensDirection.back,
        ),
        0,
      );
      expect(
        MenuOcrService.computeAndroidRotationDegrees(
          sensorOrientation: 270,
          deviceOrientation: DeviceOrientation.landscapeLeft,
          lensDirection: CameraLensDirection.front,
        ),
        0,
      );
    });

    test('convertYuv420ToNv21 interleaves V/U planes with row/pixel strides cleanly', () {
      // 4x2 frame => 8 Y bytes + 4 interleaved VU bytes = 12 bytes
      final yBytes = Uint8List.fromList([
        10, 11, 12, 13, 99, 99, // row 0 with stride=6
        20, 21, 22, 23, 99, 99, // row 1 with stride=6
      ]);
      final uBytes = Uint8List.fromList([100, 0, 101, 0]); // pixelStride=2
      final vBytes = Uint8List.fromList([200, 0, 201, 0]);

      final nv21 = MenuOcrService.convertYuv420ToNv21(
        width: 4,
        height: 2,
        yBytes: yBytes,
        yRowStride: 6,
        uBytes: uBytes,
        vBytes: vBytes,
        uvRowStride: 4,
        uvPixelStride: 2,
      );

      expect(nv21.length, 12);
      expect(nv21.sublist(0, 8), [10, 11, 12, 13, 20, 21, 22, 23]);
      // NV21 order: V0, U0, V1, U1
      expect(nv21.sublist(8, 12), [200, 100, 201, 101]);

      // Fast path (yRowStride == width) with separate vRowStride/vPixelStride
      final fastNv21 = MenuOcrService.convertYuv420ToNv21(
        width: 4,
        height: 2,
        yBytes: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        yRowStride: 4,
        uBytes: Uint8List.fromList([50, 51]),
        vBytes: Uint8List.fromList([60, 0, 61, 0]),
        uvRowStride: 2,
        uvPixelStride: 1,
        vRowStride: 4,
        vPixelStride: 2,
      );
      expect(fastNv21, [1, 2, 3, 4, 5, 6, 7, 8, 60, 50, 61, 51]);
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
