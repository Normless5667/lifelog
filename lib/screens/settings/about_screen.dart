import 'package:flutter/material.dart';

/// 关于页（隐藏彩蛋：展示大肥鱼 Q 版形象与说明）
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于 · 生活助手')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/icon/dafeiyu_mascot.png',
                      width: 136,
                      height: 136,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '生活助手 (Life Assistant)',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('版本 v1.2.0 (Build 3)', style: TextStyle(color: cs.outline, fontSize: 13)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '🐟 由大肥鱼协助开发与监工 · 陪伴你的每一天',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '集课程表、Hai Ba Trung 校车倒计时、实时天气播报、拍照热量识别、力量训练计时、MET 有氧与自动计步、DeepSeek AI 私人教练于一体的全能个人生活助手。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
