# FPLShell

_A TUI application built for [Fantasy Premier League](https://fantasy.premierleague.com/) team planning._

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

## Controls

1. General controls:

   | Button             | Action                                          |
   | ------------------ | ----------------------------------------------- |
   | `Arrow Left/Right` | Moves between tables.                           |
   | `Arrow Up/Down`    | Moves up and down the rows of the active table. |
   | `Tab`              | Switches to gameweek selector mode.             |
   | `/`, `:` or `;`    | Turns on command mode.                          |

2. Search table:

   | Button  | Action                                                              |
   | ------- | ------------------------------------------------------------------- |
   | `Enter` | Adds the hovered player to the lineup, if the transfer is possible. |

3. Lineup table:

   | Button  | Action                                                                     |
   | ------- | -------------------------------------------------------------------------- |
   | `Enter` | Removes the hovered player from the lineup.                                |
   | `c`     | Gives the hovered player captaincy.                                        |
   | `v`     | Gives the hovered player vice-captaincy.                                   |
   | `Space` | Selects a player. Select two players to swap their positions on the table. |

4. Gameweek selector:

   | Button             | Action                       |
   | ------------------ | ---------------------------- |
   | `Arrow Left/Right` | Changes the active gameweek. |

You can see the list of valid commands and their descriptions by typing `/`, `:` or `;` inside the command menu.

## Building

_Prerequisites: you must have [Zig 0.14.1](https://ziglang.org/download/#release-0.14.1) installed._

1. `zig build` for a debug build, `zig build -Doptimize=ReleaseFast` for a `ReleaseFast` build. [There are more build modes if you wish to use them.](https://ziglang.org/documentation/0.14.1/#Build-Mode)
