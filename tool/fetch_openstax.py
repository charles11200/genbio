"""
Fetches OpenStax Biology 2e's section text (CC BY 4.0) from its official
GitHub source and writes it to openstax_biology_corpus.txt - a third
training-corpus source alongside biology_corpus.txt (Wikipedia) and
questions_corpus.txt (self-authored question bank), for
train_embeddings.py.

Source: github.com/cnx-user-books/cnxbook-biology-2e (the canonical
Connexions/OpenStax repo for this exact book - CC BY 4.0, safe to reuse
including for derived training data). Fetches each module's index.cnxml
(a small, text-only XML file per section - NOT the repo's ~480MB media/
folder, which we don't need or clone) via raw.githubusercontent.com and
strips the CNXML markup down to plain prose.

Run from anywhere:  python tool/fetch_openstax.py
"""
import json
import time
import urllib.error
import urllib.request
from pathlib import Path
from xml.etree import ElementTree as ET

REPO_API = "https://api.github.com/repos/cnx-user-books/cnxbook-biology-2e/contents/modules"
RAW_BASE = "https://raw.githubusercontent.com/cnx-user-books/cnxbook-biology-2e/main/modules"
HEADERS = {
    "User-Agent": "GenBioCapstone/1.0 (educational offline app corpus "
                  "collection; contact: thesiscpe837@gmail.com)"
}
CNXML_NS = "{http://cnx.rice.edu/cnxml}"
# Text-bearing tags worth extracting; explicitly skips <metadata> (uuids,
# ids - not prose) and figure/media elements (image refs, not text).
TEXT_TAGS = {
    CNXML_NS + "para", CNXML_NS + "title", CNXML_NS + "item",
    CNXML_NS + "caption",
}

HERE = Path(__file__).parent
OUT_PATH = HERE / "openstax_biology_corpus.txt"


def list_module_ids() -> list[str]:
    """Discovers module directory names from the repo itself via the
    GitHub contents API, rather than a hardcoded/pre-saved list - keeps
    this script fully self-contained and re-runnable standalone."""
    req = urllib.request.Request(REPO_API, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as resp:
        entries = json.load(resp)
    return [e["name"] for e in entries if e["type"] == "dir"]


def fetch_module_text(module_id: str) -> str | None:
    url = f"{RAW_BASE}/{module_id}/index.cnxml"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            xml_bytes = resp.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None  # some module dirs use a different filename - skip
        print(f"  failed: {module_id} ({e})")
        return None
    except Exception as e:
        print(f"  failed: {module_id} ({e})")
        return None

    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError as e:
        print(f"  parse failed: {module_id} ({e})")
        return None

    content = root.find(f"{CNXML_NS}content")
    if content is None:
        return None
    parts = []
    for el in content.iter():
        if el.tag in TEXT_TAGS and el.text:
            parts.append(el.text.strip())
        if el.tail and el.tail.strip():
            parts.append(el.tail.strip())
    text = " ".join(p for p in parts if p)
    return text if len(text) > 100 else None


def main():
    module_ids = list_module_ids()
    print(f"Fetching {len(module_ids)} OpenStax Biology 2e modules...")

    ok = 0
    with open(OUT_PATH, "w", encoding="utf-8") as out:
        for i, module_id in enumerate(module_ids):
            text = fetch_module_text(module_id)
            if text:
                out.write(text + "\n\n")
                ok += 1
            if (i + 1) % 50 == 0:
                print(f"  ...{i + 1}/{len(module_ids)} processed, {ok} usable so far")
            time.sleep(0.15)  # be a reasonable citizen even though raw.githubusercontent.com isn't as tightly rate-limited as an API

    size = OUT_PATH.stat().st_size
    print(f"Fetched {ok}/{len(module_ids)} usable modules -> {OUT_PATH} ({size:,} bytes)")


if __name__ == "__main__":
    main()
