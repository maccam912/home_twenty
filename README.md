# Home Twenty

A PS2-era winter driving game set in rural Wisconsin, 1998. This first playable shift takes you from the home place on County Q to the Becks’ propane tank and back. Open a continuous swath for a delivery truck, visit the porch, then bring Deb the news. Cleared snow and windrows stay in the world for the shift.

## Downloads

Download the [latest release](https://github.com/maccam912/home_twenty/releases/latest) for Android, macOS (Universal), Windows (x86-64), or Linux (x86-64). In the [release history](https://github.com/maccam912/home_twenty/releases), **Build 7.2** means the second commit in workflow run 7. The highest build number is marked **Latest**. Each release is tagged with its source commit and includes SHA-256 checksums. The Android APK is signed for sideloading. The macOS build is ad-hoc signed.

## Play

On a Mac, open **build/Home Twenty.app**. On Android, install **build/HomeTwenty.apk** and turn the phone sideways. The Android build offers steering and pedals, blade control, both views, a hold-to-talk mic, and touch buttons for the map and porches. The controls accept two fingers so you can steer while holding the gas.

To play from source, open the project in Godot 4.7 and press F6 on `game/shift.tscn` or F5 to run. From the project folder, `godot --path .` also starts the game.

| Control | Action |
| --- | --- |
| W / S or ↑ / ↓ | Accelerate, brake and reverse. Walk forward or back on foot. |
| A / D or ← / → | Steer the truck or turn on foot. |
| B | Raise or lower the plow. Push snow while moving forward. |
| C | Switch between the cab and the chase camera. |
| E | Stop and step outside, or get back in beside the truck. |
| Hold F | Shovel packed snow away from a buried wheel while on foot. On Android, hold **SHOVEL**. |
| H | Sound the truck horn. |
| Hold R, then release | Transmit on the cab CB, then listen for Deb’s directions. |
| X | Knock at a porch on foot. |
| M / Tab | Open your marked plat book. |
| Esc | Pause or resume. |

Start up the home drive and turn left on County Q. The Beck mailbox is a mile north, past the co-op sign. Their unloading yard sits about 400 feet back from the road.

With the blade up, the pickup can reach 50 mph on County Q. Above 35 mph the tires start sliding wide in turns and braking takes longer. Slow down before the farm entrances. If you bury the wheels in a drift, climb out, stand beside a tire and shovel three scoops. Get back in and ease onto the road.

The blade cuts a continuous path where you drive it. At the Becks’, start at the mouth of the lane on Q and carry the pass through to the unloading area. Outside the truck, frost builds up. Return to the cab to warm up.

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
python3 tools/generate_sfx.py wind crosswind heater engine ignition plat_fold plow shovel radio_key radio_squelch horn door blade_lift blade_drop
```

Generated MP3s go to `audio/generated/`. Restart the project to load new sounds. To include new sounds in the standalone app, reimport the assets and export the macOS and Android presets again.


## Development

Install Git LFS before cloning so Git downloads the models, textures, fonts and sound effects. If you already cloned the repository, run `git lfs install` and `git lfs pull`. The editable Blender source is in `world/trees/source/`. Godot uses the exported GLB in `world/trees/`.

Run `python3 tools/run_tests.py` from the repository with Godot 4.7.2 and Python 3 on your path. Set `GODOT_BIN` to use a specific engine executable. The suite includes an entire delivery and return driven through the normal input system. The tests run offline with the bundled audio.

GitHub Actions runs tests for pull requests and each commit pushed to a branch. Before publishing a full release, Actions starts the packaged game on Linux, Windows, and macOS and verifies the Android APK signature and manifest. Android release signing uses the repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.
