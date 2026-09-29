"""MkDocs-Hook: Links aus docs/ heraus auf GitHub umleiten.

Die Kapitel verlinken auf Dateien außerhalb von docs/, z. B. ../kubernetes/apps/…
oder ../examples/…. Auf GitHub funktioniert das direkt, auf der Website gibt es diese
Dateien aber nicht. Der Hook schreibt solche Links auf die GitHub-Ansicht um.
"""

import re

REPO = "https://github.com/Katagawa94/homelab-tutorial"
BRANCH = "main"

# ](../pfad) oder ](../pfad#anker), aber keine Bilder/Links innerhalb von docs/
LINK = re.compile(r"\]\(\.\./(?P<path>[^)#\s]+)(?P<anchor>#[^)\s]*)?\)")


def _github_url(path: str) -> str:
    # Ordner (enden auf / oder haben keine Dateiendung) → /tree/, Dateien → /blob/
    last = path.rstrip("/").rsplit("/", 1)[-1]
    kind = "tree" if path.endswith("/") or "." not in last else "blob"
    return f"{REPO}/{kind}/{BRANCH}/{path.rstrip('/')}"


def on_page_markdown(markdown, page, config, files):
    def replace(match):
        url = _github_url(match["path"]) + (match["anchor"] or "")
        return f"]({url})"

    return LINK.sub(replace, markdown)
