import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/screens/diet/menu_ocr_lab_screen.dart';
import 'package:lifelog/services/ai_service.dart';
import 'package:lifelog/services/menu_ocr_service.dart';
import 'package:lifelog/theme/app_theme.dart';

void main() {
  const sampleOcr = MenuOcrFrameResult(
    blocks: [
      OcrTextItem(
        text: 'Phở bò 120.000đ\nBún chả 65k',
        boundingBox: Rect.fromLTWH(20, 40, 300, 80),
      ),
    ],
    fullText: 'Phở bò 120.000đ\nBún chả 65k',
    elapsedMs: 48,
    imageSize: Size(720, 1280),
    source: 'stream',
  );

  group('v3.3.1 Batch 2 Menu AI JSON Parser', () {
    test('parses valid menu JSON with fx_rate, items, macros, light & VND variants', () {
      final res = AiService.parseMenuTranslationResponse('''
```json
{
  "fx_rate": 0.000285,
  "items": [
    {
      "id": 1,
      "vn": "Phở bò",
      "cn": "牛肉粉",
      "vnd": 120000,
      "rmb": 34.2,
      "kcal": 320,
      "macros": {"p": 38, "c": 2, "f": 17},
      "light": "green",
      "tip": "高蛋白，汤底偏咸"
    },
    {
      "id": 2,
      "vn": "Bún chả",
      "cn": "烤肉米线",
      "vnd": "65k",
      "rmb": null,
      "kcal": 580,
      "macros": {"p": 26, "c": 62, "f": 22},
      "light": "yellow",
      "tip": "蘸汁略甜"
    }
  ]
}
```
''');
      expect(res.parseFailed, isFalse);
      expect(res.fxRate, closeTo(0.000285, 0.000001));
      expect(res.items.length, 2);
      expect(res.items[0].vn, 'Phở bò');
      expect(res.items[0].cn, '牛肉粉');
      expect(res.items[0].vnd, 120000);
      expect(res.items[0].effectiveRmb(0.000285), closeTo(34.2, 0.05));
      expect(res.items[0].kcal, 320);
      expect(res.items[0].light, 'green');
      expect(res.items[1].vnd, 65000);
      expect(res.items[1].effectiveRmb(0.00030), closeTo(19.5, 0.05));
    });

    test('returns parseFailed=true with rawReply intact when AI output is not valid JSON', () {
      final res = AiService.parseMenuTranslationResponse(
        'Phở bò 是牛肉粉，大约 120,000 越南盾。',
      );
      expect(res.parseFailed, isTrue);
      expect(res.items, isEmpty);
      expect(res.rawReply, contains('Phở bò 是牛肉粉'));
    });
  });

  group('v3.3.1 Batch 2 MenuOcrLabScreen Translation UI, FX Edit & Error States', () {
    testWidgets('translates OCR text to dish card list & live-recalculates RMB on FX rate edit',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MenuOcrLabScreen(
            disableCameraForTest: true,
            initialResultForTest: sampleOcr,
            onTranslateForTest: (ocrText, fx) async {
              expect(ocrText, contains('Phở bò'));
              return const MenuTranslationResult(
                fxRate: 0.000285,
                items: [
                  MenuDishItem(
                    id: 1,
                    vn: 'Phở bò',
                    cn: '牛肉粉',
                    vnd: 120000,
                    rmb: 34.2,
                    kcal: 320,
                    proteinG: 38,
                    carbsG: 2,
                    fatG: 17,
                    light: 'green',
                    tip: '高蛋白，汤底偏咸',
                  ),
                ],
                rawReply: '{}',
              );
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('menu_translate_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('menu_translated_list')), findsOneWidget);
      expect(find.text('牛肉粉'), findsOneWidget);
      expect(find.text('Phở bò'), findsOneWidget);
      expect(find.text('120,000₫ ≈ 34.2元'), findsOneWidget);
      expect(find.text('320 kcal'), findsOneWidget);
      expect(find.text('推荐'), findsOneWidget);

      // 手动修改汇率为 0.00030 -> 120,000 * 0.00030 = 36.0元 实时重算
      await tester.enterText(find.byKey(const ValueKey('menu_fx_rate_input')), '0.00030');
      await tester.pump();
      expect(find.text('120,000₫ ≈ 36.0元'), findsOneWidget);
    });

    testWidgets('handles unconfigured API, timeout retry, and non-JSON raw reply safely',
        (tester) async {
      var attempt = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MenuOcrLabScreen(
            disableCameraForTest: true,
            initialResultForTest: sampleOcr,
            onTranslateForTest: (_, _) async {
              attempt++;
              if (attempt == 1) {
                throw AiException('还没有配置 AI 接口，请先到「设置」里填写 API Key', needsConfig: true);
              }
              if (attempt == 2) {
                throw AiException('请求超时，请稍后再试');
              }
              return const MenuTranslationResult(
                fxRate: null,
                items: [],
                rawReply: 'Raw plain text reply without JSON',
                parseFailed: true,
              );
            },
          ),
        ),
      );
      await tester.pump();

      // 1) 未配置 API -> 弹出明确错误 + 「去设置配置 API」按钮
      await tester.tap(find.byKey(const ValueKey('menu_translate_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu_translate_error_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu_open_settings_btn')), findsOneWidget);

      // 2) 点重试 -> 模拟超时 -> 仍有重试按钮
      await tester.tap(find.byKey(const ValueKey('menu_retry_btn')));
      await tester.pumpAndSettle();
      expect(find.text('请求超时，请稍后再试'), findsOneWidget);
      expect(find.byKey(const ValueKey('menu_retry_btn')), findsOneWidget);

      // 3) 再点重试 -> 非法 JSON 回复 -> 展示原始回复绝不崩溃
      await tester.tap(find.byKey(const ValueKey('menu_retry_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu_parse_failed_card')), findsOneWidget);
      expect(find.text('Raw plain text reply without JSON'), findsOneWidget);
    });
  });
}
