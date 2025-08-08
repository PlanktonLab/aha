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
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: RecordingScreen(),
    );
  }
}

class RecordingScreen extends StatefulWidget {
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
        ["assets/啊哈擰後_android.ppn"],
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
      print("Porcupine 初始化錯誤: ${err.message}");
    }
  }

  void _wakeWordCallback(int keywordIndex) async {
    print("偵測到喚醒詞！關鍵字索引: $keywordIndex");
    _toggleRecording();
  }

  void _toggleRecording() async {
    if (!_isRecording) {
      final tempDir = Directory.systemTemp;
      _lastAudioPath = '${tempDir.path}/last_record.aac';

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

      setState(() {
        _isRecording = false;
        _statusText = '錄音已儲存，等待喚醒詞...';
        _currentShape = ShapeType.flower;
        scale = 1.5;
      });
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

  // ==== 這裡開始是修改過的函式 ====
  void _sendToApi() async {
    if (_lastAudioPath.isEmpty || !File(_lastAudioPath).existsSync()) {
      setState(() => _statusText = '找不到錄音檔');
      return;
    }

    final uri = Uri.parse('https://hakka.chilljudge.com/hakka-assistant/');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('audio_file', _lastAudioPath))
      ..fields['dummy'] = 'value';

    setState(() => _statusText = '正在傳送錄音至伺服器...');

    try {
      // 發送請求，得到一個 StreamedResponse
      final streamedResponse = await request.send();

      // 從 StreamedResponse 讀取一次完整的回應，並儲存到 response 變數
      final response = await http.Response.fromStream(streamedResponse);

      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");

      if (response.statusCode == 200) {
        _responseAudioPath = '${Directory.systemTemp.path}/response.wav';
        // 使用已儲存的 response 變數，寫入檔案
        File(_responseAudioPath).writeAsBytesSync(response.bodyBytes);

        setState(() => _statusText = '伺服器回應已儲存並播放 response.wav');
        await _responsePlayer.startPlayer(fromURI: _responseAudioPath, codec: Codec.pcm16WAV);
      } else {
        setState(() => _statusText = '上傳失敗：HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _statusText = '上傳錯誤：$e');
    }
  }
  // ==== 這裡結束是修改過的函式 ====

  void _errorCallback(PorcupineException error) {
    setState(() {
      _statusText = 'Porcupine 發生錯誤: ${error.message}';
    });
    print("Porcupine 回呼錯誤: ${error.message}");
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
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _playLastRecording,
                child: Text('播放最後一次錄音'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _sendToApi,
                child: Text('送出到 API 並播放結果'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}