local ffi = require 'ffi'
local range = require 'ext.range'
local Image = require 'image'

-- reads a 8x8 tile
-- bitsPerPixel is 3 or 4
local function readpixel(tile, x, y, bitsPerPixel)
	local yhistep = 1
	if bitsPerPixel == 4 then
		yhistep = 2
	end

	-- bits 0,1,2

	-- bit 3
	if bitsPerPixel == 2 then
		return bit.bor(
			bit.band(1, bit.rshift(tile[2*y], 7-x)),
			bit.lshift(bit.band(1, bit.rshift(tile[2*y+1], 7-x)), 1)
		)
	elseif bitsPerPixel == 3 then
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
local function readTile(im, xofs, yofs, tile, bitsPerPixel, hflip, vflip)
	for y=0,tileHeight-1 do
		local dstp = im.buffer + (xofs + im.width*(yofs+y))
		local cy = vflip and tileHeight-1-y or y
		for x=0,tileWidth-1 do
			local cx = hflip and tileWidth-1-x or x
			dstp[0] = readpixel(tile, cx, cy, bitsPerPixel)
			dstp = dstp + 1
		end
	end
end

-- returns a Lua table of the palette
local function makePalette(pal, bpp, n)
	pal = ffi.cast('color_t*', pal)
	local mask = bit.lshift(1, bpp) - 1
	return range(0,(n or 256)-1):mapi(function(i)
		-- 0 is always transparent
		if bit.band(i, mask) == 0 then return {0,0,0,0} end
		local c = pal + i
		return {
			bit.bor(
				bit.lshift(c.r, 3),
				bit.rshift(c.r, 2)
			),
			bit.bor(
				bit.lshift(c.g, 3),
				bit.rshift(c.g, 2)
			),
			bit.bor(
				bit.lshift(c.b, 3),
				bit.rshift(c.b, 2)
			),
			c.a == 0 and 0xff or 0,
		}
	end)
end

local function readbit(byte, bitindex)
	return bit.band(bit.rshift(byte, bitindex), 1)
end

-- used by monsters
local function makeTiledImageWithMask(
	tilesWide,
	tilesHigh,
	bitsPerPixel,
	tileMaskData,
	tileMaskIndex,
	tileptr,
	pal
)
	assert(bitsPerPixel == 3 or bitsPerPixel == 4, "got invalid bpp: "..tostring(bitsPerPixel))
	tileMaskData = ffi.cast('uint8_t*', assert(tileMaskData))
	tileptr = ffi.cast('uint8_t*', assert(tileptr))
	-- pal better be palette_t of some kind

	-- how many bits in size
	local tileMaskStep = bit.rshift(tilesWide * tilesHigh, 3)

	local imgwidth = 0
	local imgheight = 0
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

	local im = Image(imgwidth, imgheight, 1, 'uint8_t')
		:clear()

	-- monsters have a set of tiles, in-order (cuz there aren't many duplicates),
	-- flagged on/off (cuz there are often 8x8 transparent holes in the sprites)
	local tilesize = bit.rshift(tileWidth * tileHeight * bitsPerPixel, 3)
	for y=0,tilesHigh-1 do
		for x=0,tilesWide-1 do
			local tileMaskBit = bit.lshift(tileMaskIndex * tileMaskStep, 3) + x + tilesWide * y
			if readbit(
				tileMaskData[bit.rshift(tileMaskBit, 3)],
				7 - bit.band(tileMaskBit, 7)
			) ~= 0 then
				readTile(im, x*tileWidth, y*tileHeight, tileptr, bitsPerPixel)
				tileptr = tileptr + tilesize
			end
		end
	end

	im.palette = makePalette(pal, bitsPerPixel, bit.lshift(1, bitsPerPixel))

	return im
end

return {
	readTile = readTile,
	tileWidth = tileWidth,
	tileHeight = tileHeight,
	makePalette = makePalette,
	makeTiledImageWithMask = makeTiledImageWithMask,
}
