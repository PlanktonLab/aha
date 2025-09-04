import 'package:flutter/material.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'thinkShape.dart';

// 相機
import 'package:camera/camera.dart';
// 圖片壓縮
import 'package:flutter_image_compress/flutter_image_compress.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RecordingScreen(),
    );
  }
}

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});
  @override
  _RecordingScreenState createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  PorcupineManager? _porcupineManager;
  final String _accessKey = "MBSJcPFRjHf6XxNKAtt2bGxESf6x/xKJYjphhys6elq86hMEs0dwGg==";
  String _statusText = 'Porcupine 正在初始化中...';

  bool _isRecording = false;
  String _lastAudioPath = '';
  String _responseAudioPath = '';
  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _responsePlayer = FlutterSoundPlayer();

  ShapeType _currentShape = ShapeType.flower;
  AnimationState _currentAnimationState = AnimationState.continuousRotation;
  double scale = 1.5;

  // 相機展開狀態（用於縮小「花」與調整間距）
  bool _camExpanded = false;

  // 取得相機面板的 state，供擷取靜態圖
  final GlobalKey<_ExpandableCameraPanelState> _camKey = GlobalKey<_ExpandableCameraPanelState>();

  @override
  void initState() {
    super.initState();
    _initPorcupineManager();
    _initializeRecorder();
    _responsePlayer.openPlayer();
  }

  void _initializeRecorder() async {
    await Permission.microphone.request();
    await _recorder.openRecorder();
  }

  void _initPorcupineManager() async {
    try {
      String modelAssetPath = 'assets/porcupine_params_zh.pv';

      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        _accessKey,
        ["assets/aha_android.ppn"],
        _wakeWordCallback,
        modelPath: modelAssetPath,
        errorCallback: _errorCallback,
        sensitivities: [0.7],
      );

      setState(() {
        _statusText = 'Porcupine 已就緒，等待喚醒詞...';
      });

      await _porcupineManager!.start();
    } on PorcupineException catch (err) {
      setState(() {
        _statusText = '初始化錯誤: ${err.message}';
      });
      // ignore: avoid_print
      print("Porcupine 初始化錯誤: ${err.message}");
    }
  }

  void _wakeWordCallback(int keywordIndex) async {
    _toggleRecording();
  }

  void _toggleRecording() async {
    if (!_isRecording) {
      final tempDir = Directory.systemTemp;
      _lastAudioPath = '${tempDir.path}/last_record.aac';

      await _recorder.startRecorder(
        toFile: _lastAudioPath,
        codec: Codec.aacADTS,
        // （可選）若要降低上傳大小，也可打開這些參數：
        // bitRate: 64000,
        // sampleRate: 16000,
        // numChannels: 1,
      );

      setState(() {
        _isRecording = true;
        _statusText = '正在錄音中...';
        _currentShape = ShapeType.star;
        scale = 2.0;
      });
    } else {
      await _recorder.stopRecorder();

      setState(() {
        _isRecording = false;
        _statusText = '錄音已儲存，準備送出...';
        _currentShape = ShapeType.circleGrid;
        scale = 1.5;
        _currentAnimationState = AnimationState.rotate45andPause;
      });

      // 錄音結束後送出
      _sendToApi();
    }
  }

  void _playLastRecording() async {
    if (_lastAudioPath.isNotEmpty && File(_lastAudioPath).existsSync()) {
      try {
        await _audioPlayer.play(ap.DeviceFileSource(_lastAudioPath));
        setState(() {
          _statusText = '正在播放最後一次錄音...';
        });
      } catch (e) {
        setState(() {
          _statusText = '播放失敗：${e.toString()}';
        });
      }
    } else {
      setState(() {
        _statusText = '沒有可播放的錄音。';
      });
    }
  }

  /// 將擷取到的照片壓縮：長邊 ~1280px、品質 70，輸出 JPEG。
  Future<String?> _compressImageIfAny(String? imagePath) async {
    if (imagePath == null) return null;
    try {
      // 先估算原始大小
      final orig = await File(imagePath).length();
      // 暫存輸出路徑
      final out = '${Directory.systemTemp.path}/shot_compressed_q70.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        imagePath, out,
        // 使用 minWidth/minHeight 讓最短邊至少到這個值，通常能把長邊控制在 ~1280 左右
        // 若你想更嚴格控制長邊，可自行計算等比縮放後傳給 compressWithList。
        minWidth: 1280,
        minHeight: 720,
        quality: 70,
        format: CompressFormat.jpeg,
        keepExif: true, // 保留 EXIF（若不需要可設 false）
      );

      if (result != null && File(result.path).existsSync()) {
        final after = await File(result.path).length();
        debugPrint('Image compressed: ${(orig/1024).toStringAsFixed(1)}KB -> ${(after/1024).toStringAsFixed(1)}KB');
        return result.path;
      }
    } catch (e) {
      debugPrint('圖片壓縮失敗：$e');
    }
    // 壓縮失敗就回傳原圖路徑
    return imagePath;
  }

  /// ★ 上傳：若相機開著就拍照，拍到後先壓縮再與音檔一起上傳
  Future<void> _sendToApi() async {
    if (_lastAudioPath.isEmpty || !File(_lastAudioPath).existsSync()) {
      setState(() => _statusText = '找不到錄音檔');
      return;
    }

    setState(() => _statusText = '正在準備上傳...');

    // 1) 嘗試擷取照片
    String? imagePath;
    try {
      final panelState = _camKey.currentState;
      if (panelState != null && panelState.isReady) {
        final shot = await panelState.captureStill();
        if (shot != null && File(shot.path).existsSync()) {
          imagePath = shot.path;
        }
      }
    } catch (e) {
      debugPrint('擷取相片失敗：$e');
    }

    // 2) 壓縮照片（若有拍到）
    if (imagePath != null) {
      imagePath = await _compressImageIfAny(imagePath);
    }

    // 除錯資訊
    final audioBytes = await File(_lastAudioPath).length();
    final imageBytes = imagePath != null ? await File(imagePath).length() : 0;
    debugPrint('即將上傳 -> audio: ${(audioBytes/1024).toStringAsFixed(1)}KB, '
        'image: ${(imageBytes/1024).toStringAsFixed(1)}KB');

    // 內部共用的上傳函式（可重試）
    Future<http.Response> uploadOnce({required String audioPath, String? imgPath}) async {
      final uri = Uri.parse('https://hakka.chilljudge.com/hakka-assistant/');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('audio_file', audioPath))
        ..fields['dummy'] = 'value';
      if (imgPath != null) {
        request.files.add(await http.MultipartFile.fromPath('image_file', imgPath));
      }
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    }

    setState(() => _statusText = '正在上傳（含壓縮圖片）...');

    http.Response response;
    try {
      response = await uploadOnce(audioPath: _lastAudioPath, imgPath: imagePath);
    } catch (e) {
      setState(() => _statusText = '上傳錯誤：$e');
      return;
    }

    // 若伺服器依然回 413，再做更激進一次壓縮重試（或改為只上傳音檔）
    if (response.statusCode == 413 && imagePath != null) {
      debugPrint('回 413 → 再壓縮一次並重傳');
      setState(() => _statusText = '伺服器回 413，嘗試更高壓縮後重傳...');

      try {
        final out2 = '${Directory.systemTemp.path}/shot_compressed_q50.jpg';
        final compressed2 = await FlutterImageCompress.compressAndGetFile(
          imagePath, out2,
          minWidth: 1024,
          minHeight: 576,
          quality: 50,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
        final smallerPath = (compressed2 != null && File(compressed2.path).existsSync())
            ? compressed2.path
            : imagePath;

        response = await uploadOnce(audioPath: _lastAudioPath, imgPath: smallerPath);
      } catch (e) {
        debugPrint('二次壓縮或重傳失敗：$e，改為只上傳音檔。');
        response = await uploadOnce(audioPath: _lastAudioPath, imgPath: null);
      }
    }

    if (response.statusCode == 413) {
      setState(() => _statusText = '仍為 413，改為只上傳音檔...');
      response = await uploadOnce(audioPath: _lastAudioPath, imgPath: null);
    }

    if (response.statusCode == 200) {
      _responseAudioPath = '${Directory.systemTemp.path}/response.wav';
      File(_responseAudioPath).writeAsBytesSync(response.bodyBytes);

      setState(() => _statusText = '伺服器回應已儲存並播放 response.wav');
      _currentShape = ShapeType.flower;
      scale = 1.5;
      _currentAnimationState = AnimationState.continuousRotation;

      await _responsePlayer.startPlayer(
        fromURI: _responseAudioPath,
        codec: Codec.pcm16WAV,
      );
    } else {
      setState(() => _statusText = '上傳失敗：HTTP ${response.statusCode}');
    }
  }

  void _errorCallback(PorcupineException error) {
    setState(() {
      _statusText = 'Porcupine 發生錯誤: ${error.message}';
    });
  }

  @override
  void dispose() {
    _porcupineManager?.stop();
    _porcupineManager?.delete();
    _audioPlayer.dispose();
    _recorder.closeRecorder();
    _responsePlayer.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 展開時「花變小」與「間距變小」
    final double effectiveScale = _camExpanded ? (scale * 0.5) : scale;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 15, 35, 59),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  _statusText,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),

                // 花 & 間距動畫
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  child: Column(
                    children: [
                      const SizedBox(height: 0),
                      AnimatedScale(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOutCubic,
                        scale: effectiveScale / scale,
                        child: GestureDetector(
                          onTap: _toggleRecording,
                          child: AnimatedShapeWidget(
                            shapeType: _currentShape,
                            animationState: _currentAnimationState,
                            scale: scale,
                          ),
                        ),
                      ),
                      const SizedBox(height: 0),
                    ],
                  ),
                ),

                // 相機面板（用 key 讓父層可拍照）
                ExpandableCameraPanel(
                  key: _camKey,
                  onExpandedChanged: (v) => setState(() => _camExpanded = v),
                ),
                const SizedBox(height: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// 可展開的相機面板
/// - 按鈕置中
/// - 點擊展開：螢幕寬＆高的 3/4
/// - 顯示相機畫面；再點畫面關閉
/// - 切換縮放＋淡入、預覽完成淡入
/// - 提供 captureStill() 與 isReady
/// ===============================
class ExpandableCameraPanel extends StatefulWidget {
  final ValueChanged<bool>? onExpandedChanged;
  const ExpandableCameraPanel({super.key, this.onExpandedChanged});

  @override
  State<ExpandableCameraPanel> createState() => _ExpandableCameraPanelState();
}

class _ExpandableCameraPanelState extends State<ExpandableCameraPanel> {
  bool _expanded = false;

  CameraController? _controller;
  Future<void>? _initFuture;
  bool _ready = false;

  bool get isReady => _ready;

  /// 由父層呼叫：擷取一張照片（相機要 ready）
  Future<XFile?> captureStill() async {
    if (!_ready || _controller == null) return null;
    try {
      return await _controller!.takePicture();
    } catch (e) {
      debugPrint('takePicture 失敗：$e');
      return null;
    }
  }

  Future<void> _ensureCamera() async {
    if (_controller != null && _ready) return;

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未取得相機權限')),
        );
      }
      return;
    }

    final cams = await availableCameras();
    if (cams.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到可用的相機')),
        );
      }
      return;
    }

    final backCam = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    _controller = CameraController(
      backCam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _initFuture = _controller!.initialize();
    await _initFuture;
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _open() async {
    await _ensureCamera();
    if (!_ready) return;
    setState(() => _expanded = true);
    widget.onExpandedChanged?.call(true);
  }

  void _close() {
    // 關閉釋放相機；若想保留相機加速下次展開，可註解掉以下三行
    _controller?.dispose();
    _controller = null;
    _initFuture = null;
    _ready = false;

    setState(() => _expanded = false);
    widget.onExpandedChanged?.call(false);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final double targetW = _expanded ? (size.width * 0.75) : 100;
    final double targetH = _expanded ? (size.height * 0.48) : 50;
    final double radius  = _expanded ? 24 : 20;

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        width: targetW,
        height: targetH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: const Color.fromARGB(100, 45, 75, 99),
        ),
        padding: const EdgeInsets.all(10),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) {
            final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
            return FadeTransition(
              opacity: anim,
              child: ScaleTransition(scale: curved, child: child),
            );
          },
          child: _expanded
              ? _CameraSurface(
            key: const ValueKey('expanded'),
            initFuture: _initFuture,
            controller: _controller,
            onTapToClose: _close,
          )
              : _CollapsedCameraButton(
            key: const ValueKey('collapsed'),
            onTap: _open,
          ),
        ),
      ),
    );
  }
}

class _CollapsedCameraButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CollapsedCameraButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color.fromARGB(50, 215, 215, 219),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.local_see,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

class _CameraSurface extends StatelessWidget {
  final Future<void>? initFuture;
  final CameraController? controller;
  final VoidCallback onTapToClose;
  const _CameraSurface({
    super.key,
    required this.initFuture,
    required this.controller,
    required this.onTapToClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapToClose, // 再點一下相機畫面關閉
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: const Color.fromARGB(50, 215, 215, 219),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: FutureBuilder<void>(
              future: initFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && controller != null) {
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeIn,
                    opacity: 1.0,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller!.value.previewSize?.height ?? 1280,
                        height: controller!.value.previewSize?.width ?? 720,
                        child: CameraPreview(controller!),
                      ),
                    ),
                  );
                } else if (snapshot.hasError) {
                  return const Center(
                    child: Text('相機初始化錯誤', style: TextStyle(color: Colors.white)),
                  );
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
