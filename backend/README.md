# Stove Detection Backend

Simple FastAPI backend for real-time object detection using YOLOv8.

## Setup

1. **Install dependencies:**
```bash
pip install -r requirements.txt
```

2. **Run the server:**
```bash
python main.py
```

The server will start at `http://localhost:8000`

## API Endpoints

### `GET /`
Health check - confirms the API is running

### `POST /detect`
Upload an image for object detection

**Request:**
- Method: POST
- Content-Type: multipart/form-data
- Body: image file (jpg, png, etc.)

**Response:**
```json
{
  "success": true,
  "stove_detected": true,
  "total_objects": 3,
  "detections": [
    {
      "class": "oven",
      "confidence": 0.89,
      "bbox": {
        "x1": 120.5,
        "y1": 200.3,
        "x2": 450.2,
        "y2": 600.8
      }
    }
  ]
}
```

### `GET /health`
Server health status

## Testing

### Using curl:
```bash
curl -X POST "http://localhost:8000/detect" \
  -F "file=@path/to/your/image.jpg"
```

### Using Python:
```python
import requests

url = "http://localhost:8000/detect"
files = {"file": open("stove_image.jpg", "rb")}
response = requests.post(url, files=files)
print(response.json())
```

## Notes

- YOLOv8n model downloads automatically on first run (~6MB)
- The model detects 80 COCO classes including 'oven' for stoves
- Confidence threshold is handled by YOLO defaults (0.25)
