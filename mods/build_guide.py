#!/usr/bin/env python3
"""Builds lua/speditor/cl_mods_guide.lua from mods/README_ru.md and mods/README_en.md.

The mods/ folder is not uploaded to the Workshop (see addon.json), so the guide for
mod authors travels inside the addon as a Lua string, and the game writes it to
garrysmod/data/speditor/ with the "Save the guide" button.
Run from the addon folder:  python3 mods/build_guide.py
"""
import os

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = [
    "-- Guide for mod authors. THIS FILE IS GENERATED from mods/README_ru.md and",
    "-- mods/README_en.md by mods/build_guide.py — edit those, not this file.",
    "SPeditor = SPeditor or {}",
    "SPeditor.ModGuide = {}",
    "",
]
for lang in ("ru", "en"):
    text = open(os.path.join(root, "mods", "README_%s.md" % lang), encoding="utf-8").read()
    assert "]===]" not in text
    out.append("SPeditor.ModGuide.%s = [===[\n%s]===]\n" % (lang, text))
open(os.path.join(root, "lua", "speditor", "cl_mods_guide.lua"), "w", encoding="utf-8").write("\n".join(out))
print("ok")
