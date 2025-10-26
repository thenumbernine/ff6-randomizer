local ffi = require 'ffi'
local tolua = require 'ext.tolua'
local Image = require 'image'
local makePalette = require 'graphics'.makePalette
local tileWidth = require 'graphics'.tileWidth
local tileHeight = require 'graphics'.tileHeight
local readTile = require 'graphics'.readTile

--[[
lets try to make sense of this mess...

battleAnimScriptOffsets[i]
	points to byte offset within battleAnimScripts[]

battleAnimScripts[i]
	handles frame playback of battleAnimSets[]

battleAnimSets[i]
	.wait is how long to wait
	.sound is what sound to play
	for j in 0,1,2:
		.palette[j] points into battleAnimPalettes[]
		.effect[j] points into battleAnimEffects[]
battleAnimEffects[i] ... this is one animated sequence, i.e. a collection of frames.
	.numFrames = how many frames in this animation-set's animation-effect's animation
	.width, .height = frame size, in 8x8 tiles
	._2bpp is true for 2bpp, false for 3bpp
	.graphicSet | (.graphicSetHighBit<<8)
		points into battleAnim8x8Tile_t list, which are 16x4 x 8x8 tiles
			2bpp list addr is * 0x40 + 0x12C000
			3bpp list addr is * 0x40 + 0x120000
	.frameIndexBase
		index into battleAnimFrame16x16TileOffsets[] to get effectFrame16x16TileOffsetPtr
	for frameIndex in 0..numFrames-1:
		frame16x16TilesPtr addr =
			0x110000
			+ effectFrame16x16TileOffsetPtr[frameIndex]
		... notice all these addrs span from 0x110141 to 0x11e96b,
			so it is the 'battleAnimFrame16x16Tiles'
frame16x16TilesPtr points to a list of battleAnim16x16Tile_t's = list of 16x16 tiles
	.x, .y = in 16x16 tile units, destination into this frame to draw this 16x16 tile
	.tile = index into graphicSet's 64x4 location of 8x8 tiles
		tile8x8DataBaseAddr + tileLen * graphicSetTile.tile
	.hflip16, .vflip16 = how to flip the 16x16 tile
battleAnim8x8Tile_t list holds:
	.tile = address into tile8x8DataBaseAddr + tileLen * graphicSetTile.tile
	.hflip = hflip 8x8
	.vflip = vflip 8x8


alltiles-2bpp is 512x184
alltiles-3bpp is 512x616
total is 512x800
i.e. 256x1600 i.e. 6.25 x 256x256 sheets
--]]

local battleAnimGraphicSetsPath = path'battleanim_graphicsets'
battleAnimGraphicSetsPath:mkdir()

return function(rom, game, romsize)
	local graphicSetsUsed = table()
	local paletteForTileIndex = {}
	local palettesUsed = table()
	local frame16x16TileAddrInfo = table()


	-- [==[ interface layer for game.*

	local numBattleAnimSets = game.numBattleAnimSets
	local numBattleAnimEffects = game.numBattleAnimEffects

	--[[ using the originals?
	local battleAnimSets = game.battleAnimSets
	local battleAnimEffects = game.battleAnimEffects
	local battleAnimFrame16x16TileOffsets = game.battleAnimFrame16x16TileOffsets
	local battleAnimGraphicsSets2bpp = game.battleAnimGraphicsSets2bpp
	local battleAnimGraphicsSets3bpp = game.battleAnimGraphicsSets3bpp
	local battleAnimFrame16x16Tiles = game.battleAnimFrame16x16Tiles
	--]]
	-- [[ lets try to separate the blobs and still reconstruct the same data correctly
	local battleAnimSets = ffi.new('battleAnimSet_t[?]', game.numBattleAnimSets)
	ffi.copy(battleAnimSets, game.battleAnimSets, ffi.sizeof(battleAnimSets))
	battleAnimGraphicSetsPath'animsets.bin':write(ffi.string(battleAnimSets, ffi.sizeof(battleAnimSets)))

	local battleAnimEffects = ffi.new('battleAnimEffect_t[?]', game.numBattleAnimEffects)
	ffi.copy(battleAnimEffects, game.battleAnimEffects, ffi.sizeof(battleAnimEffects))
	battleAnimGraphicSetsPath'animeffects.bin':write(ffi.string(battleAnimEffects, ffi.sizeof(battleAnimEffects)))

	local battleAnimFrame16x16TileOffsets = ffi.new('uint16_t[?]', 4194)
	ffi.copy(battleAnimFrame16x16TileOffsets, game.battleAnimFrame16x16TileOffsets, ffi.sizeof(battleAnimFrame16x16TileOffsets))
	battleAnimGraphicSetsPath'animframe16x16offsets.bin':write(ffi.string(battleAnimFrame16x16TileOffsets, ffi.sizeof(battleAnimFrame16x16TileOffsets)))

	local battleAnimGraphicsSets2bpp = ffi.new('battleAnim8x8Tile_t[?]', 0x20 * 0xb0)
	ffi.copy(battleAnimGraphicsSets2bpp, game.battleAnimGraphicsSets2bpp, ffi.sizeof(battleAnimGraphicsSets2bpp))
	battleAnimGraphicSetsPath'graphicsets2bpp.bin':write(ffi.string(battleAnimGraphicsSets2bpp, ffi.sizeof(battleAnimGraphicsSets2bpp)))

	local battleAnimGraphicsSets3bpp = ffi.new('battleAnim8x8Tile_t[?]', 0x20 * 0x180)
	ffi.copy(battleAnimGraphicsSets3bpp, game.battleAnimGraphicsSets3bpp, ffi.sizeof(battleAnimGraphicsSets3bpp))
	battleAnimGraphicSetsPath'graphicsets3bpp.bin':write(ffi.string(battleAnimGraphicsSets3bpp, ffi.sizeof(battleAnimGraphicsSets3bpp)))

	local battleAnimFrame16x16Tiles = ffi.new('battleAnim16x16Tile_t[?]', 0x74cb)
	ffi.copy(battleAnimFrame16x16Tiles, game.battleAnimFrame16x16Tiles, ffi.sizeof(battleAnimFrame16x16Tiles))
	battleAnimGraphicSetsPath'animframe16x16tiles.bin':write(ffi.string(battleAnimFrame16x16Tiles, ffi.sizeof(battleAnimFrame16x16Tiles)))

	-- no need to save 'battleAnimGraphics2bpp/3bpp, because that's tile data, stored in the tile sheets
	--]]
	--]==]

	local battleAnimGraphicSetsPerBpp = {
		[2] = battleAnimGraphicsSets2bpp,
		[3] = battleAnimGraphicsSets3bpp,
	}

	local infoPerBpp = {
		[2] = {
			-- 16x16 info in 8x8 partitions
			graphicSetBaseAddr = 0x12C000,	-- battleAnimGraphicsSets2bpp
			-- 8x8 tile data:
			tile8x8DataBaseAddr = 0x187000,	-- battleAnimGraphics2bpp
			tile8x8DataEndAddr = 0x18c9a0,
		},
		[3] = {
			graphicSetBaseAddr = 0x120000, 	-- battleAnimGraphicsSets3bpp
			tile8x8DataBaseAddr = 0x130000,	-- battleAnimGraphics3bpp
			tile8x8DataEndAddr = 0x14c998,
		},
	}

	-- total # of 8x8 tiles saved
	-- to give me a rough texture-atlas idea if I want to save the expanded tiles
	local totalTilesSaved = 0

	local battleAnimSetPath = path'battleanim'
	battleAnimSetPath:mkdir()
	for battleAnimSetIndex=0,numBattleAnimSets-1 do
		local battleAnim = battleAnimSets + battleAnimSetIndex
		print('battleAnimSet['..battleAnimSetIndex..'] = '..battleAnim)

		for j=0,2 do
			-- TODO array plz, but then TODO serialzie arrays in 'struct' please
			local effectIndex = battleAnim['effect'..(j+1)]
			local paletteIndex = battleAnim['palette'..(j+1)]

			if effectIndex ~= 0xffff then
				local unknown_15 = 0 ~= bit.band(0x8000, effectIndex)
				effectIndex = bit.band(0x7fff, effectIndex)
				-- idk what unknown_15 means.
				if effectIndex >= numBattleAnimEffects then
					-- NO MORE OF THESE ERRORS BEING HIT, NICE
					print('!!! effect is oob !!! '..('%x'):format(effectIndex))
				else
					local effect = battleAnimEffects + effectIndex
					print('\t\teffect'..(j+1)..'='..effect)

					local effectFrame16x16TileOffsetPtr = battleAnimFrame16x16TileOffsets + effect.frameIndexBase
					local graphicSetIndex = bit.bor(effect.graphicSet, bit.lshift(effect.graphicSetHighBit, 8))

					graphicSetsUsed[graphicSetIndex] = graphicSetsUsed[graphicSetIndex]
						or {
							effectDisplayIndex = {},
							palettes = {},
						}
					graphicSetsUsed[graphicSetIndex].effectDisplayIndex[j] = true
					graphicSetsUsed[graphicSetIndex].palettes[paletteIndex] = true
					palettesUsed[paletteIndex] = true

					local bpp = effect._2bpp == 1 and 2 or 3
					local info = infoPerBpp[bpp]

					-- number of battleAnim8x8Tile_t entries into the battleAnimGraphicSets[bpp] array (2 bytes each)
					local graphicSetOffset = graphicSetIndex * 0x20
					local graphicSetAddr = info.graphicSetBaseAddr + graphicSetOffset * ffi.sizeof'battleAnim8x8Tile_t'
					--local graphicSetTiles = ffi.cast('battleAnim8x8Tile_t*', rom + graphicSetAddr)
					local graphicSetTiles = battleAnimGraphicSetsPerBpp[bpp] + graphicSetOffset

					local tileLen = bit.lshift(bpp, 3)
					print('\t\teffectAddr=0x'..graphicSetAddr:hex()
						..', tileLen=0x'..tileLen:hex())

					local numFrames = effect.numFrames
					-- https://web.archive.org/web/20190907020126/https://www.ff6hacking.com/forums/thread-925.html
					-- ... says dont use the last 2 bits
					numFrames = bit.band(0x3f, numFrames)
					for frameIndex=0,numFrames-1 do
						print('\t\t\tframeIndex=0x'..frameIndex:hex()..':')

						local frame16x16TilesAddr = 0x110000 + effectFrame16x16TileOffsetPtr[frameIndex]  -- somewhere inside battleAnimFrame16x16Tiles
						print('\t\t\t\tframe16x16TilesAddr=0x'..frame16x16TilesAddr:hex())

						--[[
						ok i've got a theory.
						that the frame16x16TilesAddr (list of battleAnim16x16Tile_t's)
						 is going to be the unique identifier of an animation frame (except palette swaps).
						lets see if each frame16x16TilesAddr maps to always use the same graphicSetIndex
						i.e. they will have the same .bpp and .graphicSetIndex
						--]]
						frame16x16TileAddrInfo[frame16x16TilesAddr] = frame16x16TileAddrInfo[frame16x16TilesAddr] or table()
						local key = '0x'..graphicSetIndex:hex()..'/'..bpp
						frame16x16TileAddrInfo[frame16x16TilesAddr][key] = true

						-- convert the 0x110000-relative address into an battleAnimFrame16x16Tiles[] index since thats where it points after all
						local battleAnimFrame16x16TilesAddr = ffi.cast('uint8_t*', game.battleAnimFrame16x16Tiles) - ffi.cast('uint8_t*', rom)
						local animFrame16x16TileOffset = frame16x16TilesAddr - battleAnimFrame16x16TilesAddr
						assert.le(0, animFrame16x16TileOffset)
						assert.lt(animFrame16x16TileOffset, ffi.sizeof(game.battleAnimFrame16x16Tiles))	-- will this sizeof work?
						-- make sure its aligned to battleAnim16x16Tile_t
						assert.eq(0, bit.band(1, animFrame16x16TileOffset))
						local animFrame16x16TileIndex = bit.rshift(animFrame16x16TileOffset, 1)

						-- using the 0x110000 address offset:
						--local frame16x16TilesPtr = ffi.cast('battleAnim16x16Tile_t*', rom + frame16x16TilesAddr)
						-- using the battleAnimFrame16x16Tiles struct offset (where the ptr goes anyways):
						--local frame16x16TilesPtr = game.battleAnimFrame16x16Tiles + animFrame16x16TileIndex
						-- using the extracted binary blob:
						local frame16x16TilesPtr = battleAnimFrame16x16Tiles + animFrame16x16TileIndex

						local im = Image(
							2*tileWidth * effect.width,
							2*tileHeight * effect.height,
							1,
							'uint8_t'
						)
							:clear()

						-- looking for ways to test the tile count per-frame
						-- I think tracking the tile order is the best way
						local lastTileOrder
						for frameTile16x16Index=0,math.huge-1 do
							local battleAnim16x16Tile = frame16x16TilesPtr + frameTile16x16Index
							local x = battleAnim16x16Tile.x
							local y = battleAnim16x16Tile.y
							-- is an oob tile an end as well?
							if x >= effect.width then break end
							if y >= effect.height then break end
							local tileOrder = x + effect.width * y
							if lastTileOrder and lastTileOrder >= tileOrder then break end
							lastTileOrder = tileOrder

							totalTilesSaved = totalTilesSaved + 1

							print('\t\t\t\t\tbattleAnim16x16Tile='..battleAnim16x16Tile)
							-- paste into image
							for yofs=0,1 do
								for xofs=0,1 do
									-- this makes a lot more sense if you look it up in the 'alltiles' image below
									-- TLDR: Make a 16x8 tile display out of the 8x8 tiles pointed to by graphicSetTiles[]
									-- You'll see they make up 16x16-pixel regions
									-- Those are what we are indexing here, hence why you have to pick apart battleAnim16x16Tile.tile into its lower 3 bits and its upper 5
									local graphicSetTile = graphicSetTiles + bit.bor(
										-- bit 0 is xofs
										xofs,
										-- bits 123 is tile bits 012
										bit.lshift(
											bit.band(
												battleAnim16x16Tile.tile,
												7
											),
											1
										),
										-- bit 4 is yofs
										bit.lshift(yofs, 4),
										-- bits 567 is tile bits 345
										bit.lshift(
											-- .tile is 6 bits, so truncate 3 lower bits <-> & 0x38
											bit.band(
												battleAnim16x16Tile.tile,
												0x38
											),
										2)
									)
									local vflip = 0 ~= graphicSetTile.vflip
									local hflip = 0 ~= graphicSetTile.hflip
--print('xofs', xofs:hex(), 'yofs', yofs:hex(), 'graphicSetTile', graphicSetTile)
									-- 16384 indexable, but points to 0x130000 - 0x14c998, which only holds 4881
									paletteForTileIndex[graphicSetTile.tile] = paletteIndex
									local tile8x8DataAddr = info.tile8x8DataBaseAddr + tileLen * graphicSetTile.tile
									local xformxofs = xofs
									if battleAnim16x16Tile.hflip16 ~= 0 then
										xformxofs = 1 - xformxofs
										hflip = not hflip
									end
									local xformyofs = yofs
									if battleAnim16x16Tile.vflip16 ~= 0 then
										xformyofs = 1  - xformyofs
										vflip = not vflip
									end
									readTile(
										im,
										bit.bor(bit.lshift(x, 1), xformxofs)*tileWidth,
										bit.bor(bit.lshift(y, 1), xformyofs)*tileHeight,
										rom + tile8x8DataAddr,
										bpp,
										hflip,
										vflip
									)
								end
							end
						end

						local paltable = makePalette(game.battleAnimPalettes + paletteIndex, bit.lshift(1, bpp))
						im.palette = paltable
						im:save(battleAnimSetPath(
							('%03d'):format(battleAnimSetIndex)
							..('-%d'):format(j)	-- effect1,2,3
							..('-%02d'):format(frameIndex)
							..'.png').path)
					end
					print()
				end
			end
		end
	end
	print()

	print('total 8x8 tiles used for battle animations:', totalTilesSaved)
	print()

	local uniquePalettesUsed = palettesUsed:keys():sort()
	print('palettes used #:', uniquePalettesUsed:mapi(function(i) return '0x'..i:hex() end):concat', ')
	print('...'..#uniquePalettesUsed..' unique palettes')
	-- TODO these are palette8's used for 3bpp, but 2bpp just needs 4 colors ...
	-- 175 of 240 palettes are used ...
	-- ... I'll just copy them all into palette blobs.
	print()

	-- [[ graphic sets for effect #3 is supposed to have a different base address, hmmm...
	local uniqueGraphicSets = graphicSetsUsed:keys():sort()
	print('graphicSets used', uniqueGraphicSets:mapi(function(i) return '0x'..i:hex() end):concat', ')
	print('...'..#uniqueGraphicSets..' unique graphic sets')
	print()
	--]]

	-- so this is basically a plot of the entire pointer table at 0x120000
	--
	-- honestly this comes from a unique combo of graphicSet & effect 123 index (3 has a dif base)
	-- so I don't need to make so many copies ...
	--
	-- also each 'graphicSet' number is just 8 tiles worth of 16x16 tiles
	-- each 'graphicSet' is only addressible by 64 8x8 tiles = 16 16x16 tiles
	-- (because it's a byte, and its high two bits are used for hflip & vflip, so 64 values)
	-- so each 'graphicSet' is going to share 8 16x16 tiles in common with the next 'graphicSet'
	-- so 'graphicSet' is really '8x start of location in 8-tile-rows of 16x16 tileset'
	--
	-- so 1 'graphicSet' tiles is 16x4 of 8x8 = 8x2 of 16x16 = 128x32
	-- so 256 'graphicSets' with their even overlapping rows excluded is 128 x (32x128) = 128 x 4096
	-- but I could square this circle to be 512 x 1024
	-- ... but are there more than 256 addressible?
	-- yup there are.  so how do you address them, with just 1 byte?
	for bpp=2,3 do
		-- graphicSet * 0x40 + 0x120000 points to the table of u16 offsets
		-- the region 0x120000-0x126000 is for 'monster sprite tile mask data' ... nah, that's really just for this data.
		--		it's named 'monster' cuz monsters use 120000 as the base addr for their tile mask data,
		-- 		but really theirs always addresses into 'monsterSpriteTileMaskData'
		-- so that means there's only room for 0x180 of 0x40 within this region.
		-- so max graphics set is 0x180 ?  but how to index beyond 1 bytes worth?
		-- also
		-- monsters use 12a824-12ac24 for 8x8 tile masks
		-- and 12ac24-12b300 for 16x16 tile masks
		--local maxGraphicSet = 256
		local maxGraphicSet = assert.index({
			-- ??? wait, if its 2bpp then inc by 0x40 means skipping a full graphicsSet instead of just half...
			[2] = 0xb0,
			[3] = 384,
		}, bpp)

		-- 1 graphic set is (8x8) x (16x4)
		local setWidth = 16 * tileWidth
		local setHeight = 4 * tileHeight
		local masterSetsWide = 4	-- i'll make 4 cols of them
		local masterSetsHigh = math.ceil(maxGraphicSet/2/masterSetsWide)
		local master = Image(
			setWidth * masterSetsWide,
			setHeight * masterSetsHigh,
			4,	-- rgba
			'uint8_t'
		):clear()

		-- only plot the even graphicSetIndex tiles cuz the odd ones have a row in common
		for graphicSetIndex=0,maxGraphicSet-1,2 do
			assert.eq(bit.band(graphicSetIndex, 1), 0, "this wont be aligned in the master image")

			local halfGraphicsSetIndex = bit.rshift(graphicSetIndex, 1)
			local masterRow = halfGraphicsSetIndex % masterSetsHigh
			local masterCol = (halfGraphicsSetIndex - masterRow) / masterSetsHigh

			local graphicSetInfo = graphicSetsUsed[graphicSetIndex]
--print('graphicSet '..graphicSetIndex)
			local paletteIndex = 0
			local j = 0
			if graphicSetInfo then
				local effectDisplayIndexes = table.keys(graphicSetInfo.effectDisplayIndex):sort()
--print(' uses effect display indexes: '..effectDisplayIndexes:concat', ')
				j = effectDisplayIndexes[1] or 0
				local palettes = table.keys(graphicSetInfo.palettes):sort()
--print(' uses palettes: '..palettes:concat', ')
				paletteIndex = palettes:last() or 0
			end

			local tileLen = bit.lshift(bpp, 3)
			local info = infoPerBpp[bpp]
			local graphicSetTiles = battleAnimGraphicSetsPerBpp[bpp] + graphicSetIndex * 0x20

			local im = Image(
				0x10*tileWidth,
				4*tileHeight,
				1, 'uint8_t'
			)
			im.palette = makePalette(game.battleAnimPalettes + paletteIndex, bit.lshift(1, bpp))
			for y=0,3 do
				for x=0,15 do
					local graphicSetTile = graphicSetTiles + (x + 0x10 * y)
					local tile8x8DataAddr = info.tile8x8DataBaseAddr + tileLen * graphicSetTile.tile
					readTile(
						im,
						x * tileWidth,
						y * tileHeight,
						rom + tile8x8DataAddr,
						bpp,
						0 ~= graphicSetTile.hflip,
						0 ~= graphicSetTile.vflip
					)
				end
			end
			master:pasteInto{
				image = im:rgba(),
				x = masterCol * 128,
				y = masterRow * 32,
			}
			--im:save(battleAnimGraphicSetsPath(('%03d'):format(graphicSetIndex)..'.png').path)
		end
		master:save(battleAnimGraphicSetsPath('battle_anim_graphic_sets_'..bpp..'bpp.png').path)
	end

	print'frame16x16TileAddrInfo={'
	for _,addr in ipairs(frame16x16TileAddrInfo:keys():sort()) do
		print('\t[0x'..addr:hex()..'] = {'
			..frame16x16TileAddrInfo[addr]:keys():sort():concat', '
			..'},')
	end
	print'}'
	print()

	-- what about plotting the entire tile data?
	-- this is the data at 0x130000 - 0x14c998
	-- it's going to be 3bpp 8x8 data , so there will be 4881 of them
	do
		local tilesPerSheetInBits = 5
		local tilesPerSheetSize = bit.lshift(1, tilesPerSheetInBits)
		local sheetSize = tilesPerSheetSize * tileWidth	-- == tileHeight
		local tilesPerSheetMask = tilesPerSheetSize-1

		local tileImg = Image(tileWidth, tileHeight, 1, 'uint8_t')

		for bpp=2,3 do
			local info = infoPerBpp[bpp]
			tileImg:clear()

			local allTileSheets = table()

			local tileSizeInBytes = bit.lshift(bpp, 3)
			local totalTiles = math.floor((info.tile8x8DataEndAddr - info.tile8x8DataBaseAddr) / tileSizeInBytes)

			for tileIndex=0,totalTiles-1 do
				local tileX = bit.band(tileIndex, tilesPerSheetMask)
				local tileYAndSheetIndex = bit.rshift(tileIndex, tilesPerSheetInBits)
				local tileY = bit.band(tileYAndSheetIndex, tilesPerSheetMask)
				local sheetIndex = bit.rshift(tileYAndSheetIndex, tilesPerSheetInBits)

				readTile(
					tileImg,
					0,
					0,
					rom + info.tile8x8DataBaseAddr + tileSizeInBytes * tileIndex,
					bpp
				)
				local sheet = allTileSheets[sheetIndex+1]
				if not sheet then
					sheet = Image(sheetSize, sheetSize, 1, 'uint8_t'):clear()
					allTileSheets[sheetIndex+1] = sheet
				end

				-- use whatever's last as the palette
				local paletteIndex = paletteForTileIndex[tileIndex] or 0
				sheet.palette = makePalette(game.battleAnimPalettes + paletteIndex, bit.lshift(1, bpp))

				sheet:pasteInto{
					image = tileImg,
					x = bit.lshift(tileX, 3),	-- tx << 3 == tx * 8 == tx * tileWidth
					y = bit.lshift(tileY, 3),
				}
			end
			for sheetIndexPlus1,sheet in ipairs(allTileSheets) do
				sheet:save(battleAnimGraphicSetsPath('alltiles-'..bpp..'bpp-sheet'..sheetIndexPlus1..'.png').path)
			end
		end
	end

	-- space for 660 entries
	-- but if they are 1:1 with battleAnimEffects
	--  then just 650 entries
	local battleScriptAddrs = table()
	print()
	--for i=0,660-1 do
	for i=0,numBattleAnimEffects-1 do
		local offset = game.battleAnimScriptOffsets[i]
		local addr = offset + 0x100000
		--print('battleAnimScript['..i..']: offset=0x'..offset:hex()..', addr=0x'..addr:hex())
		battleScriptAddrs[addr] = battleScriptAddrs[addr] or table()
		battleScriptAddrs[addr]:insert(i)
	end
	print()

	-- of 660, 566 unique entries
	-- of 650, 565 as well
	local addrsInOrder = battleScriptAddrs:keys():sort()
	for i,addr in ipairs(addrsInOrder) do
		local addrend = addrsInOrder[i+1] or 0x107fb2
		print('battleAnimScript addr=0x'..addr:hex()..':')
		print(' used by script #s: '..battleScriptAddrs[addr]:concat', ')
		local pc = addr
		local linepc
		local lhs
		local function startline()
			lhs = ''
			linepc = pc
		end
		local function read()
--print(debug.traceback())			
			assert.le(0, pc)
			assert.lt(pc, romsize)
			local cmd = ffi.cast('uint8_t*', rom + pc)[0]
			--local cmd = rom[pc] --ffi.cast('uint8_t*', rom + pc)[0]
			lhs = lhs .. ' ' .. ('%02x'):format(cmd)	-- number.tostring arg is max # decimal digits ... i should do args for # lhs padding as well ...
			pc = pc + 1
assert.type(cmd, 'number')
			return cmd
		end
		local function reads8()
--print(debug.traceback())			
			assert.le(0, pc)
			assert.lt(pc, romsize)
			local cmd = ffi.cast('int8_t*', rom + pc)[0]
			--local cmd = rom[pc] --ffi.cast('int8_t*', rom + pc)[0]
			lhs = lhs .. ' ' .. ('%02x'):format(cmd)	-- number.tostring arg is max # decimal digits ... i should do args for # lhs padding as well ...
			pc = pc + 1
assert.type(cmd, 'number')
			return cmd
		end	
		local function readu16()
--print(debug.traceback())			
			assert.le(0, pc)
			assert.lt(pc, romsize-2)
			local cmd = ffi.cast('uint16_t*', rom + pc)[0]
			lhs = lhs .. ' ' .. ('%04x'):format(cmd)
			pc = pc + 2
assert.type(cmd, 'number')
			return cmd
		end
		local function readu32()
			assert.le(0, pc)
			assert.lt(pc, romsize-4)
--print(debug.traceback())			
			local cmd = ffi.cast('uint32_t*', rom + pc)[0]
			lhs = lhs .. ' ' .. ('%08x'):format(cmd)
			pc = pc + 4
assert.type(cmd, 'number')
			return cmd	
		end
		local function rhsprint(...)
--print(debug.traceback())			
			print(
				('$%04x: '):format(bit.band(0xffff, linepc))
				--('$%06x: '):format(linepc)
				..lhs
				..(' '):rep(20 - #lhs), ...)
			startline()
		end
		startline()
		
		local movedirs = {
			[0] = 'down/forward',
			'down',
			'down/back',
			'forward',
			'back',
			'up/forward',
			'up',
			'up/back'
		}

		local function u8(b)
assert.type(b, 'number')
			b = tonumber(ffi.cast('uint8_t', b))
			return ('0x%02x'):format(b)
		end
		local function s8(b)
assert.type(b, 'number')
			b = tonumber(ffi.cast('int8_t', b))
			if b < 0 then return '-0x'..math.abs(b):hex() end
			return '0x'..b:hex()
			--return ('0x%02x'):format(b)
		end
		local function u16(b)
assert.type(b, 'number')
			b = tonumber(ffi.cast('uint16_t', b))
			return ('0x%04x'):format(b)
		end

		while pc < addrend do
			local cmd = read()
			if cmd >= 0 and cmd < 0x20 then
				rhsprint('show frame '..u8(cmd))
			elseif cmd >= 0x20 and cmd < 0x80 then
				rhsprint('-')	-- that's all it has in the notes ... "-"
			elseif cmd == 0x80 then
				local subcmd = read()
				if subcmd == 0x00 then
					rhsprint('$D9BE quadra slam/quadra slice')
				elseif subcmd == 0x01 then
					rhsprint('$D9A9')
				elseif subcmd == 0x02 then
					rhsprint('$D981')
				elseif subcmd == 0x03 then
					rhsprint('$D995')
				elseif subcmd == 0x04 then
					rhsprint('$D96E randomize vector angle and position (init fire dance sprites)')
				elseif subcmd == 0x05 then
					rhsprint('$D938 bum rush')
				elseif subcmd == 0x06 then
					rhsprint('$D907 init tornado (w wind/spiraler)')
				elseif subcmd == 0x07 then
					rhsprint('$D8F2 move tornado to thread position (w wind/spiraler)')
				elseif subcmd == 0x08 then
					rhsprint('$D8EB move thread to vector position (w wind/spiraler)')
				elseif subcmd == 0x09 then
					rhsprint('$D879 update character/monster sprite tile priority for tornado (w wind/spiraler)')
				elseif subcmd == 0x0A then
					rhsprint('$D82B white/effect magic intro')
				elseif subcmd == 0x0B then
					rhsprint('$D7E3 update esper pre-animation balls position')
				elseif subcmd == 0x0C then
					rhsprint('$D753')
				elseif subcmd == 0x0D then
					rhsprint('$D7C4')
				elseif subcmd == 0x0E then
					rhsprint('$D79D')
				elseif subcmd == 0x0F then
					rhsprint('$D779')
				elseif subcmd == 0x10 then
					rhsprint('$D73E move to target position')
				elseif subcmd == 0x11 then
					rhsprint('$D727 randomize vector angle')
				elseif subcmd == 0x12 then
					rhsprint('$D734')
				elseif subcmd == 0x13 then
					rhsprint('$D6E5 toggle imp graphics for target (imp)')
				elseif subcmd == 0x14 then
					rhsprint('$D6BD make target vanish (vanish)')
				elseif subcmd == 0x15 then
					rhsprint('$D698 move circle to thread position')
				elseif subcmd == 0x16 then
					rhsprint('$D68E')
				elseif subcmd == 0x17 then
					rhsprint('$CBC1 update sprite layer priority based on target')
				elseif subcmd == 0x18 then
					rhsprint('$D677 load sketched monster palette')
				elseif subcmd == 0x19 then
					rhsprint('$D62E sketch')
				elseif subcmd == 0x1A then
					local arg = read()
					rhsprint('$CB74')
				elseif subcmd == 0x1B then
					rhsprint('$CB5D transform into magicite')
				elseif subcmd == 0x1C then
					rhsprint('$CB6A decrement screen brightness')
				elseif subcmd == 0x1D then
					rhsprint('$CB61 transform into magicite')
				elseif subcmd == 0x1E then
					rhsprint('$D56B')
				elseif subcmd == 0x1F then
					rhsprint('$D5FC')
				elseif subcmd == 0x20 then
					rhsprint('$D59F')
				elseif subcmd == 0x21 then
					rhsprint('$D54E update rotating sprite layer priority')
				elseif subcmd == 0x22 then
					rhsprint('$D4F2 pearl wind')
				elseif subcmd == 0x23 then
					rhsprint('$D4BE pearl wind')
				elseif subcmd == 0x24 then
					rhsprint('$D49B clear BG3 HDMA scroll data')
				elseif subcmd == 0x25 then
					rhsprint('$D4AD clear BG1 HDMA scroll data')
				elseif subcmd == 0x26 then
					local arg = read()
					rhsprint('$D493 '
						..(arg == 0 and 'enable' or 'disable')
						..' character color palette updates')
				elseif subcmd == 0x27 then
					local arg = read()
					rhsprint('$D48B '
						..(arg == 0 and 'show' or 'hide')
						..' characters for esper attack')
				elseif subcmd == 0x28 then
					local arg = read()
					rhsprint('$D45C affects all characters. sprite priority = '
						..bit.band(3, bit.rshift(arg, 4)))
				elseif subcmd == 0x29 then
					local arg = read()
					rhsprint('$D454 '
						..(arg == 0 and 'show' or 'hide')
						..' cursor sprites (esper attack)')
				elseif subcmd == 0x2A then
					local arg = read()
					rhsprint('$D44C load animation palette '
						..u8(arg)..', sprite')
				elseif subcmd == 0x2B then
					local arg = read()
					rhsprint('$D43C load animation palette '
						..u8(arg)
						..', bg1 (inferno)')
				elseif subcmd == 0x2C then
					local arg = read()
					rhsprint('$D444 load animation palette '
						..u8(arg)
						..', bg3 (justice, earth aura)')
				elseif subcmd == 0x2D then
					local x = readu16()
					local y = readu16()
					local z = readu16()
					rhsprint('$D423 jump to '..('$%04x'):format(x)..' for normal attack, '
						..('$%04x'):format(y)..' for back attack (or side and attacker is #3 or #4), '
						..('$%04x'):format(z)..' for pincer attack (or side and attacker is #1 or #2 or monster)')
				elseif subcmd == 0x2E then
					local x = read()
					local y = read()
					rhsprint('$D3E4 move sprite to ('
						..u8(x)..', '
						..u8(y)..')')
				elseif subcmd == 0x2F then
					rhsprint('$D3AF')
				elseif subcmd == 0x30 then
					local arg = read()
					rhsprint('$D38E load animation palette '
						..u8(arg)
						..' for character 1')
				elseif subcmd == 0x31 then
					local arg = read()
					rhsprint('$D365 move in wide vertical sine wave with speed '
						..u8(arg)
						..' (hope song, sea song)')
				elseif subcmd == 0x32 then
					local x = readu16()
					local y = readu16()
					if x == y then
						rhsprint('$D33E jump to '..('$%04x'):format(x))
					else
						rhsprint('$D33E jump to '
							..('$%04x'):format(x)..' if facing left, '
							..('$%04x'):format(y)..' if facing right')
					end
				elseif subcmd == 0x33 then
					local arg = read()
					rhsprint('$D2D2 update rainbow gradient lines')
				elseif subcmd == 0x34 then
					rhsprint('$D28D copy monster palettes to character palettes (hope song)')
				elseif subcmd == 0x35 then
					rhsprint('$D27A use character palettes for monster sprite data (hope song)')
				elseif subcmd == 0x36 then
					rhsprint('$D267 restore palettes for monster sprite data (hope song)')
				elseif subcmd == 0x37 then
					rhsprint('$D256 clear fixed color value hdma data ($2132)')
				elseif subcmd == 0x38 then
					rhsprint('$D24D enable high priority bg3 (justice)')
				elseif subcmd == 0x39 then
					local arg = read()
					rhsprint('$D1E6 update blue gradient lines (S. Cross, Carbunkl, Odin/Raiden)')
				elseif subcmd == 0x3A then
					local arg = read()
					rhsprint('$D1DE')
				elseif subcmd == 0x3B then
					rhsprint("$D1B0 set target's color palette to animation palette")
				elseif subcmd == 0x3C then
					rhsprint("$D18A set target's color palette to normal")
				elseif subcmd == 0x3D then
					rhsprint('$D12E quadra slam/quadra slice')
				elseif subcmd == 0x3E then
					local arg = read()
					rhsprint('$D126 set main screen designation ($212C)')
				elseif subcmd == 0x3F then
					rhsprint('$D0E0 sonic dive')
				elseif subcmd == 0x40 then
					local arg = read()
					rhsprint('$D0D3 set screen mode ($2105) to '
						..u8(arg))
				elseif subcmd == 0x41 then
					local cx, cy, dx, dy = reads8(), reads8(), reads8(), reads8()
					rhsprint('$D06D shrink BG1 by ('
						..s8(cx)..','..s8(cy)..') and move ('
						..s8(dx)..','..s8(dy)..')')
				elseif subcmd == 0x42 then
					local vh = read()
					rhsprint('$D064 set MODE7 Settings register ($211A)'
						..' vflip='..tostring(0 ~= bit.band(2, vh))
						..' hflip='..tostring(0 ~= bit.band(1, vh)))
				elseif subcmd == 0x43 then
					rhsprint('$D00B moon song/charm')
				elseif subcmd == 0x44 then
					rhsprint('$CFCC fire beam/bolt beam/ice beam')
				elseif subcmd == 0x45 then
					local arg = read()
					rhsprint('$CFC0 set BG1/BG2 mask settings hardware register ($2123)')
				elseif subcmd == 0x46 then
					rhsprint('$CFB9')
				elseif subcmd == 0x47 then
					rhsprint('$CFAA')
				elseif subcmd == 0x48 then
					rhsprint('$CF8D clear')
				elseif subcmd == 0x49 then
					rhsprint('$CF7F ink hit/virite')
				elseif subcmd == 0x4A then
					rhsprint('$CF6A')
				elseif subcmd == 0x4B then
					rhsprint('$D2CC update red/yellow gradient lines (megazerk)')
				elseif subcmd == 0x4C then
					rhsprint('$CF45 move triangle to thread position')
				elseif subcmd == 0x4D then
					rhsprint('$CF1C set vector from triangle to target')
				elseif subcmd == 0x4E then
					rhsprint('$CF15')
				elseif subcmd == 0x4F then
					rhsprint('$CEF0')
				elseif subcmd == 0x50 then
					rhsprint('$CE9A')
				elseif subcmd == 0x51 then
					rhsprint('$CE62 rippler')
				elseif subcmd == 0x52 then
					rhsprint('$CE29 stone')
				elseif subcmd == 0x53 then
					rhsprint('$CDDF r.polarity')
				elseif subcmd == 0x54 then
					rhsprint('$CDC4 r.polarity')
				elseif subcmd == 0x55 then
					rhsprint('$CD72 quasar')
				elseif subcmd == 0x56 then
					rhsprint('$CD28 goner')
				elseif subcmd == 0x57 then
					local arg = read()
					rhsprint('$CD1F set bg3/bg4 window mask settings ($2124) to '
						..u8(arg))
				elseif subcmd == 0x58 then
					local arg = read()
					rhsprint('$CD17 change circle shape to '
						..u8(arg))
				elseif subcmd == 0x59 then
					rhsprint('$CD12 goner/flare star')
				elseif subcmd == 0x5A then
					rhsprint('$CD0D mind blast')
				elseif subcmd == 0x5B then
					rhsprint('$CD08 mind blast')
				elseif subcmd == 0x5C then
					rhsprint('$CD03 mind blast')
				elseif subcmd == 0x5D then
					rhsprint('$CCDF')
				elseif subcmd == 0x5E then
					rhsprint('$CC98 overcast')
				elseif subcmd == 0x5F then
					local arg = reads8()
					rhsprint('$CC93 increase blue backdrop gradient by '..s8(arg)..' (used by Overcast)')
				elseif subcmd == 0x60 then
					local flags = readu32()	-- TODO is aabbccdd 8 bits or 4 bytes?
					rhsprint('$CC3F toggle attacker status'
						..(' $%08x'):format(flags)
						..' (morph/revert)')
				elseif subcmd == 0x61 then
					local xx, yy, zz = read(), read(), read()
					rhsprint('$CC1A')
				elseif subcmd == 0x62 then
					rhsprint('$CBF5 evil toot/fader')
				elseif subcmd == 0x63 then
					local arg = read()
					rhsprint('$D361 move in narrow vertical sine wave with speed '
						..u8(arg)
						..' (evil toot)')
				elseif subcmd == 0x64 then
					rhsprint('$CBE5 purifier/inviz edge')
				elseif subcmd == 0x65 then
					rhsprint('$CBE0')
				elseif subcmd == 0x66 then
					rhsprint('$CBDB shock wave')
				elseif subcmd == 0x67 then
					rhsprint('$CBD6 load extra esper palette (purifier)')
				elseif subcmd == 0x68 then
					rhsprint('$CBD1 purifier')
				elseif subcmd == 0x69 then
					rhsprint('$CBB6 update sprite layer priority based on attacker')
				elseif subcmd == 0x6A then
					rhsprint('$CBAC align bottom of thread with bottom of target (ice 3)')
				elseif subcmd == 0x6B then
					rhsprint('$CBB1 l? pearl')
				elseif subcmd == 0x6C then
					rhsprint('$CB5A overcast')
				elseif subcmd == 0x6D then
					rhsprint('$CB56 disable battle menu')
				elseif subcmd == 0x6E then
					rhsprint('$CB51')
				elseif subcmd == 0x6F then
					rhsprint('$CB4D')
				elseif subcmd == 0x70 then
					rhsprint('$CB43')
				elseif subcmd == 0x71 then
					rhsprint('$CB34 restore character palettes (purifier/hope song)')
				elseif subcmd == 0x72 then
					local arg = read()
					rhsprint('$CB48 branch forward '
						..u8(arg)..' if attack hit')
				elseif subcmd == 0x73 then
					local arg = read()
					rhsprint('$CB1D set graphics for dice roll (die index = '
						..u8(arg)..')')
				elseif subcmd == 0x74 then
					rhsprint('$CAB8')
				elseif subcmd == 0x75 then
					rhsprint('$CAE5 super ball')
				elseif subcmd == 0x76 then
					local arg = read()
					rhsprint('$CAD6 seize')
				elseif subcmd == 0x77 then
					rhsprint('$CADB seize')
				elseif subcmd == 0x78 then
					rhsprint('$CAE0 discard')
				elseif subcmd == 0x79 then
					rhsprint('$CAC2 characters run to left side of screen (takes 56 loops to reach other side)')
				elseif subcmd == 0x7A then
					rhsprint('$CAC7 characters run to right side of screen (takes 56 loops to reach other side)')
				elseif subcmd == 0x7B then
					rhsprint('$CACC flip all characters (after running to opposite side of screen)')
				elseif subcmd == 0x7C then
					rhsprint('$CAD1 swap target and attacker')
				elseif subcmd == 0x7D then
					local arg = read()
					rhsprint('$CABD if dragon horn effect is active then branch forward '
						..u8(arg)
						..' bytes')
				elseif subcmd == 0x7E then
					rhsprint('$CAA1 flip target character vertically')
				elseif subcmd == 0x7F then
					rhsprint('$CA9D hide all monsters')
				elseif subcmd == 0x80 then
					rhsprint('$CA65 boss death')
				elseif subcmd == 0x81 then
					rhsprint('$CA61')
				elseif subcmd == 0x82 then
					rhsprint('$CA3D boss death')
				elseif subcmd == 0x83 then
					rhsprint('$CA38')
				elseif subcmd == 0x84 then
					rhsprint('$CA29 chadarnook exit')
				elseif subcmd == 0x85 then
					rhsprint('$CA24 chadarnook exit')
				elseif subcmd == 0x86 then
					local arg = read()
					rhsprint('$CA0F play sound effect '
						..u8(arg)..', pan based on sprite X position')
				elseif subcmd == 0x87 then
					local arg = read()
					rhsprint('$C9F7 play sound effect '
						..u8(arg)..', pan based on sprite Y position')
				elseif subcmd == 0x88 then
					rhsprint('$C9C9')
				elseif subcmd == 0x89 then
					local arg = read()
					rhsprint('$C9C1')
				elseif subcmd == 0x8A then
					rhsprint('$C9A9 set target monster sprite priority to 0')
				elseif subcmd == 0x8B then
					rhsprint('$C9A5 play ching sound effect')
				elseif subcmd == 0x8C then
					local arg = read()
					rhsprint('$CA09 play sound effect '
						..u8(arg)..', pan center')
				else
					rhsprint('!!! uncharted subcmd')
				end
			elseif cmd == 0x81 then
				local xx, yy = read(), read()
				if xx == yy then
					rhsprint("$F347 change attacking character's graphic to "
						..u8(xx))
				else
					rhsprint("$F347 change attacking character's graphic to "
						..u8(xx).." if facing left, "
						..u8(yy).." if facing right")
				end
			elseif cmd == 0x82 then
				local xx, yy = read(), read()
				if xx == yy then
					rhsprint("$F33F change targetted character's graphic to "
						..u8(xx))
				else
					rhsprint("$F33F change targetted character's graphic to "
						..u8(xx).." if facing left, "
						..u8(yy).." if facing right")
				end
			elseif cmd == 0x83 then
				local arg = read()
				rhsprint('$F377 set dir='
					..movedirs[bit.rshift(arg, 5)]
					..' and move '
					..('$%02x'):format(bit.band(arg, 0x1f)+1))
			elseif cmd == 0x84 then
				local xx = read()
				rhsprint("$F7B3 set animation speed to "..u8(xx))
			elseif cmd == 0x85 then
				rhsprint("$F89D move thread to attacker position")
			elseif cmd == 0x86 then
				local arg = read()
				rhsprint('$F491 for attacker, set dir='
					..movedirs[bit.rshift(arg, 5)]
					..' and move '
					..('$%02x'):format(bit.band(arg, 0x1f)+1))
			elseif cmd == 0x87 then
				local arg = read()
				rhsprint('$F476 for target, set dir='
					..movedirs[bit.rshift(arg, 5)]
					..' and move '
					..('$%02x'):format(bit.band(arg, 0x1f)+1))
			elseif cmd == 0x88 then
				local arg = read()
				rhsprint([[$F71D fight: set frame to ]]
					..u8(arg)..[[ and jump forward with weapon]])
			elseif cmd == 0x89 then
				local arg = read()
				rhsprint("$F7BC loop from 0 to "..u8(arg-1))
			elseif cmd == 0x8A then
				rhsprint("$F82F loop end")
			elseif cmd == 0x8B then
				local arg = read()
				rhsprint("$F7E6 animated loop frame offset from +0 to +"..u8(arg-1))
			elseif cmd == 0x8C then
				rhsprint("$F84B animated loop end")
			elseif cmd == 0x8D then
				local arg = read()
				rhsprint("$F263 if animation is hflipped then set dir="
					..movedirs[bit.rshift(arg, 5)]
					..' and move '
					..('$%02x'):format(bit.band(arg, 0x1f)+1))
			elseif cmd == 0x8E then
				local arg = read()
				rhsprint('$F27A show thread '
					..(0 ~= bit.band(0x80, arg) and 'below' or 'above')
					..(0 ~= bit.band(0x40, arg) and 'front' or 'back')
					..' other sprites (sprite priority) with '
					..(0 ~= bit.band(1, arg) and '' or ' opposite')..'weapon hand')
			elseif cmd == 0x8F then
				-- TODO either 0x8D or 0x8F should probably be 'vflipped'
				local arg = read()
				rhsprint('$F263 if animation is hflipped then set dir='
					..movedirs[bit.rshift(arg, 5)]
					..' and move '
					..('$%02x'):format(bit.band(arg, 0x1f)+1))
			elseif cmd == 0x90 then
				local arg = read()
				rhsprint("$F255 set thread's sprite tile priority to "
					..bit.band(3, bit.rshift(arg, 4))
					..' (tile priority)')
			elseif cmd == 0x91 then
				rhsprint("$F8B4 move this thread to attacker thread position")
			elseif cmd == 0x92 then
				local speed, branch = read(), read()
				rhsprint('$FADB move thread along vector (speed '
					..u8(speed)..', code branch '
					..u8(branch)..')')
			elseif cmd == 0x93 then
				local arg = read()
				rhsprint("$FA3D set position on vector to "..u8(arg))
			elseif cmd == 0x94 then
				rhsprint("$F8E0 set vector from attacker to a random location on the target (GP Rain, AutoCrossbow)")
			elseif cmd == 0x95 then
				rhsprint("$F9E6 set vector from attacker to target")	
			elseif cmd == 0x96 then
				local xx, yy = read(), read()
				rhsprint('$FB63 if ??? then jump backwards '..u8(xx))
			elseif cmd == 0x97 then
				rhsprint("$FBD7 boomerang/wing edge/full moon/rising sun")
			elseif cmd == 0x98 then
				local arg, arg2 = read(), read()
				rhsprint('$FBA8 increment graphic index offset every '
					..u8(arg)
					..' frame(s), '..u8(arg2))
			elseif cmd == 0x99 then
				local arg = read()
				rhsprint("$FC37 set thread palette to "
					..('$%02x'):format(bit.band(7, bit.rshift(arg, 1))))
			elseif cmd == 0x9A then
				rhsprint("$FC40 set thread facing direction to match attacker")
			elseif cmd == 0x9B then
				rhsprint("$F31A")
			elseif cmd == 0x9C then
				local xx = read()
				rhsprint("$F2A2")
			elseif cmd == 0x9D then
				local xx = read()
				rhsprint("$F2F1")
			elseif cmd == 0x9E then
				rhsprint("$F2B6")
			elseif cmd == 0x9F then
				local arg = read()
				rhsprint("$F7CF animated loop start (loop count equal to the number of active threads, "
					..u8(arg).." = 0) (autocrossbow)")
			elseif cmd == 0xA0 then
				local arg, arg2 = read(), read()
				rhsprint("$FA4B jump forward along vector (speed "
					..u8(arg)..", code branch "..u8(arg)..")")
			elseif cmd == 0xA1 then
				local arg, arg2 = read(), read()
				rhsprint("$FA90 jump backward along vector (speed "
					..u8(arg)..", code branch "..u8(arg2)..")")
			elseif cmd == 0xA2 then
				rhsprint("$F2E1 drill")
			elseif cmd == 0xA3 then
				local xxxx = readu16()
				rhsprint("$F1E5 shift color palette left")
			elseif cmd == 0xA4 then
				local arg, arg2 = read(), read()
				rhsprint('$F21D shift color palette right'
					..' numcolors='..bit.band(0xf, arg)
					..' offset='..bit.band(0xf, bit.rshift(arg, 4))
					..' speed='..bit.band(0xf, arg2)
					..' paletteIndex='..bit.band(0xf, bit.rshift(arg, 4)))
			elseif cmd == 0xA5 then
				local aa, bb, cc, xx, yyyy, zz = read(), read(), read(), read(), readu16(), read()
				rhsprint('$F0EC circle origin ('
					..u8(aa+0x80)..','..u8(bb+0x80)..')'
					..' growspeed?='..u8(cc)
					..' maxsize='..u16(yyyy))
			elseif cmd == 0xA6 then
				local dx, dy, dr = read(), read(), read()
				rhsprint('$F094 move circle ('..s8(dx)..','..s8(dy)..'), size changes by '..s8(dr))
			elseif cmd == 0xA7 then
				rhsprint("$F088 update circle?")
			elseif cmd == 0xA8 then
				rhsprint("$F073 move circle to attacker")
			elseif cmd == 0xA9 then
				local dx, dy = read(), read()
				rhsprint('$EFC8 move circle ('..s8(dx)..','..s8(dy)..') (based on character facing direction)')
			elseif cmd == 0xAA then
				local arg = read()
				rhsprint('$EC6E set sprite palette 3 color subtraction (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xAB then
				local arg = read()
				rhsprint('$EC58 set sprite palette 3 color addition (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xAC then
				local xx, yy = read(), read()
				rhsprint([[$EE9C set background scroll HDMA data 123fffff vhaaaaaa 1: affect BG1 2: affect BG2 3: affect BG3 f: frequency v: vertical h: horizontal a: amplitude (max 14, must be even ???)]])
			elseif cmd == 0xAD then
				local arg = read()
				rhsprint('$EFA3 set BG scroll HDMA index: BG='..bit.rshift(arg, 6)
					..' index='..u8(bit.band(arg, 0x3f)))
			elseif cmd == 0xAE then
				local vh___123 = read()
				rhsprint("vh---123    $ED86 Update Scroll HDMA data v: vertical h: horizontal 1: affect BG1 2: affect BG2 3: affect BG3")
			elseif cmd == 0xAF then
				local arg = read()
				rhsprint('$EBDA set background palette color subtraction (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xB0 then
				local arg = read()
				rhsprint('$EBC4 set background palette color addition (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xB1 then
				local arg = read()
				rhsprint('$ECAC set sprite palette 1 color subtraction (absolute)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xB2 then
				local arg = read()
				rhsprint('$EC96 Set sprite palette 1 color addition (absolute)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xB3 then
				local arg = read()
				rhsprint('$EC4F add color to sprite palette 3 (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xB4 then
				local arg = read()
				rhsprint('$EC46 subtract color from sprite palette 3 palette (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xB5 then
				local arg = read()
				rhsprint('$EBB2 add color to background palette (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xB6 then
				local arg = read()
				rhsprint('$EBBB subtract color from background palette (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xB7 then
				local arg = read()
				rhsprint('$EC84 add color to sprite palette 1 (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xB8 then
				local arg = read()
				rhsprint('$EC8D subtract color from sprite palette 1 (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xB9 then
				local arg = read()
				rhsprint('$ECEA set monster palettes color subtraction (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xBA then
				local arg = read()
				rhsprint('$ECD4 set monster palettes color addition (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xBB then
				local arg = read()
				rhsprint('$ECCB add color to monster palettes (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xBC then
				local arg = read()
				rhsprint('$ECC2 subtract color from monster palettes (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xBD then
				-- TODO this makes me doubt the bit ordering i interpreted the rest of the docs as...
				-- is lowest bit first, or is lowest bit last?
				local abcd____ = read()
				rhsprint("$EAA1 Hide/Show BG1/BG3 Animation Thread Graphics a: affect bg1 b: affect bg3 c: bg1 (0 = show, 1 = hide) d: bg3 (0 = show, 1 = hide)")
			elseif cmd == 0xBE then
				local arg = read()
				rhsprint('$EA98 set screen mosaic to '..u8(arg)..' ($2106)')
			elseif cmd == 0xBF then
				local arg = readu16()
				rhsprint("$EA85 jump to subroutine $"..u16(arg))
			elseif cmd == 0xC0 then
				rhsprint("$EA76 return from subroutine")
			elseif cmd == 0xC1 then
				local xx, yy = read(), read()
				rhsprint('$EA05 vector movement speed? = '..u8(xx)..', branch backwards '..u8(yy)..' bytes')
			elseif cmd == 0xC2 then
				local abc_____ = read()
				rhsprint("$E9EB unpause animation a: unpause bg1 b: unpause bg3 c: unpause sprites")
			elseif cmd == 0xC3 then
				rhsprint("$F02F move circle to target")
			elseif cmd == 0xC4 then
				local ab______ = read()
				rhsprint("$E99F Move BG1/BG3 Thread to This Thread's Position a: affect bg1 b: affect bg3")
			elseif cmd == 0xC5 then
				local a, b, c, d = readu16(), readu16(), readu16(), readu16()
				rhsprint("$E8FB jump based on swdtech hit: {"
					..table{u16(a), u16(b), u16(c), u16(d)}:concat', '..'}'
					)
			elseif cmd == 0xC6 then
				local xx, yy = read(), read()
				rhsprint("$E830 quadra slam/quadra slice")
			elseif cmd == 0xC7 then
				local subcmd = read()
				if subcmd == 0x00 then
					local arg = read()
					rhsprint('$C2C39B change attacking character facing direction to '
						..(arg == 0 and 'left' or 'right'))
				elseif subcmd == 0x01 then
					rhsprint("$C2C362 reset position offsets for attacking character")
				elseif subcmd == 0x02 then
					rhsprint("$C2C31E save attacking character position")
				elseif subcmd == 0x03 then
					rhsprint("$C2C339 restore attacking character position and reset offsets")
				elseif subcmd == 0x04 then
					rhsprint("$C2C303 restore attacking character position")
				elseif subcmd == 0x05 then
					local arg = read()
					rhsprint("$C2C2B7 (unused)")
				elseif subcmd == 0x06 then
					local arg, arg2 = read(), read()
					rhsprint("$C2C26A")
				elseif subcmd == 0x07 then
					rhsprint("$C2C247 update character action based on vector direction (walking)")
				elseif subcmd == 0x08 then
					local x, y = read(), read()
					rhsprint('$C2C1D6 set vector target ('..u8(x)..','..u8(y)..') from attacker')
				elseif subcmd == 0x09 then
					rhsprint("$C2C1B3 update character action based on vector direction (arms up)")
				elseif subcmd == 0x0A then
					local xx = read()
					rhsprint("$C2C194 (unused)")
				elseif subcmd == 0x0B then
					local x, y, z = read(), read(), read()
					rhsprint("$C2C171 spc("
						..table{u8(x), u8(y), u8(z)}:concat', '..')'
					)
				elseif subcmd == 0x0C then
					local arg, arg2 = read(), read()
					rhsprint('$C2C136 change actor '..u8(arg)..' graphic index to '..u8(arg2))
				elseif subcmd == 0x0D then
					local arg = read()
					rhsprint("$C2C115")
				elseif subcmd == 0x0E then
					local arg = read()
					rhsprint("$C2C0F8 screen shaking ($6285) = "..u8(arg))
				elseif subcmd == 0x0F then
					rhsprint("$C2C0F2 (unused)")
				elseif subcmd == 0x10 then
					local xx = read()
					rhsprint("$C2C0B9")
				elseif subcmd == 0x11 then
					rhsprint("$C2C0B0 disable run from battle")
				else
					rhsprint("!!! unknown subcmd")
				end
			elseif cmd == 0xC8 then
				local arg = read()
				rhsprint("$E7B1 set attacker modified graphic index = "..u8(arg))
			elseif cmd == 0xC9 then
				local arg = read()
				rhsprint("$DAE4 "..(arg == 0 
					and ("play animation default sound effect")
					or "play sound effect "..u8(arg)
				))
			elseif cmd == 0xCA then
				rhsprint("$E798")
			elseif cmd == 0xCB then
				local eddddddd = read()
				rhsprint("$E779 enable/disable echo sprites (4 copies of character sprite) e: 1 = enable, 0 = disable d: frame delay between echo sprites (bitmask)")
			elseif cmd == 0xCC then
				local arg = read()
				rhsprint('$EC24 set sprite palette 2 color subtraction (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xCD then
				local arg = read()
				rhsprint('$EC02 set sprite palette 2 color addition (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xCE then
				local arg = read()
				rhsprint('$EBF0 add color to sprite palette 2 (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xCF then
				local arg = read()
				rhsprint('$EBF9 subtract color from sprite palette 2 (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xD0 then
				local vhftpppm = read()
				rhsprint("$E746 Set sprite data for all character/monster sprites")
			elseif cmd == 0xD1 then
				local xx = read()
				rhsprint("$E73D Validate/Invalidate Character/Monster Order Priority (0 = validate, 1 = invalidate)")
			elseif cmd == 0xD2 then
				local xx, yy = read(), read()
				rhsprint('$F86D set target position ('..u8(xx)..','..u8(yy)..") doesn't actually move target")
			elseif cmd == 0xD3 then
				rhsprint("$F044 move circle to attacking character")
			elseif cmd == 0xD4 then
				local xxxx, yy = readu16(), read()
				rhsprint([[$E722 Set Color Addition/Subtraction Data
                      shbo4321 mmss--cd (+$2130)
                               s: 0 = add, 1 = subtract
                               h: 0 = full add/sub, 1 = half add/sub
                               bo4321: layers affected by add/sub (b = background)
                               m: 0
                               s: 0
                               c: 0 = fixed color add/sub, 1 = subscreen add/sub
                               d: 0
                      ---o4321 subscreen designation ($212D)
                               o4321: layers to add/sub
]])			
			elseif cmd == 0xD5 then
				local arg = read()
				rhsprint('$E707 set monster'
					..(0 ~= bit.band(1, arg) and ' hflip' or '')
					..(0 ~= bit.band(2, arg) and ' vflip' or ''))
			elseif cmd == 0xD6 then
				rhsprint("$E6CD")
			elseif cmd == 0xD7 then
				local xx = read()
				rhsprint("$E68D move fire dance sprites")
			elseif cmd == 0xD8 then
				local xx, yy, zz = read(), read(), read()
				rhsprint('$E5F9 x speed='..u8(xx)..' y speed='..u8(yy)..' ??? = '..u8(zz))
			elseif cmd == 0xD9 then
				local xx = read()
				rhsprint("$E5F0 (bum rush)")
			elseif cmd == 0xDA then
				local xxxx = readu16()
				rhsprint("$E528 update tornado (w wind/spiraler)")
			elseif cmd == 0xDB then
				local xx = read()
				rhsprint('$E509 if character already stepped forward to attack then branch +'..u8(xx))
			elseif cmd == 0xDC then
				rhsprint("$E43A rotate triangle 2D")
			elseif cmd == 0xDD then
				local xx, yy, dd, rr = read(), read(), read(), read()
				rhsprint("$E416 init triangle")
			elseif cmd == 0xDE then
				rhsprint("$E401 move triangle to attacker position")
			elseif cmd == 0xDF then
				rhsprint("$E3EC move triangle to target position")
			elseif cmd == 0xE0 then
				local xx, yy, dd, rr = read(), read(), read(), read()
				rhsprint("$E3A0 modify triangle")
			elseif cmd == 0xE1 then
				local xx = read()
				rhsprint("$E328 show/hide attacker sprite")
			elseif cmd == 0xE2 then
				rhsprint("$DD8D")
			elseif cmd == 0xE3 then
				rhsprint("$DD42")
			elseif cmd == 0xE4 then
				rhsprint("$E286")
			elseif cmd == 0xE5 then
				local xx, yy, zz = read(), read(), read()
				rhsprint("$E15D branch -"..u8(yy))
			elseif cmd == 0xE6 then
				local xx, yy, zz = read(), read(), read()
				rhsprint("$E1B3 branch -"..u8(yy))
			elseif cmd == 0xE7 then
				rhsprint("$E25A calculate vector from attacking character to target")
			elseif cmd == 0xE8 then
				local rr, tt = read(), read()
				rhsprint('$DCDF move to polar coordinates r='..u8(rr)..' theta='..u8(tt))
			elseif cmd == 0xE9 then
				local xx, yy = read(), read()
				rhsprint('$DC9B move randomly (0..'..u8(xx)..', 0..'..u8(yy)..')')
			elseif cmd == 0xEA then
				local _13__xxxx = read()
				rhsprint("$DC81 set BG tile data quadrants 1 = affect bg1 3 = affect bg1 x = quadrant")
			elseif cmd == 0xEB then
				-- TODO count as many as threads ... how to determine # of threads?
				local xxxx = readu16()
				rhsprint("$DC66 jump to "..u16(xxxx).." based on thread index (number of addresses is number of threads)")
			elseif cmd == 0xEC then
				local xx = read()
				rhsprint("$DC55 change thread layer (0 = sprite, 1 = bg1, 2 = bg3)")
			elseif cmd == 0xED then
				rhsprint("$DB8F")
			elseif cmd == 0xEE then
				local __oo____ = read()
				rhsprint("$E5C5 set target's sprite tile priority")
			elseif cmd == 0xEF then
				local rr, tt = read(), read()
				rhsprint('$DCD9 move to polar coordinates r='..u8(rr)..' theta='..u8(tt)..' (similar to $E8)')
			elseif cmd == 0xF0 then
				local a,b,c,d,e = readu16(), readu16(), readu16(), readu16(), readu16()
				rhsprint("$DB6C jump based on current target index (char1, char2, char3, char4, monster)")
			elseif cmd == 0xF1 then
				local xx = read()
				rhsprint("$E2C0")
			elseif cmd == 0xF2 then
				rhsprint("$F980 Set a trajectory from target center to attacker")
			elseif cmd == 0xF3 then
				local a,b,c,d,e = readu16(), readu16(), readu16(), readu16(), readu16()
				rhsprint("$DB64 Jump based on current attacker index (char1, char2, char3, char4, monster)")
			elseif cmd == 0xF4 then
				local _______t = read()
				rhsprint("$F30F Set Sprite Layer Priority")
			elseif cmd == 0xF5 then
				rhsprint("$F7FC Loop End (loop until no threads are active)")
			elseif cmd == 0xF6 then
				rhsprint("$E4A2 Rotate Triangle 3D")
			elseif cmd == 0xF7 then
				local arg = read()
				rhsprint("$DB50 wait until vertical scanline position "..u8(arg))
			elseif cmd == 0xF8 then
				local xxxx, yyyy = readu16(), readu16()
				rhsprint("$DB31 if magitek mode is enabled then jump to "
					..('$%04x'):format(xxxx)
					..' else '..('$%04x'):format(yyyy))
			elseif cmd == 0xF9 then
				local xx,yy,zz = read(), read(), read()
				rhsprint("$DAF9")
			elseif cmd == 0xFA then
				local xxxx = readu16()
				rhsprint("$DB23 jump to $"..('%04x'):format(xxxx))
			elseif cmd == 0xFB then
				local arg = read()
				rhsprint('$ED4C set character palettes color subtraction (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xFC then
				local arg = read()
				rhsprint('$ED12 set character palettes color addition (absolute)'
					..' amount='..u8(bit.band(0x1f, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg)))
			elseif cmd == 0xFD then
				local arg = read()
				rhsprint('$ED00 add color to character palettes (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xFE then
				local arg = read()
				rhsprint('$ED09 subtract color from character palettes (relative)'
					..' amount='..u8(bit.band(0xf, arg))
					..' red='..tostring(0 ~= bit.band(0x80, arg))
					..' green='..tostring(0 ~= bit.band(0x40, arg))
					..' blue='..tostring(0 ~= bit.band(0x20, arg))
					..(0 ~= bit.band(0x10, arg) and 'sub' or 'add'))
			elseif cmd == 0xFF then
				rhsprint"end of animation"
			end
		end
	end
	print()

	local colorBase = ffi.cast('color_t*', game.battleAnimPalettes)
	local numColors = game.numBattleAnimPalettes * 8
	for palSheetIndex=0,math.ceil(numColors / 256)-1 do
		local palimage = Image(16, 16, 4, 'uint8_t'):clear()
		local p = palimage.buffer + 0
		for i=0,255 do
			local j = bit.bor(bit.lshift(palSheetIndex, 8), i)
			if j < numColors then
				local color = colorBase + j
				assert.le(colorBase, color)
				assert.lt(color, ffi.cast('color_t*', game.itemTypeNames))
				local r = bit.bor(
					bit.lshift(color.r, 3),
					bit.rshift(color.r, 2))
				local g = bit.bor(
					bit.lshift(color.g, 3),
					bit.rshift(color.g, 2))
				local b = bit.bor(
					bit.lshift(color.b, 3),
					bit.rshift(color.b, 2))
				local a = color.a == 0 and 0xff or 0
				-- every 8 is transparent? every 16?
				if bit.band(j, 7) == 0 then a = 0 end
				p[0], p[1], p[2], p[3] = r, g, b, a
				p = p + 4
			end
		end
		palimage:save(battleAnimGraphicSetsPath('palette'..(palSheetIndex+1)..'.png').path)
	end
end
