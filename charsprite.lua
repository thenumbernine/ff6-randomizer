local ffi = require 'ffi'
local Image = require 'image'
local graphics = require 'graphics'
local readpixel = graphics.readpixel
local readTile = graphics.readTile
local tileWidth = graphics.tileWidth
local tileHeight = graphics.tileHeight

-- TODO get this from the game?
local spriteNames = {
	'terra',
	'locke',
	'cyan',
	'shadow',
	'edgar',
	'sabin',
	'celes',
	'strago',
	'relm',
	'setzer',
	'mog',
	'gau',
	'gogo',
	'umaro',
	'soldier',
	'imp',
	'leo',
	'banon',
	'morphedTerra',
	'merchant',
	'ghost',
	'kefka',
}
-- TODO get this from ... where?
local frameNames = {
	'walkd1',
	'standd',
	'walkd2',
	'walku1',
	'standu',
	'walku2',
	'walkl1',
	'standl',
	'walkl2',
	'wound',

	'ready',
	'pain',
	'stand',
	'swing',
	'handsupl1',
	'handsupl2',
	'cast1',
	'cast2',
	'dead',
	'eyesclosed',

	'winkd',
	'winkl',
	'handsupd',
	'handsupu',
	'growl',
	'saluted1',
	'saluted2',
	'saluteu1',
	'saluteu2',
	'laugh1',

	'laugh2',
	'startled',
	'sadd',
	'sadu',
	'sadl',
	'peeved',
	'finger1',
	'finger2',
	'jikuu',
	'tent',

	'dead2',
}

local tilesWide = 2
local tilesHigh = 3

local function readFrame(im, pal, charBasePtr, frameTileOffset, bitsPerPixel)
	-- characters have a set of ptrs-to-tiles (cuz they are reused often)
	-- no flags on/off (cuz the sprites are often dense/with no 8x8 holes)
	for y=0,tilesHigh-1 do
		for x=0,tilesWide-1 do
			local tile = charBasePtr + frameTileOffset[x + 2 * y]
			readTile(im, x*tileWidth, y*tileHeight, tile, pal, bitsPerPixel)
		end
	end
end


local function readCharSprite(game, charIndex)
	local rom = ffi.cast('uint8_t*', game.padding_000000)
	assert(charIndex >= 0 and charIndex < game.numCharacterSprites)

	--local spriteName = spriteNames[charIndex+1] or 'char'..charIndex
	local spriteName = 'char'..charIndex

	local width = tileWidth*tilesWide
	local height = tileHeight*tilesHigh

	local palIndex = game.characterPaletteIndexes[charIndex]
	if palIndex > 8 then palIndex = 0 end
	if charIndex == 18 then palIndex = 8 end	-- special for morphed terra

	file'characters':mkdir()

	local bitsPerPixel = 4

	local numFrames
	if charIndex < 22 then
		numFrames = 41
	elseif charIndex < 63 then
		numFrames = 9
	else
		numFrames = 1
	end

	for frameIndex=0,numFrames-1 do
		--local frameName = frameNames[frameIndex+1] or tostring(frameIndex)
		local frameName = tostring(frameIndex)
		
		local pal = game.characterPalettes[palIndex].s
		local charBaseOffset = bit.band(
			bit.bnot(0xc00000),
			bit.bor(
				game.characterSpriteOffsetLo[charIndex],
				bit.lshift(game.characterSpriteOffsetHiAndSize[charIndex].hi, 16)
			))
		local im = Image(width, height, 4, 'unsigned char')
		ffi.fill(im.buffer, width * height * 4)
		readFrame(im, pal,
			rom + charBaseOffset,
			game.characterFrameTileOffsets + frameIndex * tilesWide * tilesHigh,
			bitsPerPixel)
		local relname = spriteName..'_'..frameName..'.png'
		im:save('characters/'..relname)
	end
end

return readCharSprite
