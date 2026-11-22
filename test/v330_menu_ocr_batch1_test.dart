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

    test('convertYPlaneToRgbaBitmap converts Y luminance to exact ARGB_8888 RGBA bytes & decimates oversized frames', () {
      final yBytes = Uint8List.fromList([
        10, 20, 99, // row 0, stride=3, width=2
        30, 40, 99, // row 1, stride=3, width=2
      ]);
      final bmp = MenuOcrService.convertYPlaneToRgbaBitmap(
        width: 2,
        height: 2,
        yBytes: yBytes,
        yRowStride: 3,
      );
      expect(bmp.width, 2);
      expect(bmp.height, 2);
      expect(bmp.rgba, [
        10, 10, 10, 255, 20, 20, 20, 255,
        30, 30, 30, 255, 40, 40, 40, 255,
      ]);

      // Oversized 2000x1000 frame decimates cleanly (step=3 -> 667x334)
      final bigY = Uint8List(2000 * 1000);
      final dec = MenuOcrService.convertYPlaneToRgbaBitmap(
        width: 2000,
        height: 1000,
        yBytes: bigY,
        yRowStride: 2000,
      );
      expect(dec.width, lessThanOrEqualTo(960));
      expect(dec.rgba.length, dec.width * dec.height * 4);
    });

    test('encodeYPlaneToUprightGrayscaleBmp builds valid 8-bit BMP with 90deg CW rotation & 4-byte padding', () {
      // 3x2 source image:
      // row 0: [10, 20, 30]
      // row 1: [40, 50, 60]
      final yBytes = Uint8List.fromList([
        10, 20, 30, 99, // stride=4
        40, 50, 60, 99,
      ]);
      // 90 deg CW => 2x3 upright image:
      // outY=0: [40, 10]
      // outY=1: [50, 20]
      // outY=2: [60, 30]
      final enc = MenuOcrService.encodeYPlaneToUprightGrayscaleBmp(
        width: 3,
        height: 2,
        yBytes: yBytes,
        yRowStride: 4,
        rotationDeg: 90,
      );
      expect(enc.width, 2);
      expect(enc.height, 3);
      // Magic 'BM'
      expect(enc.bmpBytes[0], 0x42);
      expect(enc.bmpBytes[1], 0x4D);
      // rowStride = (2 + 3) & ~3 = 4, pixelOffset = 1078, total = 1078 + 4*3 = 1090
      expect(enc.bmpBytes.length, 1090);
      // Bottom-up BMP:
      // bmpRow 0 = outY=2 => [60, 30]
      expect(enc.bmpBytes.sublist(1078, 1080), [60, 30]);
      // bmpRow 1 = outY=1 => [50, 20]
      expect(enc.bmpBytes.sublist(1082, 1084), [50, 20]);
      // bmpRow 2 = outY=0 => [40, 10]
      expect(enc.bmpBytes.sublist(1086, 1088), [40, 10]);
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
