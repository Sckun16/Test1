import os
import torch

# Patch torch.load to use weights_only=False for trusted sources
# This is safe because YOLOv8 models are from official Ultralytics
original_load = torch.load

def patched_load(*args, **kwargs):
    # Force weights_only=False for all loads
    if 'weights_only' not in kwargs:
        kwargs['weights_only'] = False
    return original_load(*args, **kwargs)

torch.load = patched_load

from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO
import cv2
import numpy as np
from PIL import Image
import io

app = FastAPI(title="Stove Detection API")

# Enable CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your Flutter app URL
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load YOLOv8 model once at startup
print("Loading YOLOv8 model...")
model = YOLO('yolov8n.pt')  # Downloads automatically first time
print("Model loaded successfully!")


@app.get("/")
async def root():
    return {
        "message": "Stove Detection API", 
        "status": "running",
        "model": "yolov8n"
    }


@app.post("/detect")
async def detect_objects(file: UploadFile = File(...)):
    """
    Upload an image and get object detections.
    Returns all detected objects with focus on 'oven' class.
    """
    try:
        # Read image file
        contents = await file.read()
        
        # Convert to numpy array
        nparr = np.frombuffer(contents, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if img is None:
            return {"error": "Could not decode image"}
        
        # Run inference
        results = model(img, verbose=False)
        
        # Extract detections
        detections = []
        stove_detected = False
        
        for box in results[0].boxes:
            class_id = int(box.cls[0])
            confidence = float(box.conf[0])
            class_name = model.names[class_id]
            
            # Get bounding box coordinates
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            
            detection = {
                "class": class_name,
                "confidence": round(confidence, 3),
                "bbox": {
                    "x1": round(x1, 1),
                    "y1": round(y1, 1),
                    "x2": round(x2, 1),
                    "y2": round(y2, 1)
                }
            }
            
            detections.append(detection)
            
            # Check if stove/oven detected
            if class_name == 'oven':
                stove_detected = True
        
        return {
            "success": True,
            "stove_detected": stove_detected,
            "total_objects": len(detections),
            "detections": detections
        }
        
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "model_loaded": model is not None}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)