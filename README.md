# Xal's Craft Courier

A World of Warcraft addon that turns your mailbox into a crafting dispatch
center - scans your bags, sorts materials by profession, and routes them
to the right crafter, personal or guild, in one click.

## Features

- **Assign a dedicated crafter for every profession** - each profession gets its own recipient
- **One-click mailing at any mailbox** - a themed "Send to Crafters" button on the default Send Mail frame
- **Personal and Guild tabs** - always a deliberate, separate choice, never an automatic fallback
- **Confirmation before sending** - a direct "Send to CHARNAME?" check before anything is queued
- **Smart bag scanning** - reads every bag, including the reagent bag
- **Filter system** - control which expansions and item types (reagents, tools, recipes) go to each crafter
- **Full guild crafter support** - pulls your live guild roster straight into the crafter picker
- **Quick setup screen** - guided first-run panel, plus a full Options panel for fine-tuning

## Commands

| Command | Effect |
|---|---|
| `/xcc` or `/xcc help` | Show the help list |
| `/xcc setup` | Quick crafter setup panel |
| `/xcc options` | Full options panel (filters, guild crafters) |
| `/xcc crafters` | List your configured crafters |
| `/xcc scan` | Preview what would be sent, without opening a mailbox |
| `/xcc splash` | Reopen the welcome screen |

## Installation

1. Download the latest release.
2. Extract the `XalsCraftCourier` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
3. Restart WoW or `/reload`.

## License

All Rights Reserved -- see [LICENSE.md](LICENSE.md).
