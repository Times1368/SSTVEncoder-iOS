# AppIcon 1024 px source placeholder

No binary icon is embedded in patches or required in this directory. Until a
finished icon is supplied, `scripts/generate_app_icon.py` draws a deterministic
opaque placeholder and builds the generated Xcode asset catalog.

To replace the placeholder, add one file at this exact path:

```text
SSTVEncoder/Resources/AppIconSource/AppIcon-1024.png
```

The source must be exactly 1024 x 1024 pixels. Use an sRGB PNG, keep the outer
corners square, and let iOS apply its icon mask. The generator converts the
result to opaque RGB so the compiled AppIcon has no alpha channel.

From the repository root, install Pillow and generate the catalog:

```sh
python3 -m pip install --disable-pip-version-check --no-input "Pillow>=12.0,<13"
python3 scripts/generate_app_icon.py
```

An alternate source may be used without copying it into the repository:

```sh
python3 scripts/generate_app_icon.py --source /path/to/AppIcon-1024.png
```

Generated files live under `SSTVEncoder/Resources/Generated/` and are ignored
by Git. GitHub Actions regenerates them before every XcodeGen invocation.
