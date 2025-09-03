# FPLShell

*A TUI application built for [Fantasy Premier League](https://fantasy.premierleague.com/) team planning.* 

### Features
- Saving and loading transfer plans.
- Importing current team from FPL via ID and `.json`.
- Built with customizability in mind.
- Minecraft-style commands for things such as player filtering, changing settings, enabling chips.

## Why?

A lot of FPL team planners have clunky/outdated UI and sometimes I am not in the mood to hunt down a specific website which I like just to see the impact of one decision in further gameweeks. 

While other team planners have a lot more functionality (as of right now), I preferred to build one tailored to my needs. This is not meant to be a one-size-fits-all solution.

## Requirements

1. A modern terminal emulator, preferably one that supports [the Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/). The application works in Windows Terminal too.

## Building

*Prerequisites: you must have Zig installed.*

1. `zig build` for a debug build, `zig build -Doptimize=ReleaseFast` for a ReleaseFast build. [There are more build modes if you wish to use them.](https://ziglang.org/documentation/0.14.1/#Build-Mode)