import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/nutrition.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';

/// 首次使用引导问卷（也可从「身体资料」页随时重新打开）
class OnboardingSheet extends StatefulWidget {
  final Profile? initialProfile;
  final double? initialWeight;

  const OnboardingSheet({super.key, this.initialProfile, this.initialWeight});

  @override
  State<OnboardingSheet> createState() => _OnboardingSheetState();
}

class _OnboardingSheetState extends State<OnboardingSheet> {
  late String _gender;
  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _targetWeight;
  late double _activity;
  late String _goal;
  late String _experience;
  late int _weeklyDays;
  late int _sessionMinutes;
  late String _equipment;
  late final TextEditingController _injuries;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile ?? Profile();
    _gender = p.gender;
    _age = TextEditingController(text: '${p.age}');
    _height = TextEditingController(text: fmtNum(p.height));
    _weight = TextEditingController(text: widget.initialWeight != null ? fmtNum(widget.initialWeight!, digits: 1) : '65');
    _targetWeight = TextEditingController(text: p.targetWeight != null ? fmtNum(p.targetWeight!, digits: 1) : '');
    _activity = Nutrition.activityLevels.containsKey(p.activity) ? p.activity : 1.375;
    _goal = p.goal;
    _experience = p.experience;
    _weeklyDays = p.weeklyDays.clamp(1, 7);
    _sessionMinutes = p.sessionMinutes;
    _equipment = p.equipment;
    _injuries = TextEditingController(text: p.injuries);
  }

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _targetWeight.dispose();
    _injuries.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final age = int.tryParse(_age.text.trim()) ?? 20;
    final height = double.tryParse(_height.text.trim()) ?? 170;
    final weight = double.tryParse(_weight.text.trim());
    final targetW = double.tryParse(_targetWeight.text.trim());

    await Repo.saveProfile(Profile(
      gender: _gender,
      age: age.clamp(10, 100),
      height: height.clamp(100, 250),
      activity: _activity,
      goal: _goal,
      targetWeight: targetW,
      experience: _experience,
      weeklyDays: _weeklyDays,
      sessionMinutes: _sessionMinutes,
      equipment: _equipment,
      injuries: _injuries.text.trim(),
    ));
    if (weight != null && weight >= 25 && weight <= 250) {
      await Repo.saveBodyRecord(BodyRecord(date: today(), weight: weight));
    }
    await Repo.setOnboardingDone();
    if (!mounted) return;
    toast(context, '个人档案已保存，TDEE 与 AI 上下文已初始化！');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    const numKb = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.assignment_ind_rounded, color: Colors.teal),
            SizedBox(width: 8),
            Text('定制你的健康与训练档案'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Repo.setOnboardingDone();
              if (context.mounted) Navigator.pop(context, false);
            },
            child: const Text('跳过'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: Colors.teal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '花 30 秒填好基本情况，系统将自动计算你的动态热量目标，并在每次与 DeepSeek AI 对话时自动带上这些条件。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('1. 基本身体数据', icon: Icons.person_rounded, iconColor: Color(0xFF42A5F5)),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'male', icon: Icon(Icons.male_rounded), label: Text('男生')),
              ButtonSegment(value: 'female', icon: Icon(Icons.female_rounded), label: Text('女生')),
            ],
            selected: {_gender},
            onSelectionChanged: (s) => setState(() => _gender = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _age,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '年龄',
                    suffixText: '岁',
                    prefixIcon: Icon(Icons.cake_rounded, color: Color(0xFFFFA726)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType: numKb,
                  decoration: const InputDecoration(
                    labelText: '身高',
                    suffixText: 'cm',
                    prefixIcon: Icon(Icons.height_rounded, color: Color(0xFF26A69A)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType: numKb,
                  decoration: const InputDecoration(
                    labelText: '当前体重',
                    suffixText: 'kg',
                    prefixIcon: Icon(Icons.monitor_weight_rounded, color: Color(0xFF42A5F5)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _targetWeight,
                  keyboardType: numKb,
                  decoration: const InputDecoration(
                    labelText: '目标体重(可选)',
                    suffixText: 'kg',
                    prefixIcon: Icon(Icons.flag_rounded, color: Color(0xFFEF5350)),
                  ),
                ),
              ),
            ],
          ),
          const SectionTitle('2. 目标与日常活动量', icon: Icons.track_changes_rounded, iconColor: Color(0xFFEF5350)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: Nutrition.goals.entries.map((e) {
              return ChoiceChip(
                label: Text(e.value),
                selected: _goal == e.key,
                onSelected: (_) => setState(() => _goal = e.key),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<double>(
            initialValue: _activity,
            decoration: const InputDecoration(
              labelText: '日常静息/工作活动水平（不含健身）',
              prefixIcon: Icon(Icons.directions_walk_rounded, color: Color(0xFF26A69A)),
            ),
            items: Nutrition.activityLevels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _activity = v ?? _activity),
          ),
          const SectionTitle('3. 运动经验与训练条件', icon: Icons.fitness_center_rounded, iconColor: Color(0xFFAB47BC)),
          const Text('运动经验', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: Nutrition.experiences.entries.map((e) {
              return ChoiceChip(
                label: Text(e.value),
                selected: _experience == e.key,
                onSelected: (_) => setState(() => _experience = e.key),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _weeklyDays,
                  decoration: const InputDecoration(
                    labelText: '每周可练天数',
                    prefixIcon: Icon(Icons.calendar_today_rounded, color: Color(0xFF42A5F5)),
                  ),
                  items: [for (var d = 1; d <= 7; d++) DropdownMenuItem(value: d, child: Text('每周 $d 天'))],
                  onChanged: (v) => setState(() => _weeklyDays = v ?? _weeklyDays),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: [30, 45, 60, 75, 90, 120].contains(_sessionMinutes) ? _sessionMinutes : 60,
                  decoration: const InputDecoration(
                    labelText: '每次时长',
                    prefixIcon: Icon(Icons.timer_rounded, color: Color(0xFFFFA726)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 分钟')),
                    DropdownMenuItem(value: 45, child: Text('45 分钟')),
                    DropdownMenuItem(value: 60, child: Text('60 分钟')),
                    DropdownMenuItem(value: 75, child: Text('75 分钟')),
                    DropdownMenuItem(value: 90, child: Text('90 分钟')),
                    DropdownMenuItem(value: 120, child: Text('120 分钟')),
                  ],
                  onChanged: (v) => setState(() => _sessionMinutes = v ?? _sessionMinutes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('可用器械', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: Nutrition.equipments.entries.map((e) {
              return ChoiceChip(
                label: Text(e.value),
                selected: _equipment == e.key,
                onSelected: (_) => setState(() => _equipment = e.key),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _injuries,
            decoration: const InputDecoration(
              labelText: '伤病或动作限制（可选）',
              hintText: '如：左膝半月板不适、腰椎间盘突出、无',
              prefixIcon: Icon(Icons.healing_rounded, color: Color(0xFFEF5350)),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check_circle_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('完成并初始化我的计划', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
