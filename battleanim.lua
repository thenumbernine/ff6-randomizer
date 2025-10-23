local ffi = require 'ffi'
local Image = require 'image'
local makePalette = require 'graphics'.makePalette
local tileWidth = require 'graphics'.tileWidth
local tileHeight = require 'graphics'.tileHeight
local readTile = require 'graphics'.readTile

return function(rom, game)
	local graphicSetsUsed = {}
	local spellDisplayPath = path'spelldisplay'
	spellDisplayPath:mkdir()
	for spellDisplayIndex=0,game.numSpellDisplays-1 do
		local spellDisplay = game.spellDisplays + spellDisplayIndex
		print('spellDisplay['..spellDisplayIndex..'] = '..spellDisplay)

		for j=0,2 do
			-- TODO array plz, but then TODO serialzie arrays in 'struct' please
			local effectIndex = spellDisplay['effect'..(j+1)]
			local palette = spellDisplay['palette'..(j+1)]
		
			if effectIndex ~= 0xffff then
				local unknown_15 = 0 ~= bit.band(0x8000, effectIndex)
				effectIndex = bit.band(0x7fff, effectIndex)
				-- idk what unknown_15 means.
				if effectIndex >= game.numSpellEffects then
					print('!!! effect is oob !!! '..('%x'):format(effectIndex))
				else
					local effect = game.spellEffects + effectIndex
					print('\t\teffect'..(j+1)..'='..effect)

					local graphicSet = effect.graphicSet
					-- hmm for bolt, it picks from a different part of RAM than i'm looking at, but where, and how to tell when?
					--if unknown_15 then
					--if effect.unknown_0_6 ~= 0 then -- spell 2 = bolt has this set ...
					--if effect.unknown_0_7 ~= 0 then -- spell 2 = bolt has this set ...
						--graphicSet = bit.bor(graphicSet, 0x200)
						--graphicSet = bit.bor(graphicSet, 0x100)
						--graphicSet = bit.bor(graphicSet, 0x80)
						--graphicSet = bit.bor(graphicSet, 0x40)
					--end

					graphicSetsUsed[graphicSet] = graphicSetsUsed[graphicSet] 
						or {
							effectDisplayIndex = {},
							palettes = {},
						}
					graphicSetsUsed[graphicSet].effectDisplayIndex[j] = true
					graphicSetsUsed[graphicSet].palettes[palette] = true

					-- is this a list of offsets to get the tileaddr's?
					local effectPtrTableAddr, effectLen, tileAddrBase, tileIndex, tileAddr, tileLen
					if j < 2 then	-- effects 1&2
						-- first uint16 entry, times tileLen, plus tileAddrBase, points to some kind of tile data ... what about the rest? how to access it?
						effectPtrTableAddr = graphicSet * 0x40 + 0x120000	-- relative to battleAnimGraphicsSets3bpp 
						-- https://web.archive.org/web/20190907020126/https://www.ff6hacking.com/forums/thread-925.html
						-- "the length of the pointer data"
						-- that means the length of where the *(uint16_t*)(rom + effectPtrTableAddr) data points to?
						-- because the length at effectPtrTableAddr itself seems to be 0x40 (cuz thats what you multiply graphicSet by)
						effectLen = 0xA0
					
						tileLen = 0x18 -- len is 24 bytes = 192 bits = 8 x 8 x 3 bits (so 3bpp)
						tileAddrBase = 0x130000	-- battleAnimGraphics 
					else
						effectPtrTableAddr = graphicSet * 0x40 + 0x12C000	-- battleAnimTileFormation2bpp
						effectLen = 0x80
						
						tileAddrBase = 0x187000	-- battleAnimGraphics2bpp 
						tileLen = 0x10 -- len is 16 bytes = 8 x 8 x 2bpp
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
					local baseFrameIndex = effect.frameIndex
					for frameIndex=0,numFrames-1 do
						print('\t\t\tframeIndex=0x'..frameIndex:hex()..':')
						local effectOffsetEntry = game.spellEffectFrameOffsets[baseFrameIndex + frameIndex]
						local addr = 0x110000 + effectOffsetEntry  -- somewhere inside spellEffectFrameData
						local addrend = 0x110000 + game.spellEffectFrameOffsets[baseFrameIndex + frameIndex + 1]	-- is this how you find the end?
						if addrend < addr then
							print("!!! addrend underflow !!!")
						else
							local len = addrend - addr
							assert.eq(bit.band(len, 1), 0, "length is not uint16 aligned!")
							len = bit.rshift(len, 1)
							print('\t\t\t\teffectOffsetEntry=0x'..effectOffsetEntry:hex()
								..', addr=0x'..addr:hex()
								..', len=0x'..len:hex())

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
							
							-- whats the bpp? differing for effect12 and 3?
							local bpp = 3
							local pointerbase = ffi.cast('uint16_t*', rom + effectPtrTableAddr)

							for k=0,len-1 do
								local x = bit.rshift(rom[addr + 2 * k], 4)
								local y = bit.band(0xf, rom[addr + 2 * k])
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
											local tileAddr = tileAddrBase + tileLen * bit.band(0x3fff, tileOffset)
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

							local paltable = makePalette(game.battleAnimPalettes + palette, bit.lshift(1, bpp))
							im.palette = paltable 
							im:save(spellDisplayPath(
								('%03d'):format(spellDisplayIndex)
								..('-%d'):format(j)	-- effect1,2,3
								..('-%02d'):format(frameIndex)
								..'.png').path)
						end
					end
					print()
				end
			end
		end
	end
	print()

	--[[ graphic sets for effect #3 is supposed to have a different base address, hmmm...
	print('graphicSetsUsed', tolua(graphicSetsUsed))
	print()
	--]]
	-- honestly this comes from a unique combo of graphicSet & effect 123 index (3 has a dif base)
	-- so I don't need to make so many copies ...
	
	-- also each 'graphicSet' number is just 8 tiles worth of 16x16 tiles
	-- each 'graphicSet' is only addressible by 64 8x8 tiles = 16 16x16 tiles
	-- (because it's a byte, and its high two bits are used for hflip & vflip, so 64 values)
	-- so each 'graphicSet' is going to share 8 16x16 tiles in common with the next 'graphicSet'
	-- so 'graphicSet' is really '8x start of location in 8-tile-rows of 16x16 tileset'

	-- so 1 'graphicSet' tiles is 16x4 of 8x8 = 8x2 of 16x16 = 128x32
	-- so 256 'graphicSets' with their even overlapping rows excluded is 128 x (32x128) = 128 x 4096
	-- but I could square this circle to be 512 x 1024
	-- ... but are there more than 256 addressible?
	-- yup there are.  so how do you address them, with just 1 byte?
	do
		local bpp = 3

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
		local maxGraphicSet = 384

		local master = Image(
			-- 1 graphic set is 16*8 x 4*8
			-- i'll make 4 cols of them
			16 * tileWidth * 4,
			4 * tileHeight * math.ceil(maxGraphicSet/8),
			4,	-- rgba
			'uint8_t'
		):clear()

		local p = path'spellgraphicsets'
		p:mkdir()
		
		for graphicSetIndex=0,maxGraphicSet-1,2 do
			-- only plot the even graphicSetIndex tiles cuz the odd ones have a row in common
			assert.eq(bit.band(graphicSetIndex, 1), 0, "this wont be aligned in the master image")
			-- use the next 2 bits as the col # (values 0-3)
			local masterCol = bit.band(bit.rshift(graphicSetIndex,1), 3)
			-- use bits 3 and up for the row #
			local masterRow = bit.rshift(graphicSetIndex,3)

			local graphicSetInfo = graphicSetsUsed[graphicSetIndex]
			print('graphicSet '..graphicSetIndex)
			local palette = 0
			local j = 0
			if graphicSetInfo then
				local effectDisplayIndexes = table.keys(graphicSetInfo.effectDisplayIndex):sort()
				print(' uses effect display indexes: '..effectDisplayIndexes:concat', ')
				j = effectDisplayIndexes[1] or 0
				local palettes = table.keys(graphicSetInfo.palettes):sort()
				print(' uses palettes: '..palettes:concat', ')
				palette = palettes[1] or 0
			end

			local effectPtrTableAddr, effectLen, tileAddrBase, tileIndex, tileAddr, tileLen
			if j < 2 then
				effectPtrTableAddr = graphicSetIndex * 0x40 + 0x120000	-- battleAnimGraphicsSets3bpp 
				effectLen = 0xA0
				tileLen = 0x18
				tileAddrBase = 0x130000
			else
				effectPtrTableAddr = graphicSetIndex * 0x40 + 0x12C000	-- battleAnimTileFormation2bpp
				effectLen = 0x80
				tileAddrBase = 0x187000
				tileLen = 0x10
			end

			local pointerbase = ffi.cast('uint16_t*', rom + effectPtrTableAddr)

			local im = Image(
				0x10*tileWidth,
				4*tileHeight,
				1, 'uint8_t'
			)
			im.palette = makePalette(game.battleAnimPalettes + palette, bit.lshift(1, bpp))
			for y=0,3 do
				for x=0,15 do
					local tileIndex = x + 0x10 * y
					local tileOffset = pointerbase[tileIndex]
					local vflip = 0 ~= bit.band(0x8000, tileOffset)
					local hflip = 0 ~= bit.band(0x4000, tileOffset)
					local tileAddr = tileAddrBase + tileLen * bit.band(0x3fff, tileOffset)
					readTile(
						im,
						x * tileWidth,-- + masterCol * 128,
						y * tileHeight,-- + masterRow * 32,
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
			--im:save(p(('%03d'):format(graphicSetIndex)..'.png').path)
		end
		master:save(p'battle_anim_graphic_sets.png'.path)
	end
end
