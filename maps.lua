local ffi = require 'ffi'
local path = require 'ext.path'
local table = require 'ext.table'
local assert = require 'ext.assert'
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
	print('mapLayoutOffsets[0x'..i:hex()..'] offset=0x'
		..offset:hex()
		..' addr=0x'..('%06x'):format(addr)
		..(data and ' size=0x'..(#data):hex() or '')
	)
	--if data then print(data:hexdump()) end
end

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
		}
	end
	print('mapTilesetOffsets[0x'..i:hex()..'] offset=0x'
		..offset:hex()
		..' addr=0x'..('%06x'):format(addr)
		..(data and ' size=0x'..(#data):hex() or '')
	)
	--if data then print(data:hexdump()) end
end
print()

local mappath = path'maps'
mappath:mkdir()

-- output town tile graphics
-- the last 3 are 0xffffff
local mapTileGraphics = table()	-- 0-based
for i=0,countof(game.mapTileGraphicsOffsets)-1 do
	local offset = game.mapTileGraphicsOffsets[i]:value()
	local addr = offset + ffi.offsetof('game_t', 'mapTileGraphics')
	-- this is times something and then a pointer into game.mapTileGraphics
	print('mapTileGraphicsOffsets[0x'..i:hex()..'] = 0x'..offset:hex()
-- the space between them is arbitrary
--		..(i>0 and ('\tdiff=0x'..(game.mapTileGraphicsOffsets[i]:value() - game.mapTileGraphicsOffsets[i-1]:value()):hex()) or '')
	)
	mapTileGraphics[i] = {
		index = i,
		offset = offset,
		addr = addr,
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
			game.mapTileGraphics + bit.lshift(i, 5),
			bpp)
	end
	-- alright where is the palette info stored?
	-- and I'm betting somewhere is the 16x16 info that points into this 8x8 tile data...
	-- and I'm half-suspicious it is compressed ...
	im.palette = makePalette(game.mapPalettes + 0xc, 4, 16 * 8)
	im:save((mappath/'tiles.png').path)
end

makePaletteSets(
	mappath,
	game.mapPalettes,
	ffi.sizeof(game.mapPalettes) / ffi.sizeof'color_t',
	function(index) return bit.band(0xf, index) == 0 end
)


for mapIndex=0,countof(game.maps)-1 do
	local map = game.maps + mapIndex
	print('maps[0x'..mapIndex:hex()..'] = '..game.maps[mapIndex])
	-- map.gfx* points into mapTileGraphicsOffsets into mapTileGraphics
	-- these are 8x8 tiles

	local gfxs = table()
	for i=1,4 do
		gfxs[i] = mapTileGraphics[tonumber(map['gfx'..i])]
	end

	local tilesets = table()
	for i=1,2 do
		tilesets[i] = mapTilesets[tonumber(map['tileset'..i])]
		print('map tileset'..i..' data size', tilesets[i] and #tilesets[i].data)
	end

	local layerPos = table()
	local layerSizes = table()
	local layouts = table()
	for i=1,3 do
		local width = bit.lshift(1, 4 + map['layer'..i..'WidthLog2Minus4'])
		local height = bit.lshift(1, 4 + map['layer'..i..'HeightLog2Minus4'])
		layerSizes[i] = vec2i(width, height)
		layouts[i] = mapLayouts[tonumber(map['layout'..i])]
		print('map layer '..i..' size', layerSizes[i], 'volume', layerSizes[i]:volume())
		print('map layout'..i..' data size', layouts[i] and #layouts[i].data)
		if i > 1 then
			local ofs = map['layer'..i..'Pos']
			layerPos[i] = vec2i(ofs.x, ofs.y)
			print('map layer'..i..' pos', layerPos[i])
		end
	end

	local palette
	if map.palette >= 0 and map.palette < countof(game.mapPalettes) then
		palette = makePalette(game.mapPalettes + map.palette, 4, 16*8)
	else
		print(' map has invalid palette!')
	end

	local function tile8x8toptr(tile8x8)
		-- first 256 is gfx1
		if tile8x8 < 0x100 then
			local bpp = 4
			local gfx = gfxs[1]
			if not gfx then return end
			local tileptr = rom + gfx.addr + bit.lshift(tile8x8, bpp+1)
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
			local tileptr = rom + gfx.addr + bit.lshift(tile8x8, bpp+1)
			return tileptr, bpp
		end

		-- [[ from 0x180 to 0x200 I'm getting discrepencies as well...
		-- (what does bit-7 here represent?)
		if tile8x8 < 0x200 then
			local bpp = 4
			local gfx = gfxs[3]
			if not gfx then return end
			tile8x8 = bit.band(0x7f, tile8x8)
			local tileptr = rom + gfx.addr + bit.lshift(tile8x8, bpp+1)
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
			local tileptr = rom + gfx.addr + bit.lshift(tile8x8, bpp+1)
			return tileptr, bpp
		end
	end

	local function drawtile16x16(img, x, y, tile16x16, layer, zLevel)
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
				-- when i==8, j==0 we get ofs=16
				-- that should be the offset for i=0, j=0, yofs=1
				-- yofs gets assigned to bit 4 ...
				local tileZLevel = bit.band(0x2000, tilesetTile) ~= 0
				if tileZLevel == zLevel then
					local tile8x8 = bit.band(tilesetTile, 0x3ff)
					local tileptr, bpp = tile8x8toptr(tile8x8)
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

	local img = Image(
		-- map size is in 16x16 tiles, right?
		-- and should I size it by the first layer, or by the max of all layers?
		bit.lshift(layerSizes[1].x, 4),
		bit.lshift(layerSizes[1].y, 4),
		1,
		'uint8_t'
	):clear()

	for z=0,1 do
		--for layer=3,1,-1 do
		for layer=2,1,-1 do
			if not layouts[layer] then
			elseif layerSizes[layer]:volume() ~= #layouts[layer].data then
				print("map layout"..layer.." data size doesn't match layer size")
			else
				local posx, posy = 0, 0
				if layerPos[layer]
				-- if we have a position for the layer, but we're using parallax, then the position is going to be relative to the view
				--and map.parallax == 0
				then
					posx, posy = layerPos[layer]:unpack()
				end
				local layoutptr = ffi.cast('uint8_t*', layouts[layer].data)
				for tileY=0,layerSizes[1].y-1 do
					for tileX=0,layerSizes[1].x-1 do
						drawtile16x16(img,
							bit.lshift(((tileX - posx) % layerSizes[1].x), 4),
							bit.lshift(((tileY - posy) % layerSizes[1].y), 4),
							layoutptr[0],
							layer,
							z == 1)
						layoutptr = layoutptr + 1
					end
				end
			end
		end
	end

	img.palette = palette
	img:save((mappath/('map'..mapIndex..'.png')).path)

	-- save all map tileset 16x16 graphics separately
	local img = Image(16 * 16, 16 * 16, 1, 'uint8_t')
	for layer=1,2 do
		img:clear()
		-- what is its format?
		for j=0,15 do
			for i=0,15 do
				for z=0,1 do
					drawtile16x16(
						img,
						bit.lshift(i, 4),
						bit.lshift(j, 4),
						bit.bor(i, bit.lshift(j, 4)),
						layer,
						z == 1
					)
				end
			end
		end
		img.palette = palette
		img:save((mappath/('tile16x16_'..mapIndex..'_'..layer..'.png')).path)
	end

	-- save all map tile graphics separately
	-- hmm why 40?  16x16 for gfx1, 16x16 for gfx2, 16x8 for gfx3 ... gfx4?
	-- 10 bits total
	local tile8x8keySize = {16,40}
	local img = Image(tile8x8keySize[1] * tileWidth, tile8x8keySize[2] * tileHeight, 1, 'uint8_t'):clear()
	for j=0,tile8x8keySize[2]-1 do
		for i=0,tile8x8keySize[1]-1 do
			local tileptr, bpp = tile8x8toptr(i + tile8x8keySize[1] * j)
			if tileptr then
				readTile(
					img,
					bit.lshift(i, 3),
					bit.lshift(j, 3),
					tileptr,
					bpp
				)
			end
		end
	end
	img.palette = palette
	img:save((mappath/('tile8x8_'..mapIndex..'.png')).path)
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
