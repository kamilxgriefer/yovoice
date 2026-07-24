from pathlib import Path
import shutil
import sys

SOURCE = Path(__file__).resolve().parent
PROJECT = Path.cwd()

if not (PROJECT / "pubspec.yaml").exists():
    raise SystemExit("Run this script from the YoVoice project root (next to pubspec.yaml).")

for source in (SOURCE / "lib").rglob("*.dart"):
    relative = source.relative_to(SOURCE)
    target = PROJECT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    print(f"Copied: {relative}")

# Best-effort patch: switch the create flow from CreateRoomScreen to RoomTypeSelectorScreen.
dart_files = list((PROJECT / "lib").rglob("*.dart"))
patched = False

for path in dart_files:
    text = path.read_text(encoding="utf-8")
    if "Create Voice Moment" not in text or "Start Voice Room" not in text:
        continue

    original = text
    import_line = "import 'package:yovoice/features/rooms/presentation/screens/room_type_selector_screen.dart';"
    if import_line not in text:
        lines = text.splitlines()
        insert_at = 0
        for i, line in enumerate(lines):
            if line.startswith("import "):
                insert_at = i + 1
        lines.insert(insert_at, import_line)
        text = "\n".join(lines) + ("\n" if original.endswith("\n") else "")

    text = text.replace(
        "builder: (_) => const CreateRoomScreen()",
        "builder: (_) => const RoomTypeSelectorScreen()",
    )
    text = text.replace(
        "builder: (context) => const CreateRoomScreen()",
        "builder: (context) => const RoomTypeSelectorScreen()",
    )

    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Patched create flow: {path.relative_to(PROJECT)}")
        patched = True
        break

if not patched:
    print()
    print("Automatic create-sheet patch was not found.")
    print("In the handler for 'Start Voice Room', open:")
    print("  const RoomTypeSelectorScreen()")
    print("instead of:")
    print("  const CreateRoomScreen()")

print()
print("Installation finished.")
print("Run: flutter analyze")
