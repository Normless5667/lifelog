import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../debug/debug_server.dart';
import '../../models/models.dart';
import '../../services/nutrition.dart';
import '../../services/usage_telemetry_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import 'profile_screen.dart';

/// 身体数据（v2.0）：体重曲线、记录列表、BMR/TDEE 核心数据看板
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
    final t0 = DateTime.now().millisecondsSinceEpoch;
    UsageTelemetryService.instance.trackFeature('log_weight', 'tap');
    final result = await showDialog<BodyRecord>(
      context: context,
      builder: (_) => _BodyRecordDialog(existing: existing),
    );
    final dur = DateTime.now().millisecondsSinceEpoch - t0;
    if (result != null) {
      try {
        if (existing != null && existing.date != result.date) {
          await Repo.deleteBodyRecord(existing.id!);
        }
        await Repo.saveBodyRecord(result);
        UsageTelemetryService.instance.trackFeature('log_weight', 'success', durationMs: dur);
        _load();
      } catch (e, st) {
        UsageTelemetryService.instance.trackFeature(
          'log_weight',
          'fail',
          durationMs: dur,
          stage: 'save',
          errorMsg: '$e',
        );
        DebugServer.instance.logError('Body', e, st, 'saveBodyRecord failed');
        if (!mounted) return;
        toast(context, context.l10n.bodySaveFailed('$e'));
      }
    } else {
      UsageTelemetryService.instance.trackFeature('log_weight', 'cancel', durationMs: dur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final bodyColor = AppColors.moduleBody(context);
    final primary = AppColors.primary(context);
    final latest = _records.where((r) => r.weight != null).toList();
    final w = latest.isEmpty ? null : latest.first.weight;

    final headerWidgets = <Widget>[
      if (!_hasProfile)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: SurfaceCard(
            backgroundColor: AppColors.softBg(context, primary, lightAlpha: 0.08, darkAlpha: 0.14),
            borderColor: AppColors.softBorder(context, primary),
            padding: AppSpacing.cardCompactPadding,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              _load();
            },
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: primary, borderRadius: AppRadius.bMd),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.bodyNoProfileTitle, style: AppTypography.cardTitle(context)),
                      const SizedBox(height: 2),
                      Text(l.bodyNoProfileSub, style: AppTypography.bodySecondary(context)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary(context)),
              ],
            ),
          ),
        ),
      if (w != null) _statsCard(w),
      SectionTitle(
        l.bodyWeightTrendTitle,
        icon: Icons.show_chart_rounded,
        iconColor: bodyColor,
      ),
      SurfaceCard(
        padding: latest.isEmpty
            ? AppSpacing.cardPadding
            : const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
        child: latest.isEmpty
            ? EmptyHint(
                icon: Icons.insights_rounded,
                text: l.bodyEmptyChartHint,
                actionLabel: l.bodyEmptyChartBtn,
                onAction: () => _addRecord(),
              )
            : SizedBox(height: 204, child: _weightChart(latest.reversed.toList())),
      ),
      SectionTitle(
        l.bodyHistoryTitle,
        icon: Icons.history_rounded,
        iconColor: primary,
      ),
    ];

    final bodyCount = _records.isEmpty ? 1 : _records.length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.sm,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, bodyColor, lightAlpha: 0.12, darkAlpha: 0.20),
                borderRadius: AppRadius.bSm,
                border: Border.all(color: AppColors.softBorder(context, bodyColor)),
              ),
              child: Icon(Icons.monitor_weight_rounded, color: bodyColor, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                l.bodyTitle,
                style: AppTypography.pageTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: AppColors.surfaceSubtle(context),
                foregroundColor: AppColors.textPrimary(context),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
                _load();
              },
              icon: const Icon(Icons.badge_rounded, size: 17),
              label: Text(l.bodyProfileBtn),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addRecord(),
        elevation: 2,
        backgroundColor: bodyColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.bLg),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          l.bodyLogWeightBtn,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: AppSpacing.pagePadding,
              itemCount: headerWidgets.length + bodyCount,
              itemBuilder: (_, idx) {
                if (idx < headerWidgets.length) {
                  return headerWidgets[idx];
                }
                if (_records.isEmpty) {
                  return EmptyHint(
                    icon: Icons.monitor_weight_rounded,
                    text: l.bodyEmptyHistoryHint,
                    actionLabel: l.bodyEmptyHistoryBtn,
                    onAction: () => _addRecord(),
                  );
                }
                final r = _records[idx - headerWidgets.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _recordRowCard(r),
                );
              },
            ),
    );
  }

  Widget _recordRowCard(BodyRecord r) {
    final l = context.l10n;
    final bodyColor = AppColors.moduleBody(context);
    final parts = [
      if (r.weight != null) '${fmtNum(r.weight!, digits: 1)} kg',
      if (r.bodyFat != null) l.bodyFatTag(fmtNum(r.bodyFat!, digits: 1)),
      if (r.waist != null) l.bodyWaistTag(fmtNum(r.waist!, digits: 1)),
    ];

    return SurfaceCard(
      onTap: () => _addRecord(r),
      padding: AppSpacing.cardCompactPadding,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, bodyColor),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(Icons.monitor_weight_rounded, color: bodyColor, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(parts.join(' · '), style: AppTypography.cardTitle(context)),
                const SizedBox(height: 2),
                Text(
                  L10nHelper.friendlyDateL10n(context, r.date),
                  style: AppTypography.bodySecondary(context),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: AppColors.textTertiary(context),
            ),
            onPressed: () async {
              if (await confirm(context, l.commonDeleteRecordConfirm)) {
                await Repo.deleteBodyRecord(r.id!);
                _load();
              }
            },
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary(context)),
        ],
      ),
    );
  }

  Widget _statsCard(double w) {
    final l = context.l10n;
    final bmi = Nutrition.bmi(_profile.height, w);

    Widget stat(IconData icon, Color color, String label, String value) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle(context),
            borderRadius: AppRadius.bLg,
          ),
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, color),
                  borderRadius: AppRadius.bSm,
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: AppTypography.metricMedium(context)),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTypography.caption(context).copyWith(fontSize: 10.5),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          Row(
            children: [
              stat(
                Icons.monitor_weight_rounded,
                AppColors.moduleBody(context),
                l.bodyStatWeight,
                fmtNum(w, digits: 1),
              ),
              stat(
                Icons.speed_rounded,
                AppColors.teal(context),
                'BMI (${L10nHelper.bmiStatusLabel(context, bmi)})',
                fmtNum(bmi, digits: 1),
              ),
              stat(
                Icons.local_fire_department_rounded,
                AppColors.warning(context),
                l.bodyStatBmr,
                fmtNum(Nutrition.bmr(_profile, w)),
              ),
            ],
          ),
          Row(
            children: [
              stat(
                Icons.bolt_rounded,
                AppColors.moduleWorkout(context),
                l.bodyStatTdee,
                fmtNum(Nutrition.tdee(_profile, w)),
              ),
              stat(
                Icons.restaurant_rounded,
                AppColors.moduleDiet(context),
                l.bodyStatTargetKcal,
                fmtNum(Nutrition.calorieTarget(_profile, w)),
              ),
              stat(
                Icons.flag_rounded,
                AppColors.moduleAi(context),
                l.bodyStatGoal,
                L10nHelper.goalLabel(context, _profile.goal),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weightChart(List<BodyRecord> asc) {
    final l = context.l10n;
    final data = asc.length > 60 ? asc.sublist(asc.length - 60) : asc;
    final first = parseDate(data.first.date);
    final spots = data
        .map((r) => FlSpot(
              parseDate(r.date).difference(first).inDays.toDouble(),
              Nutrition.sanitizeWeightKg(r.weight) ?? 60.0,
            ))
        .toList();
    if (spots.length == 1) {
      spots.add(FlSpot(1, spots.first.y));
    }
    final targetW = _profile.targetWeight;
    final ys = [...spots.map((s) => s.y), ?targetW];
    final minY = (ys.reduce((a, b) => a < b ? a : b) - 1).floorToDouble();
    final maxY = (ys.reduce((a, b) => a > b ? a : b) + 1).ceilToDouble();

    final lineColor = AppColors.moduleBody(context);
    final dangerColor = AppColors.danger(context);
    final borderColor = AppColors.border(context);

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: borderColor,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: targetW == null
            ? null
            : ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: targetW,
                    color: dangerColor,
                    strokeWidth: 1.8,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: AppTypography.badge(context, color: dangerColor)
                          .copyWith(fontSize: 10),
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
              getTitlesWidget: (v, meta) => Text(
                fmtNum(v),
                style: AppTypography.caption(context).copyWith(fontSize: 10),
              ),
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
                  child: Text(
                    '${d.month}/${d.day}',
                    style: AppTypography.caption(context).copyWith(fontSize: 10),
                  ),
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
            color: lineColor,
            barWidth: 3,
            dotData: FlDotData(show: spots.length <= 20),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  lineColor.withValues(alpha: 0.24),
                  lineColor.withValues(alpha: 0.02),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
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
    final bodyColor = AppColors.moduleBody(context);
    final teal = AppColors.teal(context);
    final warning = AppColors.warning(context);
    final aiColor = AppColors.moduleAi(context);

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, bodyColor),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(Icons.monitor_weight_rounded, color: bodyColor, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(l.bodyDialogTitle, style: AppTypography.sectionTitle(context)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_rounded, color: teal),
              title: Text(
                L10nHelper.friendlyDateL10n(context, _date),
                style: AppTypography.subtitle(context),
              ),
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
                prefixIcon: Icon(Icons.monitor_weight_rounded, color: bodyColor),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _fat,
              keyboardType: numKb,
              decoration: InputDecoration(
                labelText: l.bodyFatLabel,
                suffixText: '%',
                prefixIcon: Icon(Icons.percent_rounded, color: warning),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _waist,
              keyboardType: numKb,
              decoration: InputDecoration(
                labelText: l.bodyWaistLabel,
                suffixText: 'cm',
                prefixIcon: Icon(Icons.straighten_rounded, color: aiColor),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton.icon(
          onPressed: () {
            final rawW = _weight.text.trim();
            final rawF = _fat.text.trim();
            final rawWa = _waist.text.trim();
            final w = Nutrition.sanitizeWeightKg(Nutrition.parsePlainDouble(rawW));
            final f = Nutrition.sanitizeBodyFat(Nutrition.parsePlainDouble(rawF));
            final wa = Nutrition.sanitizeWaistCm(Nutrition.parsePlainDouble(rawWa));
            if (w == null && f == null && wa == null) {
              final reason = (rawW.isEmpty && rawF.isEmpty && rawWa.isEmpty)
                  ? 'all_fields_empty'
                  : 'invalid_or_out_of_range(w_len=${rawW.length},f_len=${rawF.length},wa_len=${rawWa.length})';
              UsageTelemetryService.instance.trackFeature(
                'log_weight',
                'fail',
                stage: 'validate',
                errorMsg: reason,
              );
              toast(context, l.commonAtLeastOneField);
              return;
            }
            Navigator.pop(
              context,
              BodyRecord(date: _date, weight: w, bodyFat: f, waist: wa),
            );
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(l.commonSave),
        ),
      ],
    );
  }
}
