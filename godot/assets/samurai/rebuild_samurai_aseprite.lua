-- rebuild_samurai_aseprite.lua
--
-- The free "Samurai 2D Pixel Art v1.2" pack only ships flattened sprite
-- sheets (IDLE.png, RUN.png, ATTACK 1.png, HURT.png) -- one PNG per
-- animation, each a horizontal strip of frames on a single flattened
-- layer. There is no original .aseprite source file in the pack, so
-- whatever layers the artist worked in are gone for good.
--
-- What this script rebuilds is the part that IS fully recoverable: the
-- frame structure. It slices each sheet back into its individual grid
-- cells and reassembles them as a single working .aseprite file with one
-- flat "character" layer, animation tags marking which frames belong to
-- which action, and no invented layer splits (Elliott chose the flat,
-- lossless option over a heuristic color-based layer split on 2026-08-05).
--
-- Run with:
--   Aseprite.exe -b --script rebuild_samurai_aseprite.lua
--
-- Output: Samurai.aseprite, next to this script.

local frameWidth = 96
local frameHeight = 96

-- Hardcoded rather than auto-detected: this script only ever runs against
-- these specific assets, and Aseprite's sandboxed Lua doesn't reliably
-- expose "the folder this script lives in" without extra assumptions.
local scriptFolder = "C:/Users/exman/mistfight/godot/assets/samurai"

-- Each entry: source sheet file name (relative to this script's folder),
-- the tag name to give its frame range, and how many 96x96 cells it holds.
-- Frame counts were measured ahead of time in Python by finding the gaps
-- of fully-transparent columns between characters in each sheet.
local animations = {
  { file = "IDLE.png",     tag = "Idle",   frameCount = 10 },
  { file = "RUN.png",      tag = "Run",    frameCount = 16 },
  { file = "ATTACK 1.png", tag = "Attack", frameCount = 7  },
  { file = "HURT.png",     tag = "Hurt",   frameCount = 4  },
}

-- A brand new sprite always starts with exactly one frame and one layer
-- already in place, so we reuse that first frame rather than adding an
-- extra blank one at the start.
local outputSprite = Sprite(frameWidth, frameHeight)
local characterLayer = outputSprite.layers[1]
characterLayer.name = "character"

local isVeryFirstFrame = true

-- Records each animation's frame range so tags can be added in a second
-- pass, once every frame already exists (see note below on why).
local frameRangeByAnimation = {}

for _, animation in ipairs(animations) do
  local sheetPath = scriptFolder .. "/" .. animation.file
  local sheetImage = Image{ fromFile = sheetPath }

  for frameIndexInSheet = 0, animation.frameCount - 1 do
    local targetFrame
    if isVeryFirstFrame then
      targetFrame = outputSprite.frames[1]
      isVeryFirstFrame = false
    else
      -- No argument appends a new empty frame at the end of the sprite.
      targetFrame = outputSprite:newEmptyFrame()
    end

    -- Crop the full 96x96 grid cell (not just the character's ink) so
    -- every frame keeps the same alignment the original sheet used --
    -- tight-cropping would make the character jump around between frames.
    local cellRectangle = Rectangle(frameIndexInSheet * frameWidth, 0, frameWidth, frameHeight)
    local cellImage = Image(sheetImage, cellRectangle)

    outputSprite:newCel(characterLayer, targetFrame, cellImage, Point(0, 0))
  end

  local lastFrameNumberOfThisAnimation = #outputSprite.frames
  local firstFrameNumberOfThisAnimation = lastFrameNumberOfThisAnimation - animation.frameCount + 1
  table.insert(frameRangeByAnimation, {
    tag = animation.tag,
    firstFrame = firstFrameNumberOfThisAnimation,
    lastFrame = lastFrameNumberOfThisAnimation,
  })
end

-- Tags are added only after every frame has been created. Aseprite auto-
-- extends a tag when its last frame is also the sprite's current last
-- frame and more frames get appended afterward -- adding tags inside the
-- loop above made every earlier tag balloon out to frame 37. Doing this
-- as a separate pass, once the frame count is final, avoids that.
for _, range in ipairs(frameRangeByAnimation) do
  local newTag = outputSprite:newTag(range.firstFrame, range.lastFrame)
  newTag.name = range.tag
end

local outputPath = scriptFolder .. "/Samurai.aseprite"
outputSprite:saveAs(outputPath)

print("Saved " .. outputPath .. " with " .. #outputSprite.frames .. " frames and " .. #outputSprite.tags .. " tags.")
for _, tag in ipairs(outputSprite.tags) do
  print("  tag " .. tag.name .. ": frames " .. tag.fromFrame.frameNumber .. "-" .. tag.toFrame.frameNumber)
end
