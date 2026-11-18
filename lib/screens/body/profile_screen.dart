import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/nutrition.dart';
import '../../widgets/common.dart';

/// 基础资料 + 运动问卷编辑（全语义图标化）
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _target = TextEditingController();
  final _injuries = TextEditingController();
  String _gender = 'male';
  double _activity = 1.375;
  String _goal = 'maintain';
  String _experience = 'beginner';
  int _weeklyDays = 3;
  int _sessionMinutes = 60;
  String _equipment = 'gym';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Repo.getProfile().then((p) {
      if (!mounted) return;
      setState(() {
        _gender = p.gender;
        _activity = Nutrition.activityLevels.containsKey(p.activity) ? p.activity : 1.375;
        _goal = Nutrition.goals.containsKey(p.goal) ? p.goal : 'maintain';
        _age.text = '${p.age}';
        _height.text = p.height.toStringAsFixed(0);
        _target.text = p.targetWeight?.toString() ?? '';
        _experience = Nutrition.experiences.containsKey(p.experience) ? p.experience : 'beginner';
        _weeklyDays = p.weeklyDays.clamp(1, 7);
        _sessionMinutes = [30, 45, 60, 75, 90, 120].contains(p.sessionMinutes) ? p.sessionMinutes : 60;
        _equipment = Nutrition.equipments.containsKey(p.equipment) ? p.equipment : 'gym';
        _injuries.text = p.injuries;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _target.dispose();
    _injuries.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await Repo.saveProfile(Profile(
      gender: _gender,
      age: int.parse(_age.text),
      height: double.parse(_height.text),
      activity: _activity,
      goal: _goal,
      targetWeight: double.tryParse(_target.text),
      experience: _experience,
      weeklyDays: _weeklyDays,
      sessionMinutes: _sessionMinutes,
      equipment: _equipment,
      injuries: _injuries.text.trim(),
    ));
    await Repo.setOnboardingDone();
    if (!mounted) return;
    toast(context, '已保存');
    Navigator.pop(context);
  }

  String? _validateNum(String? v, double min, double max) {
    final n = double.tryParse(v ?? '');
    if (n == null) return '请输入数字';
    if (n < min || n > max) return '范围 ${min.toInt()}-${max.toInt()}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF42A5F5).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.badge_rounded, color: Color(0xFF42A5F5), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('身体资料与训练档案'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SectionTitle('性别', icon: Icons.wc_rounded, iconColor: Color(0xFF42A5F5)),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'male', label: Text('男生'), icon: Icon(Icons.male_rounded)),
                      ButtonSegment(value: 'female', label: Text('女生'), icon: Icon(Icons.female_rounded)),
                    ],
                    selected: {_gender},
                    onSelectionChanged: (s) => setState(() => _gender = s.first),
                  ),
                  const SectionTitle('年龄与身高', icon: Icons.straighten_rounded, iconColor: Color(0xFF26A69A)),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _age,
                          decoration: const InputDecoration(
                            labelText: '年龄',
                            suffixText: '岁',
                            prefixIcon: Icon(Icons.cake_rounded, color: Color(0xFFFFA726)),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) => _validateNum(v, 10, 100),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _height,
                          decoration: const InputDecoration(
                            labelText: '身高',
                            suffixText: 'cm',
                            prefixIcon: Icon(Icons.height_rounded, color: Color(0xFF26A69A)),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (v) => _validateNum(v, 100, 250),
                        ),
                      ),
                    ],
                  ),
                  const SectionTitle('活动水平与目标', icon: Icons.flag_rounded, iconColor: Color(0xFFEF5350)),
                  DropdownButtonFormField<double>(
                    initialValue: _activity,
                    decoration: const InputDecoration(
                      labelText: '日常静息/工作活动水平',
                      prefixIcon: Icon(Icons.directions_run_rounded, color: Color(0xFFAB47BC)),
                    ),
                    items: Nutrition.activityLevels.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _activity = v ?? _activity),
                  ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _target,
                    decoration: const InputDecoration(
                      labelText: '目标体重（可选，将在体重趋势图画出目标线）',
                      suffixText: 'kg',
                      prefixIcon: Icon(Icons.monitor_weight_rounded, color: Color(0xFF42A5F5)),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => (v == null || v.isEmpty) ? null : _validateNum(v, 30, 250),
                  ),
                  const SectionTitle('运动条件（供 AI 定制计划）', icon: Icons.fitness_center_rounded, iconColor: Color(0xFFAB47BC)),
                  DropdownButtonFormField<String>(
                    initialValue: _experience,
                    decoration: const InputDecoration(
                      labelText: '运动经验',
                      prefixIcon: Icon(Icons.military_tech_rounded, color: Color(0xFFFFA726)),
                    ),
                    items: Nutrition.experiences.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _experience = v ?? _experience),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _weeklyDays,
                          decoration: const InputDecoration(
                            labelText: '每周可练',
                            prefixIcon: Icon(Icons.calendar_today_rounded, color: Color(0xFF42A5F5)),
                          ),
                          items: [for (var d = 1; d <= 7; d++) DropdownMenuItem(value: d, child: Text('$d 天/周'))],
                          onChanged: (v) => setState(() => _weeklyDays = v ?? _weeklyDays),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _sessionMinutes,
                          decoration: const InputDecoration(
                            labelText: '单次时长',
                            prefixIcon: Icon(Icons.timer_rounded, color: Color(0xFF26A69A)),
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
                  DropdownButtonFormField<String>(
                    initialValue: _equipment,
                    decoration: const InputDecoration(
                      labelText: '可用器械',
                      prefixIcon: Icon(Icons.handyman_rounded, color: Color(0xFFEF5350)),
                    ),
                    items: Nutrition.equipments.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _equipment = v ?? _equipment),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _injuries,
                    decoration: const InputDecoration(
                      labelText: '伤病或动作限制（可选）',
                      hintText: '如：膝盖不适、腰突、无',
                      prefixIcon: Icon(Icons.healing_rounded, color: Color(0xFFEC407A)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('保存资料'),
                  ),
                ],
              ),
            ),
    );
  }
}
