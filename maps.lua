local ffi = require 'ffi'
local path = require 'ext.path'
local table = require 'ext.table'
local range = require 'ext.range'
local assert = require 'ext.assert'
local tolua = require 'ext.tolua'
local vec2i = require 'vec-ffi.vec2i'
local Image = require 'image'
local makePalette = require 'graphics'.makePalette
local makePaletteSets = require 'graphics'.makePaletteSets
local tileWidth = require 'graphics'.tileWidth
local tileHeight = require 'graphics'.tileHeight
local readTile = require 'graphics'.readTile
local drawTile = require 'graphics'.drawTile
local decompress = require 'decompress'.decompress
local decompress0x800 = require 'decompress'.decompress0x800

-- util? ext.ffi or something?
local function countof(array)
	return ffi.sizeof(array) / ffi.sizeof(array[0])
end

return function(rom, game, romsize)

-- this holds the info of the 16x16 map blocks, interaction with player, etc
-- cache decompressed data
local mapLayouts = table()	-- 0-based
for i=0,countof(game.mapLayoutOffsets)-1 do
	local offset = game.mapLayoutOffsets[i]:value()
	local addr = 0xffffff
	local data
	if offset ~= 0xffffff then
		addr = offset + ffi.offsetof('game_t', 'mapLayoutsCompressed')
		data = decompress0x800(rom + addr, ffi.sizeof(game.mapLayoutsCompressed))
		mapLayouts[i] = {
			index = i,
			offset = offset,
			addr = addr,
			data = data,
		}
	end
	print('mapLayouts[0x'..i:hex()..'] offset=0x'
		..offset:hex()
		..' addr=0x'..('%06x'):format(addr)
		..(data and ' size=0x'..(#data):hex() or '')
	)
	--if data then print(data:hexdump()) end
end

--[[
This holds the mapping from 16x16 to 8x8 tiles.
A (layer 1 & 2) tileset is 2048 bytes in size = 256 * 2*2 * 2
(256 different mapLayout[] values) x (2x2 of the 8x8 subtiles) x (2 bytes for describing rendering the 8x8 subtile)
The 2 bytes describing rendering the 8x8 subtile provides a 10-bit index for lookup into the gfx1+2+3+4 set per map.
That means a map's tileset is unique wrt its gfx1+2+3+4 (+ palette)
--]]
local mapTilesets = table()	-- 0-based
for i=0,countof(game.mapTilesetOffsets)-1 do
	local offset = game.mapTilesetOffsets[i]:value()
	local addr = 0xffffff
	local data
	if offset ~= 0xffffff then
		addr = offset + ffi.offsetof('game_t', 'mapTilesetsCompressed')
		data = decompress0x800(rom + addr, ffi.sizeof(game.mapTilesetOffsets))
		mapTilesets[i] = {
			index = i,
			offset = offset,
			addr = addr,
			data = data,
			mapIndexes = table(),
			palettes = table(),
			gfxs = {},	-- gfx1/gfx2/gfx3/gfx4
		}
	end
	print('mapTilesets[0x'..i:hex()..'] offset=0x'
		..offset:hex()
		..' addr=0x'..('%06x'):format(addr)
		..(data and ' size=0x'..(#data):hex() or '')
	)
	--if data then print(data:hexdump()) end
end
print()

local mappath = path'maps'
mappath:mkdir()

-- map tile graphics, 8x8x4bpp tiles for layers 1 & 2
-- the last 3 are 0xffffff
local mapTileGraphics = table()	-- 0-based
for i=0,countof(game.mapTileGraphicsOffsets)-1 do
	local offset = game.mapTileGraphicsOffsets[i]:value()
	local addr = offset + ffi.offsetof('game_t', 'mapTileGraphics')
	-- this is times something and then a pointer into game.mapTileGraphics
	print('mapTileGraphics[0x'..i:hex()..'] = 0x'..offset:hex()
-- the space between them is arbitrary
--		..(i>0 and ('\tdiff=0x'..(game.mapTileGraphicsOffsets[i]:value() - game.mapTileGraphicsOffsets[i-1]:value()):hex()) or '')
	)
	mapTileGraphics[i] = {
		index = i,
		offset = offset,
		addr = addr,
		mapIndexes = table(),
	}
end
do	-- here decompress all 'mapTileGraphics' tiles irrespective of offset table
	-- 0x30c8 tiles of 8x8x4bpp = 32 bytes in game.mapTileGraphics
	local bpp = 4
	local numTiles = ffi.sizeof(game.mapTileGraphics) / bit.lshift(bpp, 3)	-- = 0x30c8
	-- 128 is just over sqrt numTiles
	local masterTilesWide = 16 -- 128
	local masterTilesHigh = math.ceil(numTiles / masterTilesWide)
	local im = Image(masterTilesWide*tileWidth, masterTilesHigh*tileHeight, 1, 'uint8_t'):clear()
	for i=0,numTiles-1 do
		local x = i % masterTilesWide
		local y = (i - x) / masterTilesWide
		readTile(im,
			x * tileWidth,
			y * tileHeight,
			game.mapTileGraphics + bit.lshift(bpp, 3),
			bpp)
	end
	-- alright where is the palette info stored?
	-- and I'm betting somewhere is the 16x16 info that points into this 8x8 tile data...
	-- and I'm half-suspicious it is compressed ...
	im.palette = makePalette(game.mapPalettes + 0xc, 4, 16 * 8)
	im:save((mappath/'tiles-layers1and2.png').path)
end

-- each points to compressed data, which decompressed is of size 0x1040
local mapTileGraphicsLayer3 = table()	--0-based
for i=0,countof(game.mapTileGraphicsLayer3Offsets)-1 do
	local offset = game.mapTileGraphicsLayer3Offsets[i]:value()
	local addr = offset + ffi.offsetof('game_t', 'mapTileGraphicsLayer3')
	local data = decompress0x800(rom + addr, ffi.sizeof('game_t', 'mapTileGraphicsLayer3'))
	mapTileGraphicsLayer3[i] = {
		index = i,
		offset = offset,
		addr = addr,
		data = data,
		mapIndexes = table(),
	}
	print('mapTileGraphicsLayer3[0x'..i:hex()..'] offset=0x'
		..offset:hex()
		..' addr=0x'..('%06x'):format(addr)
		..' size=0x'..(#data):hex()
	)
	--if data then print(data:hexdump()) end
end
-- each is 0x1040 in size .....
-- wait, is the first 0x40 the tileset?
-- leaving 0x1000 = 0x100 x 8x8x2bpp tiles
do
	local bpp = 2
	local n = countof(game.mapTileGraphicsLayer3Offsets)
	local im = Image(16*tileWidth, 16*n*tileHeight, 1, 'uint8_t'):clear()
	for i=0,n-1 do
		local gfxLayer3 = mapTileGraphicsLayer3[i]
		for x=0,15 do
			for y=0,15 do
				readTile(im,
					x * tileWidth,
					(y + 16 * i) * tileHeight,
					-- how come, for 4bpp, the tiles are 0x20 = 8*4 bytes = 8*8*4 bits = 1<<5 bytes apart
					-- but for 2bpp the tiles are 8*16 = 8*2 bytes = 8*8*2 bits = 1<<4 bytes apart ...
					ffi.cast('uint8_t*', gfxLayer3.data) + 0x40 + (x + 16 * y) * bit.lshift(bpp, 3),
					bpp)
			end
		end
	end
	-- alright where is the palette info stored?
	-- and I'm betting somewhere is the 16x16 info that points into this 8x8 tile data...
	-- and I'm half-suspicious it is compressed ...
	im.palette = makePalette(game.mapPalettes + 0xc, 4, 16 * 8)
	im:save((mappath/'tiles-layer3.png').path)
end

makePaletteSets(
	mappath,
	game.mapPalettes,
	ffi.sizeof(game.mapPalettes) / ffi.sizeof'color_t',
	function(index) return bit.band(0xf, index) == 0 end
)

local function layer1and2tile8x8toptr(tile8x8, gfxIndexes)
	local gfxs = table.mapi(gfxIndexes, function(i) return mapTileGraphics[i] end)

	-- first 256 is gfx1
	if tile8x8 < 0x100 then
		local bpp = 4
		local gfx = gfxs[1]
		if not gfx then return end
		local tileptr = rom + gfx.addr + tile8x8 * bit.lshift(bpp, 3)
		return tileptr, bpp
	end

	-- next 256 belong to gfx2?
	-- or only 128 of it?
	--if tile8x8 < 0x200 then
	-- (what does bit-7 here represent?)
	if tile8x8 < 0x180 then
		local bpp = 4
		local gfx = gfxs[2]
		if not gfx then return end
		tile8x8 = bit.band(0x7f, tile8x8)
		-- 256-511 and my tiles stop matching until I use this offset ... why
		-- skip 8x15 tiles ... idk why ... does the last 8 represent something special?
		--local gfxaddr = gfx.addr + 8 * 15 * 32
		local tileptr = rom + gfx.addr + tile8x8 * bit.lshift(bpp, 3)
		return tileptr, bpp
	end

	-- if gfx3 == gfx4 then gfx3's tiles are 0x180-0x27f
	if gfxs[3] == gfxs[4] then
		local bpp = 4
		local gfx = gfxs[3]
		if not gfx then return end
		-- is it 0x180 -> 0 or 0x180 -> 0x80?
		tile8x8 = bit.band(0xff, tile8x8 - 0x80)
		local tileptr = rom + gfx.addr + tile8x8 * bit.lshift(bpp, 3)
		return tileptr, bpp
	end

	-- [[ from 0x180 to 0x200 I'm getting discrepencies as well...
	-- (what does bit-7 here represent?)
	if tile8x8 < 0x200 then
		local bpp = 4
		local gfx = gfxs[3]
		if not gfx then return end
		tile8x8 = bit.band(0x7f, tile8x8)
		local tileptr = rom + gfx.addr + tile8x8 * bit.lshift(bpp, 3)
		return tileptr, bpp
	end
	--]]

	-- gfx3 doesn't use indexes 0x80 and over (reserved for something else?)
	-- (what does bit-7 here represent?)
	if tile8x8 < 0x280 then
		local bpp = 4
		local gfx = gfxs[4]
		if not gfx then return end
		tile8x8 = bit.band(0x7f, tile8x8)
		local tileptr = rom + gfx.addr + tile8x8 * bit.lshift(bpp, 3)
		return tileptr, bpp
	end

	-- extra notes to remember for later:
	-- animated tiles start at 0x280
	-- dialog graphics start at 0x2e0
	-- tiles 0x300-0x3ff aren't used by bg1 & bg2

end

local function layer3tile8x8toptr(tile8x8, gfxLayer3)
	local bpp = 2
	if not gfxLayer3 then return end
	if not gfxLayer3.data then return end
	local ofs = 0x40 + bit.band(0xff, tile8x8) * bit.lshift(bpp, 3)
	assert.lt(ofs, #gfxLayer3.data)
	local tileptr = ffi.cast('uint8_t*', gfxLayer3.data) + ofs
	return tileptr, bpp
end



--for mapIndex=0,countof(game.maps)-1 do
do local mapIndex=19
	local map = game.maps + mapIndex
	print('maps[0x'..mapIndex:hex()..'] = '..game.maps[mapIndex])
	-- map.gfx* points into mapTileGraphicsOffsets into mapTileGraphics
	-- these are 8x8 tiles

	local paletteIndex = tonumber(map.palette)

	local gfxIndexes = range(4):mapi(function(i)
		return tonumber(map['gfx'..i])
	end)

	local gfxs = table.mapi(gfxIndexes, function(i) return mapTileGraphics[i] end)

	for i=1,4 do
		if gfxs[i] then
			gfxs[i].mapIndexes[mapIndex] = true
		end
	end
	local gfxLayer3 = mapTileGraphicsLayer3[tonumber(map.gfxLayer3)]
	if gfxLayer3 then
		gfxLayer3.mapIndexes[mapIndex] = true
	end

	local tilesets = table()
	for i=1,2 do
		tilesets[i] = mapTilesets[tonumber(map['tileset'..i])]
		print('map tileset'..i..' data size', tilesets[i] and #tilesets[i].data)
		if tilesets[i] then
			tilesets[i].mapIndexes[mapIndex] = true
			tilesets[i].palettes[paletteIndex] = true
			tilesets[i].gfxs[
				gfxIndexes:mapi(tostring):concat'/'
			] = true
		end
	end

	local layerPos = table()
	local layerSizes = table()
	local layouts = table()
	for i=1,3 do
		local width = bit.lshift(1, 4 + map['layer'..i..'WidthLog2Minus4'])
		local height = bit.lshift(1, 4 + map['layer'..i..'HeightLog2Minus4'])
		layerSizes[i] = vec2i(width, height)
		local layoutIndex = tonumber(map['layout'..i])
		layouts[i] = layoutIndex > 0 and mapLayouts[layoutIndex] or nil
		print('map layer '..i..' size', layerSizes[i], 'volume', layerSizes[i]:volume())
		print('map layout'..i..' data size', layouts[i] and #layouts[i].data)
		if i > 1 then
			local ofs = map['layer'..i..'Pos']
			layerPos[i] = vec2i(ofs.x, ofs.y)
			print('map layer'..i..' pos', layerPos[i])
		end
	end

	local palette
	if paletteIndex >= 0 and paletteIndex < countof(game.mapPalettes) then
		palette = makePalette(game.mapPalettes + paletteIndex, 4, 16*8)
	else
		print(' map has invalid palette!')
	end

	local function tile8x8toptr(layer, tile8x8)
		if layer == 3 then
			return layer3tile8x8toptr(tile8x8, gfxLayer3)
		end
		assert(layer == 1 or layer == 2)
		return layer1and2tile8x8toptr(tile8x8, gfxIndexes)
	end

	local function layer1and2drawtile16x16(img, x, y, tile16x16, layer, zLevel)
		if not tilesets[layer] then return end
		local data = tilesets[layer].data
		assert.len(data, 0x800)
		if not data then return end
		local tilesetptr = ffi.cast('uint8_t*', data)
		for yofs=0,1 do
			for xofs=0,1 do
				local i = bit.lshift(bit.bor(xofs, bit.lshift(yofs, 1)), 8)
				local tilesetTile = bit.bor(
					tilesetptr[tile16x16 + i],
					bit.lshift(tilesetptr[tile16x16 + bit.bor(0x400, i)], 8)
				)
				local tileZLevel = bit.band(0x2000, tilesetTile) ~= 0
				if tileZLevel == zLevel then
					local tile8x8 = bit.band(tilesetTile, 0x3ff)
					local tileptr, bpp = tile8x8toptr(layer, tile8x8)
					if tileptr then
						local highPal = bit.band(7, bit.rshift(tilesetTile, 10))
						local hFlip8 = bit.band(0x4000, tilesetTile) ~= 0
						local vFlip8 = bit.band(0x8000, tilesetTile) ~= 0
						drawTile(img,
							x + bit.lshift(xofs, 3),
							y + bit.lshift(yofs, 3),
							tileptr,
							bpp,
							hFlip8,
							vFlip8,
							bit.lshift(highPal, 4),
							palette
						)
					end
				end
			end
		end
	end
	
	local function layer3drawtile16x16(img, x, y, tile16x16, zLevel)
		local layer = 3
		for yofs=0,1 do
			for xofs=0,1 do
				-- wait because tile16x16 << 2 has to be 8 bits
				-- that means tile16x16 can only be 6 bits
				-- and it also means that zLevel, hFlip, vFlip, highPal all must be 0
				local tilesetTile = bit.bor(
					bit.lshift(tile16x16, 2),
					bit.lshift(yofs, 1),
					xofs
				)
				tilesetTile = bit.band(tilesetTile, 0xff)
				local tileZLevel = bit.band(0x2000, tilesetTile) ~= 0
				if tileZLevel == zLevel then
					local tile8x8 = bit.band(tilesetTile, 0x3ff)
					-- bpp is always 2 for layer3
					local tileptr, bpp = tile8x8toptr(layer, tile8x8)
					if tileptr then
						drawTile(img,
							x + bit.lshift(xofs, 3),
							y + bit.lshift(yofs, 3),
							tileptr,
							bpp,
							nil,	-- hflip
							nil,	-- vflip
							nil,	-- palor
							palette
						)
					end
				end
			end
		end
	end

	local function drawtile16x16(img, x, y, tile16x16, layer, zLevel)
		if layer == 3 then
			return layer3drawtile16x16(img, x, y, tile16x16, zLevel)
		else
			return layer1and2drawtile16x16(img, x, y, tile16x16, layer, zLevel)
		end
	end

	local img = Image(
		-- map size is in 16x16 tiles, right?
		-- and should I size it by the first layer, or by the max of all layers?
		bit.lshift(layerSizes[1].x, 4),
		bit.lshift(layerSizes[1].y, 4),
		1,
		'uint8_t'
	):clear()

	for _,zAndLayer in ipairs(
		map.layer3Priority == 0
		and {
			{0,3},	-- layer 3 has no zOrder
			{0,2},
			{0,1},
			{1,2},
			{1,1},
		}
		or {
			{0,2},
			{0,1},
			{1,2},
			{1,1},
			{0,3},	-- layer 3 has no zOrder
		}
	)do
		local z, layer = table.unpack(zAndLayer)
		local blend = -1

		-- layer 3 avg
		if map.colorMath == 1 and layer == 3 then
			blend = 1
		-- layer 2 avg
		elseif map.colorMath == 4 and layer == 2 then
			blend = 1
		-- layer 3 add
		elseif map.colorMath == 5 and layer == 3 then
			blend = 0
		-- layer 1 avg
		elseif map.colorMath == 8 and layer == 1 then
			blend = 1
		-- there's more ofc but meh
		end
		-- TODO NOTICE blend does nothing at the moment
		-- because I'm outputting 8bpp-indexed

		local layerSize = layerSizes[layer]
		local layout = layouts[layer]
		local layoutData = layout and layout.data
		if not layout or not layoutData then
			print("missing layout "..layer, layout, layoutData)
		--elseif layerSize:volume() ~= #layouts[layer].data then
		--	print("map layout"..layer.." data size doesn't match layer size")
		-- I guess just modulo?
		else
			local posx, posy = 0, 0
			if layerPos[layer]
			-- if we have a position for the layer, but we're using parallax, then the position is going to be relative to the view
			--and map.parallax == 0
			then
				posx, posy = layerPos[layer]:unpack()
			end
			local layoutptr = ffi.cast('uint8_t*', layoutData)
			for dstY=0,layerSizes[1].y-1 do
				for dstX=0,layerSizes[1].x-1 do
					local srcX = (dstX + posx) % layerSize.x
					local srcY = (dstY + posy) % layerSize.y
					drawtile16x16(img,
						bit.lshift(dstX, 4),
						bit.lshift(dstY, 4),
						layoutptr[((srcX + layerSize.x * srcY) % #layoutData)],
						layer,
						z == 1,
						blend)
				end
			end
		end
	end

	img.palette = palette
	img:save((mappath/('map'..mapIndex..'.png')).path)

	-- save all map tileset 16x16 graphics separately
	for layer=1,3 do
		local size = layer == 3 and vec2i(8, 8) or vec2i(16, 16)
		local img = Image(16 * size.x, 16 * size.y, 1, 'uint8_t'):clear()
		-- what is its format?
		local tile16x16 = 0
		for j=0,size.y-1 do
			for i=0,size.x-1 do
				local zMax = layer == 3 and 0 or 1
				for z=0,zMax do
					drawtile16x16(
						img,
						bit.lshift(i, 4),
						bit.lshift(j, 4),
						tile16x16,
						layer,
						z == 1
					)
				end
				tile16x16 = tile16x16 + 1
			end
		end
		img.palette = palette
		img:save((mappath/('tile16x16_'..mapIndex..'_'..layer..'.png')).path)
	end

	-- save all map tile graphics separately
	-- hmm why 40?  16x16 for gfx1, 16x16 for gfx2, 16x8 for gfx3 ... gfx4?
	-- 10 bits total
	for layer=2,3 do
		local size = layer == 3 and vec2i(16,16) or vec2i(16,40)
		local img = Image(size.x * tileWidth, size.y * tileHeight, 1, 'uint8_t'):clear()
		local tile8x8 = 0
		for j=0,size.y-1 do
			for i=0,size.x-1 do
				local tileptr, bpp = tile8x8toptr(layer, tile8x8)
				if tileptr then
					readTile(
						img,
						bit.lshift(i, 3),
						bit.lshift(j, 3),
						tileptr,
						bpp
					)
				end
				tile8x8 = tile8x8 + 1
			end
		end
		img.palette = palette
		img:save((mappath/('tile8x8_'..mapIndex..'_'..(layer == 2 and '1and2' or '3')..'.png')).path)
	end
end

for _,i in ipairs(mapTilesets:keys():sort()) do
	local tileset = mapTilesets[i]
	if tileset then
		print('mapTilesets[0x'..i:hex()..']')
		print('','mapIndexes='..tolua(tileset.mapIndexes:keys():sort()))
		print('','palettes='..tolua(tileset.palettes:keys():sort()))
		print('','gfxs='..tolua(table.keys(tileset.gfxs):sort()))
	end
end

-- 8x8 tiles are going to be 16x40 = 640 in size
-- 16x16 tiles are going to be 16x16 = 256 in size
for _,i in ipairs(mapTileGraphics:keys():sort()) do
	local gfx = mapTileGraphics[i]
	local mapIndex = gfx.mapIndexes:keys():sort()[1] or 0
end

-- 8x8 tiles are going to be 16x16 = 256 in size
-- 16x16 tiles are going to be 16x16 = 256 in size
for _,i in ipairs(mapTileGraphicsLayer3:keys():sort()) do
	local gfx = mapTileGraphicsLayer3[i]
	local mapIndex = gfx.mapIndexes:keys():sort()[1] or 0
end


print()
for i=0,(0x040342 - 0x040000)/2-1 do
	local addr = game.mapEventTriggerOfs[i] + ffi.offsetof('game_t', 'mapEventTriggerOfs')
	local mapEventTrigger = ffi.cast('mapEventTrigger_t*', rom + addr)
	print('mapEventTrigger #'..i..': $'..('%04x'):format(addr))
	print(' '..mapEventTrigger)
end
print()

-- there are less entrance trigger offsets than entrance triggers
-- all the entranceTriggerOfs point into entranceTriggers aligned to entranceTrigger_t:
-- so I could dump the whole list of 0x469 entranceTrigger_t's
--  instead of just the offset list
for i=0,game.numEntranceTriggerOfs-1 do
	-- TODO use ref_t or whateever
	local addr = game.entranceTriggerOfs[i] + ffi.offsetof('game_t', 'entranceTriggerOfs')
	--assert.eq((addr - ffi.offsetof('game_t', 'entranceTriggers')) % ffi.sizeof'entranceTrigger_t', 0)
	print('entranceTrigger[0x'..i:hex()..']')
	print(' addr: $'..('%06x'):format(addr))
	local entranceTrigger = ffi.cast('entranceTrigger_t*', rom + addr)
	print(' '..entranceTrigger)
end

-- there are more entrance area trigger offsets than entrance area triggers
for i=0,game.numEntranceTriggerOfs-1 do
	local addr = game.entranceAreaTriggerOfs[i] + ffi.offsetof('game_t', 'entranceAreaTriggerOfs')
	--assert.eq((addr - ffi.offsetof('game_t', 'entranceAreaTriggers')) % ffi.sizeof'entranceAreaTrigger_t', 0)
	print('entranceAreaTrigger[0x'..i:hex()..']')
	print(' addr: $'..('%06x'):format(addr))
	local entranceAreaTrigger = ffi.cast('entranceAreaTrigger_t*', rom + addr)
	print(' '..entranceAreaTrigger)
end

print()
print(game.mapNames)

for i=0,0xff do
	print('WoBTileProps[0x'..i:hex()..'] = '..game.WoBTileProps[i])
end
for i=0,0xff do
	print('WoRTileProps[0x'..i:hex()..'] = '..game.WoRTileProps[i])
end
print()

print('WoB palette = '..game.WoBpalettes)
print('WoR palette = '..game.WoRpalettes)



--[[
-- 141002 bytes ... needs 131072 bytes ... has 9930 extra bytes ...
path'WoBMapDataCompressed.bin':write( ffi.string(game.WoBMapData+0, ffi.sizeof(game.WoBMapData)))
path'WoBMapDataCompressed.hex':write( ffi.string(game.WoBMapData+0, ffi.sizeof(game.WoBMapData)):hexdump())
local WoBMapDataDecompressed = decompress(game.WoBMapData+0, ffi.sizeof(game.WoBMapData))
print('WoBMapDataDecompressed', #WoBMapDataDecompressed)
path'WoBMapDataDecompressed.bin':write(WoBMapDataDecompressed)
path'WoBMapDataDecompressed.hex':write(WoBMapDataDecompressed:hexdump())
--]]


end
