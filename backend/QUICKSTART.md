# Quick Start Guide

## 1. Start the Backend

```bash
cd backend
pip install -r requirements.txt
python main.py
```

You should see:
```
Loading YOLOv8 model...
Model loaded successfully!
INFO:     Uvicorn running on http://0.0.0.0:8000
```

## 2. Test with Your Stove Image

If you have your stove image from Google Drive:

```bash
python test_backend.py /path/to/stove_front.jpg
```

Or test with any image:
```bash
python test_backend.py test_image.jpg
```

## 3. Test with curl

```bash
curl -X POST "http://localhost:8000/detect" \
  -F "file=@stove_front.jpg"
```

## 4. Integrate with Flutter

### Add to pubspec.yaml:
```yaml
dependencies:
  http: ^1.1.0
  camera: ^0.10.5  # For camera access
```

### Copy the service file:
Copy `flutter_example.dart` to your Flutter project as `lib/services/stove_detection_service.dart`

### Basic usage in your Flutter app:

```dart
import 'package:camera/camera.dart';
import 'services/stove_detection_service.dart';

class StoveMonitor extends StatefulWidget {
  @override
  _StoveMonitorState createState() => _StoveMonitorState();
}

class _StoveMonitorState extends State<StoveMonitor> {
  late CameraController _camera;
  final _detectionService = StoveDetectionService(
    baseUrl: 'http://YOUR_COMPUTER_IP:8000'  // Replace with your IP
  );
  
  bool _stoveDetected = false;
  bool _isProcessing = false;
  
  @override
  void initState() {
    super.initState();
    _initCamera();
    _startContinuousDetection();
  }
  
  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    _camera = CameraController(
      cameras[0],
      ResolutionPreset.medium,
    );
    await _camera.initialize();
    setState(() {});
  }
  
  void _startContinuousDetection() {
    // Send frame every 2 seconds
    Timer.periodic(Duration(seconds: 2), (timer) async {
      if (!_isProcessing && _camera.value.isInitialized) {
        _isProcessing = true;
        
        try {
          // Capture image
          final image = await _camera.takePicture();
          final bytes = await File(image.path).readAsBytes();
          
          // Send to backend
          final result = await _detectionService.detectFromBytes(bytes);
          
          if (result != null) {
            setState(() {
              _stoveDetected = result.stoveDetected;
            });
            
            if (result.stoveDetected) {
              print('🔥 STOVE DETECTED!');
              // Trigger notification/alert
            }
          }
        } catch (e) {
          print('Detection error: $e');
        } finally {
          _isProcessing = false;
        }
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Stove Monitor')),
      body: Column(
        children: [
          if (_camera.value.isInitialized)
            AspectRatio(
              aspectRatio: _camera.value.aspectRatio,
              child: CameraPreview(_camera),
            ),
          
          Padding(
            padding: EdgeInsets.all(16),
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _stoveDetected ? Colors.red : Colors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _stoveDetected ? '🔥 STOVE DETECTED' : '✅ No Stove',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

## Finding Your Computer's IP Address

### macOS/Linux:
```bash
ifconfig | grep "inet "
```

### Windows:
```bash
ipconfig
```

Look for your local IP (usually `192.168.x.x` or `10.0.x.x`)

## Important Notes

1. **Same Network**: Your phone and computer must be on the same WiFi network
2. **Firewall**: Make sure port 8000 is not blocked
3. **Production**: For production, deploy to a cloud server (AWS, Google Cloud, etc.)
4. **Rate Limiting**: Currently sends 1 frame every 2 seconds to avoid overload

## Next Steps

Once this basic setup works, you can:
- Reduce detection interval for faster response
- Add WebSocket for real-time streaming
- Implement confidence thresholds
- Add alerts/notifications
- Store detection history
