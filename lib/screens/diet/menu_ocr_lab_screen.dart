import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/menu_ocr_service.dart';
import '../../widgets/common.dart';

/// v3.3.0 第一批临时验证页：ML Kit 端侧越南语/英语菜单 OCR 实时识别实验室。
/// - 只验证 ML Kit TextRecognitionScript.latin 对真实越南菜单（如 Phở bò / Bún chả）的识别准确度与速度
/// - 不接 AI、不做 AR 浮层、不碰调试后端
class MenuOcrLabScreen extends StatefulWidget {
  final MenuOcrFrameResult? initialResultForTest;
  final bool disableCameraForTest;

  const MenuOcrLabScreen({
    super.key,
    this.initialResultForTest,
    this.disableCameraForTest = false,
  });

  @override
  State<MenuOcrLabScreen> createState() => _MenuOcrLabScreenState();
}

class _MenuOcrLabScreenState extends State<MenuOcrLabScreen>
    with WidgetsBindingObserver {
  MenuOcrService? _ocrService;
  CameraController? _cameraCtrl;
  CameraDescription? _cameraDesc;

  bool _initializing = true;
  bool _paused = false;
  bool _torchOn = false;
  bool _processingFrame = false;
  bool _busyStillOcr = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _cameraError;
  MenuOcrFrameResult? _latest;

  static const Duration _streamThrottle = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialResultForTest != null) {
      _latest = widget.initialResultForTest;
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
    _stopCamera();
    _ocrService?.dispose();
    super.dispose();
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

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _cameraError = null;
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
      final ctrl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      _cameraDesc = back;
      _cameraCtrl = ctrl;
      setState(() => _initializing = false);
      await _startStream();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _cameraError = e.toString();
      });
    }
  }

  Future<void> _startStream() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !ctrl.value.isInitialized || ctrl.value.isStreamingImages) {
      return;
    }
    try {
      await ctrl.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('[MenuOcrLab] startImageStream failed: $e');
    }
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_paused || _busyStillOcr || _processingFrame || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < _streamThrottle) return;
    final cam = _cameraDesc;
    final ctrl = _cameraCtrl;
    final ocr = _ocrService;
    if (cam == null || ctrl == null || ocr == null) return;

    _processingFrame = true;
    _lastFrameAt = now;
    try {
      final input = MenuOcrService.buildInputImageFromCameraImage(
        image: image,
        camera: cam,
        deviceOrientation: ctrl.value.deviceOrientation,
      );
      if (input == null) return;
      final res = await ocr.processInputImage(
        input,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        source: 'stream',
      );
      if (!mounted || _paused) return;
      setState(() => _latest = res);
    } catch (e) {
      debugPrint('[MenuOcrLab] frame OCR error: $e');
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
    } catch (e) {
      debugPrint('[MenuOcrLab] gallery OCR error: $e');
      if (mounted) {
        setState(() => _busyStillOcr = false);
      }
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
    return l.menuOcrStatusLive(ms, count);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    final success = AppColors.success(context);
    final warning = AppColors.warning(context);
    final res = _latest;

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
          // 上半区：实时相机取景框 + 状态胶囊
          Expanded(
            flex: 5,
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
                  ],
                ),
              ),
            ),
          ),

          // 操作栏：定格 / 拍高清帧 / 相册测图 / 复制文字
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
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
                  FilledButton.icon(
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
                    onPressed: (res != null && !res.isEmpty) ? _copyText : null,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),

          // 下半区：实时识别出的菜单文本块列表（大字号清晰展示越南语变音符）
          Expanded(
            flex: 5,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: SurfaceCard(
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
                                      style: AppTypography.caption(context)
                                          .copyWith(fontSize: 10),
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
