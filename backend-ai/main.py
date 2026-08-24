import os
import shutil
import tempfile
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List
import uvicorn
import lancedb
from ingest import ingest_file
from chat import get_answer
from sklearn.decomposition import PCA
import numpy as np 

# Store database safely in the user's AppData directory
appdata_dir = os.getenv('APPDATA')
if appdata_dir:
    DB_PATH = os.path.join(appdata_dir, "StudentRAG", "lancedb")
else:
    DB_PATH = os.path.expanduser("~/.student_rag/lancedb")
os.makedirs(DB_PATH, exist_ok=True)

# Safe temp upload directory with full write permissions
TEMP_DIR = os.path.join(tempfile.gettempdir(), "StudentRAG_uploads")
os.makedirs(TEMP_DIR, exist_ok=True)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class RemoveDocRequest(BaseModel):
    chat_id: str
    filename: str

class ChatRequest(BaseModel):
    query: str
    chat_id: str
    chat_history: Optional[List] = []
    model: Optional[str] = "qwen2.5:3b"
    attached_files: Optional[List[str]] = []

@app.post("/upload")
async def upload_document(files: List[UploadFile] = File(...), chat_id: str = Form(...)):
    allowed_extensions = {".pdf", ".docx", ".pptx", ".txt", ".md"}
    ingested_files = []
    
    for file in files:
        ext = os.path.splitext(file.filename)[1].lower()
        if ext not in allowed_extensions:
            print(f"[UPLOAD] Skipping {file.filename}: Unsupported extension")
            continue

        file_path = os.path.join(TEMP_DIR, file.filename)

        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer) 

        try:
            print(f"[UPLOAD] Ingesting {file.filename} for chat_id={chat_id}...")
            result = ingest_file(file_path, chat_id)
            print(f"[UPLOAD] Result: {result}")
            if result.get("status") in ["success", "already_indexed"]:
                ingested_files.append(file.filename)
        except Exception as e:
            print(f"[UPLOAD ERROR] Failed to ingest {file.filename}: {str(e)}")
        finally:
            if os.path.exists(file_path):
                os.remove(file_path)

    if not ingested_files:
        raise HTTPException(status_code=500, detail="Failed to process uploaded files. Check backend logs.")

    return {"message": f"Successfully ingested: {', '.join(ingested_files)}"}

@app.post("/chat")
async def chat_with_document(request: ChatRequest):
    print(f"[CHAT] Received query: '{request.query}' for chat_id={request.chat_id}")
    result = get_answer(
        user_query=request.query,
        chat_history=request.chat_history,
        chat_id=request.chat_id,
        model_name=request.model,
        attached_files=request.attached_files
    )
    return {"answer": result["text"], "sources": result["sources"]}

@app.get("/visualize/{chat_id}")
async def visualize_vectors(chat_id: str):
    db = lancedb.connect(DB_PATH)
    try:
        table = db.open_table('documents')
        records = table.search().where(f"chat_id = '{chat_id}'").limit(2000).to_list()
        print(f"[VISUALIZE] Found {len(records)} chunks for chat_id={chat_id}")
    except Exception as e:
        print(f"[VISUALIZE ERROR] {e}")
        return {"points": []}

    if not records:
        return {"points": []}

    vectors = [r["vector"] for r in records]
    n_samples = len(vectors)

    if n_samples >= 3:
        pca = PCA(n_components=3)
        coords_3d = pca.fit_transform(vectors)
        max_val = np.max(np.abs(coords_3d)) or 1.0
        coords_3d = (coords_3d / max_val).tolist()
    elif n_samples == 2:
        pca = PCA(n_components=2)
        coords_2d = pca.fit_transform(vectors)
        coords_3d = [[row[0], row[1], 0.0] for row in coords_2d]
    else:
        coords_3d = [[0.0, 0.0, 0.0]]

    points = []
    for idx, r in enumerate(records):
        points.append({
            "id": r.get("id", str(idx)),
            "x": coords_3d[idx][0],
            "y": coords_3d[idx][1],
            "z": coords_3d[idx][2],
            "source": r.get("source", "Unknown"),
            "snippet": r.get("text", "")[:120] + "..."
        })

    return {"points": points}

@app.post("/remove_document")
async def remove_document(request: RemoveDocRequest):
    db = lancedb.connect(DB_PATH)
    try:
        table = db.open_table('documents')
        table.delete(f"chat_id = '{request.chat_id}' AND source = '{request.filename}'")
        return {"status": "success", "message": f"Removed {request.filename}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to remove document: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8008)