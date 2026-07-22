#!/usr/bin/env bash
set -euo pipefail

echo "== YoVoice: safe VS Code cleanup =="

if [ ! -f "pubspec.yaml" ]; then
  echo "Uruchom ten skrypt w głównym folderze projektu YoVoice."
  exit 1
fi

mkdir -p .vscode

cat > .vscode/settings.json <<'JSON'
{
  "editor.formatOnSave": true,
  "editor.formatOnPaste": true,
  "editor.codeActionsOnSave": {
    "source.organizeImports": "explicit",
    "source.fixAll": "explicit"
  },
  "dart.lineLength": 80,
  "dart.previewFlutterUiGuides": true,
  "dart.showTodos": true,
  "dart.openDevTools": "flutter",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.exclude": {
    "**/.DS_Store": true,
    "**/__MACOSX": true,
    "**/.dart_tool": true,
    "**/build": true,
    "**/ios/Pods": true,
    "**/macos/Pods": true
  },
  "search.exclude": {
    "**/.dart_tool": true,
    "**/build": true,
    "**/ios/Pods": true,
    "**/macos/Pods": true,
    "**/web/icons": true
  },
  "explorer.compactFolders": false,
  "explorer.sortOrder": "type",
  "workbench.tree.indent": 14
}
JSON

cat > .vscode/extensions.json <<'JSON'
{
  "recommendations": [
    "Dart-Code.dart-code",
    "Dart-Code.flutter",
    "usernamehw.errorlens",
    "Gruntfuggly.todo-tree"
  ]
}
JSON

find . -name ".DS_Store" -type f -delete
find . -type d -name "__MACOSX" -prune -exec rm -rf {} +

echo
echo "== Formatting Dart files =="
dart format lib

echo
echo "== Suggested automatic fixes (preview only) =="
dart fix --dry-run || true

echo
echo "== Flutter analyzer =="
flutter analyze

echo
echo "Gotowe. Otwórz projekt ponownie komendą: code ."
