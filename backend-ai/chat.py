import os
import lancedb
from langchain_ollama import OllamaEmbeddings, ChatOllama
from langchain_core.prompts import ChatPromptTemplate
from langchain_classic.chains.combine_documents import create_stuff_documents_chain
from langchain_core.documents import Document
from langchain_core.output_parsers import StrOutputParser

# FIX: Match the AppData path used in main.py
appdata_dir = os.getenv('APPDATA')
# if appdata_dir:
DB_PATH = os.path.join(appdata_dir, "StudentRAG", "lancedb")
# else:
#     DB_PATH = os.path.expanduser("~/.student_rag/lancedb")
os.makedirs(DB_PATH, exist_ok=True)

def initialize_components(model_name: str = "qwen2.5:3b"):
    db = lancedb.connect(DB_PATH)
    embedding_question = OllamaEmbeddings(model="nomic-embed-text")
    chatmodel = ChatOllama(model=model_name, temperature=0)
    return db, embedding_question, chatmodel 

def get_answer(user_query: str, chat_history: list, chat_id: str, model_name: str = "qwen2.5:3b", attached_files: list = []):
    db, embeddings, chatmodel = initialize_components(model_name=model_name)

    formatted_history = []
    if chat_history:
        for msg in chat_history:
            role = msg.get("role", "human")
            content = msg.get("content", "")
            if role in ["human", "user"]:
                formatted_history.append(("human", content))
            elif role in ["ai", "assistant"]:
                formatted_history.append(("ai", content))

    if formatted_history:
        rephrase_prompt = ChatPromptTemplate.from_messages([
            ("system", "Given a chat history and the latest user question which might reference context in the chat history, formulate a standalone question which can be understood without the chat history. Do NOT answer the question, just reformulate it if needed and otherwise return it as is."),
            ("placeholder", "{chat_history}"),
            ("human", "{input}"),
        ])
        rewriter_chain = rephrase_prompt | chatmodel | StrOutputParser()
        search_query = rewriter_chain.invoke({
            "chat_history": formatted_history, 
            "input": user_query
        })
    else:
        search_query = user_query

    try:
        table = db.open_table('documents')
    except Exception:
        return {"text": "No documents have been uploaded or indexed yet for this workspace.", "sources": []}

    query_vec = embeddings.embed_query(search_query)
    
    # FIX: Increased limit from 4 to 6 to capture more relevant chunks (fixing the "Part A" context loss)
    raw_results = table.search(query_vec).where(f"chat_id = '{chat_id}'").limit(6).to_list()

    docs = []
    for result in raw_results:
        source_path = result.get("source", "Unknown Document")
        filename = os.path.basename(str(source_path))
        tagged_text = f"[Source File: {filename}]\n{result['text']}"
        docs.append(Document(page_content=tagged_text, metadata=result))

    if not docs:
        return {"text": "I couldn't find any relevant information in the attached documents for this query.", "sources": []}

    files_str = "\n- ".join(attached_files) if attached_files else "None"

    qa_prompt = ChatPromptTemplate.from_messages([
        ("system", 
         "You are a helpful AI study assistant.\n"
         f"Currently uploaded documents for this chat session:\n- {files_str}\n\n"
         "Guidelines:\n"
         "1. If the user asks what documents or files are uploaded, list the document names from above.\n"
         "2. For questions about document content, answer accurately using the retrieved context below.\n"
         "3. If the answer is not present in the context, state that you do not know.\n\n"
         "Retrieved Context:\n{context}"),
        ("placeholder", "{chat_history}"),
        ("human", "{input}"),
    ])

    question_answer_chain = create_stuff_documents_chain(chatmodel, qa_prompt)
    
    response = question_answer_chain.invoke({
        "context": docs,         
        "input": user_query,
        "chat_history": formatted_history
    })

    sources_list = []
    for d in docs:
        clean_text = d.page_content.split("]\n")[-1] if "]\n" in d.page_content else d.page_content
        sources_list.append({
            "source": d.metadata.get("source", "Unknown Document"),
            "text": clean_text[:200] + "..."
        })

    return {
        "text": response,
        "sources": sources_list
    }