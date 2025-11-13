import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'llm_service.dart';

class VoiceAssistantService extends ChangeNotifier {
  final LLMService _llmService;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isInitialized = false;
  bool _hasGreeted = false;
  bool _handsFreeMode = true; // Continuous listening mode
  String _lastRecognizedText = '';
  String _lastResponse = '';
  
  VoiceAssistantService(this._llmService);
  
  // Getters
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isInitialized => _isInitialized;
  bool get hasGreeted => _hasGreeted;
  String get lastRecognizedText => _lastRecognizedText;
  String get lastResponse => _lastResponse;
  bool get isActive => _isListening || _isSpeaking;
  
  /// Initialize voice services
  Future<bool> initialize() async {
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('Microphone permission denied');
        return false;
      }
      
      // Initialize speech recognition
      _isInitialized = await _speech.initialize(
        onError: (error) => print('Speech error: $error'),
        onStatus: (status) => print('Speech status: $status'),
      );
      
      // Configure TTS
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      
      // TTS completion callback
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });
      
      notifyListeners();
      return _isInitialized;
    } catch (e) {
      print('Voice initialization failed: $e');
      return false;
    }
  }
  
  /// Greet user when stove is first detected
  Future<void> greetUser() async {
    if (_hasGreeted || !_isInitialized) return;
    
    _hasGreeted = true;
    final greeting = _llmService.getInitialGreeting();
    await speak(greeting);
    
    // Auto-start listening after greeting
    Future.delayed(const Duration(milliseconds: 500), () {
      startListening();
    });
  }
  
  /// Start listening for user speech
  Future<void> startListening() async {
    if (!_isInitialized || _isListening || _isSpeaking) return;
    
    _isListening = true;
    _lastRecognizedText = '';
    notifyListeners();
    
    await _speech.listen(
      onResult: (result) {
        _lastRecognizedText = result.recognizedWords;
        notifyListeners();
        
        // When user stops speaking, process the message
        if (result.finalResult) {
          _processUserInput(_lastRecognizedText);
        }
      },
      listenFor: const Duration(seconds: 60), // Longer listening time
      pauseFor: const Duration(seconds: 2), // Shorter pause detection
      partialResults: true,
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );
  }
  
  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) return;
    
    await _speech.stop();
    _isListening = false;
    notifyListeners();
  }
  
  /// Process user input and get LLM response
  Future<void> _processUserInput(String text) async {
    if (text.trim().isEmpty) {
      _isListening = false;
      notifyListeners();
      return;
    }
    
    _isListening = false;
    notifyListeners();
    
    // Get response from LLM
    final response = await _llmService.sendMessage(text);
    
    if (response != null) {
      _lastResponse = response;
      await speak(response);
    } else {
      await speak("Sorry, I couldn't process that. Could you try again?");
    }
  }
  
  /// Speak text using TTS
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    
    _isSpeaking = true;
    _lastResponse = text;
    notifyListeners();
    
    await _tts.speak(text);
    
    // Wait for TTS to finish before proceeding
    // The completion handler will set _isSpeaking to false
  }
  
  /// Stop speaking
  Future<void> stopSpeaking() async {
    await _tts.stop();
    _isSpeaking = false;
    notifyListeners();
  }
  
  /// Manual trigger for listening (button press)
  Future<void> toggleListening() async {
    if (_isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }
  
  /// Reset assistant state
  void reset() {
    _hasGreeted = false;
    _lastRecognizedText = '';
    _lastResponse = '';
    _llmService.resetConversation();
    stopListening();
    stopSpeaking();
    notifyListeners();
  }
  
  /// Cleanup
  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    super.dispose();
  }
}