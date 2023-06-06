local bakeRGB = true

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

local function readTile(im, xofs, yofs, tile, pal, bitsPerPixel)
	for y=0,tileHeight-1 do
		for x=0,tileWidth-1 do
			local ch = readpixel(tile, x, y, bitsPerPixel)
			if bakeRGB then
				im.buffer[0 + 4*((xofs+x) + im.width * (yofs+y))] = tonumber(pal[ch].r)/0x1f*0xff
				im.buffer[1 + 4*((xofs+x) + im.width * (yofs+y))] = tonumber(pal[ch].g)/0x1f*0xff
				im.buffer[2 + 4*((xofs+x) + im.width * (yofs+y))] = tonumber(pal[ch].b)/0x1f*0xff
				im.buffer[3 + 4*((xofs+x) + im.width * (yofs+y))] = ch==0 and 0 or tonumber(1-pal[ch].a)*0xff
			else
				local i = 0xff * ch / (bit.lshift(1, bitsPerPixel) - 1)
				im.buffer[0 + 4*((xofs+x) + im.width*(yofs+y))] = i
				im.buffer[1 + 4*((xofs+x) + im.width*(yofs+y))] = i
				im.buffer[2 + 4*((xofs+x) + im.width*(yofs+y))] = i
				im.buffer[3 + 4*((xofs+x) + im.width*(yofs+y))] = 0xff
			end
		end
	end
end

return {
	readpixel = readpixel,
	readTile = readTile,
	tileWidth = tileWidth,
	tileHeight = tileHeight,
}
