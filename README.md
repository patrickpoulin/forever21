# Forever21

Blackjack for WoW Forever. Up to 5 players sit at a table and play against a dealer run by the addon. Everyone starts each game with 100 chips, and the last player with chips wins.

Built for WoW Forever 1.60.1 (addon interface 16001).

![Table window preview](docs/table-preview.png)

_Approximate render from `tools/preview.lua`; fonts and buttons look like WoW's own in game._

## Status

Milestone 2 of 5: the table window, sound effects, and solo play against the dealer. Invites and multiplayer come in milestone 3.

## Install

### With WowUp

1. In WowUp, pick your WoW Forever client, then go to **Get Addons** and choose **Install from URL**.
2. Paste `https://github.com/patrickpoulin/forever21` and install.

WowUp installs the latest GitHub release. A new release is published automatically whenever `main` has a new `## Version:` in `Forever21/Forever21.toc`.

### By hand

1. Copy the `Forever21` folder into `World of Warcraft/Interface/AddOns/` in your WoW Forever install.
2. Restart the game or type `/reload`.
3. Check it loaded with `/f21 api`.

## Play solo

Type `/f21` to open the table window and press **New Game**. Click chips (2, 4, 10) to build your bet, then **Bet** to deal. Play with **Hit**, **Stand**, **Double**, and **Split**, and answer **Insure** or **No Insurance** when the dealer shows an ace. After each round a banner shows whether you won, lost, pushed, or busted and by how many chips, and every seat is outlined green, red, or yellow with its chips won or lost. Sound effects play for cards, bets, your turn, and results; turn them off with the **Sound** button or `/f21 sound`. Drag the window to move it; Escape closes it.

Everything also works from chat:

| Command | What it does |
| --- | --- |
| `/f21` | Show or hide the table window |
| `/f21 solo` | Start a solo game with 100 chips |
| `/f21 bet <amount>` | Bet an even amount from 2 to 24 |
| `/f21 hit`, `/f21 stand`, `/f21 double`, `/f21 split` | Play your hand |
| `/f21 insure`, `/f21 noinsure` | Answer the insurance offer when the dealer shows an ace |
| `/f21 chips` | Show your chips |
| `/f21 quit` | Leave the game |
| `/f21 sound` | Turn sound effects on or off |
| `/f21 chat` | Turn the chat messages on or off |
| `/f21 stats` | Your games and hands played |
| `/f21 api` | Show the version and which addon-message API this client has |

## Rules

6-deck shoe reshuffled at 75%, blackjack pays 3 to 2, dealer stands on all 17s and peeks for blackjack with an ace or ten showing. Insurance pays 2 to 1. Double on any two cards, including after a split. Split pairs up to 4 hands; split aces get one card each. Bets are even, from 2 to 24 chips. A player with fewer than 2 chips is out.

All rules live in `Forever21/Rules.lua`.

## Development

The card, rules, and game logic (`Cards.lua`, `Rules.lua`, `Game.lua`) are plain Lua with no game API calls, so they're tested outside the game.

```sh
sudo apt-get install lua5.1 lua-busted lua-check   # or: luarocks install busted luacheck
busted        # run the tests in spec/
luacheck .    # lint
```

GitHub Actions runs both on every push and pull request. `spec/ui_spec.lua` loads the whole addon on a stubbed game API (`tools/wowstub.lua`) and plays a round through the window's buttons.

To render approximate screenshots of the window outside the game:

```sh
lua5.1 tools/preview.lua /tmp/preview && python3 tools/render_preview.py /tmp/preview
```

Card suit and chip textures are drawn by `tools/make_media.py` (needs Pillow).
