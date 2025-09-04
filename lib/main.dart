import 'package:flutter/material.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'thinkShape.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
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

  // Recorder and Player from the same package to avoid conflicts.
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  // Kept for the debug function `_playLastRecording`
  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();

  ShapeType _currentShape = ShapeType.flower;
  AnimationState _currentAnimationState = AnimationState.continuousRotation;
  double scale = 1.5;

  @override
  void initState() {
    super.initState();
    _initPorcupineManager();
    _initializeRecorder();
    _player.openPlayer(); // Initialize the player
  }

  @override
  void dispose() {
    _porcupineManager?.stop();
    _porcupineManager?.delete();
    _recorder.closeRecorder();
    _player.closePlayer(); // Dispose the player
    _audioPlayer.dispose();
    super.dispose();
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

      await _porcupineManager!.start();
      setState(() {
        _statusText = 'Porcupine 已就緒，等待喚醒詞...';
      });
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

  // In _RecordingScreenState class

  void _toggleRecording() async {
    if (!_isRecording) {
      // ... (this part remains the same)
      final tempDir = Directory.systemTemp;
      _lastAudioPath = '${tempDir.path}/last_record.aac';

      // Make sure recorder is open before starting
      await _recorder.openRecorder();
      await _porcupineManager?.start();

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

      // --- Start of the Change ---
      // Immediately stop Porcupine and close the recorder after recording is finished.
      print("Recording stopped. Releasing audio resources...");
      await _porcupineManager?.stop();
      await _recorder.closeRecorder();
      // --- End of the Change ---

      setState(() {
        _isRecording = false;
        _statusText = '錄音已儲存，正在處理...';
        _currentShape = ShapeType.circleGrid;
        scale = 1.5;
        _currentAnimationState = AnimationState.rotate45andPause;
      });
      // Now, call the API function.
      _sendToApi();
    }
  }

  // This is a debug function, you can keep it or remove it.
  void _playLastRecording() async {
    if (_lastAudioPath.isNotEmpty && await File(_lastAudioPath).exists()) {
      await _player.startPlayer(fromURI: _lastAudioPath);
    }
  }

  // ==== Fully revised function using only flutter_sound ====
  // In _RecordingScreenState class

  void _sendToApi() async {
    if (_lastAudioPath.isEmpty || !await File(_lastAudioPath).exists()) {
      setState(() => _statusText = '找不到錄音檔');
      return;
    }

    setState(() => _statusText = '正在傳送錄音至伺服器...');

    try {
      final uri = Uri.parse('https://hakka.chilljudge.com/hakka-assistant/');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('audio_file', _lastAudioPath));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print("Response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        _responseAudioPath = '${Directory.systemTemp.path}/response.wav';
        await File(_responseAudioPath).writeAsBytes(response.bodyBytes);

        // --- Start of the Change ---
        // The following two lines are now REMOVED from here.
        // await _porcupineManager?.stop();
        // await _recorder.closeRecorder();
        // --- End of the Change ---

        await _player.startPlayer(
          fromURI: _responseAudioPath,
          whenFinished: () {
            print("Playback complete. Re-initializing...");
            // Open recorder and start porcupine for the next turn.
            _recorder.openRecorder();
            _porcupineManager?.start();
            if (mounted) {
              setState(() => _statusText = '播放完畢，等待喚醒詞...');
            }
          },
        );

        if (mounted) {
          setState(() {
            _statusText = '正在播放回應...';
            _currentShape = ShapeType.flower;
            scale = 1.5;
            _currentAnimationState = AnimationState.continuousRotation;
          });
        }
      } else {
        throw Exception('上傳失敗：HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('An error occurred: $e');
      setState(() => _statusText = '處理錯誤，請重試');
      // On error, we still need to re-open resources for the next try.
      _recorder.openRecorder();
      _porcupineManager?.start();
    }
  }

  void _errorCallback(PorcupineException error) {
    setState(() {
      _statusText = 'Porcupine 發生錯誤: ${error.message}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 15, 35, 59),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _statusText,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 50),
              GestureDetector(
                onTap: _toggleRecording,
                child: AnimatedShapeWidget(
                  shapeType: _currentShape,
                  animationState: _currentAnimationState,
                  scale: scale,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}