import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/nutrition.dart';
import '../../services/running_tracker.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import '../settings/settings_screen.dart';

/// 容错解析用户编辑的时长输入：支持 `HH:MM:SS`、`MM:SS` 或纯分钟数（如 `30` / `32.5`），返回总秒数。
int? parseTreadmillDurationInput(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.contains(':')) {
    final parts = s.split(':');
    if (parts.length == 2 || parts.length == 3) {
      final nums = parts.map((e) => int.tryParse(e.trim())).toList();
      if (nums.every((n) => n != null && n >= 0)) {
        final total = parts.length == 3
            ? nums[0]! * 3600 + nums[1]! * 60 + nums[2]!
            : nums[0]! * 60 + nums[1]!;
        return (total > 0 && total <= 86400) ? total : null;
      }
    }
    return null;
  }
  final mins = double.tryParse(s);
  if (mins == null || !mins.isFinite || mins <= 0 || mins > 1440) return null;
  return (mins * 60).round();
}

/// 拍照读取跑步机 / 椭圆机 / 动感单车屏幕页面：
/// 流程：选图/拍照 -> 视觉模型识别 -> 必须展示确认/修正表单 -> 保存为 cardio_records（默认 type=treadmill）。
class TreadmillScanScreen extends StatefulWidget {
  final double weightKg;
  final TreadmillScanResult? initialResultForTest;
  final Future<void> Function(CardioRecord record)? onSaveForTest;

  const TreadmillScanScreen({
    super.key,
    required this.weightKg,
    this.initialResultForTest,
    this.onSaveForTest,
  });

  @override
  State<TreadmillScanScreen> createState() => _TreadmillScanScreenState();
}

class _TreadmillScanScreenState extends State<TreadmillScanScreen> {
  static const _machineTypes = <String>[
    CardioType.treadmill,
    CardioType.treadmillFast,
    CardioType.elliptical,
    CardioType.bike,
  ];

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _distCtrl = TextEditingController();
  final TextEditingController _durCtrl = TextEditingController();
  final TextEditingController _kcalCtrl = TextEditingController();

  File? _imageFile;
  TreadmillScanResult? _result;
  String _machineType = CardioType.treadmill;
  bool _analyzing = false;
  bool _showForm = false;
  bool _usedMetFallback = false;
  bool _userEditedCalories = false;
  String? _errorMsg;
  bool _needsAiConfig = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialResultForTest != null) {
      _applyScanResult(widget.initialResultForTest!);
    }
  }

  @override
  void dispose() {
    _distCtrl.dispose();
    _durCtrl.dispose();
    _kcalCtrl.dispose();
    super.dispose();
  }

  void _applyScanResult(TreadmillScanResult res) {
    _result = res;
    _showForm = true;
    _errorMsg = null;
    _needsAiConfig = false;
    _userEditedCalories = false;

    _machineType = _machineTypes.contains(res.machineType)
        ? res.machineType
        : CardioType.treadmill;

    _distCtrl.text =
        res.distanceKm != null ? res.distanceKm!.toStringAsFixed(2) : '';
    _durCtrl.text =
        res.durationSecs != null ? formatRunDuration(res.durationSecs!) : '';

    if (res.calories != null && res.calories! > 0) {
      _kcalCtrl.text = fmtNum(res.calories!);
      _usedMetFallback = false;
    } else {
      _usedMetFallback = true;
      _recalcMetCalories();
    }
  }

  void _enterManualMode() {
    setState(() {
      _imageFile = null;
      _result = null;
      _showForm = true;
      _errorMsg = null;
      _needsAiConfig = false;
      _machineType = CardioType.treadmill;
      _distCtrl.text = '';
      _durCtrl.text = '30:00';
      _userEditedCalories = false;
      _usedMetFallback = true;
      _recalcMetCalories();
    });
  }

  void _recalcMetCalories() {
    if (_userEditedCalories) return;
    final secs = parseTreadmillDurationInput(_durCtrl.text);
    if (secs == null || secs <= 0) {
      _kcalCtrl.text = '';
      return;
    }
    final distKm = double.tryParse(_distCtrl.text.trim());
    final est = Nutrition.estimateMachineCalories(
      machineType: _machineType,
      weightKg: widget.weightKg,
      durationMinutes: secs / 60.0,
      distanceKm: distKm,
    );
    _kcalCtrl.text = fmtNum(est);
    _usedMetFallback = true;
  }

  Future<void> _pickAndAnalyze(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      setState(() {
        _imageFile = file;
        _analyzing = true;
        _errorMsg = null;
        _needsAiConfig = false;
      });
      final res = await AiService.analyzeTreadmillImage(file);
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _applyScanResult(res);
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _errorMsg = e.message;
        _needsAiConfig = e.needsConfig;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _errorMsg = e.toString();
        _needsAiConfig = false;
      });
    }
  }

  Future<void> _save() async {
    final l = context.l10n;
    final durSecs = parseTreadmillDurationInput(_durCtrl.text);
    if (durSecs == null || durSecs <= 0) {
      toast(context, l.treadmillScanDurationInvalid);
      return;
    }

    final distRaw = _distCtrl.text.trim();
    final distKm = distRaw.isEmpty ? null : double.tryParse(distRaw);
    final durMins = durSecs / 60.0;

    final kcalParsed = double.tryParse(_kcalCtrl.text.trim());
    final effectiveKcal = (kcalParsed != null && kcalParsed.isFinite && kcalParsed > 0)
        ? kcalParsed
        : Nutrition.estimateMachineCalories(
            machineType: _machineType,
            weightKg: widget.weightKg,
            durationMinutes: durMins,
            distanceKm: distKm,
          );

    final record = CardioRecord(
      date: today(),
      type: _machineType,
      durationMinutes: double.parse(durMins.toStringAsFixed(2)),
      distanceKm: (distKm != null && distKm.isFinite && distKm > 0)
          ? double.parse(distKm.toStringAsFixed(2))
          : null,
      calories: effectiveKcal.roundToDouble(),
    );

    if (widget.onSaveForTest != null) {
      await widget.onSaveForTest!(record);
    } else {
      await Repo.saveCardioRecord(record);
    }
    if (!mounted) return;
    toast(context, l.treadmillScanSavedToast(fmtNum(record.calories)));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    final teal = AppColors.teal(context);
    final warning = AppColors.warning(context);
    final danger = AppColors.danger(context);
    final metVal = Nutrition.cardioMets[_machineType] ?? 8.0;

    return Scaffold(
      appBar: AppBar(title: Text(l.treadmillScanTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          if (!_showForm && !_analyzing)
            SurfaceCard(
              isHero: true,
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.softBg(
                          context,
                          primary,
                          lightAlpha: 0.14,
                          darkAlpha: 0.24,
                        ),
                        borderRadius: AppRadius.bXl,
                      ),
                      child: Icon(Icons.camera_alt_rounded, color: primary, size: 32),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l.treadmillScanHint,
                    style: AppTypography.bodySecondary(context),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    key: const ValueKey('treadmill_take_photo_btn'),
                    onPressed: () => _pickAndAnalyze(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded, size: 20),
                    label: Text(l.treadmillScanTakePhoto),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('treadmill_pick_gallery_btn'),
                    onPressed: () => _pickAndAnalyze(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded, size: 20),
                    label: Text(l.treadmillScanPickGallery),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    key: const ValueKey('treadmill_manual_btn'),
                    onPressed: _enterManualMode,
                    child: Text(l.treadmillScanManualBtn),
                  ),
                ],
              ),
            ),

          if (_analyzing) ...[
            SurfaceCard(
              padding: AppSpacing.cardPadding,
              child: Column(
                children: [
                  if (_imageFile != null) ...[
                    ClipRRect(
                      borderRadius: AppRadius.bLg,
                      child: Image.file(
                        _imageFile!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        cacheWidth: 720,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  CircularProgressIndicator(color: primary),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l.treadmillScanAnalyzing,
                    style: AppTypography.subtitle(context),
                  ),
                ],
              ),
            ),
          ],

          if (_errorMsg != null) ...[
            const SizedBox(height: AppSpacing.md),
            SurfaceCard(
              padding: AppSpacing.cardPadding,
              backgroundColor: AppColors.softBg(context, danger),
              borderColor: AppColors.softBorder(context, danger),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _errorMsg!,
                    style: AppTypography.body(context, color: danger),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (_needsAiConfig)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            );
                          },
                          icon: const Icon(Icons.settings_rounded, size: 18),
                          label: Text(l.treadmillScanOpenSettingsBtn),
                        ),
                      OutlinedButton(
                        onPressed: _enterManualMode,
                        child: Text(l.treadmillScanManualBtn),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (_showForm && !_analyzing) ...[
            if (_imageFile != null) ...[
              ClipRRect(
                borderRadius: AppRadius.bXl,
                child: Image.file(
                  _imageFile!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  cacheWidth: 720,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_result?.unitNote != null || _result?.paceNote != null) ...[
              SurfaceCard(
                padding: AppSpacing.cardCompactPadding,
                backgroundColor: AppColors.softBg(context, teal),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_result?.unitNote != null)
                      Text(
                        _result!.unitNote!,
                        style: AppTypography.caption(context, color: teal),
                      ),
                    if (_result?.paceNote != null)
                      Text(
                        l.treadmillScanPaceTag(_result!.paceNote!),
                        style: AppTypography.caption(context, color: teal),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            SurfaceCard(
              key: const ValueKey('treadmill_confirm_form'),
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('treadmill_dist_input'),
                    controller: _distCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      if (_usedMetFallback && !_userEditedCalories) {
                        setState(_recalcMetCalories);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: l.treadmillScanDistanceLabel,
                      suffixText: 'km',
                      prefixIcon: Icon(Icons.straighten_rounded, color: primary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const ValueKey('treadmill_dur_input'),
                    controller: _durCtrl,
                    keyboardType: TextInputType.datetime,
                    onChanged: (_) {
                      if (_usedMetFallback && !_userEditedCalories) {
                        setState(_recalcMetCalories);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: l.treadmillScanDurationLabel,
                      hintText: '32:15',
                      prefixIcon: Icon(Icons.timer_rounded, color: warning),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const ValueKey('treadmill_kcal_input'),
                    controller: _kcalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      setState(() {
                        _userEditedCalories = true;
                        _usedMetFallback = false;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: l.treadmillScanCaloriesLabel,
                      suffixText: 'kcal',
                      prefixIcon: Icon(Icons.local_fire_department_rounded, color: danger),
                    ),
                  ),
                  if (_usedMetFallback) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l.treadmillScanMetFallbackNote(metVal.toStringAsFixed(1)),
                      key: const ValueKey('treadmill_met_fallback_note'),
                      style: AppTypography.caption(context, color: warning),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('treadmill_type_dropdown'),
                    initialValue: _machineType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l.treadmillScanMachineLabel,
                      prefixIcon: Icon(Icons.directions_run_rounded, color: teal),
                    ),
                    items: _machineTypes
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              '${L10nHelper.cardioTypeLabel(context, t)} (MET ${(Nutrition.cardioMets[t] ?? 8.0).toStringAsFixed(1)})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _machineType = v;
                        if (_usedMetFallback && !_userEditedCalories) {
                          _recalcMetCalories();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l.treadmillScanEditHint,
                    style: AppTypography.caption(context),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('treadmill_retake_btn'),
                          onPressed: () => _pickAndAnalyze(ImageSource.camera),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(l.treadmillScanRetakeBtn),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('treadmill_save_btn'),
                          onPressed: _save,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text(l.treadmillScanSaveBtn),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
