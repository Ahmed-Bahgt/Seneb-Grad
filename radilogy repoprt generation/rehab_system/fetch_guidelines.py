import os
import json
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
import time

# Directory to save guidelines
SAVE_DIR = "clinical_guidelines"
os.makedirs(SAVE_DIR, exist_ok=True)

# List of broad musculoskeletal topics to fetch clinical guidelines for
TOPICS = [
    "Distal Radius Fracture Rehabilitation Guideline",
    "Osteoarthritis Knee Physical Therapy Protocol",
    "Shoulder Rotator Cuff Tear Conservative Management",
    "Anterior Cruciate Ligament (ACL) Reconstruction Rehab",
    "Hip Arthroplasty Post-Operative Protocol"
]

def search_pmc(query, retmax=1):
    """Search PubMed Central (PMC) for free full-text articles matching the query."""
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
    params = {
        "db": "pmc",
        "term": f"{query} AND open access[filter]",
        "retmode": "json",
        "retmax": retmax
    }
    url = f"{base_url}?{urllib.parse.urlencode(params)}"
    
    print(f"[*] Searching NIH Database for: {query}...")
    try:
        req = urllib.request.urlopen(url)
        data = json.loads(req.read().decode('utf-8'))
        id_list = data.get("esearchresult", {}).get("idlist", [])
        return id_list
    except Exception as e:
        print(f"[-] Failed to search PMC: {e}")
        return []

def fetch_article_text(pmcid):
    """Fetch the full XML text of a PMC article and extract readable paragraphs."""
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    params = {
        "db": "pmc",
        "id": pmcid,
        "retmode": "xml"
    }
    url = f"{base_url}?{urllib.parse.urlencode(params)}"
    
    print(f"    -> Downloading full text for PMC ID: {pmcid}...")
    try:
        req = urllib.request.urlopen(url)
        xml_data = req.read()
        
        # Parse XML
        root = ET.fromstring(xml_data)
        paragraphs = []
        for p in root.iter('p'):
            if p.text:
                # Clean up whitespace
                text = " ".join(p.text.split())
                if len(text) > 50:  # Only keep substantial paragraphs
                    paragraphs.append(text)
        
        return "\n\n".join(paragraphs)
    except Exception as e:
        print(f"[-] Failed to fetch article {pmcid}: {e}")
        return None

def main():
    print("="*60)
    print("NIH / PubMed Clinical Guideline Auto-Fetcher")
    print("="*60)
    print("Connecting to US National Library of Medicine API...\n")
    
    for topic in TOPICS:
        pmc_ids = search_pmc(topic)
        if not pmc_ids:
            print(f"[-] No open access articles found for '{topic}'\n")
            continue
            
        pmcid = pmc_ids[0]
        text_content = fetch_article_text(pmcid)
        
        if text_content:
            # Create a safe filename
            filename = topic.replace(" ", "_").replace("(", "").replace(")", "").lower() + ".txt"
            filepath = os.path.join(SAVE_DIR, filename)
            
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(f"TITLE: {topic}\n")
                f.write(f"SOURCE: PubMed Central (PMC{pmcid})\n")
                f.write("="*50 + "\n\n")
                f.write(text_content)
                
            print(f"[+] Successfully saved {len(text_content)} characters to {filepath}\n")
        
        # Respect NCBI API rate limits (3 requests per second max without API key)
        time.sleep(1)

    print("="*60)
    print("All guidelines downloaded successfully into /clinical_guidelines")
    print("="*60)

if __name__ == "__main__":
    main()
