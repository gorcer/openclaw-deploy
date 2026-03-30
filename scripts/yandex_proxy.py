#!/usr/bin/env python3
"""
Yandex Services Proxy — скрывает API ключи от агентов
Агент отправляет запрос → прокси добавляет ключ → Yandex API → результат агенту
"""

import os
import base64
import asyncio
from typing import Optional
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel
import httpx

# ============ КОНФИГУРАЦИЯ ============
# Ключи хранятся ТОЛЬКО здесь, агенты их не видят
YANDEX_API_KEY = os.getenv("YANDEX_API_KEY", "YANDEX_SPEECHKIT_KEY_PLACEHOLDER")
YANDEX_FOLDER_ID = os.getenv("YANDEX_FOLDER_ID", "YANDEX_FOLDER_ID_PLACEHOLDER")

# Лимиты
MAX_TEXT_LENGTH = 1000  # символов для TTS
MAX_AUDIO_SIZE = 10 * 1024 * 1024  # 10MB для STT
MAX_IMAGE_SIZE = 5 * 1024 * 1024  # 5MB для OCR

# ============ МОДЕЛИ ============

class TTSRequest(BaseModel):
    text: str
    voice: str = "alena"
    speed: float = 1.0

class STTRequest(BaseModel):
    audio_data: str  # base64 encoded audio
    format: str = "opus"  # opus, oggopus, lpcm
    sample_rate: int = 48000

class OCRRequest(BaseModel):
    image_data: str  # base64 encoded image
    languages: list[str] = ["ru", "en"]

# ============ APP ============

app = FastAPI(title="Yandex Proxy", description="Прокси для Yandex SpeechKit/Vision API")

# Хранилище для больших результатов (TTL 5 минут)
results_store: dict[str, tuple[str, float]] = {}  # id -> (data, expires_at)

def cleanup_old_results():
    """Удаляем просроченные результаты"""
    import time
    now = time.time()
    to_delete = [k for k, (_, exp) in results_store.items() if now > exp]
    for k in to_delete:
        del results_store[k]

# ============ TTS — Синтез речи ============

@app.post("/api/tts")
async def synthesize_speech(req: TTSRequest):
    """
    Синтез речи. Агент отправляет текст, получает base64 аудио.
    """
    cleanup_old_results()
    
    if len(req.text) > MAX_TEXT_LENGTH:
        raise HTTPException(400, f"Text too long. Max {MAX_TEXT_LENGTH} chars")
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                "https://tts.api.cloud.yandex.net/tts/v3/utteranceSynthesis",
                headers={
                    "Authorization": f"Api-Key {YANDEX_API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "text": req.text,
                    "outputAudioSpec": {
                        "containerAudio": {
                            "containerAudioType": "MP3"
                        }
                    },
                    "hints": [{"voice": req.voice}, {"speed": req.speed}]
                }
            )
            
            if response.status_code != 200:
                return JSONResponse({"error": response.text}, status_code=response.status_code)
            
            # Yandex TTS v3 возвращает base64 в JSON
            data = response.json()
            audio_b64 = data.get("result", {}).get("audioChunk", {}).get("data", "")
            
            if not audio_b64:
                return JSONResponse({"error": "No audio in response", "raw": data}, status_code=500)
            
            return {"audio": audio_b64, "format": "mp3"}
            
    except httpx.TimeoutException:
        raise HTTPException(504, "Yandex TTS timeout")
    except Exception as e:
        raise HTTPException(500, str(e))

# ============ STT — Распознавание речи ============

@app.post("/api/stt")
async def recognize_speech(req: STTRequest, background_tasks: BackgroundTasks):
    """
    Распознавание речи. Агент отправляет base64 аудио, получает текст.
    """
    cleanup_old_results()
    
    try:
        audio_bytes = base64.b64decode(req.audio_data)
    except Exception:
        raise HTTPException(400, "Invalid base64 audio data")
    
    if len(audio_bytes) > MAX_AUDIO_SIZE:
        raise HTTPException(400, f"Audio too large. Max {MAX_AUDIO_SIZE // 1024 // 1024}MB")
    
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            # STT API принимает бинарные данные
            response = await client.post(
                f"https://stt.api.cloud.yandex.net/speech/v1/stt:recognize?folderId={YANDEX_FOLDER_ID}&lang=ru-RU",
                headers={"Authorization": f"Api-Key {YANDEX_API_KEY}"},
                content=audio_bytes,
                params={"format": req.format, "sampleRate": req.sample_rate}
            )
            
            if response.status_code == 200:
                result = response.json()
                return {"text": result.get("result", ""), "confidence": result.get("confidence", 1.0)}
            else:
                return JSONResponse({"error": response.text}, status_code=response.status_code)
                
    except httpx.TimeoutException:
        raise HTTPException(504, "Yandex STT timeout")
    except Exception as e:
        raise HTTPException(500, str(e))

# ============ OCR — Распознавание текста с изображений ============

@app.post("/api/ocr")
async def recognize_text(req: OCRRequest):
    """
    OCR. Агент отправляет base64 изображение, получает распознанный текст.
    """
    cleanup_old_results()
    
    try:
        image_bytes = base64.b64decode(req.image_data)
    except Exception:
        raise HTTPException(400, "Invalid base64 image data")
    
    if len(image_bytes) > MAX_IMAGE_SIZE:
        raise HTTPException(400, f"Image too large. Max {MAX_IMAGE_SIZE // 1024 // 1024}MB")
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Yandex Vision API
            response = await client.post(
                "https://vision.api.cloud.yandex.net/vision/v1/batchAnalyze",
                headers={
                    "Authorization": f"Api-Key {YANDEX_API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "folderId": YANDEX_FOLDER_ID,
                    "analyzeSpec": [{
                        "features": [{"type": "TEXT_DETECTION"}],
                        "images": [{"image": base64.b64encode(image_bytes).decode()}]
                    }]
                }
            )
            
            if response.status_code == 200:
                data = response.json()
                # Извлекаем текст из ответа Vision API
                texts = []
                try:
                    results = data.get("results", [{}])
                    for result in results:
                        detection = result.get("detection", {})
                        entities = detection.get("entities", [])
                        for entity in entities:
                            text = entity.get("text", "")
                            if text:
                                texts.append(text)
                except Exception:
                    pass
                
                full_text = " ".join(texts) if texts else ""
                return {"text": full_text, "blocks": texts}
            else:
                return JSONResponse({"error": response.text}, status_code=response.status_code)
                
    except httpx.TimeoutException:
        raise HTTPException(504, "Yandex Vision timeout")
    except Exception as e:
        raise HTTPException(500, str(e))

# ============ HEALTH CHECK ============

@app.get("/health")
async def health():
    """Проверка работоспособности"""
    return {"status": "ok", "service": "yandex-proxy"}

@app.get("/")
async def root():
    """Информация о сервисе"""
    return {
        "service": "Yandex Proxy",
        "description": "Скрывает API ключи от агентов",
        "endpoints": {
            "/api/tts": "Синтез речи (text → audio)",
            "/api/stt": "Распознавание речи (audio → text)",
            "/api/ocr": "OCR (image → text)",
            "/health": "Health check"
        }
    }

# ============ ЗАПУСК ============

if __name__ == "__main__":
    import uvicorn
    print("Starting Yandex Proxy on http://127.0.0.1:8080")
    print("API Key: *** (скрыт от агентов)")
    uvicorn.run(app, host="127.0.0.1", port=8080)