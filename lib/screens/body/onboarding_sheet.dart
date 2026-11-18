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
    toast(context, context.l10n.onboardingSavedToast);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const numKb = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.assignment_ind_rounded, color: Colors.teal),
            const SizedBox(width: 8),
            Expanded(child: Text(l.onboardingTitle, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Repo.setOnboardingDone();
              if (context.mounted) Navigator.pop(context, false);
            },
            child: Text(l.commonSkip),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Colors.teal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.onboardingIntro,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SectionTitle(l.onboardingStep1, icon: Icons.person_rounded, iconColor: const Color(0xFF42A5F5)),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'male', icon: const Icon(Icons.male_rounded), label: Text(l.profileMale)),
              ButtonSegment(value: 'female', icon: const Icon(Icons.female_rounded), label: Text(l.profileFemale)),
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
                  decoration: InputDecoration(
                    labelText: l.profileAgeLabel,
                    suffixText: l.profileAgeUnit,
                    prefixIcon: const Icon(Icons.cake_rounded, color: Color(0xFFFFA726)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType: numKb,
                  decoration: InputDecoration(
                    labelText: l.profileHeightLabel,
                    suffixText: 'cm',
                    prefixIcon: const Icon(Icons.height_rounded, color: Color(0xFF26A69A)),
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
                  decoration: InputDecoration(
                    labelText: l.onboardingCurrentWeight,
                    suffixText: 'kg',
                    prefixIcon: const Icon(Icons.monitor_weight_rounded, color: Color(0xFF42A5F5)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _targetWeight,
                  keyboardType: numKb,
                  decoration: InputDecoration(
                    labelText: l.onboardingTargetWeight,
                    suffixText: 'kg',
                    prefixIcon: const Icon(Icons.flag_rounded, color: Color(0xFFEF5350)),
                  ),
                ),
              ),
            ],
          ),
          SectionTitle(l.onboardingStep2, icon: Icons.track_changes_rounded, iconColor: const Color(0xFFEF5350)),
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
          const SizedBox(height: 12),
          DropdownButtonFormField<double>(
            initialValue: _activity,
            decoration: InputDecoration(
              labelText: l.profileActivityLabel,
              prefixIcon: const Icon(Icons.directions_walk_rounded, color: Color(0xFF26A69A)),
            ),
            items: Nutrition.activityLevels.keys
                .map((k) => DropdownMenuItem(value: k, child: Text(L10nHelper.activityLabel(context, k))))
                .toList(),
            onChanged: (v) => setState(() => _activity = v ?? _activity),
          ),
          SectionTitle(l.onboardingStep3, icon: Icons.fitness_center_rounded, iconColor: const Color(0xFFAB47BC)),
          Text(l.profileExperienceLabel, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: Nutrition.experiences.keys.map((k) {
              return ChoiceChip(
                label: Text(L10nHelper.experienceLabel(context, k)),
                selected: _experience == k,
                onSelected: (_) => setState(() => _experience = k),
              );
            }).toList(),
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
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: [30, 45, 60, 75, 90, 120].contains(_sessionMinutes) ? _sessionMinutes : 60,
                  decoration: InputDecoration(
                    labelText: l.profileSessionMinsLabel,
                    prefixIcon: const Icon(Icons.timer_rounded, color: Color(0xFFFFA726)),
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
          Text(l.profileEquipmentLabel, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: Nutrition.equipments.keys.map((k) {
              return ChoiceChip(
                label: Text(L10nHelper.equipmentLabel(context, k)),
                selected: _equipment == k,
                onSelected: (_) => setState(() => _equipment = k),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _injuries,
            decoration: InputDecoration(
              labelText: l.profileInjuriesLabel,
              hintText: l.profileInjuriesHint,
              prefixIcon: const Icon(Icons.healing_rounded, color: Color(0xFFEF5350)),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check_circle_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l.onboardingFinishBtn, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
