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

local function readFrame(rom, im, pal, xofs, yofs, charBaseOffset, frameTileOffset)
	for y=0,tilesHigh-1 do
		for x=0,tilesWide-1 do
			local tileOffset = frameTileOffset[x + 2 * y]
			tileOffset = tileOffset + charBaseOffset
			local tile = rom + tileOffset
			readTile(im, x*tileWidth+xofs, y*tileHeight+yofs, tile, pal, 4)
		end
	end
end


local function readCharSprite(game, charIndex) 
	local rom = ffi.cast('uint8_t*', game.padding_000000)
	assert(charIndex >= 0 and charIndex < game.numCharacterSprites)
	
	local spriteName = spriteNames[charIndex+1] or 'char'..charIndex
	--local spriteName = 'char'..charIndex

	local width = tileWidth*tilesWide
	local height = tileHeight*tilesHigh
	
	local palIndex = game.characterPaletteIndexes[charIndex]
	if palIndex > 8 then palIndex = 0 end
	if charIndex == 18 then palIndex = 8 end	-- special for morphed terra
	
	file'characters':mkdir()

	assert(#frameNames == game.numCharacterSpriteFrames)
	for frameIndex=0,#frameNames-1 do
		local frameName = frameNames[frameIndex+1]
		local frameTileOffset = game.characterFrameTileOffsets + frameIndex * tilesWide * tilesHigh
		local pal = game.characterPalettes[palIndex].s
		local charBaseOffset = bit.band(
			bit.bnot(0xc00000),
			bit.bor(
				game.characterSpriteOffsetLo[charIndex],
				bit.lshift(game.characterSpriteOffsetHiAndSize[charIndex].hi, 16)
			))
		local im = Image(width, height, 4, 'unsigned char')
		ffi.fill(im.buffer, width * height * 4)
		readFrame(rom, im, pal, 0, 0, charBaseOffset, frameTileOffset)
		local relname = spriteName..'_'..frameName..'.png'
		im:save('characters/'..relname)
	end
end

return readCharSprite
