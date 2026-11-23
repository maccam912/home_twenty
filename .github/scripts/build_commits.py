"""Test each pushed checkout and package successful builds separately."""
import json
import os
import subprocess
import sys
import tarfile
import zipfile
from hashlib import sha256
from pathlib import Path


def run(args, cwd):
    subprocess.run([str(x) for x in args], cwd=cwd, check=True)


def package(checkout, output, sha, index):
    output.mkdir(parents=True)
    engine = os.environ["GODOT_BIN"]
    # Keep the APK upgradeable and expose its source revision in Android settings.
    presets = checkout / "export_presets.cfg"
    first = "version/code=1\n"
    settings = presets.read_text()
    if first not in settings or 'version/name="0.1.0"' not in settings:
        raise ValueError("Update CI version stamping to match the Android preset")
    code = int(os.environ["GITHUB_RUN_NUMBER"]) * 4096 + index
    settings = settings.replace(first, f"version/code={code}\n", 1)
    presets.write_text(settings.replace('version/name="0.1.0"', f'version/name="0.1.0+{sha[:12]}"', 1))
    binary_dir = output.parent / f"{sha}-binaries"
    binary_dir.mkdir()
    linux = binary_dir / "HomeTwenty.x86_64"
    windows = binary_dir / "HomeTwenty.exe"
    apk = output / "HomeTwenty-Android.apk"
    mac = output / "HomeTwenty-macOS.zip"
    for preset, file in [("Linux", linux), ("Windows", windows), ("macOS", mac), ("Android", apk)]:
        run([engine, "--headless", "--export-release", preset, file], checkout)
        if not file.exists() or file.stat().st_size < 100_000:
            raise ValueError(f"Incomplete {preset} export")
    linux.chmod(0o755)
    run([linux, "--headless", "--quit-after", "5"], binary_dir)
    tools = Path(os.environ["ANDROID_HOME"]) / "build-tools" / "36.0.0"
    run([tools / "apksigner", "verify", "--verbose", apk], checkout)
    metadata = subprocess.check_output([tools / "aapt", "dump", "badging", apk], text=True)
    if "dev.maccam912.hometwenty" not in metadata or f"versionCode='{code}'" not in metadata or "application-debuggable" in metadata:
        raise ValueError("Unexpected APK package, version code or debuggable flag")
    with zipfile.ZipFile(mac) as bundle:
        if not any(".app/Contents/MacOS/" in n and not n.endswith("/") for n in bundle.namelist()) or bundle.testzip():
            raise ValueError("Invalid macOS app bundle")
    with zipfile.ZipFile(output / "HomeTwenty-Windows-x64.zip", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        bundle.write(windows, windows.name)
    with tarfile.open(output / "HomeTwenty-Linux-x64.tar.gz", "w:gz", compresslevel=6) as bundle:
        bundle.add(linux, arcname=linux.name)
    records = []
    for file in sorted(output.iterdir()):
        with file.open("rb") as asset:
            digest = sha256()
            for block in iter(lambda: asset.read(1024 * 1024), b""):
                digest.update(block)
        records.append(f"{digest.hexdigest()}  {file.name}")
    (output / "SHA256SUMS.txt").write_text("\n".join(records) + "\n")


def main():
    phase = sys.argv[1]
    workspace = Path.cwd()
    staging = Path(os.environ["RUNNER_TEMP"]) / "commit-builds"
    staging.mkdir(exist_ok=True)
    verified = staging / "tested"
    verified.mkdir(exist_ok=True)
    failed = []
    for commit in json.loads(os.environ["COMMIT_BATCH"]):
        sha = commit["sha"]
        checkout = staging / sha
        print(f"::group::{phase} {sha}", flush=True)
        try:
            if phase == "test":
                # Hydrate the detached revision too: some media may only exist
                # in intermediate commits of a multi-commit push.
                subprocess.run(["git", "worktree", "add", "--detach", checkout, sha],
                               cwd=workspace, env={**os.environ, "GIT_LFS_SKIP_SMUDGE": "1"}, check=True)
                run(["git", "lfs", "pull", "--include=", "--exclude=", "origin"], checkout)
                run(["git", "lfs", "fsck", sha], checkout)
                run([sys.executable, "tools/run_tests.py"], checkout)
                (verified / sha).touch()
            elif (verified / sha).exists():
                output = staging / "packages" / sha
                package(checkout, output, sha, commit["index"])
                releases = workspace / "build" / "ci-releases"
                releases.mkdir(exist_ok=True, parents=True)
                output.rename(releases / sha)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            print(f"::error::{phase} failed for {sha}: {error}", flush=True)
            failed.append(sha)
        finally:
            print("::endgroup::", flush=True)
    return int(bool(failed))


if __name__ == "__main__":
    sys.exit(main())
