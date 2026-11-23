"""Exercise release publication and Latest selection without contacting GitHub."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / ".github/scripts"


@unittest.skipUnless(shutil.which("bash") and shutil.which("jq"), "Release scripts require bash and jq")
class PublishTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        gh = self.root / "gh"
        gh.write_text("""#!/usr/bin/env bash
IFS=$'\\t'
echo "$*" >> calls
case "$1 $2" in
    "release view") cat "$3.state" ;;
    "api "*) cat pages.json ;;
    "release create"|"release upload"|"release edit") exit 0 ;;
    *) exit 1 ;;
esac
""")
        gh.chmod(0o755)
        if sys.platform == "darwin":
            # macOS shasum supports the GNU flags used on the Ubuntu release runner.
            sha256sum = self.root / "sha256sum"
            sha256sum.write_text('#!/bin/sh\nexec shasum -a 256 "$@"\n')
            sha256sum.chmod(0o755)

    def run_script(self, name, batch=(), check=True):
        (self.root / "calls").write_text("")
        result = subprocess.run(
            ["bash", str(SCRIPTS / name)], cwd=self.root, text=True, capture_output=True,
            env={**os.environ, "PATH": str(self.root) + os.pathsep + os.environ["PATH"],
                 "COMMIT_BATCH": json.dumps(batch), "GITHUB_RUN_NUMBER": "12"},
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = [line.split("\t") for line in (self.root / "calls").read_text().splitlines()]
        return result, calls

    def package(self, sha):
        release = self.root / "releases" / sha
        receipts = self.root / "native-passes" / sha
        release.mkdir(parents=True)
        receipts.mkdir(parents=True)
        for system in ("macos", "windows"):
            asset = release / f"{system}.zip"
            asset.write_bytes(system.encode())
            digest = hashlib.sha256(asset.read_bytes()).hexdigest()
            (receipts / f"{system}.sha256").write_text(f"{digest}  {asset.name}\n")

    def test_new_draft_recovered_draft_and_published_commit(self):
        # Give the later commit a SHA that sorts first on disk.
        new, draft, published = ("b" * 40, "a" * 40, "c" * 40)
        batch = [{"sha": sha, "index": i} for i, sha in enumerate((new, draft, published), start=8)]
        for commit in batch:
            self.package(commit["sha"])
        (self.root / f"build-{draft}.state").write_text("true\n")
        (self.root / f"build-{published}.state").write_text("false\n")
        _, calls = self.run_script("publish.sh", batch)
        for sha, position, operations in [
            (new, 9, ["view", "create", "upload", "edit"]),
            (draft, 10, ["view", "upload", "edit"]),
            (published, 11, ["view"]),
        ]:
            with self.subTest(sha=sha):
                commands = [args for args in calls if args[2] == f"build-{sha}"]
                self.assertEqual([args[1] for args in commands], operations)
                if "create" in operations:
                    self.assertIn("--draft", commands[1])
                    self.assertEqual(commands[1][commands[1].index("--target") + 1], sha)
                if "edit" in operations:
                    edit = commands[-1]
                    self.assertEqual(edit[edit.index("--title") + 1], f"Home Twenty · Build 12.{position}")
                    for flag in ("--draft=false", "--prerelease=false", "--latest=false"):
                        self.assertIn(flag, edit)

    def test_incorrect_receipt_blocks_release(self):
        sha = "a" * 40
        self.package(sha)
        (self.root / "releases" / sha / "windows.zip").write_bytes(b"changed")
        result, calls = self.run_script("publish.sh", [{"sha": sha, "index": 0}], check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_latest_compares_both_numbers_across_all_pages(self):
        def release(number, digit, **fields):
            return {"name": f"Home Twenty · Build {number}", "tag_name": "build-" + digit * 40,
                    "draft": False, "prerelease": False, **fields}

        winner = release("10.12", "a")
        excluded = [release("99.1", "b", draft=True), release("99.2", "c", prerelease=True),
                    release("99.3", "d", tag_name="handmade"), release("99.4", "e", name="Old release")]
        for pages, expected in [
            ([[release("9.99", "f"), release("10.9", "1")], [winner, *excluded]], [winner["tag_name"]]),
            ([excluded], []),
        ]:
            with self.subTest(expected=expected):
                (self.root / "pages.json").write_text(json.dumps(pages))
                _, calls = self.run_script("update-latest.sh")
                self.assertIn("--paginate", calls[0])
                self.assertEqual(calls[1:], [["release", "edit", tag, "--latest"] for tag in expected])


if __name__ == "__main__":
    unittest.main()
