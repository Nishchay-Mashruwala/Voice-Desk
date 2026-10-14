"""Pre-release checks (CI runs this before building; run it yourself before tagging).

    python desktop/scripts/check-release.py            # files + versions agree
    python desktop/scripts/check-release.py v0.2.0     # ...and match this tag

Paths below are inside desktop/.

Fails when:
  - the version differs between backend/app/tauri.conf.json,
    frontend/package.json, backend/app/Cargo.toml and backend/core/Cargo.toml,
    or doesn't match the tag;
  - a Rust module declared in backend/core/src/lib.rs or backend/app/src/lib.rs
    has no file in git;
  - an engine module imported by backend/engine/engine.py (directly or through other
    engine modules) isn't in git, or a bundled engine resource isn't.
Needs Python 3.11+ and git.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESKTOP = "backend/app"
CORE = "backend/core"
ENGINE = "backend/engine"
errors: list[str] = []


def tracked_files() -> set[str]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
    return set(out.stdout.splitlines())


def read(rel: str) -> str:
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def check_versions(tag: str | None) -> None:
    versions = {
        f"{DESKTOP}/tauri.conf.json": json.loads(read(f"{DESKTOP}/tauri.conf.json")).get("version"),
        "frontend/package.json": json.loads(read("frontend/package.json")).get("version"),
        f"{DESKTOP}/Cargo.toml": tomllib.loads(read(f"{DESKTOP}/Cargo.toml"))["package"]["version"],
        f"{CORE}/Cargo.toml": tomllib.loads(read(f"{CORE}/Cargo.toml"))["package"]["version"],
    }
    if len(set(versions.values())) != 1:
        errors.append("versions differ: " + ", ".join(f"{k} = {v}" for k, v in versions.items()))
    if tag:
        want = tag[1:] if tag.startswith("v") else tag
        for file, v in versions.items():
            if v != want:
                errors.append(f"tag {tag} doesn't match {file} (version {v})")
    print("versions:", ", ".join(f"{k}={v}" for k, v in versions.items()))


def check_rust_modules(files: set[str]) -> None:
    for crate in (CORE, DESKTOP):
        for name in re.findall(r"^\s*(?:pub(?:\([\w:]+\))?\s+)?mod\s+(\w+)\s*;", read(f"{crate}/src/lib.rs"), re.M):
            options = (f"{crate}/src/{name}.rs", f"{crate}/src/{name}/mod.rs")
            if not any(o in files for o in options):
                errors.append(f"{crate}/src/lib.rs declares `mod {name};` but {options[0]} isn't in git")


def third_party_modules() -> set[str]:
    names = set()
    for req in os.listdir(os.path.join(ROOT, ENGINE)):
        if (req.startswith("requirements") or req == "constraints.txt") and req.endswith(".txt"):
            for line in read(f"{ENGINE}/{req}").splitlines():
                m = re.match(r"\s*([A-Za-z0-9_.\-]+)", line)
                if m and not line.lstrip().startswith("#"):
                    names.add(m.group(1).lower().replace("-", "_").replace(".", "_"))
    return names


def check_engine(files: set[str]) -> None:
    stdlib = set(sys.stdlib_module_names)
    external = third_party_modules()
    seen: set[str] = set()
    todo = ["engine"]
    while todo:
        mod = todo.pop()
        if mod in seen:
            continue
        seen.add(mod)
        path = f"{ENGINE}/{mod}.py"
        if path not in files:
            errors.append(f"{path} is imported by the engine but isn't in git"
                          f" (or `{mod}` is a package missing from {ENGINE}/requirements*.txt)")
        if not os.path.exists(os.path.join(ROOT, path)):
            continue
        src = read(path)
        names = re.findall(r"^\s*from\s+(\w+)[\w.]*\s+import\b", src, re.M)
        for group in re.findall(r"^\s*import\s+([\w., ]+?)\s*(?:#.*)?$", src, re.M):
            names += [n.strip().split()[0].split(".")[0] for n in group.split(",") if n.strip()]
        for n in names:
            if n == "__future__" or n in stdlib or n.lower() in external:
                continue
            todo.append(n)
    # Concrete (non-glob) resources bundled from engine/ must be in git too.
    resources = json.loads(read(f"{DESKTOP}/tauri.conf.json")).get("bundle", {}).get("resources", {})
    for src in resources if isinstance(resources, (dict, list)) else []:
        rel = os.path.normpath(os.path.join(DESKTOP, src)).replace(os.sep, "/")
        if "*" not in rel and rel not in files:
            errors.append(f"{rel} is bundled (tauri.conf.json -> resources) but isn't in git")


def main() -> int:
    tag = sys.argv[1] if len(sys.argv) > 1 else None
    files = tracked_files()
    check_versions(tag)
    check_rust_modules(files)
    check_engine(files)
    if errors:
        print("\nRelease check failed:")
        for e in errors:
            print("  -", e)
        print("\nCommit the missing files / fix the versions, then tag again.")
        return 1
    print("Release check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
