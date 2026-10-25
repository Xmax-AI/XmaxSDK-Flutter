import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

import '../../localization/xlab_localization.dart';
import 'realtime_control_panel.dart';
import 'realtime_camera_action_bar.dart';
import 'realtime_camera_switch_transition.dart';
import 'realtime_loading_overlay.dart';
import 'realtime_statistics_panel.dart';
import 'realtime_local_input.dart';
import 'realtime_file_video_source.dart';
import 'realtime_media_top_bar.dart';
import 'xlab_trajectory_renderer.dart';

/// Resolves the initial generation mode from the media input only.
///
/// Rendering customization is intentionally excluded: changing the trajectory
/// appearance must not change the camera workflow or generation condition.
XLabRealtimePanelMode initialRealtimePanelMode({
  required XLabRealtimeLocalInput? localInput,
}) => localInput is XLabRealtimeImageInput
    ? XLabRealtimePanelMode.touch
    : XLabRealtimePanelMode.character;

class RealtimePage extends StatefulWidget {
  const RealtimePage({
    required this.apiKey,
    this.environment = XmaxEnvironment.china,
    this.model = RealtimeModel.x2_1_1_preview_cn,
    this.customTrajectory = false,
    this.localInput,
    super.key,
  });

  final String apiKey;
  final XmaxEnvironment environment;
  final RealtimeModel model;
  final bool customTrajectory;
  final XLabRealtimeLocalInput? localInput;

  @override
  State<RealtimePage> createState() => _RealtimePageState();
}

class _RealtimePageState extends State<RealtimePage>
    with WidgetsBindingObserver {
  late XmaxRealtimeManaging _manager;
  late XmaxStorageManaging _storageManager;
  late MediaServicing _mediaService;
  final _promptController = TextEditingController();
  final _referencesByCategory = <String, List<XLabRealtimeReference>>{
    for (final mode in XLabRealtimePanelMode.values)
      if (mode.usesReferences) mode.id: <XLabRealtimeReference>[],
  };
  RealtimeMediaStream? _localStream;
  RealtimeMediaStream? _remoteStream;
  RealtimeState _state = const RealtimeState(
    connectionState: RealtimeConnectionState.idle,
  );
  XmaxError? _lastError;
  UplinkVideoStatistics? _uplinkStatistics;
  DownlinkVideoStatistics? _downlinkStatistics;
  RealtimeNetworkQuality? _networkQuality;
  bool _isStatisticsVisible = false;
  String? _externalVideoPath;
  bool _isAudioMuted = true;
  double _remoteAudioVolume = 1;
  RealtimeQualityLevel? _uplinkLevel;
  RealtimeQualityLevel? _downlinkLevel;
  bool _isAdjustingQuality = false;
  String? _qualityError;
  int _qualityReadVersion = 0;
  late XLabRealtimePanelMode _panelMode;
  XLabRealtimeReference? _selectedReference;
  XLabRealtimeReference? _promptReference;
  bool _cameraReady = false;
  bool _busy = false;
  bool _isSwitchingCamera = false;
  bool _isWaitingForRemoteVideo = false;
  bool _isLoading = true;
  bool _isSuspendedForBackground = false;
  bool _isResumingFromBackground = false;
  Future<void> _backgroundCleanup = Future<void>.value();
  Animation<double>? _routeAnimation;
  bool _hasScheduledInitialCameraStart = false;
  int _realtimeOperationVersion = 0;
  final _referenceUploadTokens = <String, Object>{};
  late final XLabTrajectoryRenderer? _customRenderer = widget.customTrajectory
      ? XLabTrajectoryRenderer()
      : null;

  @override
  void initState() {
    super.initState();
    _panelMode = initialRealtimePanelMode(localInput: widget.localInput);
    if (widget.localInput is XLabRealtimeImageInput) {
      _isLoading = false;
    }
    if (widget.localInput case XLabRealtimeExternalVideoInput input) {
      _externalVideoPath = input.path;
    }
    _promptController.addListener(_promptDidChange);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadReferences());
    _configureManager();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) {
      return;
    }

    _routeAnimation?.removeStatusListener(_routeAnimationDidChange);
    _routeAnimation = animation;
    animation?.addStatusListener(_routeAnimationDidChange);

    if (animation == null || animation.status == AnimationStatus.completed) {
      _scheduleInitialCameraStart();
    }
  }

  void _routeAnimationDidChange(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _scheduleInitialCameraStart();
    }
  }

  void _scheduleInitialCameraStart() {
    if (_hasScheduledInitialCameraStart ||
        widget.localInput is XLabRealtimeImageInput) {
      return;
    }

    _hasScheduledInitialCameraStart = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_startLocalMedia());
      }
    });
  }

  Future<void> _loadReferences() async {
    final references = await loadXLabRealtimeReferences();
    if (!mounted) return;
    setState(() {
      for (final reference in references) {
        _referencesByCategory
            .putIfAbsent(reference.categoryID, () => <XLabRealtimeReference>[])
            .add(reference);
      }
    });
  }

  void _configureManager() {
    final client = XmaxClient(
      configuration: XmaxConfiguration(
        apiKey: widget.apiKey,
        environment: widget.environment,
        loggerOptions: XmaxLoggerOption.all,
      ),
    );
    _storageManager = client.createStorageManager();
    _mediaService = client.createMediaService(model: widget.model);
    _manager = client.createRealtimeManager(
      options: RealtimeConfiguration(model: widget.model),
    );
    _manager.setUplinkVideoStatisticsListener((statistics) {
      if (mounted && !_isSuspendedForBackground) {
        setState(() => _uplinkStatistics = statistics);
        unawaited(_refreshQualityLevels());
      }
    });
    _manager.setDownlinkVideoStatisticsListener((statistics) {
      if (mounted && !_isSuspendedForBackground) {
        setState(() => _downlinkStatistics = statistics);
        unawaited(_refreshQualityLevels());
      }
    });
    _manager.setNetworkQualityListener((quality) {
      if (mounted && !_isSuspendedForBackground) {
        setState(() => _networkQuality = quality);
        unawaited(_refreshQualityLevels());
      }
    });
    _manager.setStateListener((state) {
      if (!mounted || _isSuspendedForBackground) return;
      unawaited(_refreshQualityLevels());
      setState(() {
        _state = state;
        if (state.connectionState == RealtimeConnectionState.ready ||
            state.connectionState == RealtimeConnectionState.idle) {
          _uplinkStatistics = null;
          _downlinkStatistics = null;
          _networkQuality = null;
        }
        if (state.connectionState == RealtimeConnectionState.preparing ||
            state.connectionState == RealtimeConnectionState.idle) {
          _cameraReady = false;
        } else if (state.connectionState == RealtimeConnectionState.ready) {
          _cameraReady = true;
          _isLoading = false;
          _isWaitingForRemoteVideo = false;
        }
        if (state.connectionState == RealtimeConnectionState.connected &&
            state.taskID == null) {
          _lastError = null;
        }
        final error = state.reason?.error;
        if (error != null) {
          _lastError = error;
          _isLoading = false;
          _isWaitingForRemoteVideo = false;
          _isSwitchingCamera = false;
        }
      });
    });
    // Performance alarms remain available in SDK logs; XLab does not promote
    // transient quality warnings to user-facing errors.
  }

  Future<void> _startLocalMedia() async {
    if (_isSuspendedForBackground || _busy || _localStream != null) return;

    final operation = ++_realtimeOperationVersion;
    setState(() {
      _busy = true;
      _cameraReady = false;
      _isLoading = true;
      _lastError = null;
    });
    try {
      final path = _externalVideoPath;
      final RealtimeMediaStream stream;
      if (path != null) {
        final source = await RealtimeFileVideoSource.make(
          path: path,
          frameRate: widget.model.defaultFrameRate,
          mediaService: _mediaService,
        );
        if (!_isCurrentRealtimeOperation(operation) ||
            _isSuspendedForBackground) {
          return;
        }
        stream = await _manager.createExternalVideoStream(source: source);
        if (_isCurrentRealtimeOperation(operation) &&
            !_isSuspendedForBackground) {
          _isAudioMuted = !source.hasAudio;
          _remoteAudioVolume = 1;
          try {
            await _manager.setRemoteAudioVolume(source.hasAudio ? 1 : 0);
          } catch (error) {
            if (_isCurrentRealtimeOperation(operation)) _showError(error);
          }
        }
      } else {
        stream = await _manager.createLocalCameraStream();
      }
      if (_isCurrentRealtimeOperation(operation)) {
        setState(() => _localStream = stream);
      }
    } catch (error) {
      if (_isCurrentRealtimeOperation(operation)) {
        _showError(error);
        setState(() => _isLoading = false);
      }
    } finally {
      if (_isCurrentRealtimeOperation(operation)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refreshQualityLevels() async {
    final version = ++_qualityReadVersion;
    final uplink = await _manager.uplinkQualityLevel;
    final downlink = await _manager.downlinkQualityLevel;
    if (!mounted ||
        _isSuspendedForBackground ||
        version != _qualityReadVersion) {
      return;
    }
    setState(() {
      _uplinkLevel = uplink;
      _downlinkLevel = downlink;
    });
  }

  Future<void> _setQualityLevel(
    RealtimeQualityLevel level, {
    required bool downlink,
  }) async {
    if (_isAdjustingQuality ||
        _state.connectionState != RealtimeConnectionState.generating) {
      return;
    }
    setState(() {
      _isAdjustingQuality = true;
      _qualityError = null;
    });
    try {
      if (downlink) {
        await _manager.setDownlinkQualityLevel(level);
      } else {
        await _manager.setUplinkQualityLevel(level);
      }
      await _refreshQualityLevels();
    } catch (error) {
      if (mounted &&
          _state.connectionState == RealtimeConnectionState.generating) {
        setState(() => _qualityError = XmaxError.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _isAdjustingQuality = false);
    }
  }

  Future<void> _startGeneration(
    RealtimeContext context, {
    bool faceRestoration = false,
  }) async {
    final localStream = _localStream;
    if (localStream == null) return;

    final connectionState = _state.connectionState;
    final isConditionUpdate =
        connectionState == RealtimeConnectionState.generating;

    // Only the newest UI operation may publish async results back to XLab.
    final operation = ++_realtimeOperationVersion;
    setState(() {
      _busy = true;
      // A change_condition keeps rendering the current remote stream. Loading
      // is reserved for the initial connection/generation transition.
      if (!isConditionUpdate) {
        _isWaitingForRemoteVideo = true;
        _isLoading = true;
      }
      _lastError = null;
    });
    try {
      // Always request the current remote track, including when a newer
      // selection supersedes the operation that originally connected it.
      final remote = await _manager.startGeneration(
        localStream: localStream,
        context: context,
        faceRestoration: faceRestoration,
      );

      if (!_isCurrentRealtimeOperation(operation)) return;
      setState(() {
        if (remote != null) _remoteStream = remote;
      });
    } catch (error) {
      if (_isCurrentRealtimeOperation(operation)) {
        _showError(error);
        setState(() {
          if (_state.connectionState != RealtimeConnectionState.generating) {
            _isWaitingForRemoteVideo = false;
            _isLoading = false;
          }
        });
      }
    } finally {
      if (_isCurrentRealtimeOperation(operation)) {
        setState(() => _busy = false);
      }
    }
  }

  void _remoteVideoDidBecomeReady() {
    if (!mounted || _isSuspendedForBackground || !_isWaitingForRemoteVideo) {
      return;
    }

    setState(() {
      _isWaitingForRemoteVideo = false;
      _isLoading = false;
      _isSwitchingCamera = false;
    });
  }

  Future<void> _stopGeneration() async {
    final connectionState = _state.connectionState;
    final canStop =
        _busy ||
        connectionState == RealtimeConnectionState.connecting ||
        connectionState == RealtimeConnectionState.connected ||
        connectionState == RealtimeConnectionState.generating;
    if (!canStop) {
      return;
    }

    final operation = ++_realtimeOperationVersion;
    setState(() {
      _busy = true;
      _isWaitingForRemoteVideo = false;
      _isLoading = !_cameraReady;
    });
    try {
      await _manager.disconnect();
      if (_isCurrentRealtimeOperation(operation)) {
        setState(() {
          _remoteStream = null;
          _selectedReference = null;
          _isLoading = !_cameraReady;
        });
      }
    } catch (error) {
      if (_isCurrentRealtimeOperation(operation)) {
        _showError(error);
        setState(() => _isLoading = !_cameraReady);
      }
    } finally {
      if (_isCurrentRealtimeOperation(operation)) {
        setState(() => _busy = false);
      }
    }
  }

  void _selectMode(XLabRealtimePanelMode mode) {
    if (_panelMode == mode) return;
    setState(() => _panelMode = mode);
  }

  Future<void> _selectReference(XLabRealtimeReference reference) async {
    final isCancellingSelection = _selectedReference?.id == reference.id;
    if (isCancellingSelection) {
      setState(() => _selectedReference = null);
      await _stopGeneration();
      return;
    }

    setState(() => _selectedReference = reference);

    switch (reference.uploadState) {
      case XLabRealtimeReferenceUploadState.uploading:
        return;
      case XLabRealtimeReferenceUploadState.failed:
        await _uploadReference(reference);
        return;
      case XLabRealtimeReferenceUploadState.ready:
        break;
    }

    final referencePath = reference.referencePath;
    if (referencePath == null) return;

    await _startGeneration(
      RealtimeContext(prompt: _panelMode.prompt, referencePath: referencePath),
      faceRestoration: reference.categoryID == 'clothx',
    );
  }

  Future<void> _startTouchGeneration() => _startGeneration(
    RealtimeContext(prompt: XLabRealtimePanelMode.touch.prompt),
  );

  Future<void> _submitPrompt() async {
    final prompt = _promptController.text.trim();
    final promptReference = _promptReference;
    if (prompt.isEmpty ||
        (promptReference != null && !promptReference.isReady)) {
      return;
    }

    await _startGeneration(
      RealtimeContext(
        prompt: prompt,
        referencePath: promptReference?.referencePath,
      ),
    );
  }

  Future<void> _pickReference({required bool forPrompt}) async {
    if (_busy) return;

    if (forPrompt && _handlePromptReferenceAction()) return;

    try {
      // Reference images come from Photos, matching the native iOS XLab.
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      final reference = XLabRealtimeReference(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        categoryID: forPrompt ? XLabRealtimePanelMode.free.id : _panelMode.id,
        title: file.name,
        referencePath: null,
        iconBytes: bytes,
        sourceURL: Uri.file(file.path),
        uploadState: XLabRealtimeReferenceUploadState.uploading,
      );

      // Match iOS: show and select the local image before COS upload begins.
      setState(() {
        _lastError = null;
        if (forPrompt) {
          _promptReference = reference;
        } else {
          _referencesByCategory
              .putIfAbsent(
                reference.categoryID,
                () => <XLabRealtimeReference>[],
              )
              .insert(0, reference);
          _selectedReference = reference;
        }
      });

      await _uploadReference(reference);
    } catch (error) {
      _showError(error);
    }
  }

  bool _handlePromptReferenceAction() {
    final reference = _promptReference;
    if (reference == null) return false;

    switch (reference.uploadState) {
      case XLabRealtimeReferenceUploadState.uploading:
        return true;
      case XLabRealtimeReferenceUploadState.failed:
        unawaited(_uploadReference(reference));
        return true;
      case XLabRealtimeReferenceUploadState.ready:
        _referenceUploadTokens.remove(reference.id);
        setState(() => _promptReference = null);
    }

    return true;
  }

  Future<void> _uploadReference(XLabRealtimeReference reference) async {
    final sourceURL = reference.sourceURL;
    if (sourceURL == null) return;

    // A token makes late COS results harmless after retry, removal, or dispose.
    final token = Object();
    _referenceUploadTokens[reference.id] = token;
    setState(() {
      reference.referencePath = null;
      reference.uploadState = XLabRealtimeReferenceUploadState.uploading;
      _lastError = null;
    });

    try {
      final uploaded = await _storageManager.uploadImage(at: sourceURL);
      if (!mounted || _referenceUploadTokens[reference.id] != token) return;

      _referenceUploadTokens.remove(reference.id);
      setState(() {
        reference.referencePath = uploaded.url.toString();
        reference.uploadState = XLabRealtimeReferenceUploadState.ready;
      });

      // Prompt references wait for the submit button. Category references
      // generate immediately when the uploaded item is still selected.
      if (identical(reference, _promptReference) ||
          _selectedReference?.id != reference.id ||
          _panelMode.id != reference.categoryID) {
        return;
      }

      await _startGeneration(
        RealtimeContext(
          prompt: XLabRealtimePanelMode.values
              .firstWhere((mode) => mode.id == reference.categoryID)
              .prompt,
          referencePath: reference.referencePath,
        ),
        faceRestoration: reference.categoryID == 'clothx',
      );
    } catch (error) {
      if (!mounted || _referenceUploadTokens[reference.id] != token) return;

      _referenceUploadTokens.remove(reference.id);
      setState(() {
        reference.uploadState = XLabRealtimeReferenceUploadState.failed;
      });
      _showError(error);
    }
  }

  Future<void> _switchCamera() async {
    if (_busy || _localStream == null) return;

    final operation = ++_realtimeOperationVersion;
    final wasGenerating =
        _state.connectionState == RealtimeConnectionState.generating;
    setState(() {
      _busy = true;
      _isSwitchingCamera = true;
      if (wasGenerating) {
        _isWaitingForRemoteVideo = true;
        _isLoading = true;
      }
    });
    try {
      final stream = await _manager.switchCamera();
      if (_isCurrentRealtimeOperation(operation)) {
        setState(() => _localStream = stream);
      }
    } catch (error) {
      if (_isCurrentRealtimeOperation(operation)) {
        _showError(error);
        setState(() {
          _isWaitingForRemoteVideo = false;
          _isLoading = !_cameraReady;
        });
      }
    } finally {
      if (_isCurrentRealtimeOperation(operation)) {
        setState(() {
          _busy = false;
          _isSwitchingCamera = false;
        });
      }
    }
  }

  Future<void> _replaceExternalVideo() async {
    if (_busy || _isSuspendedForBackground) return;
    // The system picker may temporarily background the app; select before closing the source.
    final selected = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (selected == null || !mounted) return;
    final operation = ++_realtimeOperationVersion;
    setState(() {
      _busy = true;
      _isLoading = true;
    });
    try {
      await _manager.close();
      if (!_isCurrentRealtimeOperation(operation) ||
          _isSuspendedForBackground) {
        return;
      }
      setState(() {
        _externalVideoPath = selected.path;
        _localStream = null;
        _remoteStream = null;
        _selectedReference = null;
        _cameraReady = false;
        _isWaitingForRemoteVideo = false;
      });
    } catch (error) {
      if (_isCurrentRealtimeOperation(operation)) _showError(error);
    } finally {
      if (_isCurrentRealtimeOperation(operation)) setState(() => _busy = false);
    }
    if (_isCurrentRealtimeOperation(operation) && !_isSuspendedForBackground) {
      await _startLocalMedia();
    }
  }

  Future<void> _toggleExternalAudio() async {
    try {
      final muted = !_isAudioMuted;
      await _manager.setRemoteAudioVolume(muted ? 0 : _remoteAudioVolume);
      if (mounted) setState(() => _isAudioMuted = muted);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _showExternalVolume() async {
    var value = await _manager.remoteAudioVolume;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF202024),
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, update) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  XLabLocalization.shared.text('realtime.volume.remote'),
                  style: const TextStyle(color: Colors.white),
                ),
                Slider(
                  value: value,
                  divisions: 100,
                  label: '${(value * 100).round()}%',
                  onChanged: (next) => update(() => value = next),
                  onChangeEnd: (next) async {
                    try {
                      await _manager.setRemoteAudioVolume(next);
                      if (mounted) {
                        setState(() {
                          _remoteAudioVolume = next;
                          _isAudioMuted = next == 0;
                        });
                      }
                    } catch (error) {
                      if (mounted) _showError(error);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isCurrentRealtimeOperation(int operation) =>
      mounted && operation == _realtimeOperationVersion;

  void _showError(Object error) {
    final xmaxError = XmaxError.from(error);
    if (mounted) setState(() => _lastError = xmaxError);
  }

  void _promptDidChange() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_suspendForBackground());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resumeAfterBackgroundIfNeeded());
    }
  }

  Future<void> _suspendForBackground() async {
    if (_isSuspendedForBackground) return;

    _isSuspendedForBackground = true;
    _isResumingFromBackground = false;
    _realtimeOperationVersion += 1;
    FocusManager.instance.primaryFocus?.unfocus();

    // Clear the active realtime session immediately while
    // preserving the reference catalog, prompt reference, and COS uploads.
    if (mounted) {
      setState(() {
        _localStream = null;
        _uplinkStatistics = null;
        _downlinkStatistics = null;
        _networkQuality = null;
        _remoteStream = null;
        _state = const RealtimeState(
          connectionState: RealtimeConnectionState.idle,
        );
        _selectedReference = null;
        _cameraReady = false;
        _busy = false;
        _isSwitchingCamera = false;
        _isWaitingForRemoteVideo = false;
        _isLoading = false;
        _lastError = null;
      });
    }

    final cleanup = _closeRealtimeForBackground();
    _backgroundCleanup = cleanup;
    await cleanup;
  }

  Future<void> _closeRealtimeForBackground() async {
    try {
      await _manager.close();
    } catch (_) {
      // Background cleanup must not surface a stale error after the next
      // foreground session starts.
    }
  }

  Future<void> _resumeAfterBackgroundIfNeeded() async {
    if (!_isSuspendedForBackground || _isResumingFromBackground) return;

    _isResumingFromBackground = true;
    if (mounted && widget.localInput is! XLabRealtimeImageInput) {
      setState(() => _isLoading = true);
    }

    await _backgroundCleanup;
    final isActive =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!mounted || !_isSuspendedForBackground || !isActive) {
      _isResumingFromBackground = false;
      return;
    }

    _isSuspendedForBackground = false;
    _isResumingFromBackground = false;

    if (widget.localInput is! XLabRealtimeImageInput) {
      await _startLocalMedia();
    } else {
      // File input is already retained by the page and can be displayed again
      // without reopening the camera.
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _realtimeOperationVersion += 1;
    _routeAnimation?.removeStatusListener(_routeAnimationDidChange);
    WidgetsBinding.instance.removeObserver(this);
    _manager.setStateListener(null);
    _manager.setUplinkVideoStatisticsListener(null);
    _manager.setDownlinkVideoStatisticsListener(null);
    _manager.setNetworkQualityListener(null);
    unawaited(_manager.close());
    _promptController.removeListener(_promptDidChange);
    _promptController.dispose();
    _customRenderer?.dispose();
    _referenceUploadTokens.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final generating =
        _state.connectionState == RealtimeConnectionState.generating;
    final localImage = switch (widget.localInput) {
      XLabRealtimeImageInput input => input,
      _ => null,
    };
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF101010),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: <double>[0, 0.48, 1],
                          colors: <Color>[
                            Color(0xFF171719),
                            Color(0xFF0D0D0F),
                            Color(0xFF050506),
                          ],
                        ),
                      ),
                    ),
                    if (_localStream == null && localImage != null)
                      Image.file(
                        File(localImage.path),
                        key: const ValueKey<String>(
                          'realtime-local-image-preview',
                        ),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Color(0x55FFFFFF),
                            size: 44,
                          ),
                        ),
                      ),
                    RealtimeCameraSwitchTransition(
                      active: _isSwitchingCamera,
                      child: XmaxRealtimeVideoView(
                        localTrack: _localStream?.videoTrack,
                        remoteTrack: _remoteStream?.videoTrack,
                        onRemoteVideoReady: _remoteVideoDidBecomeReady,
                        videoContentMode: VideoContentMode.fill,
                        trajectoryRenderer: _customRenderer,
                      ),
                    ),
                    if (_localStream?.videoTrack == null && localImage == null)
                      const Center(
                        child: Icon(
                          Icons.videocam_off_outlined,
                          color: Color(0x55FFFFFF),
                          size: 44,
                        ),
                      ),
                    RealtimeLoadingOverlay(isLoading: _isLoading),
                    if (_isStatisticsVisible)
                      SafeArea(
                        bottom: false,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 64, 12, 8),
                            child: RealtimeStatisticsPanel(
                              uplink: _uplinkStatistics,
                              downlink: _downlinkStatistics,
                              networkQuality: _networkQuality,
                              uplinkLevel: _uplinkLevel,
                              downlinkLevel: _downlinkLevel,
                              canAdjustQuality:
                                  _state.connectionState ==
                                  RealtimeConnectionState.generating,
                              isAdjustingQuality: _isAdjustingQuality,
                              qualityError: _qualityError,
                              onUplinkLevelChanged: (level) =>
                                  _setQualityLevel(level, downlink: false),
                              onDownlinkLevelChanged: (level) =>
                                  _setQualityLevel(level, downlink: true),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              XLabRealtimeControlPanel(
                mode: _panelMode,
                generating: generating,
                busy: _busy,
                enabled: _cameraReady,
                promptController: _promptController,
                referencesByCategory: _referencesByCategory,
                selectedReference: _selectedReference,
                promptReference: _promptReference,
                onModeChanged: _selectMode,
                onStop: () => unawaited(_stopGeneration()),
                onReferenceChanged: (reference) =>
                    unawaited(_selectReference(reference)),
                onAddReference: () =>
                    unawaited(_pickReference(forPrompt: false)),
                onTouchStart: () => unawaited(_startTouchGeneration()),
                onPromptSubmit: () => unawaited(_submitPrompt()),
                onPromptReference: () =>
                    unawaited(_pickReference(forPrompt: true)),
              ),
            ],
          ),
          SafeArea(
            bottom: false,
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 12,
                  top: 8,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      tooltip: XLabLocalization.shared.text('common.home'),
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 22,
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.localInput == null)
                  Positioned(
                    right: 8,
                    top: 6,
                    child: RealtimeCameraActionBar(
                      cameraEnabled: !_busy && _localStream != null,
                      statisticsVisible: _isStatisticsVisible,
                      onSwitchCamera: _switchCamera,
                      onToggleStatistics: () => setState(
                        () => _isStatisticsVisible = !_isStatisticsVisible,
                      ),
                    ),
                  ),
                if (_externalVideoPath != null)
                  Positioned(
                    right: 12,
                    top: 5,
                    child: RealtimeMediaTopBar(
                      enabled: !_busy,
                      isMuted: _isAudioMuted,
                      statisticsVisible: _isStatisticsVisible,
                      onGallery: () => unawaited(_replaceExternalVideo()),
                      onMute: () => unawaited(_toggleExternalAudio()),
                      onVolume: () => unawaited(_showExternalVolume()),
                      onStatistics: () => setState(
                        () => _isStatisticsVisible = !_isStatisticsVisible,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_lastError != null)
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(64, 64, 64, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xD9251719),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x55FF6B72)),
                  ),
                  child: Text(
                    _lastError!.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFB5B5),
                      fontSize: 11,
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
