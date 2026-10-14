# SPeditor wiki sources

The player documentation published at https://dikiychuvak.github.io/SPeditor/ (branch `gh-pages`).

- `parts/0*.html` — the page, split by sections. Every text is written twice: `.l-en` and `.l-ru`.
  A page is `<section class="page" id="pg-<id>" data-group="…" data-en="Title" data-ru="Заголовок">`.
- `img/` — screenshots taken in the game (1600 px wide at most, JPEG quality ~84).
- `build.py DikiyChuvak SPeditor` — builds `pages/` (the GitHub Pages site) and both PDFs
  (needs `chromium`; the PDF is the page opened with `#print-en` / `#print-ru`).

Publish: build, then commit the contents of `pages/` to the `gh-pages` branch.
