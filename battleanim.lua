local ffi = require 'ffi'
local Image = require 'image'
local makePalette = require 'graphics'.makePalette
local tileWidth = require 'graphics'.tileWidth
local tileHeight = require 'graphics'.tileHeight
local readTile = require 'graphics'.readTile

--[[
alltiles-2bpp is 512x184
alltiles-3bpp is 512x616
total is 512x800
i.e. 256x1600 i.e. 6.25 x 256x256 sheets
--]]

return function(rom, game)
	local graphicSetsUsed = {}
	local paletteForTileIndex = {}

	local battleAnimSetPath = path'spelldisplay'
	battleAnimSetPath:mkdir()
	for battleAnimSetIndex=0,game.numBattleAnimSets-1 do
		local battleAnim = game.battleAnimSets + battleAnimSetIndex
		print('battleAnimSet['..battleAnimSetIndex..'] = '..battleAnim)

		for j=0,2 do
			-- TODO array plz, but then TODO serialzie arrays in 'struct' please
			local effectIndex = battleAnim['effect'..(j+1)]
			local paletteIndex = battleAnim['palette'..(j+1)]

			if effectIndex ~= 0xffff then
				local unknown_15 = 0 ~= bit.band(0x8000, effectIndex)
				effectIndex = bit.band(0x7fff, effectIndex)
				-- idk what unknown_15 means.
				if effectIndex >= game.numBattleAnimEffects then
					-- NO MORE OF THESE ERRORS BEING HIT, NICE
					print('!!! effect is oob !!! '..('%x'):format(effectIndex))
				else
					local effect = game.battleAnimEffects + effectIndex
					print('\t\teffect'..(j+1)..'='..effect)

					local graphicSet = effect.graphicSet
					if effect.graphicSetHighBit ~= 0 then
						graphicSet = bit.bor(graphicSet, 0x100)
					end

					graphicSetsUsed[graphicSet] = graphicSetsUsed[graphicSet]
						or {
							effectDisplayIndex = {},
							palettes = {},
						}
					graphicSetsUsed[graphicSet].effectDisplayIndex[j] = true
					graphicSetsUsed[graphicSet].palettes[paletteIndex] = true

					-- is this a list of offsets to get the tileaddr's?
					local effectPtrTableAddr, effectLen, tileAddrBase, tileIndex, tileAddr, tileLen

					local bpp = effect._2bpp == 1 and 2 or 3

					if bpp == 3 then	-- effects 1&2
						-- first uint16 entry, times tileLen, plus tileAddrBase, points to some kind of tile data ... what about the rest? how to access it?
						effectPtrTableAddr = graphicSet * 0x40 + 0x120000	-- relative to battleAnimGraphicsSets3bpp
						-- https://web.archive.org/web/20190907020126/https://www.ff6hacking.com/forums/thread-925.html
						-- "the length of the pointer data"
						-- that means the length of where the *(uint16_t*)(rom + effectPtrTableAddr) data points to?
						-- because the length at effectPtrTableAddr itself seems to be 0x40 (cuz thats what you multiply graphicSet by)
						effectLen = 0xA0

						tileLen = 0x18 -- len is 24 bytes = 192 bits = 8 x 8 x 3 bits (so 3bpp)
						tileAddrBase = 0x130000	-- battleAnimGraphics
					elseif bpp == 2 then
						effectPtrTableAddr = graphicSet * 0x40 + 0x12C000	-- battleAnimTileFormation2bpp
						effectLen = 0x80

						tileAddrBase = 0x187000	-- battleAnimGraphics2bpp
						tileLen = 0x10 -- len is 16 bytes = 8 x 8 x 2bpp
					else
						error'here'
					end
					--tileIndex = ffi.cast('uint16_t*', rom + effectPtrTableAddr)[0]
					--tileAddr = tileIndex * tileLen + tileAddrBase
					-- now the tileAddr points to 8 uint16's , and then 8 uint8s that each get padded into uint16's
					print('\t\teffectAddr=0x'..effectPtrTableAddr:hex()
						..', effectLen=0x'..effectLen:hex()
						..', tileAddrBase=0x'..tileAddrBase:hex()
						..', tileLen=0x'..tileLen:hex())

					local numFrames = effect.numFrames
					-- https://web.archive.org/web/20190907020126/https://www.ff6hacking.com/forums/thread-925.html
					-- ... says dont use the last 2 bits
					numFrames = bit.band(0x3f, numFrames)
					for frameIndex=0,numFrames-1 do
						print('\t\t\tframeIndex=0x'..frameIndex:hex()..':')
						local effectOffsetEntry = game.battleAnimFrameOffsets[effect.frameIndexBase + frameIndex]
						local addr = 0x110000 + effectOffsetEntry  -- somewhere inside battleAnimFrameData

						print('\t\t\t\teffectOffsetEntry=0x'..effectOffsetEntry:hex()
							..', addr=0x'..addr:hex())

						-- now read from addr for how long? until when?
						-- addr points to:
						-- 00: loc: 4 bits y, 4 bits x
						-- 01: frame # ... into where?

						local im = Image(
							2*tileWidth * effect.width,
							2*tileHeight * effect.height,
							1,
							'uint8_t'
						)
							:clear()

						local pointerbase = ffi.cast('uint16_t*', rom + effectPtrTableAddr)

						local lastTileOrder
						for k=0,math.huge-1 do
							local x = bit.rshift(rom[addr + 2 * k], 4)
							local y = bit.band(0xf, rom[addr + 2 * k])
							if x >= effect.width then break end
							if y >= effect.height then break end
							local tileOrder = x + effect.width * y
							if lastTileOrder and lastTileOrder >= tileOrder then break end
							lastTileOrder = tileOrder
							
							local tileIndexOffset = rom[addr + 2 * k + 1]
							-- [[ is this *another* h-flip? needed for ice to work
							local hflip16 = 0 ~= bit.band(0x40, tileIndexOffset)
							local vflip16 = 0 ~= bit.band(0x80, tileIndexOffset)
							tileIndexOffset = bit.band(0x3f, tileIndexOffset)
							--]]
							--[[ or not?
							local hflip16, vflip16 = false, false
							--]]
							print('\t\t\t\t\tx='..x..', y='..y
								..', tileIndexOffset=0x'..tileIndexOffset:hex()
								..', hflip16='..tostring(hflip16)
								..', vflip16='..tostring(vflip16))
							if x < effect.width
							and y < effect.height
							then
								-- paste into image
								for yofs=0,1 do
									for xofs=0,1 do
										-- this makes a lot more sense if you look it up in the 'alltiles' image below
										-- TLDR: Make a 16x8 tile display out of the 8x8 tiles pointed to by pointerbase[]
										-- You'll see they make up 16x16-pixel regions
										-- Those are what we are indexing here, hence why you have to pick apart tileIndexOffset into its lower 3 bits and its upper 5
										local tileOffset = pointerbase[
											(2 * bit.band(tileIndexOffset, 7) + xofs)
											+ (2 * bit.rshift(tileIndexOffset, 3) + yofs) * 16
										]
										local vflip = 0 ~= bit.band(0x8000, tileOffset)
										local hflip = 0 ~= bit.band(0x4000, tileOffset)
--print('xofs', xofs:hex(), 'yofs', yofs:hex(), 'tileOffset', tileOffset:hex())
										-- 16384 indexable, but points to 0x130000 - 0x14c998, which only holds 4881
										local tileIndex = bit.band(0x3fff, tileOffset)
										paletteForTileIndex[tileIndex] = paletteIndex
										local tileAddr = tileAddrBase + tileLen * tileIndex
										local xformxofs = xofs
										if hflip16 then
											xformxofs = 1 - xformxofs
											hflip = not hflip
										end
										local xformyofs = yofs
										if vflip16 then
											xformyofs = 1  - xformyofs
											vflip = not vflip
										end
										readTile(
											im,
											(2*x + xformxofs)*tileWidth,
											(2*y + xformyofs)*tileHeight,
											rom + tileAddr,
											bpp,
											hflip,
											vflip
										)
									end
								end
							else
								print('!!! spell effect anim frame tile loc out of bounds!', x, y, tileIndexOffset)
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


	-- so this is basically a plot of the entire pointer table at 0x120000
	--
	--[[ graphic sets for effect #3 is supposed to have a different base address, hmmm...
	print('graphicSetsUsed', tolua(graphicSetsUsed))
	print()
	--]]
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
	local spellGraphicSetsPath = path'spellgraphicsets'
	spellGraphicSetsPath:mkdir()
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
			[2] = 384,	-- ??? wait, if its 2bpp then inc by 0x40 means skipping a full graphicsSet instead of just half...
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


		for graphicSetIndex=0,maxGraphicSet-1,2 do
			-- only plot the even graphicSetIndex tiles cuz the odd ones have a row in common
			assert.eq(bit.band(graphicSetIndex, 1), 0, "this wont be aligned in the master image")

			local halfGraphicsSetIndex = bit.rshift(graphicSetIndex, 1)
			local masterRow = halfGraphicsSetIndex % masterSetsHigh
			local masterCol = (halfGraphicsSetIndex - masterRow) / masterSetsHigh

			local graphicSetInfo = graphicSetsUsed[graphicSetIndex]
			print('graphicSet '..graphicSetIndex)
			local paletteIndex = 0
			local j = 0
			if graphicSetInfo then
				local effectDisplayIndexes = table.keys(graphicSetInfo.effectDisplayIndex):sort()
				print(' uses effect display indexes: '..effectDisplayIndexes:concat', ')
				j = effectDisplayIndexes[1] or 0
				local palettes = table.keys(graphicSetInfo.palettes):sort()
				print(' uses palettes: '..palettes:concat', ')
				paletteIndex = palettes:last() or 0
			end

			local effectPtrTableAddr, effectLen, tileAddrBase, tileIndex, tileAddr, tileLen
			if bpp == 3 then
				effectPtrTableAddr = graphicSetIndex * 0x40 + 0x120000	-- battleAnimGraphicsSets3bpp
				effectLen = 0xA0
				tileLen = 0x18
				tileAddrBase = 0x130000	-- game.battleAnimGraphics
			elseif bpp == 2 then
				effectPtrTableAddr = graphicSetIndex * 0x40 + 0x12C000	-- battleAnimTileFormation2bpp
				effectLen = 0x80
				tileAddrBase = 0x187000	-- game.battleAnimGraphics2bpp
				tileLen = 0x10
			else
				error'here'
			end

			local pointerbase = ffi.cast('uint16_t*', rom + effectPtrTableAddr)

			local im = Image(
				0x10*tileWidth,
				4*tileHeight,
				1, 'uint8_t'
			)
			im.palette = makePalette(game.battleAnimPalettes + paletteIndex, bit.lshift(1, bpp))
			for y=0,3 do
				for x=0,15 do
					local tileIndex = x + 0x10 * y
					local tileOffset = pointerbase[tileIndex]
					local vflip = 0 ~= bit.band(0x8000, tileOffset)
					local hflip = 0 ~= bit.band(0x4000, tileOffset)
					local tileAddr = tileAddrBase + tileLen * bit.band(0x3fff, tileOffset)
					readTile(
						im,
						x * tileWidth,
						y * tileHeight,
						rom + tileAddr,
						bpp,
						hflip,
						vflip
					)
				end
			end
			master:pasteInto{
				image = im:rgba(),
				x = masterCol * 128,
				y = masterRow * 32,
			}
			--im:save(spellGraphicSetsPath(('%03d'):format(graphicSetIndex)..'.png').path)
		end
		master:save(spellGraphicSetsPath('battle_anim_graphic_sets_'..bpp..'bpp.png').path)
	end

	-- what about plotting the entire tile data?
	-- this is the data at 0x130000 - 0x14c998
	-- it's going to be 3bpp 8x8 data , so there will be 4881 of them
	do
		local bpp = 3
		local tileSize = 8 * bpp
		local totalTiles = math.floor((0x14c998 - 0x130000) / tileSize)
		local tilesWide = 64
		local tilesHigh = math.ceil(totalTiles / tilesWide)

		local allTiles = Image(
			tileWidth * tilesWide,
			tileHeight * tilesHigh,
			4,	-- rgba
			'uint8_t'
		):clear()

		local tileImg = Image(tileWidth, tileHeight, 1, 'uint8_t')
		for tileIndex=0,totalTiles-1 do
			local tileX = tileIndex % tilesWide
			local tileY = (tileIndex - tileX) / tilesWide
			readTile(
				tileImg,
				0,
				0,
				rom + 0x130000 + tileSize * tileIndex,
				bpp
			)
			local paletteIndex = paletteForTileIndex[tileIndex] or 0
			tileImg.palette = makePalette(game.battleAnimPalettes + paletteIndex, bit.lshift(1, bpp))
			allTiles:pasteInto{
				image = tileImg:rgba(),
				x = tileWidth * tileX,
				y = tileHeight * tileY,
			}
		end
		allTiles:save(spellGraphicSetsPath'alltiles-3bpp.png'.path)
	end

	do
		local bpp = 2
		local tileSize = 8 * bpp
		local tileAddrBase = 0x187000	-- game.battleAnimGraphics2bpp
		local tileAddrEnd = 0x18c9a0
		local totalTiles = math.floor((tileAddrEnd - tileAddrBase) / tileSize)
		local tilesWide = 64
		local tilesHigh = math.ceil(totalTiles / tilesWide)

		local allTiles = Image(
			tileWidth * tilesWide,
			tileHeight * tilesHigh,
			4,	-- rgba
			'uint8_t'
		):clear()

		local tileImg = Image(tileWidth, tileHeight, 1, 'uint8_t')
		for tileIndex=0,totalTiles-1 do
			local tileX = tileIndex % tilesWide
			local tileY = (tileIndex - tileX) / tilesWide
			readTile(
				tileImg,
				0,
				0,
				rom + tileAddrBase + tileSize * tileIndex,
				bpp
			)
			local paletteIndex = paletteForTileIndex[tileIndex] or 0
			tileImg.palette = makePalette(game.battleAnimPalettes + paletteIndex, bit.lshift(1, bpp))
			allTiles:pasteInto{
				image = tileImg:rgba(),
				x = tileWidth * tileX,
				y = tileHeight * tileY,
			}
		end
		allTiles:save(spellGraphicSetsPath'alltiles-2bpp.png'.path)
	end

	print()
	for i=0,660-1 do
		print('battle anim script #'..i, '0x'..game.battleAnimScriptOffsets[i]:hex())
	end
	print()
end
