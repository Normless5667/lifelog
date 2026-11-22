import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/ai_service.dart';
import '../../services/menu_ocr_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import '../settings/settings_screen.dart';

/// v3.3.1 第二批：AR 菜单相机（ML Kit 端侧英/越 OCR + 仅发文字 AI 翻译 + 可调汇率 + 红绿灯菜品卡片列表）。
/// - 端侧实时 OCR 免费不耗 Token；仅在用户点击「翻译菜单」时把 OCR 文字发给 AI（默认 15s 超时）
/// - 汇率支持随时手动改写，所有卡片人民币价格即时重算
/// - 暂不做 Positioned AR 浮层（第三批）与调试后端（第四批）
class MenuOcrLabScreen extends StatefulWidget {
  final MenuOcrFrameResult? initialResultForTest;
  final MenuTranslationResult? initialTranslationForTest;
  final Future<MenuTranslationResult> Function(String ocrText, double? customFxRate)?
      onTranslateForTest;
  final bool disableCameraForTest;

  const MenuOcrLabScreen({
    super.key,
    this.initialResultForTest,
    this.initialTranslationForTest,
    this.onTranslateForTest,
    this.disableCameraForTest = false,
  });

  @override
  State<MenuOcrLabScreen> createState() => _MenuOcrLabScreenState();
}

class _MenuOcrLabScreenState extends State<MenuOcrLabScreen>
    with WidgetsBindingObserver {
  static final _vndFmt = NumberFormat('#,###');
  static const Duration _streamThrottle = Duration(milliseconds: 450);

  MenuOcrService? _ocrService;
  CameraController? _cameraCtrl;
  CameraDescription? _cameraDesc;

  final TextEditingController _fxCtrl = TextEditingController();
  double? _activeFxRate;
  bool _userOverrodeFx = false;

  bool _initializing = true;
  bool _paused = false;
  bool _torchOn = false;
  bool _processingFrame = false;
  bool _busyStillOcr = false;
  bool _translating = false;
  int _resultTab = 1; // 默认进入先看实时 OCR 原文，点击翻译后自动切到 0=翻译卡片
  int _ocrRunCount = 0;

  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _cameraError;
  String? _streamError;
  MenuOcrFrameResult? _latest;
  MenuTranslationResult? _translation;
  String? _translateError;
  bool _translateNeedsConfig = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialResultForTest != null) {
      _latest = widget.initialResultForTest;
      _resultTab = 1;
    }
    if (widget.initialTranslationForTest != null) {
      _applyTranslation(widget.initialTranslationForTest!);
    }
    if (widget.disableCameraForTest) {
      _initializing = false;
    } else {
      _ocrService = MenuOcrService();
      _initCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed && !widget.disableCameraForTest) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fxCtrl.dispose();
    _stopCamera();
    _ocrService?.dispose();
    super.dispose();
  }

  void _applyTranslation(MenuTranslationResult res) {
    _translation = res;
    _translateError = null;
    _translateNeedsConfig = false;
    _resultTab = 0;
    if (!_userOverrodeFx && res.fxRate != null && res.fxRate! > 0) {
      _activeFxRate = res.fxRate;
      _fxCtrl.text = res.fxRate!.toString();
    }
  }

  Future<void> _stopCamera() async {
    final ctrl = _cameraCtrl;
    _cameraCtrl = null;
    if (ctrl == null) return;
    try {
      if (ctrl.value.isStreamingImages) {
        await ctrl.stopImageStream();
      }
    } catch (_) {}
    try {
      await ctrl.dispose();
    } catch (_) {}
  }

  Future<void> _initCamera({ResolutionPreset preset = ResolutionPreset.high}) async {
    setState(() {
      _initializing = true;
      _cameraError = null;
      _streamError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera detected');
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // Android 必须用 ImageFormatGroup.yuv420：
      // camera_android_camerax 0.6.x 使用 ImageFormatGroup.nv21 时会在内部 ImageProxyUtils 抛异常导致 0 帧！
      final ctrl = CameraController(
        back,
        preset,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      _cameraDesc = back;
      _cameraCtrl = ctrl;
      setState(() => _initializing = false);
      final streamOk = await _startStream();
      if (!streamOk && preset == ResolutionPreset.high && mounted) {
        // 若部分机型高分辨率并发绑定 Preview+ImageCapture+ImageAnalysis 失败，自动降级 medium 重试一次
        await _stopCamera();
        await _initCamera(preset: ResolutionPreset.medium);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _cameraError = e.toString();
      });
    }
  }

  Future<bool> _startStream() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return false;
    if (ctrl.value.isStreamingImages) return true;
    try {
      await ctrl.startImageStream(_onCameraFrame);
      if (mounted && _streamError != null) {
        setState(() => _streamError = null);
      }
      return true;
    } catch (e, st) {
      debugPrint('[MenuOcrLab] startImageStream failed: $e\n$st');
      if (mounted) {
        setState(() => _streamError = e.toString());
      }
      return false;
    }
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_paused || _busyStillOcr || _processingFrame || _translating || !mounted) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < _streamThrottle) return;
    final cam = _cameraDesc;
    final ctrl = _cameraCtrl;
    final ocr = _ocrService;
    if (cam == null || ctrl == null || ocr == null) return;

    _processingFrame = true;
    _lastFrameAt = now;
    try {
      final res = await ocr.processCameraImage(
        image: image,
        camera: cam,
        deviceOrientation: ctrl.value.deviceOrientation,
      );
      if (res == null || !mounted || _paused) return;
      setState(() {
        _ocrRunCount++;
        _streamError = null;
        _latest = res;
        if (_translation == null && _translateError == null) {
          _resultTab = 1;
        }
      });
    } catch (e, st) {
      debugPrint('[MenuOcrLab] frame OCR error: $e\n$st');
      if (mounted) {
        setState(() {
          _streamError =
              '$e [${image.width}x${image.height} p=${image.planes.length} fmt=${image.format.raw}]';
        });
      }
    } finally {
      _processingFrame = false;
    }
  }

  Future<void> _toggleTorch() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    try {
      final next = !_torchOn;
      await ctrl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } catch (_) {}
  }

  Future<void> _captureHdPhoto() async {
    final ctrl = _cameraCtrl;
    final ocr = _ocrService;
    if (ctrl == null || !ctrl.value.isInitialized || ocr == null || _busyStillOcr) {
      return;
    }
    setState(() {
      _busyStillOcr = true;
      _paused = true;
    });
    try {
      if (ctrl.value.isStreamingImages) {
        await ctrl.stopImageStream();
      }
      final photo = await ctrl.takePicture();
      final res = await ocr.processFilePath(photo.path, source: 'photo');
      if (!mounted) return;
      setState(() {
        _latest = res;
        _busyStillOcr = false;
      });
      if (!res.isEmpty) {
        await _translateCurrentMenu();
      }
    } catch (e) {
      debugPrint('[MenuOcrLab] HD capture OCR error: $e');
      if (mounted) {
        setState(() => _busyStillOcr = false);
      }
    } finally {
      if (mounted && !_paused) {
        await _startStream();
      }
    }
  }

  Future<void> _pickGalleryPhoto() async {
    final ocr = _ocrService ?? MenuOcrService();
    _ocrService ??= ocr;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() {
      _busyStillOcr = true;
      _paused = true;
    });
    try {
      final res = await ocr.processFilePath(picked.path, source: 'gallery');
      if (!mounted) return;
      setState(() {
        _latest = res;
        _busyStillOcr = false;
      });
      if (!res.isEmpty) {
        await _translateCurrentMenu();
      }
    } catch (e) {
      debugPrint('[MenuOcrLab] gallery OCR error: $e');
      if (mounted) {
        setState(() => _busyStillOcr = false);
      }
    }
  }

  Future<void> _translateCurrentMenu() async {
    final text = _latest?.fullText.trim() ?? '';
    if (text.isEmpty || _translating) return;

    setState(() {
      _paused = true;
      _translating = true;
      _translateError = null;
      _translateNeedsConfig = false;
      _resultTab = 0;
    });

    try {
      final customFx = _userOverrodeFx ? _activeFxRate : null;
      final res = widget.onTranslateForTest != null
          ? await widget.onTranslateForTest!(text, customFx)
          : await AiService.translateMenuOcrText(
              text,
              customFxRate: customFx,
              timeout: const Duration(seconds: 15),
            );
      if (!mounted) return;
      setState(() {
        _translating = false;
        _applyTranslation(res);
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _translating = false;
        _translateError = e.message;
        _translateNeedsConfig = e.needsConfig;
        _resultTab = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _translating = false;
        _translateError = e.toString();
        _translateNeedsConfig = false;
        _resultTab = 0;
      });
    }
  }

  Future<void> _togglePause() async {
    final next = !_paused;
    setState(() => _paused = next);
    if (!next && _cameraCtrl != null && _cameraCtrl!.value.isInitialized) {
      await _startStream();
    }
  }

  Future<void> _copyText() async {
    final txt = _latest?.fullText ?? '';
    if (txt.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: txt));
    if (!mounted) return;
    toast(context, context.l10n.menuOcrCopiedToast);
  }

  String _statusText(BuildContext context) {
    final l = context.l10n;
    final res = _latest;
    final count = res?.blocks.length ?? 0;
    final ms = res?.elapsedMs ?? 0;
    if (_paused) {
      if (res?.source == 'photo') return l.menuOcrStatusPhoto(ms, count);
      if (res?.source == 'gallery') return l.menuOcrStatusGallery(ms, count);
      return l.menuOcrStatusPaused(count);
    }
    if (res == null && _ocrRunCount == 0 && _cameraError == null) {
      return l.menuOcrStatusWaiting;
    }
    return l.menuOcrStatusLive(ms, count);
  }

  Color _lightColor(BuildContext context, String light) => switch (light) {
        'green' => AppColors.success(context),
        'red' => AppColors.danger(context),
        _ => AppColors.warning(context),
      };

  String _lightLabel(BuildContext context, String light) {
    final l = context.l10n;
    return switch (light) {
      'green' => l.menuLightGreen,
      'red' => l.menuLightRed,
      _ => l.menuLightYellow,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    final success = AppColors.success(context);
    final warning = AppColors.warning(context);
    final res = _latest;
    final hasOcrText = res != null && !res.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.menuOcrTitle),
        actions: [
          if (_cameraCtrl != null && _cameraCtrl!.value.isInitialized)
            IconButton(
              tooltip: l.menuOcrTorchTooltip,
              icon: Icon(
                _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: _torchOn ? warning : null,
              ),
              onPressed: _toggleTorch,
            ),
        ],
      ),
      body: Column(
        children: [
          // 上半区：实时相机取景框 + 端侧 OCR 状态胶囊
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: ClipRRect(
                borderRadius: AppRadius.bXl,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_initializing)
                      Container(
                        color: AppColors.surfaceSubtle(context),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: primary),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              l.menuOcrCameraInit,
                              style: AppTypography.bodySecondary(context),
                            ),
                          ],
                        ),
                      )
                    else if (_cameraCtrl != null && _cameraCtrl!.value.isInitialized)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _cameraCtrl!.value.previewSize?.height ?? 720,
                          height: _cameraCtrl!.value.previewSize?.width ?? 1280,
                          child: CameraPreview(_cameraCtrl!),
                        ),
                      )
                    else
                      Container(
                        color: AppColors.surfaceSubtle(context),
                        alignment: Alignment.center,
                        padding: AppSpacing.cardPadding,
                        child: Text(
                          _cameraError != null
                              ? l.menuOcrCameraError(_cameraError!)
                              : l.menuOcrEmptyHint,
                          style: AppTypography.bodySecondary(context),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        key: const ValueKey('menu_ocr_status_pill'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surface(context).withValues(alpha: 0.90),
                          borderRadius: AppRadius.bPill,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _paused ? warning : success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _statusText(context),
                              style: AppTypography.badge(
                                context,
                                color: _paused ? warning : primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_busyStillOcr)
                      Container(
                        color: Colors.black.withValues(alpha: 0.38),
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(color: primary),
                      ),
                    if (_streamError != null)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: Container(
                          key: const ValueKey('menu_ocr_stream_error_banner'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger(context).withValues(alpha: 0.90),
                            borderRadius: AppRadius.bMd,
                          ),
                          child: SelectableText(
                            l.menuOcrStreamError(_streamError!),
                            style: AppTypography.caption(context, color: Colors.white)
                                .copyWith(fontSize: 10.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 操作栏：翻译菜单（核心 CTA）/ 定格 / 拍高清帧 / 相册测图 / 复制文字
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilledButton.icon(
                    key: const ValueKey('menu_translate_btn'),
                    onPressed: (hasOcrText && !_translating && !_busyStillOcr)
                        ? _translateCurrentMenu
                        : null,
                    icon: const Icon(Icons.translate_rounded, size: 18),
                    label: Text(l.menuTranslateBtn),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.tonalIcon(
                    key: const ValueKey('menu_ocr_pause_btn'),
                    onPressed: _togglePause,
                    icon: Icon(
                      _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 18,
                    ),
                    label: Text(_paused ? l.menuOcrResumeBtn : l.menuOcrPauseBtn),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('menu_ocr_capture_btn'),
                    onPressed: (_cameraCtrl != null &&
                            _cameraCtrl!.value.isInitialized &&
                            !_busyStillOcr)
                        ? _captureHdPhoto
                        : null,
                    icon: const Icon(Icons.camera_rounded, size: 18),
                    label: Text(l.menuOcrCaptureBtn),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('menu_ocr_gallery_btn'),
                    onPressed: _busyStillOcr ? null : _pickGalleryPhoto,
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: Text(l.menuOcrGalleryBtn),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filledTonal(
                    key: const ValueKey('menu_ocr_copy_btn'),
                    tooltip: l.menuOcrCopyBtn,
                    onPressed: hasOcrText ? _copyText : null,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),

          // 视图切换条（翻译卡片 / OCR 原文）+ 可手动编辑汇率输入框
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                ChoiceChip(
                  key: const ValueKey('menu_tab_translated'),
                  label: Text(l.menuTabTranslated),
                  selected: _resultTab == 0,
                  onSelected: (_) => setState(() => _resultTab = 0),
                ),
                const SizedBox(width: AppSpacing.xs),
                ChoiceChip(
                  key: const ValueKey('menu_tab_ocr'),
                  label: Text(l.menuTabOcrRaw),
                  selected: _resultTab == 1,
                  onSelected: (_) => setState(() => _resultTab = 1),
                ),
                const Spacer(),
                SizedBox(
                  width: 148,
                  child: TextField(
                    key: const ValueKey('menu_fx_rate_input'),
                    controller: _fxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: AppTypography.caption(context).copyWith(
                      fontSize: 12,
                      color: AppColors.textPrimary(context),
                    ),
                    onChanged: (val) {
                      final parsed = double.tryParse(val.trim());
                      setState(() {
                        if (parsed != null && parsed.isFinite && parsed > 0) {
                          _activeFxRate = parsed;
                          _userOverrodeFx = true;
                        } else if (val.trim().isEmpty) {
                          _userOverrodeFx = false;
                          _activeFxRate = _translation?.fxRate;
                        }
                      });
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      labelText: l.menuFxRateLabel,
                      hintText: '0.000285',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_activeFxRate != null && _activeFxRate! > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l.menuFxRatePreview((100000 * _activeFxRate!).toStringAsFixed(1)),
                  key: const ValueKey('menu_fx_rate_preview'),
                  style: AppTypography.caption(context).copyWith(fontSize: 10.5),
                ),
              ),
            ),

          // 下半区：翻译卡片列表 或 OCR 原文列表
          Expanded(
            flex: 6,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: _resultTab == 0
                    ? _buildTranslatedArea(context)
                    : _buildOcrRawArea(context, res),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslatedArea(BuildContext context) {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    final danger = AppColors.danger(context);
    final warning = AppColors.warning(context);

    if (_translating) {
      return SurfaceCard(
        key: const ValueKey('menu_translating_card'),
        padding: AppSpacing.cardPadding,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: primary),
              const SizedBox(height: AppSpacing.md),
              Text(
                l.menuTranslatingHint,
                style: AppTypography.bodySecondary(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_translateError != null) {
      return SurfaceCard(
        key: const ValueKey('menu_translate_error_card'),
        padding: AppSpacing.cardPadding,
        backgroundColor: AppColors.softBg(context, danger),
        borderColor: AppColors.softBorder(context, danger),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _translateError!,
                style: AppTypography.body(context, color: danger),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (_translateNeedsConfig)
                    FilledButton.icon(
                      key: const ValueKey('menu_open_settings_btn'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        );
                      },
                      icon: const Icon(Icons.settings_rounded, size: 18),
                      label: Text(l.menuOpenSettingsBtn),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('menu_retry_btn'),
                    onPressed: _translateCurrentMenu,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l.menuRetryBtn),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final trans = _translation;
    if (trans == null) {
      return SurfaceCard(
        padding: AppSpacing.cardPadding,
        child: Center(
          child: Text(
            l.menuOcrEmptyHint,
            style: AppTypography.bodySecondary(context),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (trans.parseFailed) {
      return SurfaceCard(
        key: const ValueKey('menu_parse_failed_card'),
        padding: AppSpacing.cardPadding,
        child: ListView(
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: warning),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    l.menuParseFailedHint,
                    style: AppTypography.subtitle(context, color: warning),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              trans.rawReply,
              key: const ValueKey('menu_parse_failed_raw_text'),
              style: AppTypography.body(context),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('menu_retry_btn'),
                onPressed: _translateCurrentMenu,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l.menuRetryBtn),
              ),
            ),
          ],
        ),
      );
    }

    final effectiveFx = _activeFxRate ?? trans.fxRate;
    return ListView.separated(
      key: const ValueKey('menu_translated_list'),
      itemCount: trans.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, idx) => _buildDishCard(context, trans.items[idx], effectiveFx),
    );
  }

  Widget _buildDishCard(
    BuildContext context,
    MenuDishItem item,
    double? effectiveFx,
  ) {
    final l = context.l10n;
    final lightColor = _lightColor(context, item.light);
    final lightLabel = _lightLabel(context, item.light);
    final primary = AppColors.primary(context);
    final workoutColor = AppColors.moduleWorkout(context);
    final rmb = item.effectiveRmb(effectiveFx);

    final priceParts = <String>[
      if (item.vnd != null) '${_vndFmt.format(item.vnd)}₫',
      if (rmb != null) l.menuPriceRmb(rmb.toStringAsFixed(1)),
    ];
    final priceText = priceParts.join(' ');

    final hasMacros =
        item.proteinG != null || item.carbsG != null || item.fatG != null;

    return SurfaceCard(
      padding: AppSpacing.cardCompactPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 红绿灯徽章（挂接 Material 3 现有色板）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.softBg(
                    context,
                    lightColor,
                    lightAlpha: 0.14,
                    darkAlpha: 0.24,
                  ),
                  borderRadius: AppRadius.bPill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: lightColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      lightLabel,
                      style: AppTypography.badge(context, color: lightColor)
                          .copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.cn,
                      style: AppTypography.cardTitle(context).copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      item.vn,
                      style: AppTypography.bodySecondary(context),
                    ),
                  ],
                ),
              ),
              if (item.kcal != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, workoutColor),
                    borderRadius: AppRadius.bSm,
                  ),
                  child: Text(
                    '${item.kcal} kcal',
                    style: AppTypography.badge(context, color: workoutColor),
                  ),
                ),
              ],
            ],
          ),
          if (priceText.isNotEmpty || hasMacros) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (priceText.isNotEmpty)
                  Text(
                    priceText,
                    style: AppTypography.subtitle(context, color: primary),
                  ),
                if (hasMacros)
                  Text(
                    l.menuMacrosSummary(
                      fmtNum(item.proteinG ?? 0),
                      fmtNum(item.carbsG ?? 0),
                      fmtNum(item.fatG ?? 0),
                    ),
                    style: AppTypography.caption(context),
                  ),
              ],
            ),
          ],
          if (item.tip.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.tip,
              style: AppTypography.bodySecondary(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOcrRawArea(BuildContext context, MenuOcrFrameResult? res) {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    return SurfaceCard(
      padding: AppSpacing.cardCompactPadding,
      child: (res == null || res.isEmpty)
          ? Center(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Text(
                  l.menuOcrEmptyHint,
                  style: AppTypography.bodySecondary(context),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              key: const ValueKey('menu_ocr_blocks_list'),
              itemCount: res.blocks.length,
              separatorBuilder: (_, _) => const Divider(height: 12),
              itemBuilder: (_, idx) {
                final item = res.blocks[idx];
                final rect = item.boundingBox;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.softBg(context, primary),
                            borderRadius: AppRadius.bSm,
                          ),
                          child: Text(
                            '#${idx + 1}',
                            style: AppTypography.badge(context, color: primary)
                                .copyWith(fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '(${rect.left.round()}, ${rect.top.round()}) ${rect.width.round()}×${rect.height.round()}',
                          style: AppTypography.caption(context).copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      item.text,
                      style: AppTypography.body(context).copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
