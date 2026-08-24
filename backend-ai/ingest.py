import hashlib
import os
import lancedb
import pymupdf4llm
from markitdown import MarkItDown
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_ollama import OllamaEmbeddings

appdata_dir = os.getenv('APPDATA')
if appdata_dir:
    DB_PATH = os.path.join(appdata_dir, "StudentRAG", "lancedb")
else:
    DB_PATH = os.path.expanduser("~/.student_rag/lancedb")
os.makedirs(DB_PATH, exist_ok=True)

def extract_markdown(file_path: str) -> str:
    extension = os.path.splitext(file_path)[1].lower()
    if extension == '.pdf':
        return pymupdf4llm.to_markdown(file_path)
    elif extension in ['.docx', '.pptx', '.txt', '.md']:
        mid = MarkItDown()
        result = mid.convert(file_path)
        return result.text_content
    else:
        raise ValueError(f"Unsupported file extension: {extension}")

def compute_sha256(file_path: str) -> str:
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(8192):
            hasher.update(chunk)
    return hasher.hexdigest()

def ingest_file(file_path: str, chat_id: str) -> dict:
    file_hash = compute_sha256(file_path)
    filename = os.path.basename(file_path)
    
    db = lancedb.connect(DB_PATH)
    
    table = None
    try:
        table = db.open_table('documents')
        exist = table.search().where(f"file_hash = '{file_hash}' AND chat_id = '{chat_id}'").limit(1).to_list()
        if exist:
            print(f"[INGEST] File '{filename}' is already indexed for chat_id={chat_id}")
            return {
                'status': "already_indexed",
                "filename": filename,
                "file_hash": file_hash
            }
    except Exception as e:
        print(f"[INGEST] Table 'documents' not found or empty, creating new table... ({e})")

    markdown_cont = extract_markdown(file_path)
    if not markdown_cont or not markdown_cont.strip():
        print(f"[INGEST WARNING] Extracted text from '{filename}' was empty.")
        return {
            "status": "empty_file",
            "filename": filename
        }

    rctp = RecursiveCharacterTextSplitter(
        chunk_size=700,
        chunk_overlap=150,
        separators=["\n## ", "\n### ", "\n\n", "\n", " ", ""],
    )
    chunks = rctp.split_text(markdown_cont)
    print(f"[INGEST] Split '{filename}' into {len(chunks)} chunks.")
    
    embedding_model = OllamaEmbeddings(model="nomic-embed-text")
    vectors = embedding_model.embed_documents(chunks)

    records = []
    for idx, (chunk_text, vector) in enumerate(zip(chunks, vectors)):
        records.append({
            "id": f"{file_hash}_{idx}",
            "vector": vector,
            "text": chunk_text,
            "source": filename,
            "chat_id": chat_id,
            "file_hash": file_hash
        })
    
    if table is None:
        db.create_table('documents', data=records)
    else:
        table.add(records)

    print(f"[INGEST SUCCESS] Stored {len(records)} vector records for '{filename}'")
    return {
        "status": "success",
        "chunks_indexed": len(records), 
        "filename": filename
    }