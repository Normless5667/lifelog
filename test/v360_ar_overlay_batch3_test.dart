import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/screens/diet/menu_ocr_lab_screen.dart';
import 'package:lifelog/services/ai_service.dart';
import 'package:lifelog/services/menu_ocr_service.dart';
import 'package:lifelog/theme/app_theme.dart';

void main() {
  group('v3.6.0 AR Overlay coordinate mapping & 1.5s stability helpers', () {
    test('foldVietnameseToAscii & computeOcrTextSimilarity match diacritic variants reliably', () {
      expect(
        MenuOcrService.foldVietnameseToAscii('CÀ PHÊ SỮA ĐÁ · Phở Bò Tái Chín'),
        'ca phe sua da · pho bo tai chin',
      );
      final sim = MenuOcrService.computeOcrTextSimilarity(
        'CÀ PHÊ ĐEN ĐÁ 45K\nBẠC XỈU 50K\nTRÀ ĐÀO 55K',
        'CA PHE DEN DA 45000đ\nBAC XIU 50000đ\nTRA DAO 55000đ',
      );
      expect(sim, greaterThanOrEqualTo(0.75));
    });

    test('computeArOverlayAnchors maps dishes to OCR boxes, caps at 5 items & avoids vertical overlap', () {
      final blocks = <OcrTextItem>[
        const OcrTextItem(
          text: 'CÀ PHÊ ĐEN ĐÁ',
          boundingBox: Rect.fromLTWH(40, 120, 260, 40),
        ),
        const OcrTextItem(
          text: 'CÀ PHÊ SỮA ĐÁ',
          boundingBox: Rect.fromLTWH(40, 125, 260, 40), // 故意紧贴上一项测试防重叠
        ),
        const OcrTextItem(
          text: 'BẠC XỈU',
          boundingBox: Rect.fromLTWH(40, 320, 220, 40),
        ),
      ];
      final dishes = List<MenuDishItem>.generate(
        7,
        (i) => MenuDishItem(
          id: i + 1,
          vn: switch (i) {
            0 => 'Cà phê đen đá',
            1 => 'Cà phê sữa đá',
            2 => 'Bạc xỉu',
            _ => 'Món số ${i + 1}',
          },
          cn: '菜品${i + 1}',
          vnd: 45000 + i * 5000,
          rmb: 12.8,
          kcal: 120 + i * 30,
          light: i == 0 ? 'green' : (i == 6 ? 'red' : 'yellow'),
        ),
      );

      final anchors = MenuOcrService.computeArOverlayAnchors(
        dishes: dishes,
        blocks: blocks,
        imageSize: const Size(720, 1280),
        viewSize: const Size(360, 320),
        maxOverlayCount: 5,
      );

      // 超过 5 项时浮层最多只取前 5 项
      expect(anchors.length, 5);
      expect(anchors[0].matchedBox, isTrue);
      expect(anchors[1].matchedBox, isTrue);
      expect(anchors[2].matchedBox, isTrue);
      // 垂直防重叠：前两项原本高度几乎重合，避让后间距 >= 30px
      expect((anchors[1].top - anchors[0].top).abs(), greaterThanOrEqualTo(30.0));
      // 所有标签严格限制在取景框安全边界内
      for (final a in anchors) {
        expect(a.left, greaterThanOrEqualTo(8.0));
        expect(a.top, inInclusiveRange(40.0, 320.0 - 46.0));
      }
    });
  });

  group('v3.6.0 MenuOcrLabScreen AR Overlay & >5 ModalBottomSheet widget tests', () {
    testWidgets('renders Positioned AR tags and collapses >5 items into ModalBottomSheet',
        (tester) async {
      const mockOcr = MenuOcrFrameResult(
        blocks: [
          OcrTextItem(
            text: 'CÀ PHÊ ĐEN ĐÁ 45K',
            boundingBox: Rect.fromLTWH(30, 100, 260, 40),
          ),
          OcrTextItem(
            text: 'BẠC XỈU 50K',
            boundingBox: Rect.fromLTWH(30, 240, 240, 40),
          ),
        ],
        fullText: 'CÀ PHÊ ĐEN ĐÁ 45K\nBẠC XỈU 50K',
        elapsedMs: 180,
        imageSize: Size(720, 1280),
        source: 'stream',
      );

      final sevenDishes = MenuTranslationResult(
        fxRate: 0.000285,
        rawReply: '{}',
        items: [
          for (var i = 1; i <= 7; i++)
            MenuDishItem(
              id: i,
              vn: i == 1 ? 'Cà phê đen đá' : 'Món $i',
              cn: '越式咖啡$i号',
              vnd: 50000,
              rmb: 14.3,
              kcal: 90 + i * 10,
              light: i == 1 ? 'green' : 'yellow',
            ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MenuOcrLabScreen(
            disableCameraForTest: true,
            initialResultForTest: mockOcr,
            initialTranslationForTest: sevenDishes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 取景框内最多渲染 5 个 AR 浮层标签（1..5 存在，6..7 被折叠）
      expect(find.byKey(const ValueKey('menu_ar_tag_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu_ar_tag_5')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu_ar_tag_6')), findsNothing);

      // 超过 5 项时显示折叠胶囊按钮
      final collapseBtn = find.byKey(const ValueKey('menu_ar_more_sheet_btn'));
      expect(collapseBtn, findsOneWidget);
      expect(find.textContaining('共 7 道菜（已折叠 2 项）'), findsOneWidget);

      // 点击折叠胶囊弹出 ModalBottomSheet 展示全部 7 道菜
      await tester.tap(collapseBtn);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu_ar_all_dishes_sheet')), findsOneWidget);
      expect(find.text('全部识别菜品（7）'), findsOneWidget);
    });
  });
}
