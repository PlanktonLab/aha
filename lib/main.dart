import 'package:flutter/material.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
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
  final String _accessKey = "U9jgjZuhwycgzA0uAWMztf2/pjcPCd3jJOiRzgOh5dI67tjkTK6/Zw==";
  String _statusText = 'Porcupine 正在初始化中...';

  bool _isRecording = false;
  String _lastAudioPath = '';
  String _responseAudioPath = '';

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();

  ShapeType _currentShape = ShapeType.flower;
  AnimationState _currentAnimationState = AnimationState.continuousRotation;
  double scale = 1.5;

  bool _camExpanded = false;
  final GlobalKey<_ExpandableCameraPanelState> _camKey = GlobalKey<_ExpandableCameraPanelState>();

  @override
  void initState() {
    super.initState();
    _initPorcupineManager();
    _initializeRecorder();
    _player.openPlayer();
  }

  void _initializeRecorder() async {
    await Permission.microphone.request();
    await _recorder.openRecorder();
  }

  void _initPorcupineManager() async {
    try {
      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        _accessKey,
        ["assets/啊哈擰後_zh_ios_v3_0_0.ppn"],
        _wakeWordCallback,
        modelPath: 'assets/porcupine_params_zh.pv',
        errorCallback: _errorCallback,
        sensitivities: [0.7],
      );
      // [FIX 1]: Start listening right after initialization.
      _resetToListeningState();
    } on PorcupineException catch (err) {
      setState(() {
        _statusText = '初始化錯誤: ${err.message}';
      });
    }
  }

  void _wakeWordCallback(int keywordIndex) {
    print("偵測到喚醒詞！關鍵字索引: $keywordIndex");
    if (mounted) {
      _toggleRecording();
    }
  }

  // [FIX 1 START]: Logic for restarting the wake word listener.
  Future<void> _resetToListeningState() async {
    try {
      // Ensure recorder is not active
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
      }
      await _recorder.closeRecorder();

      // Start Porcupine to listen for the wake word
      await _porcupineManager?.start();

      if (mounted) {
        setState(() {
          _statusText = 'Porcupine 已就緒，等待喚醒詞...';
          _currentShape = ShapeType.flower;
          scale = 1.5;
          _currentAnimationState = AnimationState.continuousRotation;
          _isRecording = false;
        });
      }
    } on PorcupineException catch (e) {
      if (mounted) {
        setState(() {
          _statusText = '重新啟動監聽失敗: ${e.message}';
        });
      }
    }
  }
  // [FIX 1 END]

  void _toggleRecording() async {
    if (!_isRecording) {
      // [FIX 1]: Stop Porcupine before starting to record to release the mic.
      await _porcupineManager?.stop();

      final tempDir = Directory.systemTemp;
      _lastAudioPath = '${tempDir.path}/last_record.aac';

      await _recorder.openRecorder();
      await _recorder.startRecorder(
        toFile: _lastAudioPath,
        codec: Codec.aacADTS,
      );

      setState(() {
        _isRecording = true;
        _statusText = '正在錄音中...';
        _currentShape = ShapeType.star;
        scale = 2.0;
      });
    } else {
      await _recorder.stopRecorder();
      await _recorder.closeRecorder();

      setState(() {
        _isRecording = false;
        _statusText = '錄音已儲存，準備送出...';
        _currentShape = ShapeType.circleGrid;
        scale = 1.5;
        _currentAnimationState = AnimationState.rotate45andPause;
      });

      _sendToApi();
    }
  }

  Future<String?> _compressImageIfAny(String? imagePath) async {
    if (imagePath == null) return null;
    try {
      final orig = await File(imagePath).length();
      final out = '${Directory.systemTemp.path}/shot_compressed_q70.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        imagePath, out,
        minWidth: 1280,
        minHeight: 720,
        quality: 70,
        format: CompressFormat.jpeg,
        keepExif: true,
      );

      if (result != null && File(result.path).existsSync()) {
        final after = await File(result.path).length();
        debugPrint('Image compressed: ${(orig/1024).toStringAsFixed(1)}KB -> ${(after/1024).toStringAsFixed(1)}KB');
        return result.path;
      }
    } catch (e) {
      debugPrint('圖片壓縮失敗：$e');
    }
    return imagePath;
  }

  Future<http.Response> uploadOnce({required String audioPath, String? imgPath, String? prompt}) async {
    final uri = Uri.parse('https://hakka.chilljudge.com/hakka-assistant/');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('audio_file', audioPath))
      ..fields['prompt'] = prompt ?? '';
    if (imgPath != null) {
      request.files.add(await http.MultipartFile.fromPath('image_file', imgPath));
    }
    final streamed = await request.send();
    return http.Response.fromStream(streamed);
  }

  void _sendToApi() async {
    if (_lastAudioPath.isEmpty || !await File(_lastAudioPath).exists()) {
      setState(() => _statusText = '找不到錄音檔');
      // [FIX 1]: Reset to listening state even if there's an error.
      _resetToListeningState();
      return;
    }

    // [FIX 1]: Use try...finally to ensure we always reset to listening state.
    try {
      setState(() => _statusText = '阿客思考中 ...');

      String? imagePath;
      if (_camExpanded) {
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
      }
      if (imagePath != null) {
        imagePath = await _compressImageIfAny(imagePath);
      }

      final audioBytes = await File(_lastAudioPath).length();
      final imageBytes = imagePath != null ? await File(imagePath).length() : 0;
      debugPrint('即將上傳 -> audio: ${(audioBytes/1024).toStringAsFixed(1)}KB, image: ${(imageBytes/1024).toStringAsFixed(1)}KB');

      setState(() => _statusText = '阿客正在思考中 ...');

      String userPrompt = '';
      try {
        userPrompt = await rootBundle.loadString('lib/prompt.txt');
      } catch (e) {
        debugPrint('讀取 prompt.txt 失敗：$e');
        userPrompt = '請將我的華語音訊內容翻譯成客語。';
      }

      http.Response response;
      try {
        response = await uploadOnce(audioPath: _lastAudioPath, imgPath: imagePath, prompt: userPrompt);
      } catch (e) {
        setState(() => _statusText = '上傳錯誤：$e');
        return; // The 'finally' block will still execute
      }

      if (response.statusCode == 413 && imagePath != null) {
        debugPrint('回 413 → 再壓縮一次並重傳');
        setState(() => _statusText = '伺服器回 413，嘗試更高壓縮後重傳...');
        try {
          final out2 = '${Directory.systemTemp.path}/shot_compressed_q50.jpg';
          final compressed2 = await FlutterImageCompress.compressAndGetFile(
            imagePath, out2,
            minWidth: 1024, minHeight: 576, quality: 50,
            format: CompressFormat.jpeg, keepExif: false,
          );
          final smallerPath = (compressed2 != null && File(compressed2.path).existsSync())
              ? compressed2.path
              : imagePath;
          response = await uploadOnce(audioPath: _lastAudioPath, imgPath: smallerPath, prompt: userPrompt);
        } catch (e) {
          debugPrint('二次壓縮或重傳失敗：$e，改為只上傳音檔。');
          response = await uploadOnce(audioPath: _lastAudioPath, imgPath: null, prompt: userPrompt);
        }
      }

      if (response.statusCode == 413) {
        setState(() => _statusText = '仍為 413，改為只上傳音檔...');
        response = await uploadOnce(audioPath: _lastAudioPath, imgPath: null, prompt: userPrompt);
      }

      if (response.statusCode == 200) {
        print("----------------------------------");
        print(response.body);
        if (response.body.contains('error')) {
          setState(() => _statusText = '阿客現在不在');
        } else {
          await Future.wait([
            _playResponseAudio(response.bodyBytes),
            _getGeminiText(),
          ]).catchError((e) {
            debugPrint('處理回應時發生錯誤：$e');
            setState(() => _statusText = '處理回應時發生錯誤。');
          });
        }
      } else {
        setState(() => _statusText = '上傳失敗：HTTP ${response.statusCode}');
      }
    } finally {
      // [FIX 1]: This will run regardless of success or failure, ensuring the app is ready for the next command.
      _resetToListeningState();
    }
  }

  Future<void> _playResponseAudio(List<int> audioBytes) async {
    try {
      _responseAudioPath = '${Directory.systemTemp.path}/response.wav';
      File(_responseAudioPath).writeAsBytesSync(audioBytes);
      await _player.startPlayer(fromURI: _responseAudioPath, codec: Codec.pcm16WAV);
    } catch (e) {
      debugPrint('播放語音發生錯誤：$e');
    }
  }

  Future<void> _getGeminiText() async {
    try {
      final resultResponse = await http.get(Uri.parse('https://hakka.chilljudge.com/hakka-assistant/result/'));
      if (resultResponse.statusCode != 200) return;

      final jsonBody = json.decode(resultResponse.body) as Map<String, dynamic>;
      String geminiResponse = jsonBody['gemini_response'] as String? ?? '';

      geminiResponse = geminiResponse.replaceAll("json", '');
      if (geminiResponse.startsWith('```')) geminiResponse = geminiResponse.substring(3);
      if (geminiResponse.endsWith('```')) geminiResponse = geminiResponse.substring(0, geminiResponse.length - 3);

      Map<String, dynamic> parsedResponse;
      try {
        parsedResponse = json.decode(geminiResponse) as Map<String, dynamic>;
      } catch (_) {
        if (jsonBody['answer'] is Map<String, dynamic>) {
          parsedResponse = {
            'answer': jsonBody['answer'],
            if (jsonBody['step'] != null) 'step': jsonBody['step'],
          };
        } else {
          return;
        }
      }

      final answerMap = parsedResponse['answer'] as Map<String, dynamic>?;
      final answerContent = (answerMap?['content'] as String?)?.trim() ?? '';
      if (answerContent.isNotEmpty && mounted) {
        setState(() => _statusText = answerContent);
      }

      final step = parsedResponse['step'];
      if (step is Map<String, dynamic>) {
        final modules = step['modules'];
        if (modules is List && modules.isNotEmpty && mounted) {
          final steps = <StepModule>[];
          for (final m in modules) {
            if (m is Map<String, dynamic>) {
              final title = (m['title'] as String?)?.trim() ?? '';
              final content = (m['content'] as String?)?.trim() ?? '';
              if (title.isNotEmpty) {
                steps.add(StepModule(title: title, content: content));
              }
            }
          }
          if (steps.isNotEmpty) {
            final recognizedText = jsonBody['recognized_text'] as String? ?? '';
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StepsPage(
                  title: '教學步驟', introText: answerContent,
                  recognizedText: recognizedText, steps: steps,
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('取得回應文字發生錯誤：$e');
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
    _player.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                SizedBox(height: _camExpanded ? 0 : 50),
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
                SizedBox(height: _camExpanded ? 0 : 50),
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

class StepModule {
  final String title;
  final String content;
  StepModule({required this.title, required this.content});
}

class StepsPage extends StatelessWidget {
  final String title;
  final String introText;
  final String recognizedText;
  final List<StepModule> steps;

  const StepsPage({
    super.key,
    required this.title,
    required this.introText,
    required this.recognizedText,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    const darkBg = Color.fromARGB(255, 15, 35, 59);
    const cardBg = Color.fromARGB(255, 45, 75, 99);
    const innerBg = Color.fromARGB(255, 79, 107, 127);
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg, elevation: 0, foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (introText.isNotEmpty) _IntroBubble(text: introText),
            const SizedBox(height: 16),
            if (recognizedText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('你的需求：$recognizedText', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            for (int i = 0; i < steps.length; i++) ...[
              _StepCard(index: i + 1, title: steps[i].title, content: steps[i].content, cardBg: cardBg, innerBg: innerBg),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _IntroBubble extends StatelessWidget {
  final String text;
  const _IntroBubble({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: const Color.fromARGB(255, 26, 49, 74), borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2, right: 10), child: Icon(Icons.local_florist, color: Colors.white, size: 20)),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4))),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int index;
  final String title;
  final String content;
  final Color cardBg;
  final Color innerBg;

  const _StepCard({required this.index, required this.title, required this.content, required this.cardBg, required this.innerBg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16, backgroundColor: Colors.white24,
                child: Text('$index', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(color: innerBg, borderRadius: BorderRadius.circular(18)),
            child: Text(
              content.isNotEmpty ? content : '（這步驟沒有詳細說明）',
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

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

  Future<XFile?> captureStill() async {
    if (!_ready || _controller == null) return null;
    try {
      return await _controller!.takePicture();
    } catch (e) {
      debugPrint('takePicture 失敗：$e');
      return null;
    }
  }

  // [FIX 2 START]: Enhanced permission handling for camera.
  Future<void> _ensureCamera() async {
    if (_controller != null && _ready) return;

    var status = await Permission.camera.request();

    if (status.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('相機權限已被永久拒絕'),
            content: const Text('我們需要相機權限才能為您拍照。請前往應用程式設定頁面手動開啟權限。'),
            actions: <Widget>[
              TextButton(child: const Text('取消'), onPressed: () => Navigator.of(context).pop()),
              TextButton(
                child: const Text('前往設定'),
                onPressed: () {
                  openAppSettings();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      }
      return;
    }

    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未取得相機權限')));
      }
      return;
    }

    final cams = await availableCameras();
    if (cams.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('找不到可用的相機')));
      }
      return;
    }

    final backCam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);

    _controller = CameraController(
      backCam, ResolutionPreset.medium,
      enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      _initFuture = _controller!.initialize();
      await _initFuture;
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      debugPrint("Camera initialization error: $e");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('相機初始化失敗: $e')));
      }
      _controller?.dispose();
      _controller = null;
      _ready = false;
    }
  }
  // [FIX 2 END]

  Future<void> _open() async {
    await _ensureCamera();
    if (!_ready) return;
    setState(() => _expanded = true);
    widget.onExpandedChanged?.call(true);
  }

  void _close() {
    setState(() => _expanded = false);
    widget.onExpandedChanged?.call(false);
    // [FIX 2]: Dispose controller on close to free up resources. It will be re-initialized on next open.
    _controller?.dispose();
    _controller = null;
    _initFuture = null;
    _ready = false;
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
    final double radius = _expanded ? 24 : 20;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        width: targetW, height: targetH,
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
            return FadeTransition(opacity: anim, child: ScaleTransition(scale: curved, child: child));
          },
          child: _expanded
              ? _CameraSurface(key: const ValueKey('expanded'), initFuture: _initFuture, controller: _controller, onTapToClose: _close)
              : _CollapsedCameraButton(key: const ValueKey('collapsed'), onTap: _open),
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
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color.fromARGB(50, 215, 215, 219)),
        alignment: Alignment.center,
        child: const Icon(Icons.local_see, color: Colors.white, size: 20),
      ),
    );
  }
}

class _CameraSurface extends StatelessWidget {
  final Future<void>? initFuture;
  final CameraController? controller;
  final VoidCallback onTapToClose;
  const _CameraSurface({super.key, required this.initFuture, required this.controller, required this.onTapToClose});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapToClose,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: const Color.fromARGB(50, 215, 215, 219),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: FutureBuilder<void>(
              future: initFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && controller != null && controller!.value.isInitialized) {
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
                  return const Center(child: Text('相機初始化錯誤', style: TextStyle(color: Colors.white)));
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