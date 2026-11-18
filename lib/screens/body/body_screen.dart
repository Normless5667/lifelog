import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/nutrition.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import 'profile_screen.dart';

/// 身体数据：体重曲线、记录列表、BMR/TDEE
class BodyScreen extends StatefulWidget {
  const BodyScreen({super.key});

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  List<BodyRecord> _records = [];
  Profile _profile = Profile();
  bool _hasProfile = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Repo.getBodyRecords();
    final p = await Repo.getProfile();
    final has = await Repo.hasProfile();
    if (!mounted) return;
    setState(() {
      _records = r;
      _profile = p;
      _hasProfile = has;
      _loading = false;
    });
  }

  Future<void> _addRecord([BodyRecord? existing]) async {
    final result = await showDialog<BodyRecord>(
      context: context,
      builder: (_) => _BodyRecordDialog(existing: existing),
    );
    if (result != null) {
      if (existing != null && existing.date != result.date) await Repo.deleteBodyRecord(existing.id!);
      await Repo.saveBodyRecord(result);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final latest = _records.where((r) => r.weight != null).toList();
    final w = latest.isEmpty ? null : latest.first.weight;
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
              child: const Icon(Icons.monitor_weight_rounded, color: Color(0xFF42A5F5), size: 20),
            ),
            const SizedBox(width: 10),
            Text(l.bodyTitle),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              _load();
            },
            icon: const Icon(Icons.badge_rounded),
            label: Text(l.bodyProfileBtn),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addRecord(),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.bodyLogWeightBtn),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                if (!_hasProfile)
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
                      title: Text(l.bodyNoProfileTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(l.bodyNoProfileSub),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                        _load();
                      },
                    ),
                  ),
                if (w != null) _statsCard(w),
                SectionTitle(l.bodyWeightTrendTitle, icon: Icons.show_chart_rounded, iconColor: const Color(0xFF26A69A)),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
                    child: latest.isEmpty
                        ? EmptyHint(
                            icon: Icons.insights_rounded,
                            text: l.bodyEmptyChartHint,
                            actionLabel: l.bodyEmptyChartBtn,
                            onAction: () => _addRecord(),
                          )
                        : SizedBox(height: 200, child: _weightChart(latest.reversed.toList())),
                  ),
                ),
                SectionTitle(l.bodyHistoryTitle, icon: Icons.history_rounded, iconColor: const Color(0xFF42A5F5)),
                if (_records.isEmpty)
                  EmptyHint(
                    icon: Icons.monitor_weight_rounded,
                    text: l.bodyEmptyHistoryHint,
                    actionLabel: l.bodyEmptyHistoryBtn,
                    onAction: () => _addRecord(),
                  )
                else
                  Card(
                    child: Column(
                      children: _records.map((r) {
                        final parts = [
                          if (r.weight != null) '${fmtNum(r.weight!, digits: 1)} kg',
                          if (r.bodyFat != null) l.bodyFatTag(fmtNum(r.bodyFat!, digits: 1)),
                          if (r.waist != null) l.bodyWaistTag(fmtNum(r.waist!, digits: 1)),
                        ];
                        return ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF42A5F5).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.monitor_weight_rounded, color: Color(0xFF42A5F5)),
                          ),
                          title: Text(parts.join(' · '), style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(L10nHelper.friendlyDateL10n(context, r.date)),
                          onTap: () => _addRecord(r),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () async {
                                  if (await confirm(context, l.commonDeleteRecordConfirm)) {
                                    await Repo.deleteBodyRecord(r.id!);
                                    _load();
                                  }
                                },
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _statsCard(double w) {
    final l = context.l10n;
    final bmi = Nutrition.bmi(_profile.height, w);
    Widget stat(IconData icon, Color color, String label, String value) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11), textAlign: TextAlign.center),
              ],
            ),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(children: [
              stat(Icons.monitor_weight_rounded, const Color(0xFF42A5F5), l.bodyStatWeight, fmtNum(w, digits: 1)),
              stat(Icons.speed_rounded, const Color(0xFF26A69A), 'BMI (${L10nHelper.bmiStatusLabel(context, bmi)})', fmtNum(bmi, digits: 1)),
              stat(Icons.local_fire_department_rounded, const Color(0xFFFFA726), l.bodyStatBmr, fmtNum(Nutrition.bmr(_profile, w))),
            ]),
            Row(children: [
              stat(Icons.bolt_rounded, const Color(0xFFEF5350), l.bodyStatTdee, fmtNum(Nutrition.tdee(_profile, w))),
              stat(Icons.restaurant_rounded, const Color(0xFF66BB6A), l.bodyStatTargetKcal, fmtNum(Nutrition.calorieTarget(_profile, w))),
              stat(Icons.flag_rounded, const Color(0xFFAB47BC), l.bodyStatGoal, L10nHelper.goalLabel(context, _profile.goal)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _weightChart(List<BodyRecord> asc) {
    final l = context.l10n;
    final data = asc.length > 60 ? asc.sublist(asc.length - 60) : asc;
    final first = parseDate(data.first.date);
    final spots = data
        .map((r) => FlSpot(parseDate(r.date).difference(first).inDays.toDouble(), r.weight!))
        .toList();
    if (spots.length == 1) {
      spots.add(FlSpot(1, spots.first.y));
    }
    final targetW = _profile.targetWeight;
    final ys = [...spots.map((s) => s.y), if (targetW != null) targetW];
    final minY = (ys.reduce((a, b) => a < b ? a : b) - 1).floorToDouble();
    final maxY = (ys.reduce((a, b) => a > b ? a : b) + 1).ceilToDouble();
    final color = Theme.of(context).colorScheme.primary;
    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        extraLinesData: targetW == null
            ? null
            : ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: targetW,
                    color: const Color(0xFFEF5350),
                    strokeWidth: 2,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFEF5350)),
                      labelResolver: (_) => l.bodyChartTargetLine(fmtNum(targetW, digits: 1)),
                    ),
                  ),
                ],
              ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) => Text(fmtNum(v), style: const TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: spots.last.x <= 7 ? 1 : (spots.last.x / 5).ceilToDouble(),
              getTitlesWidget: (v, meta) {
                final d = first.add(Duration(days: v.toInt()));
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${d.month}/${d.day}', style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(show: spots.length <= 20),
            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.14)),
          ),
        ],
      ),
    );
  }
}

class _BodyRecordDialog extends StatefulWidget {
  final BodyRecord? existing;
  const _BodyRecordDialog({this.existing});

  @override
  State<_BodyRecordDialog> createState() => _BodyRecordDialogState();
}

class _BodyRecordDialogState extends State<_BodyRecordDialog> {
  late String _date;
  late final TextEditingController _weight;
  late final TextEditingController _fat;
  late final TextEditingController _waist;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.date ?? today();
    _weight = TextEditingController(text: e?.weight?.toString() ?? '');
    _fat = TextEditingController(text: e?.bodyFat?.toString() ?? '');
    _waist = TextEditingController(text: e?.waist?.toString() ?? '');
  }

  @override
  void dispose() {
    _weight.dispose();
    _fat.dispose();
    _waist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const numKb = TextInputType.numberWithOptions(decimal: true);
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF42A5F5).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.monitor_weight_rounded, color: Color(0xFF42A5F5), size: 22),
          ),
          const SizedBox(width: 10),
          Text(l.bodyDialogTitle),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded, color: Color(0xFF26A69A)),
              title: Text(L10nHelper.friendlyDateL10n(context, _date), style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.edit_calendar_rounded, size: 18),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: parseDate(_date),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = fmtDate(d));
              },
            ),
            TextField(
              controller: _weight,
              keyboardType: numKb,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.bodyWeightLabel,
                suffixText: 'kg',
                prefixIcon: const Icon(Icons.monitor_weight_rounded, color: Color(0xFF42A5F5)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fat,
              keyboardType: numKb,
              decoration: InputDecoration(
                labelText: l.bodyFatLabel,
                suffixText: '%',
                prefixIcon: const Icon(Icons.percent_rounded, color: Color(0xFFFFA726)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _waist,
              keyboardType: numKb,
              decoration: InputDecoration(
                labelText: l.bodyWaistLabel,
                suffixText: 'cm',
                prefixIcon: const Icon(Icons.straighten_rounded, color: Color(0xFFAB47BC)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton.icon(
          onPressed: () {
            final w = double.tryParse(_weight.text);
            final f = double.tryParse(_fat.text);
            final wa = double.tryParse(_waist.text);
            if (w == null && f == null && wa == null) {
              toast(context, l.commonAtLeastOneField);
              return;
            }
            Navigator.pop(context, BodyRecord(date: _date, weight: w, bodyFat: f, waist: wa));
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(l.commonSave),
        ),
      ],
    );
  }
}
