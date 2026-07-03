# GaasRoads

A 3D space racing game heavily inspired by [SkyRoads](https://en.wikipedia.org/wiki/SkyRoads_(video_game)) (1993) by BlueMoon Interactive.

This is a test project for recreating a classic game with GenAI (Claude Code).

Built with Godot 4.6 (GDScript, GL Compatibility renderer).

## Play

Web version: https://needlefi.itch.io/gaasroads

## Features

- 20 tracks across 4 themed groups (Cosmic Highway, Nebula Run, Solar Burn, Dark Matter)
- ASCII text file-based level design
- Speed control, jumping, lane-based elevation
- Per-group gravity tuning and visual themes
- Track completion tracking
- Warp takeoff animation on level completion
- Procedural ship and environment meshes

## Controls

- Arrow keys: steer left/right, speed up/down
- Space: jump
- Escape: back to menu

## Web build

The Web export preset uses thread support (audio mixes off the main thread),
which requires a cross-origin-isolated page:

- Export the `Web` preset into `Builds/`, then package with `package-web.ps1`
- Test locally with `python serve_web.py` (plain file serving won't boot the
  threaded build - the script adds the required COOP/COEP headers)
- On itch.io, enable **SharedArrayBuffer support** in the project's embed options

Music tracks in `Music/` are baked with `python bake_music.py` (needs ffmpeg).

## Testing

Headless tests (physics smokes, generator fairness, level completability
solver) are documented in [TESTING.md](TESTING.md).
