import os
import re
import shutil
import tempfile
from difflib import get_close_matches
from typing import Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from faster_whisper import WhisperModel

app = FastAPI(title="Field Manager STT Backend", version="1.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_model: Optional[WhisperModel] = None
_model_load_error: Optional[str] = None


def get_model() -> WhisperModel:
    global _model
    global _model_load_error

    if _model is None:
        model_size = os.getenv("WHISPER_MODEL_SIZE", "small")
        device = os.getenv("WHISPER_DEVICE", "cpu")
        compute_type = os.getenv("WHISPER_COMPUTE_TYPE", "int8")

        print(
            f"[MODEL] loading model: size={model_size}, device={device}, compute_type={compute_type}",
            flush=True,
        )

        _model = WhisperModel(
            model_size_or_path=model_size,
            device=device,
            compute_type=compute_type,
        )

        _model_load_error = None
        print("[MODEL] model loaded successfully", flush=True)

    return _model


@app.on_event("startup")
def startup_event() -> None:
    global _model_load_error

    try:
        get_model()
    except Exception as e:
        _model_load_error = str(e)
        print(f"[STARTUP ERROR] model preload failed: {_model_load_error}", flush=True)
        raise RuntimeError(f"model preload failed: {_model_load_error}")


def normalize_text(text: str) -> str:
    text = text.replace("\n", " ").replace("\r", " ")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def normalize_datetime_text(text: str) -> str:
    value = normalize_text(text)

    replacements = {
        "년": "-",
        "월": "-",
        "일": "",
        "시": ":",
        "분": "",
    }

    for old, new in replacements.items():
        value = value.replace(old, new)

    value = re.sub(r"\s+", " ", value).strip()
    value = re.sub(r"-+", "-", value)
    value = re.sub(r":+", ":", value)
    return value


def normalize_category_text(text: str) -> str:
    value = normalize_text(text)

    category_keywords = {
        "안전": ["안전", "위험", "안전관리"],
        "품질": ["품질", "하자", "품질관리"],
        "공정": ["공정", "일정", "진도"],
        "환경": ["환경", "폐기물", "분진", "소음"],
        "기타": ["기타"],
    }

    for category, keywords in category_keywords.items():
        if any(keyword in value for keyword in keywords):
            return category

    candidates = list(category_keywords.keys())
    matches = get_close_matches(value, candidates, n=1, cutoff=0.4)
    if matches:
        return matches[0]

    return value


def cleanup_by_field_type(field_type: str, text: str) -> str:
    value = normalize_text(text)
    field_type = field_type.strip().lower()

    if field_type in {"inspection_datetime", "date_time", "datetime"}:
        return normalize_datetime_text(value)

    if field_type in {"category", "inspection_category"}:
        return normalize_category_text(value)

    return value


@app.get("/")
def root() -> dict:
    return {
        "message": "ok",
        "service": "field-manager-stt-backend",
    }


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok" if _model_load_error is None else "error",
        "model_loaded": _model is not None,
        "model_load_error": _model_load_error,
        "model_size": os.getenv("WHISPER_MODEL_SIZE", "small"),
        "device": os.getenv("WHISPER_DEVICE", "cpu"),
        "compute_type": os.getenv("WHISPER_COMPUTE_TYPE", "int8"),
    }


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    field_type: str = Form("general"),
    language: str = Form("ko"),
    beam_size: int = Form(5),
) -> dict:
    global _model_load_error

    if _model_load_error is not None:
        raise HTTPException(
            status_code=500,
            detail=f"model preload failed: {_model_load_error}",
        )

    if not file.filename:
        raise HTTPException(status_code=400, detail="audio file is missing")

    suffix = os.path.splitext(file.filename)[1] or ".m4a"
    temp_path = None

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            temp_path = temp_file.name
            shutil.copyfileobj(file.file, temp_file)

        model = get_model()

        segments, info = model.transcribe(
            audio=temp_path,
            language=language,
            beam_size=beam_size,
            vad_filter=True,
            condition_on_previous_text=False,
        )

        raw_text_parts = []
        for segment in segments:
            segment_text = segment.text.strip()
            if segment_text:
                raw_text_parts.append(segment_text)

        raw_text = normalize_text(" ".join(raw_text_parts))
        clean_text = cleanup_by_field_type(field_type=field_type, text=raw_text)

        return {
            "field_type": field_type,
            "text": clean_text,
            "raw_text": raw_text,
            "clean_text": clean_text,
            "language": info.language,
            "language_probability": info.language_probability,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"transcription failed: {e}")

    finally:
        try:
            await file.close()
        except Exception:
            pass

        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except Exception:
                pass


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
