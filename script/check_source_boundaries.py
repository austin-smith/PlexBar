#!/usr/bin/env python3
"""Reject app-owned Swift sources compiled by another application target."""

import json
from pathlib import Path
import subprocess
import sys

REPOSITORY = Path(__file__).resolve().parent.parent
PROJECT = REPOSITORY / "PlexBar.xcodeproj/project.pbxproj"
TARGET_ROOTS = {
    "PlexBar": Path("PlexBar"),
    "PlexBarTV": Path("PlexBar/TV"),
    "PlexBarTopShelf": Path("PlexBar/TopShelf/Extension"),
    "PlexBarStudio": Path("Studio"),
}


def violations(project: Path) -> list[str]:
    objects = json.loads(subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", str(project)], text=True
    ))["objects"]
    parents = {
        child: identifier
        for identifier, item in objects.items()
        for child in item.get("children", [])
    }

    def source_path(identifier: str) -> Path:
        item = objects[identifier]
        path = Path(item.get("path", ""))
        if item.get("sourceTree") == "SOURCE_ROOT" or identifier not in parents:
            return path
        return source_path(parents[identifier]) / path

    errors = []
    for target in objects.values():
        name = target.get("name")
        if target.get("isa") != "PBXNativeTarget" or name not in TARGET_ROOTS:
            continue
        paths = set()
        for identifier in target.get("fileSystemSynchronizedGroups", []):
            paths.add(source_path(identifier))
        for identifier in target.get("buildPhases", []):
            phase = objects[identifier]
            if phase["isa"] == "PBXSourcesBuildPhase":
                for build_file in phase["files"]:
                    paths.add(source_path(objects[build_file]["fileRef"]))
        for path in sorted(paths):
            own_root = TARGET_ROOTS[name]
            owned = path.is_relative_to(own_root)
            if name == "PlexBar":
                owned = owned and not any(path.is_relative_to(root)
                                          for root in (Path("PlexBar/TV"), Path("PlexBar/TopShelf")))
            if not owned:
                errors.append(f"{name} compiles {path}; shared code must use a package product")
    return errors


if __name__ == "__main__":
    errors = violations(Path(sys.argv[1]) if len(sys.argv) == 2 else PROJECT)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)
    print("App source boundaries passed")
