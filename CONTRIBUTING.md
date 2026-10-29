# Contributing

Thanks for helping! Fenn Focus aims to stay **small, local-first and key-free**: everything must work without an
account, and any cloud AI is something the user adds with their own key.

## Build

```bash
python3 Scripts/generate_xcodeproj.py
open FennFocus.xcodeproj
```

The project file is generated – edit `Scripts/generate_xcodeproj.py` instead of the `.pbxproj`, then run it again.
New `.swift` files under `Sources/` are picked up automatically.

Signing defaults to "Sign to Run Locally". To use your own team, copy `Config/Local.xcconfig.example` to
`Config/Local.xcconfig` (ignored by git).

## Layout

| Folder | What lives there |
|---|---|
| `Sources/FennFocus` | The app: notch island, window, tasks, calendar, focus, routines, notes, AI agent, MCP server |
| `Sources/FennFocusCore` | Shared by the app and the widgets: snapshot format, tokens, localisation |
| `Sources/FennFocusWidgets` | Desktop widgets (WidgetKit) |
| `Support` | Info.plists, entitlements, asset catalogs |
| `docs` | Model guide and other docs |

## Guidelines

- German and English: user-facing strings go through `tr("Deutsch", "English")`.
- Data stays in plain Markdown/JSON files in the user's folder – no database, no proprietary format.
- Never commit API keys, tokens, model weights or personal data.
- Keep the AI optional: every feature should still work, perhaps more simply, with no model configured.
