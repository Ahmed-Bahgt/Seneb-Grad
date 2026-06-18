import os
import pickle
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

GUIDELINES_DIR = "clinical_guidelines"
VECTOR_STORE_PATH = "rag_vector_store.pkl"

def chunk_text(text, chunk_size=500, overlap=100):
    """Splits text into overlapping chunks for better retrieval precision."""
    words = text.split()
    chunks = []
    for i in range(0, len(words), chunk_size - overlap):
        chunk = " ".join(words[i:i + chunk_size])
        chunks.append(chunk)
    return chunks

def build_vector_store():
    print("="*60)
    print("Building Local RAG Vector Database")
    print("="*60)
    
    documents = []
    metadata = []
    
    if not os.path.exists(GUIDELINES_DIR):
        print(f"Error: Directory {GUIDELINES_DIR} does not exist.")
        return

    # Read all text files from the guidelines directory
    for filename in os.listdir(GUIDELINES_DIR):
        if filename.endswith(".txt"):
            filepath = os.path.join(GUIDELINES_DIR, filename)
            with open(filepath, "r", encoding="utf-8") as f:
                content = f.read()
                
            # Chunk the document
            chunks = chunk_text(content)
            for i, chunk in enumerate(chunks):
                documents.append(chunk)
                metadata.append({
                    "source": filename,
                    "chunk_id": i
                })
            print(f"[+] Processed {filename} -> {len(chunks)} chunks.")

    if not documents:
        print("No documents found to process.")
        return

    print("\n[*] Vectorizing documents using TF-IDF...")
    vectorizer = TfidfVectorizer(stop_words='english')
    tfidf_matrix = vectorizer.fit_transform(documents)

    # Save the vector store
    print(f"[*] Saving vector store to {VECTOR_STORE_PATH}...")
    with open(VECTOR_STORE_PATH, "wb") as f:
        pickle.dump({
            "vectorizer": vectorizer,
            "tfidf_matrix": tfidf_matrix,
            "documents": documents,
            "metadata": metadata
        }, f)

    print("="*60)
    print("RAG Database successfully built and saved!")
    print(f"Indexed {len(documents)} total text chunks.")
    print("="*60)

def retrieve_guidelines(query, top_k=3):
    """Retrieves the top-k most relevant chunks for a given query."""
    if not os.path.exists(VECTOR_STORE_PATH):
        print("Vector store not found. Building it now...")
        build_vector_store()

    try:
        with open(VECTOR_STORE_PATH, "rb") as f:
            data = pickle.load(f)
    except Exception as e:
        print(f"Error loading vector store (likely scikit-learn version mismatch): {e}")
        print("Rebuilding vector store...")
        build_vector_store()
        with open(VECTOR_STORE_PATH, "rb") as f:
            data = pickle.load(f)
    
    vectorizer = data["vectorizer"]
    tfidf_matrix = data["tfidf_matrix"]
    documents = data["documents"]
    metadata = data["metadata"]

    query_vec = vectorizer.transform([query])
    similarities = cosine_similarity(query_vec, tfidf_matrix).flatten()
    
    # Get top_k indices
    top_indices = similarities.argsort()[-top_k:][::-1]
    
    results = []
    for idx in top_indices:
        if similarities[idx] > 0.05:  # Relevance threshold
            results.append({
                "text": documents[idx],
                "score": similarities[idx],
                "metadata": metadata[idx]
            })
            
    return results

if __name__ == "__main__":
    build_vector_store()
