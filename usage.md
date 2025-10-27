# AFMD Usage Guide

AFMD (Apple Foundation Models Daemon) is a local server that provides OpenAI-compatible APIs for on-device AI models, including text generation, vision analysis, and multimodal capabilities.

## Table of Contents

- [Quick Start](#quick-start)
- [Python API Quick Start](#python-api-quick-start)
- [API Endpoints](#api-endpoints)
- [Authentication](#authentication)
- [Examples](#examples)
- [Vision APIs](#vision-apis)
- [Error Handling](#error-handling)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

## Quick Start

1. **Start the server**: Launch AFMD from the menu bar or command line
2. **Check status**: Visit `http://localhost:11535/health` to verify the server is running
3. **Get your API key**: The server runs without authentication by default
4. **Make requests**: Use any HTTP client to interact with the APIs

### Base URL
```
http://localhost:11535/v1
```

## Python API Quick Start

### Installation

Install the required Python packages:

```bash
pip install openai requests pillow
```

### Basic Setup

```python
from openai import OpenAI
import requests
import base64
from PIL import Image
import io

# Initialize the OpenAI client
client = OpenAI(
    base_url="http://localhost:11535/v1",
    api_key="not-needed"  # No authentication required
)
```

### 1. Basic Chat Completions

```python
def basic_chat(message):
    """Basic text chat with the model"""
    try:
        response = client.chat.completions.create(
            model="AFM-on-device",
            messages=[{"role": "user", "content": message}],
            temperature=0.7,
            max_tokens=1000
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Error: {e}"

# Example usage
result = basic_chat("Hello! How are you today?")
print(result)
```

### 2. Streaming Chat

```python
def streaming_chat(message):
    """Stream chat responses for real-time output"""
    try:
        stream = client.chat.completions.create(
            model="AFM-on-device",
            messages=[{"role": "user", "content": message}],
            stream=True,
            temperature=0.8
        )
        
        for chunk in stream:
            if chunk.choices[0].delta.content is not None:
                print(chunk.choices[0].delta.content, end="", flush=True)
        print()  # New line after streaming
    except Exception as e:
        print(f"Error: {e}")

# Example usage
streaming_chat("Tell me a short story about a robot")
```

### 3. Multimodal Chat (Text + Images)

```python
def multimodal_chat(text_message, image_path):
    """Chat with both text and image input"""
    try:
        # Encode image to base64
        with open(image_path, "rb") as image_file:
            base64_image = base64.b64encode(image_file.read()).decode('utf-8')
        
        response = client.chat.completions.create(
            model="AFM-on-device",
            messages=[{
                "role": "user",
                "content": [
                    {"type": "text", "text": text_message},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{base64_image}"
                        }
                    }
                ]
            }],
            temperature=0.7
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Error: {e}"

# Example usage
result = multimodal_chat("What do you see in this image?", "path/to/your/image.jpg")
print(result)
```

### 4. Vision APIs

#### OCR (Text Recognition)

```python
def extract_text_from_image(image_path):
    """Extract text from an image using OCR"""
    try:
        with open(image_path, "rb") as image_file:
            response = requests.post(
                "http://localhost:11535/v1/vision/ocr",
                data=image_file,
                headers={"Content-Type": "application/octet-stream"}
            )
        
        if response.status_code == 200:
            result = response.json()
            return {
                "text": result.get("text", ""),
                "language": result.get("language", "unknown")
            }
        else:
            return {"error": f"HTTP {response.status_code}: {response.text}"}
    except Exception as e:
        return {"error": str(e)}

# Example usage
ocr_result = extract_text_from_image("document.jpg")
print(f"Extracted text: {ocr_result.get('text', 'No text found')}")
print(f"Language: {ocr_result.get('language', 'Unknown')}")
```

#### Object Detection

```python
def detect_objects_in_image(image_path):
    """Detect objects in an image"""
    try:
        with open(image_path, "rb") as image_file:
            response = requests.post(
                "http://localhost:11535/v1/vision/detect",
                data=image_file,
                headers={"Content-Type": "application/octet-stream"}
            )
        
        if response.status_code == 200:
            result = response.json()
            return result.get("objects", [])
        else:
            return [{"error": f"HTTP {response.status_code}: {response.text}"}]
    except Exception as e:
        return [{"error": str(e)}]

# Example usage
objects = detect_objects_in_image("photo.jpg")
for obj in objects:
    if "error" not in obj:
        print(f"Found: {obj.get('label', 'Unknown')} - {obj.get('description', 'No description')}")
    else:
        print(f"Error: {obj['error']}")
```

#### Comprehensive Image Analysis

```python
def analyze_image(image_path):
    """Perform comprehensive image analysis"""
    try:
        with open(image_path, "rb") as image_file:
            response = requests.post(
                "http://localhost:11535/v1/vision/analyze",
                data=image_file,
                headers={"Content-Type": "application/octet-stream"}
            )
        
        if response.status_code == 200:
            return response.json()
        else:
            return {"error": f"HTTP {response.status_code}: {response.text}"}
    except Exception as e:
        return {"error": str(e)}

# Example usage
analysis = analyze_image("complex_image.jpg")
if "error" not in analysis:
    print(f"Text content: {analysis['analysis']['text_content']}")
    print(f"Image description: {analysis['analysis']['image_description']}")
    print(f"Objects detected: {len(analysis['analysis']['object_detections'])}")
    print(f"Processing time: {analysis['processing_time']:.2f}s")
else:
    print(f"Error: {analysis['error']}")
```

### 5. Advanced Usage Examples

#### Conversation with Memory

```python
class ChatSession:
    def __init__(self):
        self.messages = []
    
    def add_message(self, role, content):
        self.messages.append({"role": role, "content": content})
    
    def chat(self, user_message):
        self.add_message("user", user_message)
        
        response = client.chat.completions.create(
            model="AFM-on-device",
            messages=self.messages,
            temperature=0.7
        )
        
        assistant_message = response.choices[0].message.content
        self.add_message("assistant", assistant_message)
        
        return assistant_message

# Example usage
session = ChatSession()
print(session.chat("My name is Alice"))
print(session.chat("What's my name?"))
```

#### Batch Processing

```python
def process_multiple_images(image_paths, analysis_type="ocr"):
    """Process multiple images in batch"""
    results = []
    
    for image_path in image_paths:
        print(f"Processing {image_path}...")
        
        if analysis_type == "ocr":
            result = extract_text_from_image(image_path)
        elif analysis_type == "detect":
            result = detect_objects_in_image(image_path)
        elif analysis_type == "analyze":
            result = analyze_image(image_path)
        else:
            result = {"error": "Invalid analysis type"}
        
        results.append({
            "image": image_path,
            "result": result
        })
    
    return results

# Example usage
image_files = ["image1.jpg", "image2.jpg", "image3.jpg"]
batch_results = process_multiple_images(image_files, "ocr")
for result in batch_results:
    print(f"{result['image']}: {result['result']}")
```

### 6. Error Handling and Best Practices

```python
def safe_api_call(func, *args, **kwargs):
    """Wrapper for safe API calls with error handling"""
    try:
        return func(*args, **kwargs)
    except requests.exceptions.ConnectionError:
        return {"error": "Cannot connect to AFMD server. Is it running?"}
    except requests.exceptions.Timeout:
        return {"error": "Request timed out"}
    except Exception as e:
        return {"error": f"Unexpected error: {str(e)}"}

# Example usage
result = safe_api_call(basic_chat, "Hello!")
if "error" in result:
    print(f"Error: {result['error']}")
else:
    print(result)
```

### 7. Utility Functions

```python
def check_server_status():
    """Check if the AFMD server is running"""
    try:
        response = requests.get("http://localhost:11535/health", timeout=5)
        return response.status_code == 200
    except:
        return False

def get_available_models():
    """Get list of available models"""
    try:
        response = requests.get("http://localhost:11535/v1/models")
        if response.status_code == 200:
            return response.json()
        return {"error": f"HTTP {response.status_code}"}
    except Exception as e:
        return {"error": str(e)}

# Example usage
if check_server_status():
    print("✅ AFMD server is running")
    models = get_available_models()
    print(f"Available models: {models}")
else:
    print("❌ AFMD server is not running")
```

## API Endpoints

### Core OpenAI-Compatible APIs

#### 1. Chat Completions
**Endpoint**: `POST /v1/chat/completions`

Standard OpenAI chat completions API for text generation.

#### 2. Multimodal Chat
**Endpoint**: `POST /v1/chat/completions/multimodal`

Enhanced chat API that supports both text and images in conversations.

#### 3. Models
**Endpoint**: `GET /v1/models`

List available models and their capabilities.

#### 4. Health Check
**Endpoint**: `GET /health`

Check server status and availability.

### Vision APIs

#### 1. OCR (Optical Character Recognition)
**Endpoint**: `POST /v1/vision/ocr`

Extract text from images using Apple's Vision framework.

#### 2. Object Detection
**Endpoint**: `POST /v1/vision/detect`

Detect and classify objects in images.

#### 3. Image Analysis
**Endpoint**: `POST /v1/vision/analyze`

Comprehensive image analysis including OCR, object detection, and description generation.

## Authentication

AFMD currently runs without authentication. All requests can be made directly without API keys.

## Examples

### Basic Chat Completion

```bash
curl -X POST "http://localhost:11535/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "AFM-on-device",
    "messages": [
      {
        "role": "user",
        "content": "Hello, how are you?"
      }
    ],
    "temperature": 0.7,
    "max_tokens": 1000
  }'
```

### Streaming Chat Completion

```bash
curl -X POST "http://localhost:11535/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "AFM-on-device",
    "messages": [
      {
        "role": "user",
        "content": "Tell me a story"
      }
    ],
    "stream": true,
    "temperature": 0.8
  }'
```

### Multimodal Chat (Text + Images)

```bash
curl -X POST "http://localhost:11535/v1/chat/completions/multimodal" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "AFM-on-device",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "What do you see in this image?"
          },
          {
            "type": "image_url",
            "image_url": {
              "url": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQ..."
            }
          }
        ]
      }
    ],
    "temperature": 0.7
  }'
```

### List Available Models

```bash
curl -X GET "http://localhost:11535/v1/models"
```

### Health Check

```bash
curl -X GET "http://localhost:11535/health"
```

## Vision APIs

### OCR (Text Recognition)

Extract text from images:

```bash
curl -X POST "http://localhost:11535/v1/vision/ocr" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @image.jpg
```

**Response:**
```json
{
  "text": "Extracted text from image",
  "confidence": 0.95,
  "language": "en"
}
```

### Object Detection

Detect objects in images:

```bash
curl -X POST "http://localhost:11535/v1/vision/detect" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @image.jpg
```

**Response:**
```json
{
  "objects": [
    {
      "label": "person",
      "description": "person with 95% confidence"
    },
    {
      "label": "car",
      "description": "car with 87% confidence"
    }
  ]
}
```

### Comprehensive Image Analysis

Perform complete image analysis:

```bash
curl -X POST "http://localhost:11535/v1/vision/analyze" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @image.jpg
```

**Response:**
```json
{
  "id": "vision-12345",
  "object": "vision.analysis",
  "created": 1640995200,
  "model": "AFM-on-device",
  "analysis": {
    "text_content": "Extracted text from image",
    "object_detections": [
      {
        "label": "person",
        "bounding_box": {
          "x": 0.1,
          "y": 0.2,
          "width": 0.3,
          "height": 0.4
        },
        "description": "person with 95% confidence"
      }
    ],
    "image_description": "Image analysis completed. Contains text: 'Hello World'. Objects detected: person, car. Analysis confidence: 95%.",
    "language": "en"
  },
  "processing_time": 1.23
}
```

## Error Handling

### Common Error Responses

#### 400 Bad Request
```json
{
  "error": {
    "message": "Invalid request format",
    "type": "invalid_request_error",
    "code": "invalid_request"
  }
}
```

#### 500 Internal Server Error
```json
{
  "error": {
    "message": "Model processing failed",
    "type": "server_error",
    "code": "model_error"
  }
}
```

#### 503 Service Unavailable
```json
{
  "error": {
    "message": "Model not available",
    "type": "service_unavailable",
    "code": "model_unavailable"
  }
}
```

### Vision API Errors

#### 415 Unsupported Media Type
```json
{
  "error": {
    "message": "Content-Type must be application/octet-stream",
    "type": "invalid_request_error",
    "code": "unsupported_media_type"
  }
}
```

## Configuration

### Server Configuration

- **Host**: `0.0.0.0` (default)
- **Port**: `11535` (default)
- **Max Body Size**: `50MB` (for image uploads)

### Model Configuration

- **Model Name**: `AFM-on-device`
- **Vision Analysis**: Enabled by default
- **Language Detection**: Enabled by default

### Environment Variables

- `AFMD_DAEMON_MODE`: Set to `true` to run as background daemon
- `AFMD_HOST`: Override default host (default: `0.0.0.0`)
- `AFMD_PORT`: Override default port (default: `11535`)

## Troubleshooting

### Common Issues

#### 1. Server Won't Start
- **Check port availability**: Ensure port 11535 is not in use
- **Check model availability**: Verify Apple Intelligence is available on your system
- **Check logs**: Review server logs in the Preferences window

#### 2. Model Not Available
- **System requirements**: Ensure you're running macOS with Apple Intelligence support
- **Model loading**: The model may take time to load on first use
- **Memory**: Ensure sufficient system memory is available

#### 3. Vision APIs Not Working
- **Image format**: Ensure images are in supported formats (JPEG, PNG, etc.)
- **Image size**: Check that images are not too large (>50MB)
- **Content-Type**: Ensure correct `application/octet-stream` header

#### 4. Performance Issues
- **Model loading**: First request may be slower due to model initialization
- **Memory usage**: Large images or long conversations may consume more memory
- **Concurrent requests**: Multiple simultaneous requests may impact performance

### Debug Mode

Enable debug logging in the Preferences window to get detailed information about requests and responses.

### Logs

Server logs are available in the Preferences window under the "Recent" tab. Logs include:
- Request/response details
- Error messages
- Performance metrics
- Vision processing results

## Advanced Usage

### Custom Headers

You can add custom headers to requests:

```bash
curl -X POST "http://localhost:11535/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Custom-Header: value" \
  -d '{"model": "AFM-on-device", "messages": [...]}'
```

### CORS Support

The server includes CORS middleware for web applications:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Headers: Content-Type, Authorization`
- `Access-Control-Allow-Methods: POST, GET, OPTIONS`

### Rate Limiting

Currently no rate limiting is implemented. Consider implementing client-side rate limiting for production use.
