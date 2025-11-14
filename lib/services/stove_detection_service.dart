import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class StoveDetectionService {
  final String baseUrl;
  
  StoveDetectionService({this.baseUrl = 'http://localhost:8000'});
  
  /// Check if the backend is running
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      print('Health check failed: $e');
      return false;
    }
  }
  
  /// Send an image file for detection
  Future<DetectionResult?> detectObjects(String imagePath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/detect'),
      );
      
      // Add the image file
      request.files.add(
        await http.MultipartFile.fromPath('file', imagePath),
      );
      
      // Send request with timeout
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
      );
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DetectionResult.fromJson(data);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Detection request failed: $e');
      return null;
    }
  }
  
  /// Send image bytes (useful for camera frames)
  Future<DetectionResult?> detectFromBytes(List<int> imageBytes) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/detect'),
      );
      
      // Add image bytes
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'frame.jpg',
        ),
      );
      
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
      );
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DetectionResult.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Detection failed: $e');
      return null;
    }
  }
}

/// Model for detection results
class DetectionResult {
  final bool success;
  final bool stoveDetected;
  final int totalObjects;
  final List<Detection> detections;
  
  DetectionResult({
    required this.success,
    required this.stoveDetected,
    required this.totalObjects,
    required this.detections,
  });
  
  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      success: json['success'] ?? false,
      stoveDetected: json['stove_detected'] ?? false,
      totalObjects: json['total_objects'] ?? 0,
      detections: (json['detections'] as List?)
          ?.map((d) => Detection.fromJson(d))
          .toList() ?? [],
    );
  }
}

/// Model for individual detection
class Detection {
  final String className;
  final double confidence;
  final BoundingBox bbox;
  
  Detection({
    required this.className,
    required this.confidence,
    required this.bbox,
  });
  
  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      className: json['class'],
      confidence: json['confidence'].toDouble(),
      bbox: BoundingBox.fromJson(json['bbox']),
    );
  }
}

/// Model for bounding box
class BoundingBox {
  final double x1, y1, x2, y2;
  
  BoundingBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });
  
  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x1: json['x1'].toDouble(),
      y1: json['y1'].toDouble(),
      x2: json['x2'].toDouble(),
      y2: json['y2'].toDouble(),
    );
  }
}