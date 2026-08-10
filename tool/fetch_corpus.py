"""
Fetches plaintext Wikipedia extracts for a spread of core Biology topics
and writes them to biology_corpus.txt - the training corpus
train_embeddings.py uses to build the on-device term-embedding model (see
that file for why: rule-based question generation stays as-is, only
distractor relevance scoring is ML-assisted).

Run from anywhere - paths are relative to this script's own location, not
the working directory:

    python tool/fetch_corpus.py

Wikipedia's API is rate-limited (HTTP 429 under a burst of requests), so
each fetch backs off and retries automatically rather than needing a
separate manual retry pass.
"""
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

TOPICS = [
    "Cell (biology)", "Cell membrane", "Mitochondrion", "Chloroplast",
    "Photosynthesis", "Cellular respiration", "DNA", "RNA", "Gene",
    "Genetics", "Mendelian inheritance", "Mitosis", "Meiosis", "Protein",
    "Enzyme", "Homeostasis", "Evolution", "Natural selection", "Ecosystem",
    "Ecology", "Food chain", "Human digestive system",
    "Circulatory system", "Respiratory system", "Nervous system",
    "Immune system", "Osmosis", "Diffusion", "Taxonomy (biology)",
    "Biodiversity", "Reproduction", "Plant", "Bacteria", "Virus",
    "Photosystem", "Amino acid", "Carbohydrate", "Lipid",
    "Nucleic acid", "Chromosome", "Stem cell", "Tissue (biology)",
    "Organ (biology)", "Skeletal system", "Muscular system",
    "Endocrine system", "Hormone", "Excretory system", "Kidney",
    "Photoreceptor cell", "Nutrient cycle",
]

API = "https://en.wikipedia.org/w/api.php"
HEADERS = {
    "User-Agent": "GenBioCapstone/1.0 (educational offline app corpus "
                  "collection; contact: thesiscpe837@gmail.com)"
}

OUT_PATH = Path(__file__).parent / "biology_corpus.txt"


def fetch_one(title: str) -> str | None:
    params = {
        "action": "query", "prop": "extracts", "explaintext": "1",
        "format": "json", "titles": title, "redirects": "1",
    }
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=HEADERS)

    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.load(resp)
            pages = data["query"]["pages"]
            page = next(iter(pages.values()))
            extract = page.get("extract", "")
            if not extract or len(extract) < 200:
                return None
            # Strip section headers like "== History ==" - we want prose,
            # not the wiki markup structure around it.
            extract = re.sub(r"={2,}[^=]+={2,}", " ", extract)
            return re.sub(r"\s+", " ", extract).strip()
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 3:
                time.sleep(5 * attempt)
                continue
            print(f"  failed: {title} ({e})")
            return None
        except Exception as e:
            print(f"  failed: {title} ({e})")
            return None
    return None


def main():
    ok = 0
    with open(OUT_PATH, "w", encoding="utf-8") as out:
        for title in TOPICS:
            extract = fetch_one(title)
            if extract:
                out.write(extract + "\n\n")
                ok += 1
            time.sleep(1.5)  # stay well under Wikipedia's rate limit
    print(f"Fetched {ok}/{len(TOPICS)} articles into {OUT_PATH}")


if __name__ == "__main__":
    main()
