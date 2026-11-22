import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/models.dart';
import 'package:lifelog/screens/diet/quick_log_meal_dialog.dart';
import 'package:lifelog/theme/app_theme.dart';

void main() {
  final sampleRecent = <Meal>[
    Meal(
      date: '2026-11-20',
      mealType: 1,
      name: '鸡胸肉饭',
      amount: '1份',
      calories: 320,
      protein: 38,
      carbs: 35,
      fat: 5,
    ),
    Meal(
      date: '2026-11-21',
      mealType: 0,
      name: '牛肉粉',
      amount: '1碗',
      calories: 280,
      protein: 24,
      carbs: 36,
      fat: 6,
    ),
  ];

  Widget buildHost({
    required ValueChanged<QuickLogMealResult?> onResult,
    Future<({List<FoodEstimate> foods, String note})> Function(String name)? onEstimate,
  }) {
    return MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open_quick_meal'),
              onPressed: () async {
                final res = await showDialog<QuickLogMealResult>(
                  context: context,
                  builder: (_) => QuickLogMealDialog(
                    date: '2026-11-22',
                    mealType: 1,
                    recentMeals: sampleRecent,
                    onEstimateForTest: onEstimate,
                  ),
                );
                onResult(res);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  group('v3.5.0 QuickLogMealDialog two-step quick diet logging', () {
    testWidgets('Step 1 has only 1 TextField & 1-tap recent item saves immediately as reuseRecent',
        (tester) async {
      QuickLogMealResult? result;
      await tester.pumpWidget(buildHost(onResult: (r) => result = r));
      await tester.tap(find.byKey(const ValueKey('open_quick_meal')));
      await tester.pumpAndSettle();

      // 第一步严格只有 1 个输入框，不再吓跑用户
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_meal_name_input')), findsOneWidget);
      expect(find.text('鸡胸肉饭'), findsOneWidget);
      expect(find.text('牛肉粉'), findsOneWidget);

      // 点「最近吃过」第一项，直接带出热量营养素并关闭弹窗
      await tester.tap(find.byKey(const ValueKey('quick_recent_meal_0')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.path, QuickLogMealPath.reuseRecent);
      expect(result!.meal.name, '鸡胸肉饭');
      expect(result!.meal.calories, 320);
      expect(result!.meal.protein, 38);
      expect(result!.meal.date, '2026-11-22');
    });

    testWidgets('Step 1 -> Next prioritizes exact recent meal match without calling AI',
        (tester) async {
      QuickLogMealResult? result;
      var aiCalled = false;
      await tester.pumpWidget(
        buildHost(
          onResult: (r) => result = r,
          onEstimate: (_) async {
            aiCalled = true;
            return (foods: const <FoodEstimate>[], note: '');
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open_quick_meal')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('quick_meal_name_input')), '牛肉粉');
      await tester.tap(find.byKey(const ValueKey('quick_meal_next_btn')));
      await tester.pumpAndSettle();

      expect(aiCalled, isFalse);
      expect(find.text('已从历史记录带出'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_meal_confirm_kcal')), findsOneWidget);
      expect(find.text('280'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quick_meal_confirm_save_btn')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.path, QuickLogMealPath.quickSave);
      expect(result!.meal.name, '牛肉粉');
      expect(result!.meal.calories, 280);
    });

    testWidgets('Step 1 -> Next calls AI estimate for new food & saves on confirm',
        (tester) async {
      QuickLogMealResult? result;
      await tester.pumpWidget(
        buildHost(
          onResult: (r) => result = r,
          onEstimate: (name) async => (
            foods: [
              FoodEstimate(
                name: name,
                amount: '1碗约350g',
                calories: 460,
                protein: 28,
                carbs: 52,
                fat: 14,
              ),
            ],
            note: '高蛋白碳水均衡',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open_quick_meal')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('quick_meal_name_input')), '越南烤肉米线');
      await tester.tap(find.byKey(const ValueKey('quick_meal_next_btn')));
      await tester.pumpAndSettle();

      expect(find.text('AI 已自动估算'), findsOneWidget);
      expect(find.text('460'), findsOneWidget);
      expect(find.text('高蛋白碳水均衡'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quick_meal_confirm_save_btn')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.path, QuickLogMealPath.quickSave);
      expect(result!.meal.name, '越南烤肉米线');
      expect(result!.meal.calories, 460);
      expect(result!.meal.protein, 28);
    });

    testWidgets('Step 1 -> Next falls back cleanly to full form when AI estimate fails',
        (tester) async {
      QuickLogMealResult? result;
      await tester.pumpWidget(
        buildHost(
          onResult: (r) => result = r,
          onEstimate: (_) async => throw StateError('API not configured'),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open_quick_meal')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('quick_meal_name_input')), '未知甜点');
      await tester.tap(find.byKey(const ValueKey('quick_meal_next_btn')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.path, QuickLogMealPath.openFullForm);
      expect(result!.meal.name, '未知甜点');
      expect(result!.fallbackError, contains('API not configured'));
    });
  });
}
