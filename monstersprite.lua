local ffi = require 'ffi'
local Image = require 'image'
local graphics = require 'graphics'
local readpixel = graphics.readpixel
local readTile = graphics.readTile
local tileWidth = graphics.tileWidth
local tileHeight = graphics.tileHeight

function readbit(ptr, ofs, bitindex)
	local b = ptr[ofs]
	return bit.band(bit.rshift(b, bitindex), 1)	
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

	-- weir that the tile-is-16-pixels bit is at the end of the 1st and not the 2nd byte ...
	local paletteIndex = monsterSprite.palLo + monsterSprite.palHi * 0x100
	
	local mold = monsterSprite.mold
	
	-- now find a monster image with a matching offset...
	
	local numColors = bit.lshift(1, bitsPerPixel)
	local tilesize = bit.rshift(tileWidth * tileHeight * bitsPerPixel, 3)
	local tileaddr = game.monsterSpriteData + offset * 8
		
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
	
	local pal = game.monsterPalettes[paletteIndex].s

	local moldData8, moldData16
	do
		local addr1 = game.monsterSprite8MoldOfs + 0x120000
		local addr2 = game.monsterSprite16MoldOfs + 0x120000
		local addr3 = 0x12b300
		
		local nummolds8 = bit.rshift((addr2 - addr1), 3)
		local nummolds16 = bit.rshift((addr3 - addr2), 5)
		
		-- 8 bytes, each byte is a row, each bit is a column flag
		moldData8 = rom + addr1
		-- by default points to start of monsterSpriteMoldData  
		--, nummolds8 * 8)
		
		-- 16 shorts, each short is a row, each bit is a column flag
		moldData16 = rom + addr2
		-- by default points inside of monsterSpriteMoldData  
		--, nummolds16 * 32)
	end



	local moldData
	if monsterSprite.tile16 == 0 then
		moldData = moldData8
	elseif monsterSprite.tile16 == 1 then
		moldData = moldData16
	end
	local moldstep = bit.rshift(tilesWide * tilesHigh, 3)
	
	local imgwidth = 0
	local imgheight = 0
	do
		local moldByte = mold * moldstep
		local moldBit = 0
		for y=0,tilesHigh-1 do
			for x=0,tilesWide-1 do
				if readbit(moldData, moldByte, 7-moldBit) ~= 0 then
					imgwidth = math.max(imgwidth, x)
					imgheight = math.max(imgheight, y)
				end
				moldBit = moldBit + 1
				if moldBit == 8 then
					moldBit = 0
					moldByte = moldByte + 1
				end
			end
		end
		
		imgwidth = imgwidth + 1
		imgheight = imgheight + 1
		imgwidth = imgwidth * tileWidth
		imgheight = imgheight * tileHeight
	end

	file'monsters':mkdir()

	local im = Image(imgwidth, imgheight, 4, 'unsigned char')
	ffi.fill(im.buffer, imgwidth * imgheight * 4)

	local moldByte = mold * moldstep
	local moldBit = 0
	for y=0,tilesHigh-1 do
		for x=0,tilesWide-1 do
			if readbit(moldData, moldByte, 7-moldBit) ~= 0 then
				local tile = tileaddr --, tilesize)
				readTile(im, x*tileWidth, y*tileHeight, tile, pal, bitsPerPixel)
				tileaddr = tileaddr + tilesize
			end
			moldBit = moldBit + 1
			if moldBit == 8 then
				moldBit = 0
				moldByte = moldByte + 1
			end
		end
	end
	
	im:save('monsters/monster'..index..'.png')
end
return writeMonsterSprite
