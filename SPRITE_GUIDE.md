# Reproducing a Character Sprite to the Samurai Pack's Quality

This is a production brief, not a study. Its job is to let someone -- a
human artist, an AI image generator, or Elliott with a pixel art editor --
draw a new character's sprite set that (a) matches the visual production
quality of the samurai placeholder pack already in this project, and (b)
covers a more complete set of animations than that pack actually has,
since part 2 below shows the samurai pack itself is missing several
animations a full character usually needs.

Every number in Part 1 was measured directly from the actual PNG files in
`godot/assets/samurai/` using Python's Pillow library -- not estimated by
eye. Part 2's animation list comes from a mix of the pack's own product
listing and general research; both are labeled so it is clear which is
which.

## Part 1: matching the samurai pack's production quality

### Canvas

Every frame is a 96x96 pixel RGBA PNG (transparent background). Frames
sit in a single horizontal strip with no gap between them -- frame N
occupies pixels `[N*96, (N+1)*96)` along the strip's width. A new
character's sheets should follow the same 96x96 frame, same strip layout,
so they slot into the same kind of `SpriteFrames`/`AtlasTexture` setup
without new plumbing.

### Frame count, and how much of the 96x96 canvas the character actually fills

Measured directly from the PNG files -- frame count per animation, and
the real drawn pixels (the non-transparent bounding box) in every frame:

| Animation | Frame count | Drawn width (px) | Drawn height (px) | Top of art (row) | Feet row |
| --- | --- | --- | --- | --- | --- |
| Idle | 10 | 20-22 | 31-34 | 47-50 | 81 |
| Run | 16 | 23-32 | 24-30 | 50-54 | 74-81 |
| Attack 1 | 7 | 20-56 | 27-33 | 49-54 | 81-82 |
| Hurt | 4 | 19-23 | 34 | 47 | 81 |

The character itself is small -- roughly 20-34 pixels tall depending on
pose -- inside a 96-pixel-tall canvas. Most of the frame is deliberate
empty space, not character. Draw a new character at a similar scale
(call it 30-35px tall standing) rather than filling the 96x96 canvas
edge to edge; a character drawn too large will look mismatched next to
this one, even at the same frame size.

Attack 1's width jumps to 56px in its lunge frames because of an added
motion-blur streak trailing the sword (see "Motion effects" below) --
that is a deliberate effect reaching outside the character's own
silhouette, not a sizing mistake. Leave similar headroom for any new
animation that has a weapon swing, dash, or other effect that extends
past the character's own outline.

### Pivot -- where the feet land

In every animation with planted feet (Idle, Hurt, and Attack 1's start
and recovery frames), the bottom of the drawn pixels sits at row 81 of
96, measured from the top. Run's feet bob between rows 74 and 81 -- a
7-pixel up-and-down bounce that is the walk cycle's natural motion, not
drift or error.

Draw every new animation so the character's feet land on row 81 (with
the same kind of small bob during a run/walk cycle). This is what lets a
new character's sheets sit in the same scene as the samurai's without
the character appearing to float above the ground or sink into it.

### Outline

The darkest colors actually used, measured directly, are `#100515` and
`#0E071B` -- a very dark, slightly purple-tinted near-black, not pure
black (`#000000`). This is a common pixel art choice: a tinted dark color
reads as an outline without going flat, dead black. Use a similarly
tinted near-black for a new character's outline rather than pure black.

Edges are anti-aliased -- soft blended pixels at the silhouette, not a
hard 1-pixel binary outline. The evidence: each sheet's raw unique-color
count (up to 41 for Attack 1) runs roughly double its count of fully
opaque colors alone (18-19, see Palette below); that gap is anti-aliasing
blend pixels, not extra "real" palette colors.

### Shading

Most material regions (robe, pants, boots, hair) use only 2 to 4 distinct
value steps: a base color, one shadow, and occasionally one highlight.
This is shallow, efficient shading, not deeply rendered gradient work --
match that restraint rather than adding many more shading steps, or a
new character will read as more detailed than the rest of the set.

### Palette

Counting only fully opaque pixels (ignoring anti-aliasing blends) across
all four animation sheets combined: **exactly 20 unique colors**, reused
across the whole character.

| Swatch | RGB | Role (by inspection) |
| --- | --- | --- |
| ![#100515](https://img.shields.io/badge/-100515-100515) | 16, 5, 21 | outline (darkest) |
| ![#0E071B](https://img.shields.io/badge/-0E071B-0E071B) | 14, 7, 27 | outline |
| ![#131313](https://img.shields.io/badge/-131313-131313) | 19, 19, 19 | near-black neutral shadow |
| ![#1A1932](https://img.shields.io/badge/-1A1932-1A1932) | 26, 25, 50 | navy shadow (pants/robe) |
| ![#221C36](https://img.shields.io/badge/-221C36-221C36) | 34, 28, 54 | navy shadow |
| ![#391F21](https://img.shields.io/badge/-391F21-391F21) | 57, 31, 33 | maroon shadow (sash/scabbard) |
| ![#571C27](https://img.shields.io/badge/-571C27-571C27) | 87, 28, 39 | maroon (sash/scabbard) |
| ![#2A2F4E](https://img.shields.io/badge/-2A2F4E-2A2F4E) | 42, 47, 78 | navy midtone (pants) |
| ![#5D2C28](https://img.shields.io/badge/-5D2C28-5D2C28) | 93, 44, 40 | brown shadow (boots) |
| ![#424C6E](https://img.shields.io/badge/-424C6E-424C6E) | 66, 76, 110 | navy midtone (robe shadow) |
| ![#BF6F4A](https://img.shields.io/badge/-BF6F4A-BF6F4A) | 191, 111, 74 | brown (boots) |
| ![#858585](https://img.shields.io/badge/-858585-858585) | 133, 133, 133 | neutral grey (hair shadow) |
| ![#92A1B9](https://img.shields.io/badge/-92A1B9-92A1B9) | 146, 161, 185 | pale blue-grey (robe/hair) |
| ![#E69C69](https://img.shields.io/badge/-E69C69-E69C69) | 230, 156, 105 | skin midtone |
| ![#B4B4B4](https://img.shields.io/badge/-B4B4B4-B4B4B4) | 180, 180, 180 | neutral grey (light) |
| ![#C3CBDB](https://img.shields.io/badge/-C3CBDB-C3CBDB) | 195, 203, 219 | pale blue-white (robe/hair) |
| ![#C7CFDD](https://img.shields.io/badge/-C7CFDD-C7CFDD) | 199, 207, 221 | pale blue-white (robe/hair) |
| ![#F6CA9F](https://img.shields.io/badge/-F6CA9F-F6CA9F) | 246, 202, 159 | skin highlight |
| ![#FFFCFC](https://img.shields.io/badge/-FFFCFC-FFFCFC) | 255, 252, 252 | near-white highlight |
| ![#FFFFFF](https://img.shields.io/badge/-FFFFFF-FFFFFF) | 255, 255, 255 | white highlight |

That sorts into roughly six color families -- near-black outline, navy
(pants/robe shadow), maroon (sash/scabbard), brown/skin, neutral grey
(hair shadow), and pale blue-white (robe/hair) -- each with 2 to 4 value
steps. Checked per animation, Idle/Attack/Hurt each use 18 of these 20
colors and Run uses 19: almost the entire palette is shared across every
animation, with only one or two colors added per sheet.

To match this: fix a roughly 20-color palette, grouped the same way
(one near-black outline family, four or five hue families at 2-4 steps
each), before drawing the first frame of a new character, and draw every
animation from that same fixed set rather than picking new colors per
animation.

### Motion effects

Attack 1's lunge frames include a separate light grey-blue streak
graphic trailing the sword tip, layered on top of the character
silhouette -- a stylized motion blur, not part of the character's body.
It is what pushes that sheet's drawn width out to 56px. Any new attack,
dash, or fast-movement animation that wants a similar sense of speed
should budget canvas space the same way, as an addition on top of the
character rather than a stretch of the character itself.

### Playback speed (a reference point, not a rule)

As currently wired into this project's Godot scene, all four animations
above play back at 5 frames per second. That is one real example of how
many frames (see the table above) read as smooth motion at that speed --
useful as a sanity check when deciding how many frames a new animation
needs, not a number to hit exactly. A punchier attack might need fewer
frames at a higher speed; a slower guard stance might need fewer frames
still.

## Part 2: what the samurai pack is missing, against a full character set

### Against the pack's own product listing

A web search turned up a CraftPix.net pack, "Free Samurai Pixel Art
Sprite Sheets," that is likely where this project's zip came from. Its
product page (checked via an automated page-content fetch, not manually
read start to finish) lists animations for attack(s), dead, hurt, idle,
jump, protect, run, and walk, across 3 characters and 10 sheets at
128px-tall frames. This project's zip has 1 character, 4 sheets, and
96px-tall frames -- so this is either an older/smaller free release of
the same pack (it's named "v1.2"), or a different pack. Worth confirming
directly against CraftPix before treating the two as identical, but the
animation names are a reasonable signal either way.

Measured against that list, this project's zip has: **Idle, Run, Attack,
Hurt**. It is missing: **Dead, Jump, Protect (guard/block), and Walk as
its own animation distinct from Run**.

### Against general 2D action/fighting game convention (research, not this pack)

Beyond that specific pack's own list, general research on 2D
fighting/action game sprite sets turned up these additional categories
that full character sets commonly include, which are not confirmed to be
part of even the larger CraftPix pack:

- **Crouch**, sometimes with its own crouching attack.
- **More than one attack type** -- this pack has only one attack; many
  full sets split light/heavy or give a combo of 2-3 distinct attacks.
- **Situational extras**: a throw, a dash, a victory pose, a knockdown
  distinct from the death animation.

### Completion checklist

| Animation | In this pack now? | Source calling for it | Match-the-style notes |
| --- | --- | --- | --- |
| Idle | Yes | -- | -- |
| Run | Yes | -- | -- |
| Attack | Yes (one type) | -- | -- |
| Hurt | Yes | -- | -- |
| Dead | No | CraftPix listing | One-shot, non-looping; feet can leave row 81 as the character falls, unlike every current animation |
| Jump | No | CraftPix listing | Likely needs separate rise/fall poses since the silhouette usually changes shape in the air |
| Protect / Guard | No | CraftPix listing | Held/looping stance, similar to Idle's loop style |
| Walk | No | CraftPix listing | Distinct from Run -- slower cadence, likely fewer frames than Run's 16 |
| Crouch | No | General research only | Lower the drawn bounding box, feet still at row 81 |
| Second attack type | No | General research only | Reuse the same ~20-color palette and 2-4-step shading |
| Throw / dash / victory | No | General research only | Lowest priority -- only needed if the game's actual mechanics call for it |

Every new animation in this table should hold to what Part 1 measured:
96x96 frame, feet at row 81 (give or take a run-style bob), character
drawn around 30-35px tall, the same ~20-color palette, a tinted
near-black outline, and 2-4 shading steps per material.

## Sources

- [Free Samurai Pixel Art Sprite Sheets Download - CraftPix.net](https://craftpix.net/freebies/free-samurai-pixel-art-sprite-sheets/)
- [2D Player Animations - The Indie Dev Professor](https://theindieprofessor.wordpress.com/2024/12/11/crafting-2d-games-2d-player-animations/)
- [How to Build Sprite Sheets for 2D Games - A Practical Guide for Indie Devs - DEV Community](https://dev.to/code280fox/how-to-build-sprite-sheets-for-2d-games-a-practical-guide-for-indie-devs-46ib)
- [2D Fighter Game Character Sprite Sheet - OpenGameArt.org](https://opengameart.org/forumtopic/2d-fighter-game-character-sprite-sheet)
- [Pixel Art Spritesheet Tutorial: From Character Design to Game-Ready Animation - Spritesheets.ai](https://www.spritesheets.ai/blog/pixel-art-spritesheet-tutorial)
- [2D pixel art style guide - from 8-bit to modern HD - Sprite-AI](https://www.sprite-ai.art/blog/2d-pixel-art-style-guide)
- [Pixel art fundamentals: everything you need to know - Sprite-AI](https://www.sprite-ai.art/guides/pixel-art-fundamentals)

These are general web sources, not one authoritative standard -- Part
2's general-research row is common practice found online, not a rule.
Part 1's numbers are direct measurements of this project's own files and
are as solid as the measurement method (Pillow bounding boxes and exact
pixel color reads).
