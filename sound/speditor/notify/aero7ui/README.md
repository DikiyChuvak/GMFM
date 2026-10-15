# Aero7UI — notification sounds from Windows 7

An example of a sound set that does not come from the Workshop: any folder in
`sound/speditor/notify/` becomes a set in Interface settings → Notifications → Sound.

Files (`.wav`, `.mp3` or `.ogg`; a missing one is silent). Here: `error` — Windows Critical
Stop, `info` — Windows Exclamation, `success` — Windows Notify, `save` — Windows Recycle.
error, info, success are matched to -16 LUFS (peaks limited to -3 dBFS); save (a noisy crumple that sounds louder than it measures) is 6 dB lower, by ear.

| file      | notification              |
|-----------|---------------------------|
| `info`    | information               |
| `error`   | error                     |
| `success` | done                      |
| `save`    | saving (silent otherwise) |

The same works without touching the addon: put the files into
`garrysmod/data/speditor/sounds/<set name>/`.

This README is not packed into the Workshop build (`*.md` is in `addon.json` ignore).
