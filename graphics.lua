local range = require 'ext.range'

-- bitsPerPixel is 3 or 4
local function readpixel(tile, x, y, bitsPerPixel)
	local yhistep = 1
	if bitsPerPixel == 4 then
		yhistep = 2
	end

	-- bits 0,1,2

	-- bit 3
	if bitsPerPixel == 3 then
		return bit.bor(
			bit.band(1, bit.rshift(tile[2*y], 7-x)),
			bit.lshift(bit.band(1, bit.rshift(tile[2*y+1], 7-x)), 1),
			bit.lshift(bit.band(1, bit.rshift(tile[y+16], 7-x)), 2))
	elseif bitsPerPixel == 4 then
		return bit.bor(
			bit.band(1, bit.rshift(tile[2*y], 7-x)),
			bit.lshift(bit.band(1, bit.rshift(tile[2*y+1], 7-x)), 1),
			bit.lshift(bit.band(1, bit.rshift(tile[2*y+16], 7-x)), 2),
			bit.lshift(bit.band(1, bit.rshift(tile[2*y+17], 7-x)), 3))
	end
end

local tileWidth = 8
local tileHeight = 8

-- reads as 8bpp-indexed
-- you have to bake palette yourself
local function readTile(im, xofs, yofs, tile, bitsPerPixel)
	for y=0,tileHeight-1 do
		local dstp = im.buffer + (xofs + im.width*(yofs+y))
		for x=0,tileWidth-1 do
			dstp[0] = readpixel(tile, x, y, bitsPerPixel)
			dstp = dstp + 1
		end
	end
end

-- returns a Lua table of the palette
local function makePalette(pal, n)
	return range(0,255):mapi(function(i)
		local b = bit.band(i , 15)
		local a = bit.rshift(i, 4)
		return
		b == 0 and {0,0,0,0} or 	-- 0 always transparent
		{
			math.floor(pal[a].s[b].r / 0x1f * 255),
			math.floor(pal[a].s[b].g / 0x1f * 255),
			math.floor(pal[a].s[b].b / 0x1f * 255),
			math.floor((1-pal[a].s[b].a) * 255),
		}
	end)

end

return {
	readpixel = readpixel,
	readTile = readTile,
	tileWidth = tileWidth,
	tileHeight = tileHeight,
	makePalette = makePalette,
}
