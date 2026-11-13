# Forever21

Blackjack for WoW Forever. Up to 5 players sit at a table and play against a dealer run by the addon. Everyone starts each game with 100 chips, and the last player with chips wins.

Built for WoW Forever 1.60.1 (addon interface 16001).

## Status

Milestone 1 of 5: the rules engine and solo play from chat commands. The table window, invites, and multiplayer come in later milestones. See the design plan for the full roadmap.

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

| Command | What it does |
| --- | --- |
| `/f21 solo` | Start a solo game with 100 chips |
| `/f21 bet <amount>` | Bet an even amount from 2 to 24 |
| `/f21 hit`, `/f21 stand`, `/f21 double`, `/f21 split` | Play your hand |
| `/f21 insure`, `/f21 noinsure` | Answer the insurance offer when the dealer shows an ace |
| `/f21 chips` | Show your chips |
| `/f21 quit` | Leave the game |
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

GitHub Actions runs both on every push and pull request.
