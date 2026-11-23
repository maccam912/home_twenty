# Home Twenty

A PS2-era winter driving game set in rural Wisconsin, 1998. Turn the key and Deb draws the first job. Work as long as you like on one continuous outdoor shift across 35 properties. Finish at the customer’s place and the next call comes over the truck radio.

## Downloads

Download the [latest release](https://github.com/maccam912/home_twenty/releases/latest) for Android, macOS (Universal), Windows (x86-64), or Linux (x86-64). In the [release history](https://github.com/maccam912/home_twenty/releases), **Build 7.2** means the second commit in workflow run 7. The highest build number is marked **Latest**. Each release is tagged with its source commit and includes SHA-256 checksums. The Android APK is signed for sideloading. The macOS build is ad-hoc signed.

## Play

On a Mac, open **build/Home Twenty.app**. On Android, install **build/HomeTwenty.apk** and turn the phone sideways. The Android build offers steering and pedals, blade control, both views, a hold-to-talk mic, and touch buttons for the plat book and outdoor handoffs. The controls accept two fingers so you can steer while holding the gas.

To play from source, open the project in Godot 4.7 and press F6 on `game/shift.tscn` or F5 to run. From the project folder, `godot --path .` also starts the game.

| Control | Action |
| --- | --- |
| W / S or ↑ / ↓ | Accelerate, brake and reverse. Walk forward or back on foot. |
| A / D or ← / → | Steer the truck or turn on foot. |
| B | Raise or lower the plow. Push snow while moving forward. |
| C | Switch between the cab and the chase camera. |
| E | Stop and step outside, or get back in beside the truck. |
| H | Sound the truck horn. |
| Hold R, then release | Transmit on the cab CB, then listen for Deb’s directions. |
| X | Use the marked outdoor fixture on foot to check in, load, deliver or sign off. |
| M / Tab | Open or close the plat book. Press V or tap the paper tab to turn from the county index to the local sheet and the assigned yard. Arrow keys browse sheets. You can also tap a square on the index. |
| Esc | Pause or resume. |

The township is about eight miles square (12.8 km on a side). County Q crosses it north to south and County H crosses it west to east. A straight crossing takes about 9 minutes 35 seconds at full throttle, or 13 minutes 38 seconds at a steady 35 mph. The seven original properties cluster around the Q section. The outer roads pass sugar camps, timber landings, town halls, orchards and isolated farmyards. Spruce woodlots and birch stands break up the rolling fields.

Deb usually has work in the vicinity of your last stop. She gives turns, distances and landmarks over the CB. Your paper atlas has 16 section sheets and a close-up of the assigned yard. Use it to find the handoff point, then climb back into the cab for the next call.

An approach job needs a continuous blade-width opening from the public road to the yard. For a loading-bay call, push the new pile between the orange stakes. Those piles can turn up again after a loader or tractor has been through. Previously opened approaches and wheel tracks stay put. Supply runs have a pickup and a delivery, and some neighbors just need you to stop and check a reading or collect a slip.

With the blade up, the pickup can reach 50 mph on County Q. Above 35 mph the tires start sliding wide in turns and braking takes longer. Follow the ditches on either side to read the road through blowing snow. They open at intersections and driveways. If you slide into deep snow, the truck slows to a crawl. Stay in the cab and steer back up the shoulder, or reverse along the way you came.

Outside the truck, frost builds up. Climb back into the cab to warm up.

## Sound effects

The sound effects in this shift were generated with ElevenLabs. Both builds play the bundled MP3s locally. Deb’s lines in this slice are subtitled.

The generator reads `ELEVENLABS_API_KEY` from its environment or a user-owned file at `~/.config/home-twenty/elevenlabs.key` with permissions `600`. Save the raw key on a single line. With the key on your Mac clipboard, run the following in your own Terminal:

```sh
mkdir -p ~/.config/home-twenty
(umask 077; pbpaste > ~/.config/home-twenty/elevenlabs.key)
chmod 600 ~/.config/home-twenty/elevenlabs.key
```

List cues with `python3 tools/generate_sfx.py --list`. To generate the sounds used in this shift, run:

```sh
python3 tools/generate_sfx.py wind crosswind heater engine ignition plat_fold plow radio_key radio_squelch horn door blade_lift blade_drop
```

Generated MP3s go to `audio/generated/`. Restart the project to load new sounds. To include new sounds in the standalone app, reimport the assets and export the macOS and Android presets again.


## Development

Install Git LFS before cloning so Git downloads the models, textures, fonts and sound effects. If you already cloned the repository, run `git lfs install` and `git lfs pull`. The editable Blender source is in `world/trees/source/`. Godot uses the exported GLB in `world/trees/`.

Run `python3 tools/run_tests.py` from the repository with Godot 4.7.2 and Python 3 on your path. Set `GODOT_BIN` to use a specific engine executable. The suite drives a full county crossing, signs two successive field orders through the normal input system, checks routes between all 35 properties, and exercises dispatch over 600 contracts. The tests run offline with the bundled audio.

GitHub Actions runs tests for pull requests and each commit pushed to a branch. Before publishing a full release, Actions starts the packaged game on Linux, Windows, and macOS and verifies the Android APK signature and manifest. Android release signing uses the repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.
