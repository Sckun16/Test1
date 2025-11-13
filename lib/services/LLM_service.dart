import 'dart:convert';
import 'package:http/http.dart' as http;

class LLMService {
  final String apiKey;
  final List<Map<String, dynamic>> _conversationHistory = [];
  
  LLMService({String? apiKey}) : apiKey = apiKey ?? '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';
  
  /// Send a message to Groq and get a response
  Future<String?> sendMessage(String userMessage) async {
    try {
      // Add user message to history
      _conversationHistory.add({
        'role': 'user',
        'content': userMessage,
      });
      
      // Prepare messages with system prompt
      final messages = [
        {
          'role': 'system',
          'content': '''You are a friendly cooking assistant helping someone who is using their stove. 
Your role is to:
- Ask what they're cooking and provide helpful tips
- Give cooking advice, timing suggestions, and safety reminders
- Keep responses very concise (2-3 sentences max) since they'll be spoken aloud
- Be warm, encouraging, and helpful
- Remember the context of the conversation'''
        },
        ..._conversationHistory,
      ];
      
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.1-70b-versatile', // Fast and capable free model
          'messages': messages,
          'temperature': 0.7,
          'max_tokens': 150, // Keep responses short for TTS
          'top_p': 1,
          'stream': false,
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final assistantMessage = data['choices'][0]['message']['content'] as String;
        
        // Add assistant response to history
        _conversationHistory.add({
          'role': 'assistant',
          'content': assistantMessage,
        });
        
        return assistantMessage.trim();
      } else {
        print('Groq API Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('LLM request failed: $e');
      return null;
    }
  }
  
  /// Initialize conversation when stove is first detected
  String getInitialGreeting() {
    return "Hi! I noticed you're using the stove. What are you cooking today?";
  }
  
  /// Reset conversation history
  void resetConversation() {
    _conversationHistory.clear();
  }
  
  /// Get conversation history length
  int get messageCount => _conversationHistory.length;
}