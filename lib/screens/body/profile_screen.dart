import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/nutrition.dart';
import '../../widgets/common.dart';

/// 基础资料 + 运动问卷编辑
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
    toast(context, context.l10n.commonSavedToast);
    Navigator.pop(context);
  }

  String? _validateNum(String? v, double min, double max) {
    final l = context.l10n;
    final n = double.tryParse(v ?? '');
    if (n == null) return l.commonInvalidNumber;
    if (n < min || n > max) return l.commonRangeError(min.toInt(), max.toInt());
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
            Expanded(child: Text(l.profileTitle, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(l.commonSave),
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
                  SectionTitle(l.profileGenderSection, icon: Icons.wc_rounded, iconColor: const Color(0xFF42A5F5)),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'male', label: Text(l.profileMale), icon: const Icon(Icons.male_rounded)),
                      ButtonSegment(value: 'female', label: Text(l.profileFemale), icon: const Icon(Icons.female_rounded)),
                    ],
                    selected: {_gender},
                    onSelectionChanged: (s) => setState(() => _gender = s.first),
                  ),
                  SectionTitle(l.profileAgeHeightSection, icon: Icons.straighten_rounded, iconColor: const Color(0xFF26A69A)),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _age,
                          decoration: InputDecoration(
                            labelText: l.profileAgeLabel,
                            suffixText: l.profileAgeUnit,
                            prefixIcon: const Icon(Icons.cake_rounded, color: Color(0xFFFFA726)),
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
                          decoration: InputDecoration(
                            labelText: l.profileHeightLabel,
                            suffixText: 'cm',
                            prefixIcon: const Icon(Icons.height_rounded, color: Color(0xFF26A69A)),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (v) => _validateNum(v, 100, 250),
                        ),
                      ),
                    ],
                  ),
                  SectionTitle(l.profileActivityGoalSection, icon: Icons.flag_rounded, iconColor: const Color(0xFFEF5350)),
                  DropdownButtonFormField<double>(
                    initialValue: _activity,
                    decoration: InputDecoration(
                      labelText: l.profileActivityLabel,
                      prefixIcon: const Icon(Icons.directions_run_rounded, color: Color(0xFFAB47BC)),
                    ),
                    items: Nutrition.activityLevels.keys
                        .map((k) => DropdownMenuItem(value: k, child: Text(L10nHelper.activityLabel(context, k))))
                        .toList(),
                    onChanged: (v) => setState(() => _activity = v ?? _activity),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: Nutrition.goals.keys.map((k) {
                      return ChoiceChip(
                        label: Text(L10nHelper.goalLabel(context, k)),
                        selected: _goal == k,
                        onSelected: (_) => setState(() => _goal = k),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _target,
                    decoration: InputDecoration(
                      labelText: l.profileTargetWeightLabel,
                      suffixText: 'kg',
                      prefixIcon: const Icon(Icons.monitor_weight_rounded, color: Color(0xFF42A5F5)),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => (v == null || v.isEmpty) ? null : _validateNum(v, 30, 250),
                  ),
                  SectionTitle(l.profileTrainingConditionSection, icon: Icons.fitness_center_rounded, iconColor: const Color(0xFFAB47BC)),
                  DropdownButtonFormField<String>(
                    initialValue: _experience,
                    decoration: InputDecoration(
                      labelText: l.profileExperienceLabel,
                      prefixIcon: const Icon(Icons.military_tech_rounded, color: Color(0xFFFFA726)),
                    ),
                    items: Nutrition.experiences.keys
                        .map((k) => DropdownMenuItem(value: k, child: Text(L10nHelper.experienceLabel(context, k))))
                        .toList(),
                    onChanged: (v) => setState(() => _experience = v ?? _experience),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _weeklyDays,
                          decoration: InputDecoration(
                            labelText: l.profileWeeklyDaysLabel,
                            prefixIcon: const Icon(Icons.calendar_today_rounded, color: Color(0xFF42A5F5)),
                          ),
                          items: [
                            for (var d = 1; d <= 7; d++)
                              DropdownMenuItem(value: d, child: Text(l.profileWeeklyDaysItem(d))),
                          ],
                          onChanged: (v) => setState(() => _weeklyDays = v ?? _weeklyDays),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _sessionMinutes,
                          decoration: InputDecoration(
                            labelText: l.profileSessionMinsLabel,
                            prefixIcon: const Icon(Icons.timer_rounded, color: Color(0xFF26A69A)),
                          ),
                          items: [
                            for (final m in [30, 45, 60, 75, 90, 120])
                              DropdownMenuItem(value: m, child: Text(l.profileSessionMinsItem(m))),
                          ],
                          onChanged: (v) => setState(() => _sessionMinutes = v ?? _sessionMinutes),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _equipment,
                    decoration: InputDecoration(
                      labelText: l.profileEquipmentLabel,
                      prefixIcon: const Icon(Icons.handyman_rounded, color: Color(0xFFEF5350)),
                    ),
                    items: Nutrition.equipments.keys
                        .map((k) => DropdownMenuItem(value: k, child: Text(L10nHelper.equipmentLabel(context, k))))
                        .toList(),
                    onChanged: (v) => setState(() => _equipment = v ?? _equipment),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _injuries,
                    decoration: InputDecoration(
                      labelText: l.profileInjuriesLabel,
                      hintText: l.profileInjuriesHint,
                      prefixIcon: const Icon(Icons.healing_rounded, color: Color(0xFFEC407A)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(l.profileSaveBtn),
                  ),
                ],
              ),
            ),
    );
  }
}
