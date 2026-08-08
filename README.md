# Xal's Craft Courier

A World of Warcraft addon that turns your mailbox into a crafting dispatch
center - scans your bags, sorts materials by profession, and routes them
to the right crafter, personal or guild, in one click.

## Features

- **Assign a dedicated crafter for every profession** - each profession gets its own recipient
- **True one-click mailing at any mailbox** - a themed "Send to Crafters" button on the default Send Mail frame; hit Send All and every mail sends itself automatically. Drag the button anywhere and right-click to lock it in place
- **Personal and Guild tabs** - always a deliberate, separate choice, never an automatic fallback - guild crafters are kept fully separate per guild
- **Profession list in the send window** - every profession is shown, with a green dot marking which ones have something ready to send right now
- **Smart bag scanning** - reads every bag, including the reagent bag
- **Filter system** - control which expansions and item types (reagents, tools, recipes) go to each crafter
- **Full guild crafter support** - pulls your live guild roster straight into the crafter picker
- **Quick setup screen** - guided first-run panel, plus a full Options panel for fine-tuning
- **Plays nicely with other mailing addons** - works correctly alongside TSM and similar addons that customize the mailbox

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

MIT License -- see [LICENSE.md](LICENSE.md).
