#!/usr/bin/env python3
"""Package TeX4ht output as a self-contained, phone-first HTML document."""

from __future__ import annotations

import argparse
import base64
import html
import mimetypes
import re
from pathlib import Path


MOBILE_CSS = r"""
:root {
  color-scheme: light dark;
  --bg: #edf2f7;
  --paper: #ffffff;
  --text: #172033;
  --muted: #64748b;
  --line: #d8e1eb;
  --accent: #175f91;
  --accent-soft: #e7f2f9;
  --code-bg: #f2f6fa;
  --shadow: 0 16px 44px rgba(24, 42, 68, 0.12);
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0f1724;
    --paper: #172131;
    --text: #edf4fb;
    --muted: #a9b7c8;
    --line: #344357;
    --accent: #78c6f3;
    --accent-soft: #223b4e;
    --code-bg: #101a28;
    --shadow: 0 18px 50px rgba(0, 0, 0, 0.32);
  }
}

* { box-sizing: border-box; }
html { scroll-behavior: smooth; -webkit-text-size-adjust: 100%; }
body {
  margin: 0 !important;
  max-width: none !important;
  padding: 0 !important;
  background: var(--bg);
  color: var(--text);
  font-family: Iowan Old Style, Charter, Georgia, Cambria, serif;
  font-size: 18px;
  line-height: 1.62;
  overflow-wrap: anywhere;
}

.skip-link {
  position: fixed;
  left: 12px;
  top: -80px;
  z-index: 100;
  padding: 8px 12px;
  background: var(--paper);
  color: var(--accent);
  border-radius: 8px;
}
.skip-link:focus { top: 12px; }

.mobile-bar {
  position: sticky;
  top: 0;
  z-index: 50;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 50px;
  padding: 9px max(14px, env(safe-area-inset-right)) 9px max(14px, env(safe-area-inset-left));
  border-bottom: 1px solid color-mix(in srgb, var(--line) 75%, transparent);
  background: color-mix(in srgb, var(--paper) 92%, transparent);
  backdrop-filter: blur(14px);
  -webkit-backdrop-filter: blur(14px);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
.mobile-bar strong { font-size: 0.95rem; letter-spacing: 0.01em; }
.mobile-bar nav { display: flex; gap: 8px; }
.mobile-bar a {
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 4px 10px;
  color: var(--accent);
  font-size: 0.78rem;
  font-weight: 700;
  text-decoration: none;
}

.report-shell {
  width: min(100% - 24px, 860px);
  margin: 18px auto 48px;
  padding: clamp(24px, 5vw, 58px);
  border: 1px solid var(--line);
  border-radius: 22px;
  background: var(--paper);
  box-shadow: var(--shadow);
}

.edition-note {
  display: inline-flex;
  align-items: center;
  margin-bottom: 18px;
  padding: 5px 10px;
  border: 1px solid var(--line);
  border-radius: 999px;
  color: var(--muted);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.maketitle { margin: 0 0 2rem; text-align: left !important; }
h2.titleHead {
  margin: 0 0 0.7rem;
  color: var(--text);
  font-size: clamp(2.1rem, 8vw, 3.8rem);
  line-height: 1.04;
  letter-spacing: -0.035em;
}
.author, .date { color: var(--muted); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
.author { font-weight: 700; }
.date { font-size: 0.88rem; line-height: 1.45; }

.abstract {
  width: auto !important;
  margin: 1.4rem 0 1.6rem;
  padding: 1rem 1.1rem 0.9rem;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: color-mix(in srgb, var(--accent-soft) 55%, var(--paper));
}
.abstract p { margin: 0 !important; }
.abstracttitle { margin: 0 0 0.45rem; color: var(--accent); font-size: 1rem; }

div.colorbox {
  margin: 1.3rem 0 1.6rem !important;
  padding: 1rem 1.1rem !important;
  border: 0 !important;
  border-left: 5px solid var(--accent) !important;
  border-radius: 10px;
  background: var(--accent-soft) !important;
  color: var(--text) !important;
}
div.minipage { width: auto !important; }

.toc {
  margin: 1.8rem 0 2.4rem;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: color-mix(in srgb, var(--paper) 84%, var(--accent-soft));
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
.toc summary {
  cursor: pointer;
  padding: 0.85rem 1rem;
  color: var(--accent);
  font-weight: 800;
}
.toc .tableofcontents { padding: 0 1rem 1rem; font-size: 0.88rem; line-height: 1.7; }
.toc .tableofcontents a { text-decoration: none; }

h3.sectionHead, h3.likesectionHead {
  margin: 2.7rem 0 0.9rem;
  padding-top: 0.5rem;
  color: var(--text);
  font-size: clamp(1.55rem, 6vw, 2.2rem);
  line-height: 1.17;
  letter-spacing: -0.022em;
}
h4.subsectionHead {
  margin: 2rem 0 0.65rem;
  color: var(--text);
  font-size: clamp(1.18rem, 4.7vw, 1.5rem);
  line-height: 1.25;
}
h5.subsubsectionHead { font-size: 1.05rem; }
.titlemark { color: var(--accent); }

p { margin: 0.76rem 0; }
ul, ol { padding-left: 1.35rem; }
li { margin: 0.34rem 0; }
a { color: var(--accent); text-decoration-thickness: 0.08em; text-underline-offset: 0.14em; }
math { color: inherit; font-size: 1.02em; }

.table-scroll {
  width: 100%;
  margin: 1rem 0 1.25rem;
  overflow-x: auto;
  overscroll-behavior-inline: contain;
  -webkit-overflow-scrolling: touch;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: var(--paper);
}
.table-scroll:focus { outline: 3px solid color-mix(in srgb, var(--accent) 35%, transparent); }
.table-scroll table { margin: 0 !important; border: 0 !important; }
table.tabular, table.longtable { min-width: 610px; border-collapse: collapse; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 0.83rem; line-height: 1.35; }
table.tabular td, table.longtable td { padding: 0.46rem 0.55rem; border-bottom: 1px solid var(--line); }
table.equation, table.equation-star { min-width: max-content; padding: 0.55rem; }
td.eq-no { width: auto !important; padding-left: 0.8rem; color: var(--muted); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 0.8rem; }

pre.lstlisting {
  max-width: 100%;
  margin: 1rem 0 1.3rem;
  padding: 1rem !important;
  overflow-x: auto;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: var(--code-bg) !important;
  color: var(--text) !important;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.79rem;
  line-height: 1.52;
  tab-size: 2;
  -webkit-overflow-scrolling: touch;
}

.report-figure {
  display: block;
  width: 100% !important;
  height: auto !important;
  margin: 1.4rem auto 0.7rem;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: #fff;
}
div.caption, figcaption.caption {
  margin: 0.5rem 0 1.5rem !important;
  text-align: left !important;
  text-indent: 0 !important;
  color: var(--muted);
  font-size: 0.84rem;
  line-height: 1.45;
}

.thebibliography { font-size: 0.88rem; }
p.bibitem, p.bibitem-p { overflow-wrap: anywhere; }
.footnote-text { font-size: 0.82rem; }

.mobile-footer {
  margin-top: 3rem;
  padding-top: 1.2rem;
  border-top: 1px solid var(--line);
  color: var(--muted);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 0.78rem;
  text-align: center;
}

@media (max-width: 640px) {
  body { font-size: 17px; line-height: 1.58; background: var(--paper); }
  .mobile-bar { min-height: 48px; }
  .mobile-bar strong span { display: none; }
  .report-shell {
    width: 100%;
    margin: 0;
    padding: 26px 16px max(40px, env(safe-area-inset-bottom));
    border: 0;
    border-radius: 0;
    box-shadow: none;
  }
  h2.titleHead { font-size: clamp(2rem, 10.5vw, 2.75rem); }
  h3.sectionHead, h3.likesectionHead { scroll-margin-top: 58px; }
  .abstract, div.colorbox { padding: 0.9rem !important; }
  table.tabular, table.longtable { font-size: 0.78rem; }
  .table-scroll { margin-left: 0; margin-right: 0; }
  pre.lstlisting { margin-left: 0; margin-right: 0; font-size: 0.74rem; }
}

@media print {
  body { background: #fff; color: #000; font-size: 11pt; }
  .mobile-bar, .skip-link, .edition-note { display: none; }
  .report-shell { width: 100%; margin: 0; padding: 0; border: 0; box-shadow: none; }
  .toc { break-after: page; }
  .table-scroll { overflow: visible; border: 0; }
  .report-figure { break-inside: avoid; }
}
"""


FIGURE_ALTS = {
    "graph_concepts": "Graph-theory concepts: direction, paths, weak connectivity, and strong connectivity.",
    "veneto_network": "High-flow core of the Veneto firm mobility network, with directed worker flows between 24 anonymized firms.",
    "rank_comparison": "Scatterplot comparing Sorkin and Bradley-Terry firm-rank percentiles in the Veneto example.",
    "akm_comparison": "Scatterplots comparing flow-ranking percentiles with the two-period AKM-style benchmark.",
}


def data_uri(path: Path) -> str:
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    payload = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{payload}"


def embed_images(document: str, base_dir: Path) -> str:
    pattern = re.compile(r"<img\s+([^>]*?)src=(['\"])(.*?)\2([^>]*)>", re.IGNORECASE)

    def replace(match: re.Match[str]) -> str:
        before, _quote, source, after = match.groups()
        asset = (base_dir / source.replace("//", "/")).resolve()
        if not asset.is_file():
            raise FileNotFoundError(f"HTML image is missing: {asset}")
        key = next((name for name in FIGURE_ALTS if name in asset.name), "")
        alt = FIGURE_ALTS.get(key, "Technical report figure")
        attributes = re.sub(r"\s*alt=(['\"]).*?\1", "", before + after, flags=re.IGNORECASE)
        attributes = re.sub(r"\s*(height|width)=(['\"]).*?\2", "", attributes, flags=re.IGNORECASE)
        return (
            f'<img class="report-figure" alt="{html.escape(alt, quote=True)}" '
            f'src="{data_uri(asset)}" loading="lazy" decoding="async"{attributes}>'
        )

    return pattern.sub(replace, document)


def package_html(source_html: Path, source_css: Path, output: Path) -> None:
    document = source_html.read_text(encoding="utf-8")
    css = source_css.read_text(encoding="utf-8")

    document = re.sub(
        r"<title>.*?</title>",
        "<title>Firm Rankings from Worker Flows · ferank Technical Guide</title>",
        document,
        count=1,
        flags=re.DOTALL | re.IGNORECASE,
    )
    document = re.sub(r"<link\b[^>]*rel=['\"]stylesheet['\"][^>]*/?>", "", document, flags=re.IGNORECASE)
    document = document.replace("<html lang='en-US' xml:lang='en-US'>", "<html lang='en'>")
    head_additions = (
        "<meta name='theme-color' content='#175f91'>\n"
        "<meta name='apple-mobile-web-app-capable' content='yes'>\n"
        "<meta name='format-detection' content='telephone=no'>\n"
        "<meta name='description' content='A technical guide to ferank for labor economists, with graph theory, estimators, command details, and a worked Veneto example.'>\n"
        f"<style>\n{css}\n{MOBILE_CSS}\n</style>\n"
    )
    document = document.replace("</head>", f"{head_additions}</head>", 1)
    document = embed_images(document, source_html.parent)

    toc_pattern = re.compile(
        r"<h3 class=['\"]likesectionHead['\"] id=['\"]contents['\"]>.*?</h3>\s*"
        r"(<div class=['\"]tableofcontents['\"]>.*?</div>)",
        re.DOTALL | re.IGNORECASE,
    )
    document, toc_count = toc_pattern.subn(
        r"<details class='toc' id='contents'><summary>Contents</summary>\1</details>", document, count=1
    )
    if toc_count != 1:
        raise RuntimeError("could not locate and transform the table of contents")

    document = re.sub(
        r"<table\b",
        "<div class='table-scroll' role='region' aria-label='Scrollable table or equation' tabindex='0'><table",
        document,
        flags=re.IGNORECASE,
    )
    document = re.sub(r"</table>", "</table></div>", document, flags=re.IGNORECASE)

    body_pattern = re.compile(r"<body>(.*)</body>", re.DOTALL | re.IGNORECASE)
    body_match = body_pattern.search(document)
    if not body_match:
        raise RuntimeError("could not locate HTML body")
    body = body_match.group(1)
    wrapped = f"""
<body id='top'>
<a class='skip-link' href='#contents'>Skip to contents</a>
<header class='mobile-bar'>
  <strong>ferank <span>technical report</span></strong>
  <nav aria-label='Document shortcuts'><a href='#contents'>Contents</a><a href='#top'>Top</a></nav>
</header>
<main class='report-shell'>
<div class='edition-note'>Self-contained phone edition · Veneto example</div>
{body}
<footer class='mobile-footer'>Generated from the reproducible LaTeX companion report for ferank 0.1.</footer>
</main>
</body>"""
    document = document[: body_match.start()] + wrapped + document[body_match.end() :]

    if re.search(r"\[\s*\?\s*\]", document) or "undefined citation" in document.casefold():
        raise RuntimeError("the packaged HTML contains unresolved citations")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(document, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--html", type=Path, required=True)
    parser.add_argument("--css", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    package_html(args.html.resolve(), args.css.resolve(), args.output.resolve())
    print(f"Built {args.output.resolve()}")


if __name__ == "__main__":
    main()
