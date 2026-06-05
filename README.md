<p align="center">
  <img src="https://github.com/user-attachments/assets/5908664d-271b-4d45-921c-e54d56702c33" alt="Iliad" width="256">
</p>

# Iliad

A minimal native macOS app for focused writing. It keeps your text in a calm reading column so you can focus on the words, it's for AI enabled workflows so you can work with AI to Write or edit your copy as you need it, and hide it away until you're ready to use it again, it's designed to work with any AI service that runs in the terminal and can edit markdown files all in one focused screen.

Everything you write is a plain `.md` file on disk. There is no database, no proprietary format, and nothing to export. Open the folder somewhere else and your work is just there just like a coding IDE but for writing.

## Screenshots

![Focus mode dims everything but the paragraph you're in](https://github.com/user-attachments/assets/e2c7d1c1-7fe2-4d95-874b-566afed48cbf)

![Reviewing AI edits as a word-level diff, with per-change accept and reject](https://github.com/user-attachments/assets/c953a260-9983-4cf2-80a5-88eed82ccc7c)

![The built-in terminal running Claude Code next to your draft](https://github.com/user-attachments/assets/94aa5e08-7536-4cb2-8e3f-19ecd74d1d15)

## Features

**Writing**
- Live Markdown styling with the syntax markers hidden until you edit a line
- A responsive reading column with adjustable width
- Separate controls for font size, line height, line width, and paragraph and title weight, all in Settings (⌘,)
- Focus mode that dims everything except the paragraph you are in
- Typewriter scrolling that keeps the current line centred
- Zen mode that hides the chrome and gives you the page
- A live word, character, and reading-time count

**Your library**
- A floating sidebar that lists the folders and files in whatever directory you open
- Double-click a file or folder to rename it in place
- Drag files and folders between folders, or back out to the top level
- Right-click for the usual actions: new file, new folder, rename, duplicate, copy, paste, reveal in Finder, delete
- New files and folders ask for a name up front
- Sorted by name, the way you'd expect

**Themes**
- Light and dark themes built in
- Import terminal colour schemes (iTerm2, Ghostty, and similar `.itermcolors` / config files) and use them as editor themes

**Built-in terminal**
- A real terminal (⌘J) running your login shell, so full-screen tools like vim, htop, and Claude Code work properly
- Drag a file or folder onto it to drop the path in at the prompt

**Working with an AI editor**
- When a file changes underneath you, Iliad shows the difference as an inline diff: word-level when only a few words moved, the whole paragraph when it was rewritten
- Accept or reject each change with the buttons next to it, or step through them and accept or reject everything from the bar in the corner

**Saving**
- Everything autosaves as you type
- A hidden baseline lives alongside your folder so the diff view has something to compare against

## Building

Iliad is a Swift package. The app bundle is assembled by a small script:

```sh
./build.sh
open Iliad.app
```

It needs macOS 13 or later. SwiftTerm provides the terminal; the fonts and themes are bundled.

## Layout

- `Sources/Editor.swift`: the Markdown text view, live styling, and the diff renderer
- `Sources/UI.swift`: the sidebar, toolbar, and overall window
- `Sources/Store.swift`: files, autosave, and the baseline/diff logic
- `Sources/Diff.swift`: line and word diffing
- `Sources/Themes.swift` / `Theme.swift`: colours, fonts, and theme import
- `Sources/Terminal.swift`: the embedded terminal
- `Sources/Settings.swift`: the settings window
