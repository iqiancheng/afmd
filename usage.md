# AFMD Usage Guide

AFMD (Apple Foundation Models Daemon) is a local server that provides OpenAI-compatible APIs for on-device AI models, including text generation, vision analysis, and multimodal capabilities.

## Table of Contents

- [Quick Start](#quick-start)
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
