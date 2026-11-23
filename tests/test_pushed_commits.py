"""Exercise the Actions revision matrix against local Git histories."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PLANNER = Path(__file__).resolve().parents[1] / ".github/scripts/pushed_commits.py"
NEW_BRANCH = "0" * 40


class PushedCommitsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_AUTHOR_NAME="Planner Test",
            GIT_COMMITTER_NAME="Planner Test",
            GIT_AUTHOR_EMAIL="planner@example.invalid",
            GIT_COMMITTER_EMAIL="planner@example.invalid",
        )
        self.git("init", "--bare", "--quiet", "--initial-branch=main")
        self.tree = self.git("mktree")

    def git(self, *args):
        return subprocess.check_output(
            ["git", *args], cwd=self.root, env=self.env, text=True, input=""
        ).strip()

    def make_commits(self, branch, count, parent=None):
        commits = []
        for index in range(count):
            args = ["commit-tree", self.tree, "-m", f"{branch} change {index}"]
            if parent:
                args.extend(["-p", parent])
            parent = self.git(*args)
            commits.append(parent)
        self.git("update-ref", f"refs/heads/{branch}", parent)
        return commits

    def plan(self, event_name, head, event):
        payload = self.root / "event.json"
        output = self.root / "actions-output"
        payload.write_text(json.dumps(event))
        output.write_text("")
        subprocess.run(
            [sys.executable, str(PLANNER)],
            cwd=self.root,
            env=dict(
                self.env,
                GITHUB_EVENT_NAME=event_name,
                GITHUB_SHA=head,
                GITHUB_EVENT_PATH=str(payload),
                GITHUB_OUTPUT=str(output),
            ),
            check=True,
        )
        name, data = output.read_text().strip().split("=", 1)
        self.assertEqual(name, "batches")
        batches = json.loads(data)
        for batch in batches:
            self.assertEqual(batch["label"], batch["commits"][-1]["sha"][:12])
        return batches

    def assert_commit_order(self, batches, expected):
        commits = [commit for batch in batches for commit in batch["commits"]]
        self.assertEqual(commits, [{"sha": sha, "index": i} for i, sha in enumerate(expected)])

    def test_push_preserves_every_new_revision_in_oldest_first_order(self):
        before, *new = self.make_commits("main", 4)
        # Event commit lists can be truncated. Git history is necessary to include all three.
        batches = self.plan("push", new[-1], {"before": before, "commits": [{"id": new[-1]}]})
        self.assert_commit_order(batches, new)

    def test_new_branch_skips_ancestors_of_published_builds(self):
        base = self.make_commits("main", 3)
        self.git("tag", f"build-{base[-1]}", base[-1])
        feature = self.make_commits("snow", 2, parent=base[-1])
        self.git("tag", "field-test", feature[0])
        batches = self.plan("push", feature[-1], {"before": NEW_BRANCH, "ref": "refs/heads/snow"})
        self.assert_commit_order(batches, feature)

    def test_manual_and_pull_request_runs_check_only_the_workflow_sha(self):
        base, head = self.make_commits("main", 2)
        for event_name, event in [
            ("workflow_dispatch", {"ref": "main"}),
            ("pull_request", {"pull_request": {"head": {"sha": base}}}),
        ]:
            with self.subTest(event_name=event_name):
                self.assert_commit_order(self.plan(event_name, head, event), [head])

    def test_push_above_matrix_limit_keeps_all_commits_and_global_indices(self):
        commits = self.make_commits("main", 257)
        batches = self.plan("push", commits[-1], {"before": NEW_BRANCH})
        self.assertLessEqual(2 * len(batches), 256)  # macOS and Windows each run every batch.
        self.assert_commit_order(batches, commits)


if __name__ == "__main__":
    unittest.main()
