import requests
import sys

def test_backend(image_path, server_url="http://localhost:8000"):
    """
    Test the detection endpoint with an image
    """
    print(f"Testing backend at: {server_url}")
    print(f"Using image: {image_path}\n")
    
    # First check if server is running
    try:
        health = requests.get(f"{server_url}/health")
        print(f"✅ Server is running: {health.json()}\n")
    except requests.exceptions.ConnectionError:
        print("❌ Server is not running! Start it with: python main.py")
        return
    
    # Test detection
    try:
        with open(image_path, 'rb') as f:
            files = {'file': f}
            response = requests.post(f"{server_url}/detect", files=files)
        
        result = response.json()
        
        if result.get('success'):
            print("=" * 50)
            print("DETECTION RESULTS")
            print("=" * 50)
            print(f"Stove detected: {'✅ YES' if result['stove_detected'] else '❌ NO'}")
            print(f"Total objects found: {result['total_objects']}\n")
            
            if result['detections']:
                print("Detected objects:")
                for i, det in enumerate(result['detections'], 1):
                    print(f"\n{i}. {det['class'].upper()}")
                    print(f"   Confidence: {det['confidence']:.1%}")
                    print(f"   Bounding box: {det['bbox']}")
            else:
                print("No objects detected in image")
            
        else:
            print(f"❌ Error: {result.get('error')}")
            
    except FileNotFoundError:
        print(f"❌ Image file not found: {image_path}")
    except Exception as e:
        print(f"❌ Error during request: {e}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_backend.py <path_to_image>")
        print("Example: python test_backend.py stove.jpg")
        sys.exit(1)
    
    image_path = sys.argv[1]
    test_backend(image_path)
