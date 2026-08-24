# 🎓 StudentRAG

<p align="center">
  <img src="https://img.shields.io/badge/Frontend-Flutter-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Backend-Python_3.10+-3776AB?logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/Vector_DB-LanceDB-FF4F00" alt="LanceDB">
  <img src="https://img.shields.io/badge/Local_LLM-Ollama-000000?logo=ollama&logoColor=white" alt="Ollama">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License">
</p>

<p align="center">
  <b>Chat with your local documents. 100% offline. 100% private.</b>
</p>

StudentRAG is a privacy-first desktop application designed for students, researchers, and professionals. It lets you "chat" with your local documents using advanced Retrieval-Augmented Generation (RAG) — without sending a single byte of data to the cloud.

---

## 📸 Preview

> 
>
<table>
  <tr>
    <td><img src="https://github.com/sibghatullah-1/StudentRAG/blob/c29c7192744c0e8f48613e37f755518248d2ad69/Screenshot%202026-08-24%20215956.png" width="300" alt="Photo 1 description"/></td>
    <td><img src="https://github.com/sibghatullah-1/StudentRAG/blob/c29c7192744c0e8f48613e37f755518248d2ad69/Screenshot%202026-08-24%20220015.png" width="300" alt="Photo 2 description"/></td>
    <td><img src="https://github.com/sibghatullah-1/StudentRAG/blob/c29c7192744c0e8f48613e37f755518248d2ad69/Screenshot%202026-08-24%20220051.png" width="300" alt="Photo 3 description"/></td>
  </tr>
</table>

https://github.com/user-attachments/assets/844b6363-5b9b-42a0-b0a9-6150a1b587d4

---

## ✨ Features

| | |
|---|---|
| 🔒 **100% Local & Private** | Everything runs on your machine using local LLMs via Ollama. No API keys, no subscriptions, zero data leakage. |
| 📄 **Universal Document Support** | Attach and query multiple file types at once — `.pdf`, `.docx`, `.pptx`, `.txt`, `.md` — powered by PyMuPDF and Microsoft's MarkItDown. |
| 🧠 **Smart Auto-Titling** | Chats are automatically titled using fast local AI generation, similar to Gemini/ChatGPT. |
| 💾 **Context Memory** | Instantly clear context or export entire conversations to Markdown. |
| 🎨 **Fluid UI** | Draggable sidebar, markdown-rendered code blocks, and source-citation tooltips so you always know which document the AI pulled its answer from. |
| 🌌 **3D Vector Visualization** | Click the scatter-plot icon to open an interactive 3D graph of your document embeddings, using PCA to map high-dimensional chunks into browsable 3D space. |

---

## 🏗️ How It Works (Architecture)

StudentRAG uses a **sidecar pattern**, bridging a high-performance Dart frontend with a heavy data-science Python backend.

```
┌─────────────────────┐        ┌──────────────────────────┐
│   Flutter Frontend   │◄──────►│   FastAPI Python Backend  │
│  (Windows Desktop)   │  IPC   │      (Sidecar Process)    │
└─────────────────────┘        └──────────────────────────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    ▼                     ▼                     ▼
              LangChain            nomic-embed-text          LanceDB
             (chunking)              (embeddings)          (vector store)
                                          │
                                          ▼
                                       Ollama
                                  (local LLM inference)
```

1. **The UI (Flutter)** — Provides a fluid, native Windows desktop experience. Handles state management, local persistence (`shared_preferences`), UI animations, and Markdown rendering.
2. **The Microservice (FastAPI/Python)** — Packaged as a standalone executable and launched silently by the frontend. It handles:
   - Chunking documents with **LangChain**
   - Generating embeddings via **`nomic-embed-text`**
   - Storing and retrieving vectors with **LanceDB** (an ultra-fast Apache Arrow columnar database)
   - Routing conversational prompts to your local **Ollama** instance

---

## 🚀 Getting Started

### Prerequisites

Since StudentRAG runs entirely offline, you'll need [Ollama](https://ollama.com/) installed to run the models.

```bash
# 1. Install Ollama, then pull the embedding model
ollama pull nomic-embed-text

# 2. Pull a reasoning model of your choice
ollama pull llama3.2
```

### Installation (Windows)

1. Go to the [Releases](https://github.com/sibghatullah-1/StudentRAG/releases) page.
2. Download the latest `StudentRAG_Setup.exe`.
3. Run the installer and launch the app.
4. Select your preferred local model from the dropdown, attach your study materials, and start chatting!

---

## 🛠️ For Developers (Running from Source)

```bash
# Clone the repository
git clone https://github.com/sibghatullah-1/StudentRAG.git
cd StudentRAG

# Set up the Python backend
cd backend-ai
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
python main.py
```

In a separate terminal:

```bash
# Launch the Flutter frontend
flutter pub get
flutter run -d windows
```

---

## 🗺️ Roadmap

- [ ] macOS / Linux builds
- [ ] Support for additional local model backends
- [ ] In-app model manager (pull/switch models without the CLI)

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/sibghatullah-1/StudentRAG/issues).

## 📄 License

This project is open-source and available under the [MIT License](LICENSE).
