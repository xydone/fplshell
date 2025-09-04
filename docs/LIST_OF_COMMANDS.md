# List of commands

| Command                      | Description                                                                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `/chip <chip name>`          | Actives a chip. Leave empty to deactivate the current chip.                                                                           |
| `/filter <filter type>`      | Runs a filter on the search table. [You can find the list of filters here](#filters). Multiple filters can be chained in one command. |
| `/go <number>`               | Moves the search table to a given line.                                                                                               |
| `/horizon <number> <number>` | Changes the horizon to a new one given a start and end value.                                                                         |
| `/save <name>`               | Saves the current transfer plan to a file.                                                                                            |
| `/load <name>`               | Loads a transfer plan from a file.                                                                                                    |
| `/search <name>`             | Searches for a player via their name.                                                                                                 |
| `/quit`                      | Have a guess.                                                                                                                         |

## Filters

| Filter                               | Description                                                                                                                                    |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `position=<gk \| def \| mid \| fwd>` | Shows players who have the requested position.                                                                                                 |
| `price=X..Y`                         | Shows players who fit within the requested price range. `X` or `Y` can be left empty (ex: `price=..4.5`) if you don't want a lower/upper limit |
| `team=<name>`                        | Shows players who play for the requested position.                                                                                             |
| `asc`                                | Sorts players by their price in a ascending order.                                                                                             |
| `desc`                               | Sorts players by their price in a descending order.                                                                                            |
| `reset`                              | Clears all filters.                                                                                                                            |
