import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/stove_detection_service.dart';
import '../services/llm_service.dart';
import '../services/voice_assistant_service.dart';

class StoveDetectorScreen extends StatefulWidget {
  const StoveDetectorScreen({super.key});

  @override
  State<StoveDetectorScreen> createState() => _StoveDetectorScreenState();
}

class _StoveDetectorScreenState extends State<StoveDetectorScreen> {
  late StoveDetectionService _detectionService;
  VoiceAssistantService? _voiceAssistant;
  
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  
  DetectionResult? _result;
  bool _isDetecting = false;
  bool _isBackendHealthy = false;
  bool _isSessionActive = false;
  bool _stoveWasDetected = false; // Track first detection
  final bool _handsFreeMode = true; // NEW: Continuous listening mode
  String _backendUrl = 'http://172.20.10.7:8000';
  String _apiKey = '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'; // Groq API key
  
  Timer? _detectionTimer;
  int _frameCount = 0;
  DateTime? _lastDetectionTime;
  
  @override
  void initState() {
    super.initState();
    _detectionService = StoveDetectionService(baseUrl: _backendUrl);
    _checkBackendHealth();
    _initCamera();
    
    // Show API key dialog on first launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_apiKey.isEmpty) {
        _showApiKeyDialog();
      }
    });
  }
  
  void _showApiKeyDialog() {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('🆓 Groq API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Get your FREE API key at:\nconsole.groq.com\n\nNo credit card required!',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Groq API Key',
                hintText: 'gsk_...',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showErrorDialog(
                'API Key Required',
                'Voice assistant will not work without an API key. Add it later in settings.',
              );
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _apiKey = controller.text.trim();
                  _initializeVoiceService();
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _initializeVoiceService() async {
    if (_apiKey.isEmpty) return;
    
    final llmService = LLMService(apiKey: _apiKey);
    _voiceAssistant = VoiceAssistantService(llmService);
    
    final initialized = await _voiceAssistant!.initialize();
    if (!initialized) {
      if (mounted) {
        _showErrorDialog(
          'Voice Assistant Error',
          'Could not initialize voice services. Please check microphone permissions.',
        );
      }
    }
  }
  
  Future<void> _checkBackendHealth() async {
    final isHealthy = await _detectionService.checkHealth();
    setState(() {
      _isBackendHealthy = isHealthy;
    });
    
    if (!isHealthy && mounted) {
      _showErrorDialog(
        'Backend Not Running',
        'Please start the Python backend server:\n\npython backend/main.py\n\nAnd update the IP address in settings.',
      );
    }
  }
  
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        _showErrorDialog('No Camera', 'No camera found on this device');
        return;
      }
      
      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      _showErrorDialog('Camera Error', 'Failed to initialize camera: $e');
    }
  }
  
  void _toggleSession() {
    if (_isSessionActive) {
      _stopSession();
    } else {
      _startSession();
    }
  }
  
  void _startSession() {
    if (!_isBackendHealthy) {
      _showErrorDialog('Backend Error', 'Backend is not running. Please start the server first.');
      return;
    }
    
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _showErrorDialog('Camera Error', 'Camera is not ready');
      return;
    }
    
    setState(() {
      _isSessionActive = true;
      _stoveWasDetected = false;
      _frameCount = 0;
    });
    
    // Reset voice assistant for new session
    _voiceAssistant?.reset();
    
    // Start continuous detection
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isSessionActive && !_isDetecting) {
        _captureAndDetect();
      }
    });
  }
  
  void _stopSession() {
    _detectionTimer?.cancel();
    setState(() {
      _isSessionActive = false;
      _stoveWasDetected = false;
      _result = null;
    });
    
    // Stop voice assistant
    _voiceAssistant?.reset();
  }
  
  Future<void> _captureAndDetect() async {
    if (_isDetecting || _cameraController == null) return;
    
    setState(() {
      _isDetecting = true;
      _frameCount++;
    });
    
    try {
      final image = await _cameraController!.takePicture();
      final bytes = await File(image.path).readAsBytes();
      
      _lastDetectionTime = DateTime.now();
      final result = await _detectionService.detectFromBytes(bytes);
      
      await File(image.path).delete();
      
      if (result != null && mounted) {
        setState(() {
          _result = result;
        });
        
        // First time stove detected - trigger voice assistant!
        if (result.stoveDetected && !_stoveWasDetected && _isSessionActive) {
          _stoveWasDetected = true;
          _onFirstStoveDetection();
        }
      }
    } catch (e) {
      print('Detection error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
      }
    }
  }
  
  Future<void> _onFirstStoveDetection() async {
    // Show visual alert
    _showStoveAlert();
    
    // Start voice interaction if initialized
    if (_voiceAssistant != null && _voiceAssistant!.isInitialized) {
      await _voiceAssistant!.greetUser();
    } else if (_apiKey.isEmpty) {
      _showErrorDialog(
        'Voice Assistant Disabled',
        'Add your Groq API key in settings to enable voice interaction.',
      );
    }
  }
  
  void _showStoveAlert() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.warning, color: Colors.white),
            SizedBox(width: 12),
            Text('🔥 STOVE DETECTED!', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  void _showSettingsDialog() {
    final urlController = TextEditingController(text: _backendUrl);
    final keyController = TextEditingController(text: _apiKey);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'http://192.168.1.100:8000',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'Groq API Key',
                  hintText: 'gsk_...',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              const Text(
                'Get free key at console.groq.com',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _backendUrl = urlController.text;
                _apiKey = keyController.text;
                _detectionService = StoveDetectionService(baseUrl: _backendUrl);
                if (_apiKey.isNotEmpty) {
                  _initializeVoiceService();
                }
              });
              Navigator.pop(context);
              _checkBackendHealth();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _detectionTimer?.cancel();
    _cameraController?.dispose();
    _voiceAssistant?.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔥 Stove Monitor'),
        actions: [
          // Backend health indicator
          IconButton(
            icon: Icon(
              Icons.circle,
              color: _isBackendHealthy ? Colors.green : Colors.red,
              size: 12,
            ),
            onPressed: _checkBackendHealth,
            tooltip: _isBackendHealthy ? 'Backend Online' : 'Backend Offline',
          ),
          // Voice assistant indicator
          if (_voiceAssistant != null && _voiceAssistant!.isInitialized)
            const Icon(
              Icons.mic,
              color: Colors.blue,
              size: 20,
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera Preview
          Expanded(
            flex: 3,
            child: _buildCameraPreview(),
          ),
          
          // Voice Assistant Panel (only show after stove detected)
          if (_voiceAssistant != null && _stoveWasDetected)
            _buildVoiceAssistantPanel(),
          
          // Status Bar
          _buildStatusBar(),
          
          // Control Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: _toggleSession,
              icon: Icon(_isSessionActive ? Icons.stop : Icons.play_arrow),
              label: Text(
                _isSessionActive ? 'Stop Monitoring' : 'Start Monitoring',
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                backgroundColor: _isSessionActive ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
              ),
            ),
          ),
          
          // Detection Results
          if (_result != null) _buildCompactResults(),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
  
  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_cameraController!),
        
        // Overlay when stove detected
        if (_result?.stoveDetected == true && _isSessionActive)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red, width: 4),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning, color: Colors.white, size: 64),
                    SizedBox(height: 12),
                    Text(
                      '🔥 STOVE DETECTED!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildVoiceAssistantPanel() {
    return AnimatedBuilder(
      animation: _voiceAssistant!,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border(
              top: BorderSide(color: Colors.blue.shade200, width: 2),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Status icon
                  Icon(
                    _voiceAssistant!.isListening 
                        ? Icons.mic 
                        : _voiceAssistant!.isSpeaking 
                            ? Icons.volume_up 
                            : Icons.mic_none,
                    color: _voiceAssistant!.isActive ? Colors.blue : Colors.grey,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  
                  // Status text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _voiceAssistant!.isListening 
                              ? 'Listening...'
                              : _voiceAssistant!.isSpeaking 
                                  ? 'Speaking...'
                                  : 'Voice Assistant',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (_voiceAssistant!.lastRecognizedText.isNotEmpty)
                          Text(
                            'You: ${_voiceAssistant!.lastRecognizedText}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (_voiceAssistant!.lastResponse.isNotEmpty)
                          Text(
                            'Assistant: ${_voiceAssistant!.lastResponse}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  
                  // Manual mic button
                  IconButton(
                    icon: Icon(
                      _voiceAssistant!.isListening ? Icons.stop : Icons.mic,
                      color: Colors.blue,
                    ),
                    onPressed: () => _voiceAssistant!.toggleListening(),
                    tooltip: _voiceAssistant!.isListening ? 'Stop' : 'Talk',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: _isSessionActive ? Colors.green.shade100 : Colors.grey.shade200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatusItem(
            Icons.fiber_manual_record,
            _isSessionActive ? 'MONITORING' : 'STOPPED',
            _isSessionActive ? Colors.green : Colors.grey,
          ),
          _buildStatusItem(
            Icons.image,
            'Frames: $_frameCount',
            Colors.blue,
          ),
          if (_isDetecting)
            _buildStatusItem(
              Icons.sync,
              'Detecting...',
              Colors.orange,
            ),
        ],
      ),
    );
  }
  
  Widget _buildStatusItem(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildCompactResults() {
    if (_result == null) return const SizedBox();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _result!.stoveDetected ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _result!.stoveDetected ? Colors.red : Colors.green,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _result!.stoveDetected ? Icons.warning : Icons.check_circle,
                color: _result!.stoveDetected ? Colors.red : Colors.green,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _result!.stoveDetected ? 'Stove Detected!' : 'No Stove',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _result!.stoveDetected ? Colors.red.shade900 : Colors.green.shade900,
                  ),
                ),
              ),
              if (_lastDetectionTime != null)
                Text(
                  '${DateTime.now().difference(_lastDetectionTime!).inSeconds}s ago',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
            ],
          ),
          if (_result!.detections.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _result!.detections.take(5).map((det) => Chip(
                avatar: Icon(
                  det.className == 'oven' ? Icons.local_fire_department : Icons.category,
                  size: 16,
                  color: det.className == 'oven' ? Colors.orange : Colors.blue,
                ),
                label: Text(
                  '${det.className} ${(det.confidence * 100).toInt()}%',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: det.className == 'oven' 
                    ? Colors.orange.shade100 
                    : Colors.blue.shade50,
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}