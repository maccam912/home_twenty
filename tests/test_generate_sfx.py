"""Offline coverage of the ElevenLabs developer tool. No account or network needed."""
import contextlib
import http.client
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

from tools import generate_sfx as sfx


TEST_KEY = "synthetic-test-token"
# Two MPEG1 Layer III frames, 128kb/s at 44.1kHz.
MPEG_FRAMES = (b"\xff\xfb\x90\x64" + bytes(413)) * 2


class AudioResponse(io.BytesIO):
    def __init__(self, data=MPEG_FRAMES, content_length=None):
        super().__init__(data)
        self.headers = {} if content_length is None else {"Content-Length": str(content_length)}


class SoundGenerationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.key_file = self.root / "test.key"
        self.output = self.root / "sounds"
        self.output.mkdir()
        self.overrides = contextlib.ExitStack()
        self.addCleanup(self.overrides.close)
        self.overrides.enter_context(patch.object(sfx, "KEY_FILE", self.key_file))
        self.overrides.enter_context(patch.object(sfx, "DESTINATION", self.output))
        self.overrides.enter_context(patch.dict(os.environ, {"ELEVENLABS_API_KEY": ""}))
        self.opener_factory = self.overrides.enter_context(patch.object(sfx.urllib.request, "build_opener"))
        self.open = self.opener_factory.return_value.open
        self.open.side_effect = AssertionError("Unexpected request")

    def save_key(self, value=TEST_KEY, mode=0o600):
        self.key_file.write_text(value, encoding="utf-8")
        self.key_file.chmod(mode)

    def invoke(self, *args):
        out = io.StringIO()
        with patch.object(sfx.sys, "argv", ["generate_sfx.py", *args]), contextlib.redirect_stdout(out):
            sfx.run()
        return out.getvalue()

    def test_missing_credentials_and_empty_file(self):
        with self.assertRaisesRegex(ValueError, "Set ELEVENLABS_API_KEY"):
            sfx.api_key()
        self.save_key("\n")
        with self.assertRaisesRegex(ValueError, "Set ELEVENLABS_API_KEY"):
            sfx.api_key()

    def test_private_file_accepts_trailing_newline(self):
        self.save_key(TEST_KEY + "\n")
        self.assertEqual(sfx.api_key(), TEST_KEY)

    def test_environment_key_takes_precedence_over_file(self):
        self.save_key("file-token", 0o644)
        os.environ["ELEVENLABS_API_KEY"] = "  " + TEST_KEY + "  "
        self.assertEqual(sfx.api_key(), TEST_KEY)

    def test_rejects_non_ascii_and_internal_whitespace_without_echoing_token(self):
        for bad in ["é-secret", "a b", "two\nlines", "control\x01", "one\ttwo"]:
            with self.subTest(value=repr(bad)):
                self.save_key(bad)
                with self.assertRaisesRegex(ValueError, "one token") as error:
                    sfx.api_key()
                self.assertNotIn(bad, str(error.exception))

    def test_refuses_group_or_world_readable_key_files(self):
        for mode in [0o640, 0o604, 0o666]:
            with self.subTest(mode=oct(mode)):
                self.save_key(mode=mode)
                with self.assertRaisesRegex(ValueError, "owned by you"):
                    sfx.api_key()

    def test_refuses_a_key_owned_by_someone_else(self):
        self.save_key()
        owner = self.key_file.stat().st_uid
        with patch.object(sfx.os, "getuid", return_value=owner + 1):
            with self.assertRaisesRegex(ValueError, "owned by you"):
                sfx.api_key()

    def test_list_reports_catalog_without_credentials_or_requests(self):
        catalog = self.invoke("--list")
        self.assertEqual([line.split()[0] for line in catalog.splitlines()], list(sfx.CUES))
        self.assertIn("one-shot", catalog)
        self.assertIn("loop", catalog)
        self.open.assert_not_called()

    def test_rejects_unknown_cues_before_spending_anything(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                self.invoke("wind", "undefined-cue")
        self.assertEqual(error.exception.code, 2)
        self.assertEqual(list(self.output.iterdir()), [])
        self.open.assert_not_called()

    def test_loop_and_one_shot_send_declared_prompts_timing_and_credentials(self):
        self.open.side_effect = lambda request, timeout: AudioResponse(content_length=len(MPEG_FRAMES))
        for name in ["wind", "radio_key"]:
            with self.subTest(name=name):
                out = self.output / (name + ".mp3")
                sfx.generate(name, TEST_KEY, out)
                request = self.open.call_args.args[0]
                self.assertEqual(request.get_method(), "POST")
                self.assertEqual(request.full_url, sfx.ENDPOINT)
                headers = {k.lower(): v for k, v in request.header_items()}
                self.assertEqual(headers["xi-api-key"], TEST_KEY)
                self.assertEqual(headers["content-type"], "application/json")
                self.assertEqual(headers["accept"], "audio/mpeg")
                body = json.loads(request.data)
                cue = sfx.CUES[name]
                self.assertEqual(body["text"], cue.prompt)
                self.assertEqual(body["duration_seconds"], cue.seconds)
                self.assertIs(body["loop"], cue.loop)
                self.assertEqual(body["model_id"], "eleven_text_to_sound_v2")
                self.assertNotIn(TEST_KEY, request.data.decode())
                self.assertEqual(out.read_bytes(), MPEG_FRAMES)
                self.assertIsInstance(self.opener_factory.call_args.args[0], sfx.NoRedirect)

    def test_duplicate_cues_and_second_run_reuse_existing_files(self):
        self.save_key()
        self.open.side_effect = lambda request, timeout: AudioResponse()
        self.invoke("horn", "wind", "horn", "wind")
        self.assertEqual(self.open.call_count, 2)
        self.key_file.unlink()
        self.open.reset_mock()
        self.assertIn("Kept horn.mp3", self.invoke("horn", "wind"))
        self.open.assert_not_called()
        self.assertEqual(sorted(f.name for f in self.output.iterdir()), ["horn.mp3", "wind.mp3"])

    def test_all_only_requests_missing_tracks(self):
        self.save_key()
        for name in sfx.CUES:
            if name != "crosswind":
                (self.output / (name + ".mp3")).write_bytes(MPEG_FRAMES)
        self.open.side_effect = lambda request, timeout: AudioResponse()
        self.invoke("--all")
        self.open.assert_called_once()
        self.assertEqual(json.loads(self.open.call_args.args[0].data)["text"], sfx.CUES["crosswind"].prompt)
        self.assertEqual({p.stem for p in self.output.iterdir()}, set(sfx.CUES))

    def test_partial_batch_resumes_with_the_first_missing_clip(self):
        self.save_key()
        self.open.side_effect = [AudioResponse(), http.client.IncompleteRead(b"part", 7)]
        with self.assertRaisesRegex(ValueError, "ended early"):
            self.invoke("radio_key", "horn")
        self.assertEqual({p.name for p in self.output.iterdir()}, {"radio_key.mp3"})
        self.open.reset_mock()
        self.open.side_effect = lambda request, timeout: AudioResponse()
        self.invoke("radio_key", "horn")
        self.open.assert_called_once()
        self.assertEqual(json.loads(self.open.call_args.args[0].data)["text"], sfx.CUES["horn"].prompt)

    def test_invalid_existing_cache_is_preserved_and_reported(self):
        corrupt = self.output / "horn.mp3"
        corrupt.write_bytes(b"damaged")
        with self.assertRaisesRegex(ValueError, "not a valid MP3"):
            self.invoke("horn")
        self.assertEqual(corrupt.read_bytes(), b"damaged")
        self.open.assert_not_called()

    def test_truncated_unrecognized_and_short_responses_leave_no_output(self):
        for name, payload, count in [
            ("length mismatch", MPEG_FRAMES, len(MPEG_FRAMES) + 40),
            ("json error instead of audio", b"{" * 700, None),
            ("only a frame header", MPEG_FRAMES[:4], 4),
        ]:
            with self.subTest(name=name):
                self.open.side_effect = None
                self.open.return_value = AudioResponse(payload, count)
                with self.assertRaisesRegex(ValueError, "incomplete or unexpected"):
                    sfx.generate("wind", TEST_KEY, self.output / "wind.mp3")
                self.assertEqual(list(self.output.iterdir()), [])

    def test_interrupted_transfer_preserves_destination(self):
        destination = self.output / "horn.mp3"
        destination.write_bytes(b"previous take")
        response = AudioResponse()
        with patch.object(response, "read", side_effect=http.client.IncompleteRead(b"part", 7)):
            self.open.side_effect = None
            self.open.return_value = response
            with self.assertRaisesRegex(ValueError, "ended early"):
                sfx.generate("horn", TEST_KEY, destination)
        self.assertEqual(destination.read_bytes(), b"previous take")
        self.assertEqual(list(self.output.iterdir()), [destination])

    def test_failed_atomic_replace_keeps_old_file_and_cleans_staging_file(self):
        destination = self.output / "wind.mp3"
        destination.write_bytes(b"previous take")
        self.open.side_effect = lambda request, timeout: AudioResponse()

        def fail_commit(staging, target):
            self.assertEqual(target, destination)
            self.assertEqual(target.read_bytes(), b"previous take")
            self.assertEqual(staging.read_bytes(), MPEG_FRAMES)
            self.assertEqual(staging.parent, target.parent)
            raise OSError("simulated filesystem failure")

        with patch.object(Path, "replace", fail_commit):
            with self.assertRaisesRegex(OSError, "simulated filesystem"):
                sfx.generate("wind", TEST_KEY, destination)
        self.assertEqual(destination.read_bytes(), b"previous take")
        self.assertEqual(list(self.output.iterdir()), [destination])

    def test_http_failures_leave_no_cache_or_leaked_key(self):
        for status in [401, 403, 429, 500]:
            with self.subTest(status=status):
                response_body = io.BytesIO(b"private server diagnostic")
                self.open.side_effect = urllib.error.HTTPError(sfx.ENDPOINT, status, TEST_KEY, {}, response_body)
                with self.assertRaisesRegex(ValueError, f"HTTP {status}") as error:
                    sfx.generate("horn", TEST_KEY, self.output / "horn.mp3")
                self.assertNotIn(TEST_KEY, str(error.exception))
                self.assertTrue(response_body.closed)
                self.assertEqual(list(self.output.iterdir()), [])

    def test_redirects_do_not_create_a_request_with_the_api_key(self):
        request = sfx.urllib.request.Request(sfx.ENDPOINT, headers={"xi-api-key": TEST_KEY})
        for status in [301, 302, 303, 307, 308]:
            with self.subTest(status=status):
                redirect = sfx.NoRedirect().redirect_request(request, None, status, "Moved", {}, "https://example.invalid/next")
                self.assertIsNone(redirect)
