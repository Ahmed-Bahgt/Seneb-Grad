import os
import json
import re
import time
import requests
from Bio import Entrez
import google.generativeai as genai

# --- CONFIGURATION ---
GEMINI_API_KEY = "YOUR_GEMINI_API_KEY_HERE"
GEMINI_MODEL = "gemini-2.5-flash"  # Highly efficient for RAG
ENTREZ_EMAIL = "your_medical_app@example.com"  # PubMed requirement

class MedicalService:
    def __init__(self):
        genai.configure(api_key=GEMINI_API_KEY)
        self.model = genai.GenerativeModel(GEMINI_MODEL)
        Entrez.email = ENTREZ_EMAIL
        Entrez.tool = "TamrenTechMedicalAssistant"

    def safe_generate(self, contents):
        for _ in range(3):
            try:
                res = self.model.generate_content(contents)
                if res and res.text: return res.text
            except Exception as e:
                print(f"Gemini Error: {e}")
                time.sleep(1.5)
        return "I apologize, but I am unable to generate a response at the moment."

    def search_pubmed(self, query, max_results=3):
        """Search PubMed for the latest medical research."""
        try:
            print(f"🔍 Searching PubMed for: {query[:50]}...")
            handle = Entrez.esearch(db="pubmed", term=query, retmax=max_results, sort="relevance")
            record = Entrez.read(handle)
            pmids = record["IdList"]
            handle.close()

            if not pmids: return []

            handle = Entrez.efetch(db="pubmed", id=pmids, retmode="xml")
            articles = Entrez.read(handle)
            handle.close()

            results = []
            for article in articles.get("PubmedArticle", []):
                try:
                    citation = article["MedlineCitation"]
                    title = citation["Article"]["ArticleTitle"]
                    abstract = ""
                    if "Abstract" in citation["Article"]:
                        abstract_parts = citation["Article"]["Abstract"]["AbstractText"]
                        abstract = " ".join([str(p) for p in abstract_parts]) if isinstance(abstract_parts, list) else str(abstract_parts)
                    
                    journal = citation["Article"]["Journal"]["Title"]
                    year = citation["Article"]["Journal"]["JournalIssue"]["PubDate"].get("Year", "N/A")
                    pmid = citation["PMID"]
                    
                    results.append({
                        "title": title,
                        "abstract": abstract[:1000] + "..." if len(abstract) > 1000 else abstract,
                        "journal": f"{journal} ({year})",
                        "link": f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/"
                    })
                except: continue
            return results
        except Exception as e:
            print(f"PubMed Error: {e}")
            return []

    def medical_chat(self, question, context_type="general"):
        """Main entry point for medical chat with RAG."""
        # 1. Search PubMed for context
        research = self.search_pubmed(question)
        
        context_text = ""
        if research:
            context_text = "\n\nRELEVANT PUBMED RESEARCH:\n"
            for i, res in enumerate(research, 1):
                context_text += f"[{i}] {res['title']} - {res['journal']}\nKey Findings: {res['abstract']}\n\n"

        # 2. Construct Prompt based on context_type
        system_instructions = {
            "general": "You are an expert Medical Research Assistant for Doctors.",
            "clinical": "You are a Clinical Diagnostician helping with a case analysis.",
            "terms": "You are a Medical Educator simplifying complex terms."
        }
        
        prompt = f"""
        {system_instructions.get(context_type, system_instructions['general'])}
        
        USER QUESTION: {question}
        {context_text}
        
        STRICT RULES:
        1. Be highly professional, evidence-based, and concise.
        2. Use bullet points for recommendations or findings.
        3. Cite the PubMed sources using [1], [2], etc. when referencing their data.
        4. Use bold text for key medical terms.
        5. If research is found, summarize the consensus. If not, state that based on general medical knowledge.
        6. Use Emojis for sections: 🔬 (Research), 📋 (Recommendations), ⚠️ (Precautions).
        7. If asked about a clinical case, provide: Differential Diagnosis, Suggested Tests, and Treatment Approaches.
        """
        
        return self.safe_generate(prompt)

medical_service = MedicalService()
