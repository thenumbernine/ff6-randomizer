local ffi = require 'ffi'
local Image = require 'image'
local graphics = require 'graphics'
local readpixel = graphics.readpixel
local readTile = graphics.readTile
local makePalette = graphics.makePalette
local tileWidth = graphics.tileWidth
local tileHeight = graphics.tileHeight

local function readbit(byte, bitindex)
	return bit.band(bit.rshift(byte, bitindex), 1)
end

local function writeMonsterSprite(game, index)
	local rom = ffi.cast('uint8_t*', game.padding_000000)
	local monsterSprite = game.monsterSprites[index]

	local offset = monsterSprite.offset

	local bitsPerPixel
	if monsterSprite._3bpp ~= 0 then
		bitsPerPixel = 3
	else
		bitsPerPixel = 4
	end

	local tileMaskIndex = monsterSprite.tileMaskIndex

	-- now find a monster image with a matching offset...

	local tilesWide, tilesHigh
	if monsterSprite.tile16 == 0 then
		tilesWide = 8
		tilesHigh = 8
	elseif monsterSprite.tile16 == 1 then
		tilesWide = 16
		tilesHigh = 16
	else
		error("danger danger")
	end

	-- weir that the tile-is-16-pixels bit is at the end of the 1st and not the 2nd byte ...
	local paletteIndex = bit.bor(monsterSprite.palLo, bit.lshift(monsterSprite.palHi, 8))
	local pal = game.monsterPalettes + paletteIndex

	local tileMaskData8, tileMaskData16
	do
		local addr1 = game.monsterSpriteTileMask8Ofs + 0x120000
		local addr2 = game.monsterSpriteTileMask16Ofs + 0x120000
		local addr3 = 0x12b300

		local numTileMasks8 = bit.rshift((addr2 - addr1), 3)
		local numTileMasks16 = bit.rshift((addr3 - addr2), 5)

		-- 8 bytes, each byte is a row, each bit is a column flag
		tileMaskData8 = rom + addr1
		-- by default points to start of monsterSpriteTileMaskData
		--, numTileMasks8 * 8)

		-- 16 shorts, each short is a row, each bit is a column flag
		tileMaskData16 = rom + addr2
		-- by default points inside of monsterSpriteTileMaskData
		--, numTileMasks16 * 32)
	end

	-- bitflags of which 8x8 tiles are used
	local tileMaskData
	if monsterSprite.tile16 == 0 then
		tileMaskData = tileMaskData8
	elseif monsterSprite.tile16 == 1 then
		tileMaskData = tileMaskData16
	end
	-- how many bits in size
	local tileMaskStep = bit.rshift(tilesWide * tilesHigh, 3)

	local imgwidth = 0
	local imgheight = 0
	do
		for y=0,tilesHigh-1 do
			for x=0,tilesWide-1 do
				local tileMaskBit = bit.lshift(tileMaskIndex * tileMaskStep, 3) + x + tilesWide * y
				if readbit(
					tileMaskData[bit.rshift(tileMaskBit, 3)],
					7 - bit.band(tileMaskBit, 7)
				) ~= 0 then
					imgwidth = math.max(imgwidth, x)
					imgheight = math.max(imgheight, y)
				end
			end
		end
		imgwidth = (imgwidth + 1) * tileWidth
		imgheight = (imgheight + 1) * tileHeight
	end

	path'monsters':mkdir()

	local im = Image(imgwidth, imgheight, 1, 'uint8_t')
	ffi.fill(im.buffer, im:getBufferSize())

	-- monsters have a set of tiles, in-order (cuz there aren't many duplicates),
	-- flagged on/off (cuz there are often 8x8 transparent holes in the sprites)
	local tilesize = bit.rshift(tileWidth * tileHeight * bitsPerPixel, 3)
	local tileaddr = game.monsterSpriteData + offset * 8
	for y=0,tilesHigh-1 do
		for x=0,tilesWide-1 do
			local tileMaskBit = bit.lshift(tileMaskIndex * tileMaskStep, 3) + x + tilesWide * y
			if readbit(
				tileMaskData[bit.rshift(tileMaskBit, 3)],
				7 - bit.band(tileMaskBit, 7)
			) ~= 0 then
				readTile(im, x*tileWidth, y*tileHeight, tileaddr, bitsPerPixel)
				tileaddr = tileaddr + tilesize
			end
		end
	end
	im.palette = makePalette(pal, 16)
	im:save('monsters/monster'..('%03d'):format(index)..' '..game.monsterNames[index]..'.png')

	return im.width * im.height
end
return writeMonsterSprite
