#!/usr/bin/env python3
"""Builds the SPeditor wiki.
  index.html       - the claude.ai artifact (no <html>/<head>: the host wraps it)
  local.html       - a standalone copy used for checks and for printing the PDFs
  pages/           - the GitHub Pages site: standalone index.html, img/, the PDFs
Usage: build.py [github_user] [repo]
"""
import glob, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
USER = sys.argv[1] if len(sys.argv) > 1 else ""
REPO = sys.argv[2] if len(sys.argv) > 2 else "SPeditor"

body = "".join(open(p, encoding="utf-8").read() for p in sorted(glob.glob(os.path.join(HERE, "parts", "0*.html"))))
open(os.path.join(HERE, "index.html"), "w", encoding="utf-8").write(body)

HEAD = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        '<meta name="description" content="SPeditor wiki: the poster, scene and animation studio for Garry\'s Mod. Every window, tool and hotkey with screenshots, in English and Russian.">\n'
        '<style>img{max-width:100%}[hidden]{display:none!important}body{margin:0}</style>\n')
open(os.path.join(HERE, "local.html"), "w", encoding="utf-8").write(HEAD + body + "\n</html>\n")

# GitHub Pages: links that only make sense on a real website
links = ''
if USER:
    links = (
        '\n  <h2><span class="l-en">Download</span><span class="l-ru">Скачать</span></h2>\n'
        '  <div class="cards">\n'
        '    <a class="card" href="SPeditor_Guide_EN.pdf" download><b>PDF · English</b><span class="l-en">The whole wiki as one file.</span><span class="l-ru">Вся вики одним файлом.</span></a>\n'
        '    <a class="card" href="SPeditor_Guide_RU.pdf" download><b>PDF · Русский</b><span class="l-en">The same in Russian.</span><span class="l-ru">Вся вики одним файлом, по-русски.</span></a>\n'
        '    <a class="card" href="https://github.com/%s/%s"><b>GitHub</b><span class="l-en">Source code, issues and releases.</span><span class="l-ru">Исходный код, баг-репорты и релизы.</span></a>\n'
        '    <a class="card" href="https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435"><b>Steam Workshop</b><span class="l-en">Subscribe to the addon.</span><span class="l-ru">Подписаться на аддон.</span></a>\n'
        '  </div>\n' % (USER, REPO))
marker = '  <h2><span class="l-en">Where to start</span>'
assert marker in body
pages_body = body.replace(marker, links + marker, 1)
pages_body = pages_body.replace('<title>SPeditor Wiki</title>', '<title>SPeditor Wiki</title>', 1)
out = os.path.join(HERE, "pages")
if os.path.isdir(out):
    for name in os.listdir(out):
        if name == ".git":
            continue
        path = os.path.join(out, name)
        shutil.rmtree(path) if os.path.isdir(path) else os.remove(path)
else:
    os.makedirs(out)
open(os.path.join(out, "index.html"), "w", encoding="utf-8").write(HEAD + pages_body + "\n</html>\n")
shutil.copytree(os.path.join(HERE, "img"), os.path.join(out, "img"))
open(os.path.join(out, ".nojekyll"), "w").close()

# PDFs from the standalone copy (print mode: #print-en / #print-ru)
for lang in ("en", "ru"):
    pdf = os.path.join(HERE, "SPeditor_Guide_%s.pdf" % lang.upper())
    subprocess.run(["chromium", "--headless=new", "--disable-gpu", "--no-sandbox", "--virtual-time-budget=20000",
                    "--no-pdf-header-footer", "--print-to-pdf=" + pdf,
                    "file://%s#print-%s" % (os.path.join(HERE, "local.html"), lang)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    shutil.copy(pdf, out)
print("built", len(body), "bytes; pages in", out)
