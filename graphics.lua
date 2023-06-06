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
		local dstp = im.buffer + 4 * (xofs + im.width*(yofs+y))
		for x=0,tileWidth-1 do
			local ch = readpixel(tile, x, y, bitsPerPixel)
			if bakeRGB then
				local srcp = pal[ch]
				dstp[0] = tonumber(srcp.r)/0x1f*0xff
				dstp[1] = tonumber(srcp.g)/0x1f*0xff
				dstp[2] = tonumber(srcp.b)/0x1f*0xff
				dstp[3] = ch==0 and 0 or tonumber(1-srcp.a)*0xff
			else
				local i = 0xff * ch / (bit.lshift(1, bitsPerPixel) - 1)
				dstp[0] = i
				dstp[1] = i
				dstp[2] = i
				dstp[3] = 0xff
			end
			dstp = dstp + 4
		end
	end
end

return {
	readpixel = readpixel,
	readTile = readTile,
	tileWidth = tileWidth,
	tileHeight = tileHeight,
}
