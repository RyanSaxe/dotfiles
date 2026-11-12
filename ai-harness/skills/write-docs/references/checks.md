# Checks

Run this script from the repository root. For `README.md` and each page under `docs/`, it prints the word count, the
number of paragraphs over 50 words, the relative links and image paths that don't resolve, and whether the page
contains a Mermaid block.

```python
import pathlib
import re

# Tables, headings, lists, quotes and HTML blocks are not paragraphs.
NOT_PROSE = ("|", "#", "-", ">", "<", "1.")
pages = [pathlib.Path("README.md"), *sorted(pathlib.Path("docs").rglob("*.md"))]
for page in pages:
    text = page.read_text()
    prose = re.sub(r"```.*?```", "", text, flags=re.S)
    paragraphs = [block for block in re.split(r"\n\s*\n", prose) if block.strip()]
    prose_blocks = [block for block in paragraphs if not block.lstrip().startswith(NOT_PROSE)]
    long = [block for block in prose_blocks if len(block.split()) > 50]
    broken = [
        target
        for target in re.findall(r'(?:\]\(|src="|srcset=")([^)"#]+)', text)
        if not target.startswith("http") and not (page.parent / target).exists()
    ]
    flags = ["mermaid"] if "```mermaid" in text else []
    print(f"{page}: {len(prose.split())} words, {len(long)} long paragraphs, broken {broken} {flags}")
```

Shorten or split a page over about 600 words. Split each long paragraph, fix each broken path and replace each
Mermaid block with an SVG diagram.
