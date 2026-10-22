import os
import shutil
import subprocess
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import FileResponse
from pathlib import Path

app = FastAPI(title="AI Super App Voice Server")

# Directory setup
UPLOAD_DIR = Path("uploads")
OUTPUT_DIR = Path("separated")
UPLOAD_DIR.mkdir(exist_ok=True)
OUTPUT_DIR.mkdir(exist_ok=True)

@app.post("/separate")
async def separate_audio(file: UploadFile = File(...)):
    """
    Separates vocals from an audio file using Demucs.
    Returns the vocals.wav file path.
    """
    file_path = UPLOAD_DIR / file.filename
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    
    # Run Demucs: -n htdemucs is the high quality model
    try:
        subprocess.run([
            "demucs", 
            "-n", "htdemucs", 
            str(file_path), 
            "-o", str(OUTPUT_DIR)
        ], check=True)
        
        # Path: separated/htdemucs/[filename]/vocals.wav
        folder_name = file.filename.rsplit(".", 1)[0]
        vocals_path = OUTPUT_DIR / "htdemucs" / folder_name / "vocals.wav"
        
        if vocals_path.exists():
            return FileResponse(vocals_path, media_type="audio/wav", filename=f"{folder_name}_vocals.wav")
        else:
            raise HTTPException(status_code=500, detail="Vocal file not generated")
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/status")
def get_status():
    return {"status": "online", "model": "Demucs htdemucs"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
