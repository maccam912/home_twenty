#!/usr/bin/env python3
"""Generate the game's sound library with ElevenLabs. Requires Python 3.9+."""

import argparse
from dataclasses import dataclass
import fcntl
import http.client
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import urllib.error
import urllib.request


PROJECT = Path(__file__).resolve().parents[1]
DESTINATION = PROJECT / "audio" / "generated"
KEY_FILE = Path.home() / ".config" / "home-twenty" / "elevenlabs.key"
ENDPOINT = "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128"


@dataclass(frozen=True)
class Cue:
    seconds: float
    loop: bool
    prompt: str


CUES = {
    "wind": Cue(12, True, "Open Wisconsin farm country in a blizzard. Steady low winter wind across an open field, fine powder hissing under occasional soft surges. Natural field recording, no voices, music or animals."),
    "crosswind": Cue(15, True, "Field recording of a violent crosswind combing powder snow across an empty Wisconsin road at night. A close, sustained, whipping airy rush with a dry granular sandpaper hiss over deeper gusting air. Slowly passing across the stereo field. The gust stays strong so its level can be ridden in a game. Isolated wind and snow, no voices, whistles, music, thunder, trees or vehicles."),
    "heater": Cue(7, True, "Inside a parked 1990s pickup, a warm dashboard heater fan on low. Soft steady air through old vents and a faint bearing whirr. Isolated recording, no engine, speech or music."),
    "engine": Cue(7, True, "A 1990s American gasoline pickup engine holding a steady low idle. Close, warm muffled mechanical rumble from the driver seat, with subtle pulses. No revs, starts, stops, wind or music."),
    "ignition": Cue(1.6, False, "From the driver's seat of an old American gasoline pickup on a cold morning. A small metal key turns with a distinct click, the starter cranks twice and the engine catches with one low, warm chuff. Short clean tail on the catch. Isolated close mechanical recording, no extended idle, revving, voices, warning chime or music."),
    "plat_fold": Cue(0.7, False, "A gloved hand turns one broad folded leaf of a well-worn paper county plat map. A single soft, dry paper swish with a little crease crackle and a gentle settling flap. Close natural foley in a quiet truck cab. Immediate onset, no tearing, repeated flipping, voices, engine or music."),
    "plow": Cue(6, True, "A pickup snowplow pushing heavy packed snow down a gravel drive. Steady granular shushing, low steel blade rasp under load. Consistent movement, no engine, impacts, voices or music."),
    "radio_key": Cue(0.5, False, "One close mechanical press of a 1990s CB microphone push to talk switch. Small dry plastic thumb click. No voice, beep, background hiss or music."),
    "radio_squelch": Cue(0.7, False, "A short soft burst of analog CB radio static with a tight squelch cutoff, like a rural truck radio ending a transmission. No speech, beeps or music."),
    "horn": Cue(1.1, False, "One continuous medium-length honk of an older American pickup horn. Clear dual-tone, outdoors on a snow-muted country lane. Clean onset and release. No traffic or music."),
    "door": Cue(0.9, False, "A single old pickup driver's door closing. Solid dull metal and rubber thump, latch catching with a tiny window rattle. Close recording, no engine or music."),
    "blade_lift": Cue(1.1, False, "A hydraulic snowplow blade lifting on the front of an old pickup, short ascending electric pump whine ending in a gentle mechanical stop. No engine or music."),
    "blade_drop": Cue(0.9, False, "A steel snowplow blade settling onto a packed snowy driveway. Brief hydraulic release and one low muffled metal clunk into granular snow. No engine or music."),
    "tow_chain": Cue(1.5, False, "Cold work gloves drawing a short tow chain tight and hooking steel onto a tow eye. Three close, weighty metal clinks in snow, then silence. No voices or music."),
    "mailbox": Cue(0.8, False, "One small rural sheet-metal mailbox getting clipped, a hollow tin bonk followed by the little door rattling against its latch. No voices or music."),
    "payphone": Cue(5.5, True, "One second of a sharp mechanical brass telephone bell rattling inside an old American outdoor payphone, followed by four seconds of silence between calls. Isolated mono field recording of the phone, muted metal enclosure, no voices, no wind or music. Repeating ring cadence."),
}


def api_key():
    value = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not value:
        try:
            with KEY_FILE.open(encoding="utf-8") as handle:
                info = os.fstat(handle.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                    raise ValueError(f"Use a key file owned by you with mode 600: {KEY_FILE}")
                value = handle.read(2048).strip()
        except FileNotFoundError:
            pass
    if not value:
        raise ValueError(f"Set ELEVENLABS_API_KEY or put the raw key in {KEY_FILE} (mode 600).")
    if not value.isascii() or not value.isprintable() or any(c.isspace() for c in value):
        raise ValueError("The API key must contain one token.")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # A redirect must never forward the private xi-api-key header.
        return None


def looks_like_mp3(header):
    return header[:3] == b"ID3" or (len(header) >= 2 and header[0] == 0xFF and header[1] & 0xE0 == 0xE0)


def generate(name, key, destination):
    cue = CUES[name]
    body = json.dumps({
        "text": cue.prompt,
        "duration_seconds": cue.seconds,
        "loop": cue.loop,
        "model_id": "eleven_text_to_sound_v2",
    }).encode()
    request = urllib.request.Request(ENDPOINT, data=body, headers={
        "Content-Type": "application/json", "Accept": "audio/mpeg", "xi-api-key": key,
    })
    opener = urllib.request.build_opener(NoRedirect())
    try:
        with opener.open(request, timeout=120) as response:
            sound = response.read()
            expected = response.headers.get("Content-Length")
            if (expected and int(expected) != len(sound)) or len(sound) < 512 or not looks_like_mp3(sound):
                raise ValueError(f"{name}: ElevenLabs returned incomplete or unexpected audio.")
    except urllib.error.HTTPError as error:
        error.close()
        raise ValueError(f"{name}: ElevenLabs returned HTTP {error.code}. Check key permissions, credits and rate limits.") from None
    except http.client.IncompleteRead:
        raise ValueError(f"{name}: transfer ended early. No audio file was written.") from None
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=f".{name}-", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(sound)
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(destination)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cues", nargs="*", metavar="CUE", help="one or more cue IDs from --list")
    parser.add_argument("--list", action="store_true", help="list cues without contacting ElevenLabs")
    parser.add_argument("--all", action="store_true", help="generate all missing cues (uses API credits)")
    args = parser.parse_args()
    if args.list:
        for name, cue in CUES.items():
            print(f"{name:15s} {cue.seconds:4.1f}s  {'loop' if cue.loop else 'one-shot'}")
        return
    if bool(args.cues) == args.all:
        parser.error("specify cue IDs or --all")
    names = list(CUES) if args.all else list(dict.fromkeys(args.cues))
    unknown = [name for name in names if name not in CUES]
    if unknown:
        parser.error("unknown cue(s): " + ", ".join(unknown))
    DESTINATION.mkdir(parents=True, exist_ok=True)
    # Serialize generation across simultaneous CLI calls to avoid duplicate paid requests.
    directory_fd = os.open(DESTINATION, os.O_RDONLY)
    try:
        fcntl.flock(directory_fd, fcntl.LOCK_EX)
        key = None
        for name in names:
            destination = DESTINATION / f"{name}.mp3"
            if destination.exists():
                with destination.open("rb") as handle:
                    if destination.stat().st_size < 512 or not looks_like_mp3(handle.read(4)):
                        raise ValueError(f"{destination} is not a valid MP3. Move it aside before regenerating.")
                print(f"Kept {destination.name}")
                continue
            if key is None:
                key = api_key()
            print(f"Generating {name}…", flush=True)
            generate(name, key, destination)
            print(f"Wrote {destination.name}")
    finally:
        os.close(directory_fd)


if __name__ == "__main__":
    try:
        run()
    except (ValueError, OSError) as error:
        sys.exit(str(error))
