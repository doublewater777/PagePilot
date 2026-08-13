#!/usr/bin/env python3
"""Validate app-bundle and App Store localization completeness."""

from __future__ import annotations

import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_LOCALES = ("en", "zh-Hans", "es", "fr", "de")
ASC_LOCALES = ("en-US", "zh-Hans", "es-ES", "fr-FR", "de-DE")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[-+#0]*\d*(?:\.\d+)?[@diouxXeEfFgGcCsSpaAn]")


def strings_dict(path: Path) -> dict[str, str]:
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", "--", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    value = json.loads(result.stdout)
    if not isinstance(value, dict):
        raise ValueError(f"{path} is not a dictionary")
    return value


def placeholders(value: str) -> list[str]:
    return sorted(PLACEHOLDER.findall(value.replace("%%", "")))


def check_strings(relative: str, baseline_locale: str, locales: tuple[str, ...] = APP_LOCALES) -> list[str]:
    errors: list[str] = []
    baseline_path = ROOT / relative.format(locale=baseline_locale)
    baseline = strings_dict(baseline_path)
    for locale in locales:
        path = ROOT / relative.format(locale=locale)
        if not path.exists():
            errors.append(f"missing {path.relative_to(ROOT)}")
            continue
        try:
            current = strings_dict(path)
        except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, ValueError) as exc:
            errors.append(f"cannot parse {path.relative_to(ROOT)}: {exc}")
            continue
        if set(current) != set(baseline):
            missing = sorted(set(baseline) - set(current))
            extra = sorted(set(current) - set(baseline))
            if missing:
                errors.append(f"{path.relative_to(ROOT)} missing keys: {', '.join(missing)}")
            if extra:
                errors.append(f"{path.relative_to(ROOT)} has extra keys: {', '.join(extra)}")
        for key in set(baseline) & set(current):
            if placeholders(baseline[key]) != placeholders(current[key]):
                errors.append(f"{path.relative_to(ROOT)} placeholder mismatch for {key}")
    return errors


def check_metadata() -> list[str]:
    errors: list[str] = []
    app_fields = {"name", "subtitle", "privacyPolicyUrl"}
    version_fields = {"description", "keywords", "marketingUrl", "promotionalText", "supportUrl", "whatsNew"}
    app_dir = ROOT / "metadata" / "app-info"
    version_dir = ROOT / "metadata" / "version" / "1.0.16"
    for locale in ASC_LOCALES:
        app_path = app_dir / f"{locale}.json"
        version_path = version_dir / f"{locale}.json"
        for path, fields in ((app_path, app_fields), (version_path, version_fields)):
            if not path.exists():
                errors.append(f"missing {path.relative_to(ROOT)}")
                continue
            try:
                data = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError) as exc:
                errors.append(f"cannot parse {path.relative_to(ROOT)}: {exc}")
                continue
            missing = fields - set(data)
            if missing:
                errors.append(f"{path.relative_to(ROOT)} missing fields: {', '.join(sorted(missing))}")
            if path == app_path:
                if len(data.get("name", "")) > 30:
                    errors.append(f"{path.relative_to(ROOT)} name exceeds 30 characters")
                if len(data.get("subtitle", "")) > 30:
                    errors.append(f"{path.relative_to(ROOT)} subtitle exceeds 30 characters")
            else:
                for field, limit in (("keywords", 100), ("description", 4000), ("whatsNew", 4000), ("promotionalText", 170)):
                    if len(data.get(field, "")) > limit:
                        errors.append(f"{path.relative_to(ROOT)} {field} exceeds {limit} characters")
    return errors


def main() -> int:
    errors: list[str] = []
    errors.extend(check_strings("Sources/Resources/{locale}.lproj/Localizable.strings", "en"))
    bundle_locales = ("Base", "zh-Hans", "es", "fr", "de")
    errors.extend(check_strings("WatchRemote/{locale}.lproj/Localizable.strings", "Base", bundle_locales))
    errors.extend(check_strings("iPhone/{locale}.lproj/InfoPlist.strings", "Base", bundle_locales))
    errors.extend(check_strings("WatchRemote/{locale}.lproj/InfoPlist.strings", "Base", bundle_locales))
    errors.extend(check_strings("Sources/Library/{locale}.lproj/PublicationMenuViewController.strings", "en", ("en", "es", "fr", "de")))
    errors.extend(check_metadata())
    for plist in (ROOT / "iPhone/Info.plist", ROOT / "WatchRemote/Info.plist"):
        with plist.open("rb") as stream:
            data = plistlib.load(stream)
        declared = set(data.get("CFBundleLocalizations", []))
        expected = set(APP_LOCALES)
        if not expected <= declared:
            errors.append(f"{plist.relative_to(ROOT)} missing declared locales: {', '.join(sorted(expected - declared))}")
    if errors:
        print("Localization validation failed:", file=sys.stderr)
        print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
        return 1
    print(f"Localization validation passed for {len(APP_LOCALES)} app locales and {len(ASC_LOCALES)} ASC locales.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
