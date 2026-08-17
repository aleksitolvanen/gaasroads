# GaasRoads

A 3D space racing game heavily inspired by [SkyRoads](https://en.wikipedia.org/wiki/SkyRoads_(video_game)) (1993) by BlueMoon Interactive.

This is a test project for recreating a classic game with GenAI (Claude Code).

Built with Godot 4.6 (GDScript, GL Compatibility renderer).

## Play

Web version: https://needlefi.itch.io/gaasroads

## Features

- 15 authored tracks across 3 themed groups (Nebula Run, Solar Burn, Dark Matter)
- Procedural presets, custom track settings and endless mode
- Track sharing: compact paste codes for generated tracks, raw text for the rest
- ASCII text file-based level design
- Speed control, jumping, lane-based elevation
- Per-group gravity tuning and visual themes
- Track completion tracking
- Warp takeoff animation on level completion
- Procedural ship and environment meshes

## Controls

- Arrow keys or WASD: steer left/right, speed up/down
- Space: jump
- C: share track — V (in menu): paste a shared track, L: load a track file
- Escape or Q: back to menu

## Web build

The Web export preset uses thread support (audio mixes off the main thread),
which requires a cross-origin-isolated page:

- Release: `.\release-web.ps1` — exports the `Web` preset headless and pushes
  it to itch.io with [butler](https://itch.io/docs/butler/) (one-time
  `butler login` first; Godot binary via `$env:GODOT` or the script default)
- Manual fallback: export the `Web` preset into `Builds/`, package with
  `package-web.ps1`, upload the zip by hand
- Test locally with `python serve_web.py` (plain file serving won't boot the
  threaded build - the script adds the required COOP/COEP headers)
- On itch.io, enable **SharedArrayBuffer support** in the project's embed options

Music tracks in `Music/` are baked with `python bake_music.py` (needs ffmpeg).

## Testing

Headless tests (physics smokes, generator fairness, level completability
solver) are documented in [TESTING.md](TESTING.md).
