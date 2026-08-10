"""
Fetches two more OpenStax textbooks (both CC BY 4.0) from their official
GitHub source, the same way fetch_openstax.py already does for Biology 2e -
additional training-corpus sources for train_embeddings.py, added to grow
real vocabulary coverage rather than just raising VOCAB_SIZE on an
unchanged corpus (see the "sapat na ba" follow-up: at min_count>=3 the
original 3-source corpus only had ~12,830 qualifying words, already
against the 12,000 cap - more vocab requires more source text, not a
bigger config number).

Sources (both verified CC BY 4.0 via each repo's own LICENSE file, same
cnx-user-books/Connexions repo layout as cnxbook-biology-2e):
  - github.com/cnx-user-books/cnxbook-concepts-of-biology - OpenStax
    "Concepts of Biology" (non-majors intro). Overlaps Biology 2e's topics
    but in different, simpler phrasing - reinforces borderline-frequency
    terms past the min_count=3 threshold rather than mostly adding brand
    new ones.
  - github.com/cnx-user-books/cnxbook-microbiology - OpenStax
    "Microbiology". Adds vocabulary Biology 2e barely touches (pathogens,
    immune response, lab/staining technique) that's still in-scope for a
    STEM Biology reviewer.

Run from anywhere:  python tool/fetch_openstax_extra.py
"""
import json
import time
import urllib.error
import urllib.request
from pathlib import Path
from xml.etree import ElementTree as ET

HEADERS = {
    "User-Agent": "GenBioCapstone/1.0 (educational offline app corpus "
                  "collection; contact: thesiscpe837@gmail.com)"
}
CNXML_NS = "{http://cnx.rice.edu/cnxml}"
TEXT_TAGS = {
    CNXML_NS + "para", CNXML_NS + "title", CNXML_NS + "item",
    CNXML_NS + "caption",
}

HERE = Path(__file__).parent

BOOKS = [
    ("cnxbook-concepts-of-biology", HERE / "openstax_concepts_corpus.txt"),
    ("cnxbook-microbiology", HERE / "openstax_microbiology_corpus.txt"),
]


def list_module_ids(repo: str) -> list[str]:
    url = f"https://api.github.com/repos/cnx-user-books/{repo}/contents/modules"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as resp:
        entries = json.load(resp)
    return [e["name"] for e in entries if e["type"] == "dir"]


def fetch_module_text(repo: str, module_id: str) -> str | None:
    url = (f"https://raw.githubusercontent.com/cnx-user-books/{repo}/main/"
           f"modules/{module_id}/index.cnxml")
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            xml_bytes = resp.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
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


def fetch_book(repo: str, out_path: Path) -> None:
    module_ids = list_module_ids(repo)
    print(f"Fetching {len(module_ids)} modules from {repo}...")

    ok = 0
    with open(out_path, "w", encoding="utf-8") as out:
        for i, module_id in enumerate(module_ids):
            text = fetch_module_text(repo, module_id)
            if text:
                out.write(text + "\n\n")
                ok += 1
            if (i + 1) % 50 == 0:
                print(f"  ...{i + 1}/{len(module_ids)} processed, {ok} usable so far")
            time.sleep(0.15)

    size = out_path.stat().st_size
    print(f"Fetched {ok}/{len(module_ids)} usable modules -> {out_path} ({size:,} bytes)")


def main():
    for repo, out_path in BOOKS:
        fetch_book(repo, out_path)


if __name__ == "__main__":
    main()
