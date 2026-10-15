# Carry

Pick up a section of your base and put it down somewhere else, as it is. Buildings keep what's in them: chest and
machine contents, belt items, recipes and crafting progress, fluids, and the wires between them. No robots, no
rebuilding: it moves at once.

## Use

1. Press the **Carry** shortcut (or **Ctrl+Alt+C**) and drag over the section.
2. The section is now in your hand as a print: the game shows where it would land. **R** turns it.
3. Click where it should go. A card says how many buildings moved; **Move back** puts it back where it was.

It can land partly on where it stood (moving it a few tiles is fine). If something of your base is in the way, nothing
moves: a red box shows what's blocking. **Shift-click** clears trees, rocks and cliffs in the way first (trees and
rocks are mined into your inventory, cliffs removed); your own buildings still block.

## What happens to the edges

- Poles that had a wire to a pole outside the section are joined to the nearest pole in reach where it lands.
- Circuit wires to outside the section are dropped (the card says how many).
- Belts at the edge simply end where the section ends; connect them again yourself.

## Limits (0.1)

- No flipping (F / G): put it down unflipped.
- Rails can be moved but not turned.
- Trains, cars and spidertrons stay where they are; so do tiles (concrete, landfill).
- The game's Undo doesn't know about a move: use **Move back** on the card.

## Tests

`python test/run.py --all` (from this folder): a running section (belt with plates, chest, assembler mid-craft, pipe of
water, a combinator wired to a pole powered from outside) is shifted onto itself, moved back, turned, moved back,
blocked, blocked by trees and a rock then moved with them cleared, and dropped as a player's print; then 2500 belts are moved and back, timed.
