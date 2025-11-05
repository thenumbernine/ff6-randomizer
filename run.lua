#!/usr/bin/env luajit
local ffi = require 'ffi'
local Image = require 'image'
local makePalette = require 'graphics'.makePalette
local makePaletteSets = require 'graphics'.makePaletteSets
local tileWidth = require 'graphics'.tileWidth
local tileHeight = require 'graphics'.tileHeight
local readTile = require 'graphics'.readTile
local decompress = require 'decompress'.decompress
local decompress0x800 = require 'decompress'.decompress0x800
require 'ext'

local int16_t = ffi.typeof'int16_t'

local infn, outfn = ...
assert(infn, "missing filename")
local data = assert(path(infn):read())
local rom = ffi.cast('uint8_t*', data) + 0x200
-- you can only load this once, from there all the types' metatables are bound to the game pointer
-- so even if you load a second game file, all the metatypes will be bound to the first pointer
-- I can't change that without associating the C data with the Lua object.
local game = require 'ff6'(rom)

for i=0,game.numSpells-1 do
	print('spell #'..i)
	print('Name="'..game.getSpellName(i)..'"')
	if i < 54 then
		print('Desc="'..game.gamezstr(game.spellDescBase + game.spellDescOffsets[i])..'"')
	elseif i >= 54 and i < 64 then
		-- should I put esper descs here, or in the esper output, or both?
	end
	print(game.spells[i])
	print()
end

for i=0,game.numSpells-1 do
	if game.spells[i].isLore ~= 0 then
		print('Name="'..game.getSpellName(i)..'"')
		for j=0,game.numMonsters-1 do
			for k=0,1 do
				if game.monsterSketches[j].s[k].i == i then
					print('\tsketch '..game.monsterNames[j])
				end
			end
			if j < game.numRages then
				for k=0,1 do
					if game.monsterRages[j].s[k].i == i then
						print('\trage '..game.monsterNames[j])
					end
				end
			end
		end
	end
end
print()

for i=0,game.numEspers-1 do
	print('esper #'..i)
	print('Name="'..game.getEsperName(i)..'"')
	print('AttackName="'..game.esperAttackNames[i]..'"')
	print('Desc="'..game.gamezstr(game.esperDescBase + game.esperDescOffsets[i])..'"')
	print(game.espers[i])
	print()
end

for i=0,game.numEsperBonuses-1 do
	print('esper bonus #'..i)
	print('desc = "'..game.esperBonusDescs[i]..'"')
	print('long desc = "'..game.gamezstr(game.longEsperBonusDescBase  + game.longEsperBonusDescOffsets[i])..'"')
	print()
end

for i=0,game.numItems-1 do
	print('item #'..i)
	print('Name="'..game.itemNames[i]..'"')
	print('Desc="'..game.gamezstr(game.itemDescBase + game.itemDescOffsets[i])..'"')
	print(game.items[i])
	print(game.itemColosseumInfos[i])
	print()
end

for i=0,game.numItemTypes-1 do
	print('item type #'..i..' = '..game.itemTypeNames[i])
end
print()

for i=0,game.numRareItems-1 do
	print('rare item #'..i)
	print('name="'..game.rareItemNames[i]..'"')
	print('desc="'..game.gamezstr(game.rareItemDescBase + game.rareItemDescOffsets[i])..'"')
	print()
end

for i=0,game.numCharacterPalettes-1 do
	print('characterPalettes[0x'..i:hex()..'] = '..game.characterPalettes[i])
end
print()

do
	local unique = {}
	for i=0,game.numMonsterPalettes-1 do
		print('monsterPalettes[0x'..i:hex()..'] = '..game.monsterPalettes[i])
		unique[ffi.string(game.monsterPalettes + i, ffi.sizeof'palette8_t')] = true
	end
	-- 646 of 768 unique values used
	-- only indexes 0-656 are used, the rest are black
	-- overall, 256 x 20.5 palette-blobs are used
	print('# unique: '..#table.keys(unique))
	print()
end

for i=0,game.numMonsters-1 do
	print('monster #'..i)
	print('Name="'..game.monsterNames[i]..'"')
	print('AttackName="'..game.monsterAttackNames[i]..'"')
	print(game.monsters[i])
	print('spells = '..game.monsterSpells[i])
	print(game.monsterItems[i])
	print('sketches = '..game.monsterSketches[i])
	if i < game.numRages then print('rages = '..game.monsterRages[i]) end
	print()
end

local totalPixels = 0
-- [[
local writeMonsterSprite = require 'monstersprite'
for i=0,game.numMonsterSprites-1 do
	print('monsterSprites[0x'..i:hex()..'] = '..game.monsterSprites[i])
	totalPixels = totalPixels + writeMonsterSprite(game, i)
end
print('wrote monster pixels', totalPixels)
print()
--]]

-- [[ see how many unique monsters there are ...
local monsterSpriteOffsetSet = {}
--local monsterSpriteOffsets = table() -- from 1-based monster index to offset #

-- from palLo | palHi | _3bpp to monsterSprite.offset
-- so I can try to group monsterSprite.offset by matching palettes
local monsterPalettes_monsterSpriteIndexes = {}

for i=0,game.numMonsterSprites-1 do
	local monsterSprite = game.monsterSprites + i
	if not monsterSpriteOffsetSet[monsterSprite.offset] then
		monsterSpriteOffsetSet[monsterSprite.offset] = table()
	end
	monsterSpriteOffsetSet[monsterSprite.offset]:insert(i)
	--monsterSpriteOffsets[i+1] = monsterSpriteOffsetSet[monsterSprite.offset][1]

	local palIndex = bit.bor(
		monsterSprite.palLo,
		bit.lshift(monsterSprite.palHi, 8),
		bit.lshift(monsterSprite._3bpp, 15)
	)
	monsterPalettes_monsterSpriteIndexes[palIndex] = monsterPalettes_monsterSpriteIndexes[palIndex] or {}
	monsterPalettes_monsterSpriteIndexes[palIndex][i] = true
end

--print('monsterSpriteOffsets = '..tolua(monsterSpriteOffsets))

--[[
_3bpp, tile16, tileMaskIndex are constant per-offset
only palHi and palLo vary per offset
so here, write us only unique monsters with the first palette
--]]
for _,offset in ipairs(table.keys(monsterSpriteOffsetSet):sort()) do
	print('monsterSpriteOffset '..('0x%04x'):format(offset)..' has sprites: '..table.concat(monsterSpriteOffsetSet[offset], ', '))
end
print()

do
	local monsterPalettesUnique = table.keys(
		monsterPalettes_monsterSpriteIndexes
	):sort()
	
	-- what about palette indexes that are odd ...
	-- if a palette index is odd ....
	local transparents = {}
	local opaques = {}
	for _,pal in ipairs(monsterPalettesUnique) do
		local indexbase = bit.lshift(bit.band(pal, 0x7fff), 3)
		local bpp = bit.band(pal, 0x8000) ~= 0 and 3 or 4
		local numColors = bit.lshift(bpp, 1)
		transparents[indexbase] = true
		assert.eq(opaques[indexbase], nil)
		for i=indexbase+1,indexbase+numColors-1 do
			opaques[i] = true
			assert.eq(transparents[i], nil)
		end
	end
	for _,pal in ipairs(monsterPalettesUnique) do
		local indexes = table.keys(monsterPalettes_monsterSpriteIndexes[pal]):sort()
		io.write('monsterPalettes[0x'..('%04x'):format(pal)..'] is used by ')

		-- [=[ print indexes
		io.write('indexes ')
		for _,index in ipairs(indexes) do
			io.write(('0x%x'):format(index), ', ')
		end
		--]=]
		--[=[ print offsets, which correlate to unique images
		local offsets = {}
		for _,i in ipairs(table.keys(monsterPalettes_monsterSpriteIndexes[pal]):sort()) do
			local monsterSprite = game.monsterSprites + i
			offsets[monsterSprite.offset] = true
		end

		io.write('offsets ')
		for _,offset in ipairs(table.keys(offsets):sort()) do
			io.write(('0x%x'):format(offset), ', ')
		end
		--]=]
		print()
	end
	print()

	-- write monster palettes
	local p = path'monsters_graphicset'
	makePaletteSets(
		p,
		game.monsterPalettes,
		bit.lshift(game.numMonsterPalettes, 3),
		function(index)
			return transparents[index]
		end
	)
end
--]]

for i=0,game.numMetamorphSets-1 do
	print('metamorph set #'..i..' = '..game.metamorphSets[i])
end
print()

for i=0,game.numFormations-1 do
	print('formation #'..i)
	if i < game.numFormationMPs then
		print('mp='..game.formationMPs[i])
	end
	print(game.formations[i])
	print(game.formation2s[i])
	print()
end

for i=0,game.numFormationSizeOffsets-1 do
	print('formation offset ptr #'..i..' = '..('0x%04x'):format(game.formationSizeOffsets[i]))
end
print()

for i=0,game.numFormationSizes-1 do
	print('formation size #'..i..' = '
		..('0x%04x'):format(ffi.cast('uint8_t*', game.formationSizes + i) - rom)
		..' '..game.formationSizes[i])
end
print()

-- [[ get some statistics on our structure fields
local mins = {}
local maxs = {}
local sums = {}
for i=0,game.numCharacters-1 do
	print('character #'..i)
	print('Name="'..game.characterNames[i]..'"')
	print(game.characters[i])
	print()
	for name,ctype,field in game.character_t:fielditer() do
		local value
		if ctype == 'uint8_t' then
			value = game.characters[i][name]
		elseif ctype == 'menuref4_t'
		or ctype == 'itemref_t'
		or ctype == 'itemref2_t'
		then
			-- TODO count unique values
			goto skip
		else
			error("don't know how to handle ctype "..ctype)
		end
		value = tonumber(value) or error("failed to convert "..tostring(value).." to a number")
		mins[name] = not mins[name] and value or math.min(mins[name], value)
		maxs[name] = not maxs[name] and value or math.max(maxs[name], value)
		sums[name] = not sums[name] and value or (sums[name] + value)
::skip::
	end
end
print((require'ext.tolua'({
	mins = mins,
	maxs = maxs,
	avgs = table.map(sums, function(v) return v/game.numCharacters end),
})
	:gsub(', ',',\n\t\t')
	:gsub('}','\n\t}')
	:gsub('={','={\n\t\t')
))
--]]

-- [[
local readCharSprite = require 'charsprite'
local totalPixels = 0
-- [=[
local chx, chy = 0, 0
local sheetIndex = 0
local charSheet = Image(256, 256, 1, 'uint8_t')
local function flushCharSheet()
	charSheet.palette = makePalette(game.characterPalettes, 4, 256)
	charSheet:save('characters/sheet'..sheetIndex..'.png')
	charSheet:clear()
	sheetIndex = sheetIndex + 1
	chx, chy = 0, 0
end
local function pushSpriteFrame(charIndex, frameIndex, im, palIndex)
	-- offset into our palette
	im = im + bit.lshift(palIndex, 4)
	-- [==[ hack to fit 4 chars into one sheet
	if frameIndex == 38 	-- only exists for Terra I think
	--or frameIndex == 39 	-- tent
	then return end
	--]==]
	charSheet:pasteInto{
		x = chx,
		y = chy,
		image = im,
	}
	chx = chx + im.width
	if chx + im.width > charSheet.width then
		chx = 0
		chy = chy + im.height
		if chy + im.height > charSheet.height then
			flushCharSheet()
		end
	end
end
--]=]
for charIndex=0,game.numCharacterSprites-1 do
	--local spriteName = spriteNames[charIndex+1] or 'char'..charIndex
	local spriteName = 'char'..('%03d'):format(charIndex)
	--[=[ save to char sheet
	local charSheet = Image(256, 256, 1, 'uint8_t')
		:clear()
	local chx, chy = 0, 0
	--]=]
	readCharSprite(game, charIndex, function(charIndex, frameIndex, im, palIndex)
		-- [=[ save each frame individually...
		--local frameName = frameNames[frameIndex+1] or tostring(frameIndex)
		--local frameName = tostring(frameIndex)
		local frameName = ('%02d'):format(frameIndex)
		local relname = spriteName..'_'..frameName..'.png'
		im.palette = makePalette(game.characterPalettes + palIndex, 4, 16)
		im:save('characters/'..relname)
		--]=]
		--[=[ save to our char sheet
		charSheet:pasteInto{
			x = chx,
			y = chy,
			image = im,
		}
		chx = chx + im.width
		if chx + im.width > charSheet.width then
			chx = 0
			chy = chy + im.height
		end
		--]=]
		-- [=[ compact sheets
		pushSpriteFrame(charIndex, frameIndex, im, palIndex)
		--]=]
		totalPixels = totalPixels + im.width * im.height
	end)
	--[=[ save to our char sheet
	charSheet:save('characters/sheet'..spriteName..'.png')
	--]=]
	--[=[ extra sheet condition to not wrap or something idk
	-- it is specific to the char # so meh gotta guess here
	if chy + 3*8*4 > charSheet.height then
		flushCharSheet()
	end
	--]=]
end
-- [=[
if chx > 0 or chy > 0 then
	flushCharSheet()
end
--]=]
print('wrote total pixels', totalPixels)
--]]
-- [[ while we're here , why not write out the char palettes
makePaletteSets(
	path'character_pals',
	game.characterPalettes,
	16 * game.numCharacterPalettes,
	function(index)
		return bit.band(0xf, index) == 0
	end
)
--]]

for i=0,game.numMenuNames-1 do
	print('menu #'..i..' = "'..game.menuNames[i]..'"')
end
print()

for i=0,game.numMogDances-1 do
	print('mog dance #'..i..' = '..game.mogDanceNames[i])
end
print()

for i=0,game.numSwordTechs-1 do
	print('sword tech #'..i..' name="'..game.swordTechNames[i]..'" desc="'..game.gamezstr(game.swordTechDescBase + game.swordTechDescOffsets[i])..'"')
end
print()

for i=0,game.numBlitzes-1 do
	io.write('blitz #'..i)
	print(' desc="'..game.gamezstr(game.blitzDescBase + game.blitzDescOffsets[i])..'"')
	print('blitz data: '..game.blitzData[i])
	print()
end
print()

for i=0,game.numLores-1 do
	print('lore #'..i..' desc="'..game.gamezstr(game.loreDescBase + game.loreDescOffsets[i])..'"')
end
print()

io.write('exp for level up: ')
for i=0,game.numExpLevelUps-1 do
	io.write(' ',game.expForLevelUp[i])
end
print()

io.write('hpmax+ per level up: ')
for i=0,game.numLevels-1 do
	io.write(' ',game.hpIncPerLevelUp[i])
end
print()

io.write('mpmax+ per level up: ')
for i=0,game.numLevels-1 do
	io.write(' ',game.mpIncPerLevelUp[i])
end
print()
print()

for i=0,game.numShops-1 do
	print('shop #'..i..': '..game.shops[i])
end

print()
for i=0,game.numLocations-1 do
	print('location #'..i..': '..game.locations[i])
end

print()
for i=0,(0x040342 - 0x040000)/2-1 do
	local addr = game.mapEventTriggerOfs[i] + ffi.offsetof('game_t', 'mapEventTriggerOfs')
	local mapEventTrigger = ffi.cast('mapEventTrigger_t*', rom + addr)
	print('mapEventTrigger #'..i..': $'..('%04x'):format(addr))
	print(' '..mapEventTrigger)
end
print()

for i=0,game.numLocationTileFormationOfs-1 do
	local offset = game.locationTileFormationOfs[i]:value()
	local dist
	local addr = 0xffffff 
	if offset ~= 0xffffff then
		addr = offset + 0x1e0000
		local nextoffset = rom - ffi.cast('uint8_t*', game.padding_1fbaff)
		if i < game.numLocationTileFormationOfs-1 then
			local nextoffsettest = game.locationTileFormationOfs[i+1]:value()
			if nextoffsettest ~= 0xffffff then
				nextoffset = nextoffsettest 
			end
		end
		dist = nextoffset - offset
	end
	print('locationTileFormationOfs[0x'..i:hex()..'] = 0x'
		..('%06x'):format(addr))
	if addr ~= 0xffffff then
		-- try to decompress ...
		local ptr = rom + addr
		local row, endptr = decompress0x800(ptr, ffi.sizeof(game.locationTileFormationOfs))
		print(' dist to next entry / end = 0x'..dist:hex())
		print(' compressed size = 0x'..(endptr - ptr):hex())
		print(' decompressed size = 0x'..(#row):hex())
		print(' '..row:hex())
	end
end
print()

for i=0,game.numEntranceTriggerOfs-1 do
	-- TODO use ref_t or whateever
	local addr = game.entranceTriggerOfs[i] + ffi.offsetof('game_t', 'entranceTriggerOfs')
	print('location entrance trigger #'..i)
	print(' addr: $'..('%06x'):format(addr))
	local entranceTrigger = ffi.cast('entranceTrigger_t*', rom + addr)
	print(' '..entranceTrigger)
end

print()
print(game.locationNames)
print(game.dialog)
print(game.battleDialog)
print(game.battleDialog2)
print(game.battleMessages)
print(game.positionedText)

print('WoB palette = '..game.WoBpalettes)
print('WoR palette = '..game.WoRpalettes)
print('setzer airship palette = '..game.setzerAirshipPalette)
print('daryl airship palette = '..game.darylAirshipPalette)
print('menuWindowPalettes = '..game.menuWindowPalettes)

--print('characterMenuImages = '..game.characterMenuImages)
do
	local bpp = 4
	local tilesWide = 5
	local tilesHigh = 5
	local menucharpath = path'characters_menu'
	menucharpath:mkdir()
	local ptr = game.characterMenuImages
	for charIndex=0,game.numMenuChars-1 do
		-- same same anyways?
		if charIndex < 16 then
			ptr = rom + 0x2d0000 + game.characterMenuImageOffsets[charIndex]
		else
			ptr = game.characterMenuImages + charIndex * (tilesWide * tilesHigh * 8 * bpp)
		end
		local baseptr = ptr
		local im = Image(tileWidth*tilesWide, tileHeight*tilesHigh, 1, 'uint8_t')
			:clear()
		local tileIndex = 0
		for ty=0,tilesHigh-1 do
			for tx=0,tilesWide-1 do
				ptr = baseptr + game.characterMenuImageTileLayout[tileIndex] * 8 * bpp
				readTile(im, tx*tileWidth, ty*tileHeight, ptr, bpp)
				tileIndex = tileIndex + 1
			end
		end
		im.palette = makePalette(game.menuPortraitPalette + charIndex, 4, 16)
		im:save(
			menucharpath('menu'..charIndex..'.png').path
		)
	end
	--for charIndex=0,game.numMenuChars-1 do
	--	print('menuPortraitPalette = '..game.menuPortraitPalette[charIndex])
	--end
end
--print('handCursorGraphics = '..game.handCursorGraphics)
print('battleWhitePalette = '..game.battleWhitePalette)
print('battleGrayPalette = '..game.battleGrayPalette)
print('battleYellowPalette = '..game.battleYellowPalette)
print('battleBluePalette = '..game.battleBluePalette)
print('battleEmptyPalette = '..game.battleEmptyPalette)
print('battleGrayPalette = '..game.battleGrayPalette)
print('battleGreenPalette = '..game.battleGreenPalette)
print('battleRedPalette = '..game.battleRedPalette)
print('battleMenuPalettes = '..game.battleMenuPalettes)
print()

require 'battleanim'(rom, game, #data - 0x200)

do
	local img = Image(8*16, 8*16, 1, 'uint8_t')
	for j=0,15 do
		for i=0,15 do
			local index = i + 16 * j
			for x=0,7 do
				for y=0,7 do
					img.buffer[
						(x + 8 * i) + img.width * (y + 8 * j)
					] = bit.bor(
						bit.band(bit.rshift(game.font[2*y + 0x10 * index], 7-x), 1),
						bit.lshift(bit.band(bit.rshift(game.font[2*y+1 + 0x10 * index], 7-x), 1), 1)
					)
				end
			end
		end
	end
	img.palette = range(0,3):mapi(function(i)
		local l = math.floor(i/3*255)
		return {l,l,l}
	end)
	img:save'font.png'

	print('font16 widths: '..range(0,0x7f):mapi(function(i)
		return ('%02x'):format(game.font16_widths[i])
	end):concat' ')
end

--[[
TODO
output font ...
	font16_20_to_7f

output audio ...
	spcMainCodeLoopLen
	spcMainCode
	spcMainCode
	brrSamplePtrs
	loopStartOfs
	pitchMults
	adsrData
	brrSamples
--]]

print('spcMainCodeLoopLen = '..game.spcMainCodeLoopLen)
print('spcMainCode = '..
	range(0,math.min(game.spcMainCodeLoopLen, ffi.sizeof(game.spcMainCode))-1)
	:mapi(function(i) return (' %02x'):format(game.spcMainCode[i]) end):concat()
)
local brrAddrs = table()
local brrLengths = table()
print'brr info:'
for i=0,game.numBRRSamples-1 do
	-- addrs are in ascending order
	local brrAddr = bit.bor(
		game.brrSamplePtrs[i].lo,
		bit.lshift(game.brrSamplePtrs[i].hi, 16)
	)
	assert.ne(bit.band(0xc00000, brrAddr), 0)
	brrAddr = brrAddr - 0xc00000
	brrAddrs[i] = brrAddr
	io.write(('#%02d: '):format(i))
	io.write(' samplePtr: '..('0x%06x'):format(brrAddr))

	-- first two bytes fo the samplePtr is the length-in-bytes of the brr sample
	brrLengths[i] = ffi.cast('uint16_t*', rom+brrAddr)[0]
	assert.eq(brrLengths[i] % 9, 0, "why isn't the brr length aligned to brr frames?")
	io.write(' length: '..('0x%04x'):format(brrLengths[i]))

	-- if loopStartPtr is only 16bit then it can't span the full range of the brrSample data, which covers 0x31245 bytes
	-- so it must be an offset into the structure
	assert.eq(game.loopStartOfs[i] % 9, 0, "why isn't the brr loop aligned to brr frames?")
	io.write(' loopStartPtr: '..('0x%04x'):format(tonumber(game.loopStartOfs[i])))
	io.write(' pitchMults: '..('0x%04x'):format(tonumber(game.pitchMults[i])))
	io.write(' adsrData: '..('0x%04x'):format(tonumber(game.adsrData[i])))

	print()
	-- then the brr data should decode until it gets to a loop frame, and ideally that'll be right before the next brr's address
end
local brrpath = path'brr'
brrpath:mkdir()
local wavpath = path'wav'
wavpath:mkdir()
print'brr data:'
for i=0,game.numBRRSamples-1 do
	local startAddr = brrAddrs[i] + 2			-- skip past the length info
	local len = brrLengths[i]
	local numFrames = len / 9
	local endAddr = startAddr + len
	local calcdEndAddr
	if i < game.numBRRSamples-1 then
		calcdEndAddr = brrAddrs[i+1]
	else
		calcdEndAddr = (ffi.cast('uint8_t*', game.brrSamples) + ffi.sizeof(game.brrSamples) - rom)
	end
	assert.eq(endAddr, calcdEndAddr)	-- perfectly fits
	print(('#%02d: '):format(i)
		..('$%06x-$%06x: '):format(startAddr, endAddr)
		..('(%4d brr frames) '):format(numFrames)
		--[[ this is a lot
		..range(0, len-1):mapi(function(i)
			local s = ('%02x'):format(rom[startAddr + i])
			if i % 9 == 0 then s = '['..s end
			if i % 9 == 8 then s = s..']' end
			return s
		end):concat' '
		--]]
	)

	-- write out the brr
	-- should I put pitch, adsr, loop info at the start of the brr sample?
	brrpath:write(i..'.brr', ffi.string(rom + startAddr, len))
	-- write out the wav too
	-- that means converting it from brr to wav
	-- that means ... 16bpp samples, x16 samples per brr-frame
	local numSamples = 16 * numFrames
	local wavData = ffi.new('int16_t[?]', numSamples)
	local brrptr = rom + startAddr
	local wavptr = wavData + 0
	local lastSample = ffi.new('int16_t[2]', {0,0})	-- for filters
	local function clampbits(x, b)
		return math.clamp(x, bit.lshift(-1, b-1), bit.lshift(1, b-1)-1)
	end
	for j=0,numFrames-1 do
		local endflag = bit.band(brrptr[0], 1) ~= 0
		local loopflag = bit.band(brrptr[0], 2) ~= 0
		local decodeFilter = bit.band(bit.rshift(brrptr[0], 2), 3)	-- 0-3 = decode filter = combine nibble with previous nibbles ...
		local shift = bit.band(bit.rshift(brrptr[0], 4), 0xf)
		-- https://wiki.superfamicom.org/bit-rate-reduction-(brr)
		-- https://github.com/Optiroc/BRRtools/blob/master/src/brr.c
		-- https://github.com/boldowa/snesbrr/blob/master/src/brr/BrrCodec.cpp
		for k=0,15 do
			local sample
			if bit.band(k,1) == 0 then
				sample = bit.band(bit.rshift(brrptr[1+bit.rshift(k,1)], 4), 0xf)
			else
				sample = bit.band(brrptr[1+bit.rshift(k,1)], 0xf)
			end

			-- sample is now 0 to 15 , representing a 4-bit-signed -8 to +7
			--if sample >= 8 then sample = sample - 16 end
			sample = bit.bxor(sample, 8) - 8
			-- sample is now -8 to +7

			-- [[ invalid shift
			if shift > 0xc then
				sample = bit.band(sample, bit.bnot(0x7ff))
			else
				sample = bit.lshift(sample, shift)
				-- why is this? maybe to do with the filter using the post-sampled value for previous frame values?
				sample = bit.arshift(sample, 1)
			end
			--]]

			local sampleBeforeFilter = sample
			-- [[ https://github.com/boldowa/snesbrr/blob/master/src/brr/BrrCodec.cpp
			if decodeFilter == 0 then
			elseif decodeFilter == 1 then
				sample = sample
					+ lastSample[0]
					- bit.arshift(lastSample[0], 4)
			elseif decodeFilter == 2 then
				sample = sample
					+ bit.lshift(lastSample[0], 1)
					+ bit.arshift(-(lastSample[0] + bit.lshift(lastSample[0], 1)), 5)
					- lastSample[1]
					+ bit.arshift(lastSample[1], 4)
				sample = clampbits(sample, 16)
			elseif decodeFilter == 3 then
				sample = sample +
					  bit.lshift(lastSample[0], 1)
					+ bit.arshift(-(lastSample[0] + bit.lshift(lastSample[0], 2) + bit.lshift(lastSample[0], 3)), 6)
					- lastSample[1]
					+ bit.arshift(lastSample[1] + bit.lshift(lastSample[1], 1), 4)
				sample = clampbits(sample, 16)
			else
				error'here'
			end
			--]]

			-- [[ snesbrr: "wrap to 15 bits, sign-extend to 16 bits"
			sample = bit.arshift(bit.lshift(sample, 1), 1)
			sample = ffi.cast(int16_t, sample)
			--]]

			lastSample[1] = lastSample[0]
			lastSample[0] = sample

			--sample = bit.arshift(sample * 0x7f, 7)	-- volume ... ?
			wavptr[0] = bit.lshift(sample, 1)

			--wavptr[0] = bit.lshift(sample, 1)
			--lastSample[0], lastSample[1] = sampleBeforeFilter, lastSample[0]
			wavptr = wavptr + 1
		end
		brrptr = brrptr + 9
	end
	assert.eq(wavptr, wavData + numSamples)
	assert.eq(brrptr, rom + endAddr)
	-- [[ now gaussian filter
	do
		local prev = (372 + 1304) * wavData[0] + 372 * wavData[1]
		for i=1,numSamples-2 do
			local k0 = 372 * (wavData[i-1] + wavData[i+1])
			local k = 1304 * wavData[i]
			wavData[i-1] = bit.arshift(prev, 11)
			prev = k0 + k
		end
		local last = 372 * wavData[numSamples-2] + (1304 + 372) * wavData[numSamples-1]
		wavData[numSamples-2] = bit.arshift(prev, 11)
		wavData[numSamples-1] = bit.arshift(last, 11)
	end
	--]]
	-- now save the wav
	local basename = ('%02X'):format(i+1)
	local freq = 32000
	local AudioWAV = require 'audio.io.wav'
	AudioWAV():save{
		filename = wavpath(basename..'.wav').path,
		ctype = int16_t,
		channels = 1,
		data = wavData,
		size = numSamples * ffi.sizeof(int16_t),
		freq = freq,
	}
	-- and its associated info
	wavpath(basename..'.txt'):write(table{
		('adsr=0x%04X'):format(tonumber(game.adsrData[i])),
		('pitch=0x%04X'):format(tonumber(game.pitchMults[i])),
		('loopOffset=0x%04X/9*32'):format(tonumber(game.loopStartOfs[i])),
	}:concat'\n'..'\n')
	--[[ debug plot it so i can see the waveform.
	require'gnuplot'{
		terminal = 'svg size '..math.floor(4*numSamples)..',512',
		output = wavpath(basename..'.svg').path,
		--samples = numSamples,
		style = 'data linespoints',
		unset = {'colorbox'},
		range = {numSamples/freq, 1},
		cbrange = {0,1},
		data = {
			range(0,numSamples-1):mapi(function(j) return j/freq end),
			range(0,numSamples-1):mapi(function(j) return tonumber(wavData[j])/32768 end),
			range(0,numSamples-1):mapi(function(j)
				local brraddr = j/16*9
				return brraddr >= game.loopStartOfs[i] and .5 or 0
			end)
		},
		{using='1:2:3', notitle=true, palette=true},
	}
	--]]
end

-- 141002 bytes ... needs 131072 bytes ... has 9930 extra bytes ...
path'WoBMapDataCompressed.bin':write( ffi.string(game.WoBMapData+0, ffi.sizeof(game.WoBMapData)))
path'WoBMapDataCompressed.hex':write( ffi.string(game.WoBMapData+0, ffi.sizeof(game.WoBMapData)):hexdump())
local WoBMapDataDecompressed = decompress(game.WoBMapData+0, ffi.sizeof(game.WoBMapData))
print('WoBMapDataDecompressed', #WoBMapDataDecompressed)
path'WoBMapDataDecompressed.bin':write(WoBMapDataDecompressed)
path'WoBMapDataDecompressed.hex':write(WoBMapDataDecompressed:hexdump())


-- output town tile graphics
-- the last 3 are 0xffffff
for i=0,0x51 do
	local ofs = game.townTileGraphicsOffsets[i]:value()
	-- this is times something and then a pointer into game.townTileGraphics
	print('townTileGraphicsOffsets[0x'..i:hex()..'] = 0x'..ofs:hex()
-- the space between them is arbitrary
--		..(i>0 and ('\tdiff=0x'..(game.townTileGraphicsOffsets[i]:value() - game.townTileGraphicsOffsets[i-1]:value()):hex()) or '')
	)
end
do
	-- 0x30c8 tiles of 8x8x4bpp = 32 bytes in game.townTileGraphics 
	local bpp = 4
	local numTiles = (0x25f400 - 0x1fdb00) / (8 * bpp)	-- = 0x30c8
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
			game.townTileGraphics + bit.lshift(i, 5),
			bpp)
	end
	-- alright where is the palette info stored?
	-- and I'm betting somewhere is the 16x16 info that points into this 8x8 tile data...
	-- and I'm half-suspicious it is compressed ...
	im.palette = makePalette(game.characterPalettes + 0x11, 4, 16)
	im:save'towntiles.png'
end


print'end of rom output'

--print('0x047aa0: ', game.padding_047aa0)

if outfn then
	math.randomseed(os.time())

	--[[ randomize ...
	here's my idea:
	make swords randomly cast.
	make espers only do stat-ups
	make later-equipment teach you spells ... and be super-weak ... and cursed-shield-break into some crap item (turn Paladin Shield into dried meat)

list of spells in order of power / when you should get them

Osmose	1
Scan	3
Antdot	3
Poison	3
Fire	4
Ice	5
Cure	5
Slow	5
Sleep	5
Bolt	6
Muddle	8
Mute	8
Haste	10
Stop	10
Imp	10
Regen	10
Rasp	12
Safe	12
Shell	15
Remedy	15
Drain	15
Bserk	16
Float	17
Vanish	18
Warp	20
Fire 2	20
Ice 2	21
Bolt 2	22
Rflect	22
Cure 2	25
Dispel	25
Break	25
Slow 2	26
Bio	26
Life	30
Demi	33
Doom	35
Haste2	38
Cure 3	40
Pearl	40
Flare	45
Quartr	48
Life 3	50
Quake	50
Fire 3	51
Ice 3	52
Bolt 3	53
X-Zone	53
Life 2	60
Meteor	62
W Wind	75
Ultima	80
Merton	85
Quick	99
	--]]

	local itemsForType = table()
	for i=0,game.numItems-1 do
		local key = game.items[i].itemType
		itemsForType[key] = itemsForType[key] or table()
		itemsForType[key]:insert(ffi.new('itemref_t', i))
	end
	print(tolua(itemsForType))
	print('number of swords: '..#itemsForType[1])

-- [[ spells ... gobbleygook
-- this made the screen go garbage at the first battle
	for i=0,game.numSpells-1 do
		local spell = game.spells+i
		for j=0,ffi.sizeof'spell_t'-1 do
			spell.s[j] = math.random(0,255)
		end
		spell.unused_7_2 = 0
		-- should this be a percent?
		spell.killsCaster = 0
	end
--]]

-- [[ swords cast random things
	for _,ref in ipairs(itemsForType[1]) do
		local item = game.items[ref.i]
		item.spellCast = math.random(0,53)
		-- this isn't working...
		item.castOnAttack = 1
		item.castOnItemUse = 1
		item.canUseInBattle = 1	-- this uses the spell
		item.canBeThrown = 1
		item.battlePower_defense = 0
	end
--]]

-- [[ random learn from all equipment ... and relics?
	for itemType=2,5 do
		for _,ref in ipairs(itemsForType[itemType]) do
			local item = game.items[ref.i]
			item.spellLearn.rate = math.random(1,100)
			item.spellLearn.spell.i = math.random(0,53)
		end
	end

	-- mithril knife teaches quick
	--game.items[1].spellCast = 43
--]]

--[[ espers ... gobbleygook everywhere
	for i=0,game.numEspers-1 do
		for j=0,ffi.sizeof'esper_t'-1 do
			game.espers[i].s[j] = math.random(0,255)
		end
	end
--]]
-- [[ espers: no spells and only stats
	local esperBonuses = range(0, 16)
	esperBonuses:removeObject(7)	-- not applicable
	esperBonuses:removeObject(8) 	-- nothing
	for i=0,game.numEspers-1 do
		local esper = game.espers[i]
		-- disable all spells
		for j=1,5 do
			esper['spellLearn'..j].rate = 255
		end
		-- pick a random bonus
		esper.bonus.i = table.pickRandom(esperBonuses)
	end
--]]

--[[ items
-- all the monsto death, countdown, etc is done through here it seems
-- this makes countdown often
	for i=0,game.numItems-1 do		-- is numItems 256 or 255?
		local item = game.items+i
		for j=0,ffi.sizeof'item_t'-1 do
			item.s[j] = math.random(0,255)
		end
		-- I think this is what causes glitches ... maybe ...
		item.unused_0_7 = 0
		item.unused_5_2 = 0
		item.unused_5_3 = 0
		item.unused_5_4 = 0
		item.unused_5_6 = 0
		item.unused_b_1 = 0
		item.unused_c_7 = 0
		item.unused_d_2 = 0
		item.unused_d_5 = 0
		item.unused_d_6 = 0
		item.unused_13_2 = 0
		--item.givesEffect2.countdown = 0
		--item.givesEffect2.muddle = 0
	end
--]]

-- [[ I think it's a monster_t stat that makes monsters insta-die ... like maybe negative life?
-- for that matter, maybe health can only exceed 32k if it has some extra magic flag set?
-- likewise there is some perma-confused in here
	for i=0,game.numMonsters-1 do
		--[=[ all fields
		for j=0,ffi.sizeof'monster_t'-1 do
			game.monsters[i].s[j] = math.random(0,255)
		end
		--]=]
		-- [=[ each individually
		game.monsters[i].speed = math.random(0,255)
--		game.monsters[i].battlePower = math.random(0,255)
		game.monsters[i].hitChance = math.random(0,255)
		game.monsters[i].evade = math.random(0,255)
        game.monsters[i].magicBlock = math.random(0,255)
        game.monsters[i].defense = math.random(0,255)
        game.monsters[i].magicDefense = math.random(0,255)
        game.monsters[i].magicPower = math.random(0,255)
 --       game.monsters[i].hp = math.random(0,65535)
  --      game.monsters[i].mp = math.random(0,65535)
        game.monsters[i].exp = math.random(0,65535)
        game.monsters[i].gold = math.random(0,65535)
        game.monsters[i].level = math.random(0,255)
        game.monsters[i].metamorphSet = math.random(0,31)
        game.monsters[i].metamorphResist = math.random(0,7)

		--game.monsters[i].diesIfRunOutOfMP = math.random(0,1)

		game.monsters[i].undead = math.random(0,1)
		game.monsters[i].cantSuplex = math.random(0,1)
		game.monsters[i].cantRun = math.random(0,1)
		game.monsters[i].cantControl = math.random(0,1)

		-- random per bitflag?
		game.monsters[i].immuneToEffect1.s[0] = math.random(0,255)

		game.monsters[i].elementHalfDamage.s[0] = math.random(0,255)
		game.monsters[i].elementAbsorb.s[0] = math.random(0,255)
		game.monsters[i].elementNoEffect.s[0] = math.random(0,255)
		game.monsters[i].elementWeak.s[0] = math.random(0,255)

		game.monsters[i].specialAttack = math.random(0,127)
		game.monsters[i].specialAttackDealsNoDamage = math.random(0,1)
		--]=]

		for j=0,ffi.sizeof'spellref4_t'-1 do
			game.monsterSpells[i].s[j].i = math.random(0,255)
		end
		for j=0,ffi.sizeof'spellref2_t'-1 do
			game.monsterSketches[i].s[j].i = math.random(0,255)
		end
		if i < game.numRages then
			for j=0,ffi.sizeof'spellref2_t'-1 do
				game.monsterRages[i].s[j].i = math.random(0,255)
			end
		end
	end
--]]

	-- good menu stuff:
	-- exclude Fight Item Magic Def Row
	local goodMenus = range(0,29)
	for _,i in ipairs{0,1,2,4,20,21} do
		goodMenus:removeObject(i)
	end
	-- TODO if you pick Leap then you should proly change Fight to Rage too  ... or not?

-- [[ equipping items in the wrong spot has adverse effects
	for i=0,game.numCharacters-1 do
		--[=[
		for j=0,ffi.sizeof'character_t'-1 do
			game.characters[i].s[j] = math.random(0,255)
		end
		--]=]
		-- [=[
		game.characters[i].hp = math.random(0,255)
		game.characters[i].mp = math.random(0,255)
		--game.characters[i].menu.s[0].i = math.random(0,game.numMenuNames-1)		-- fight
		--game.characters[i].menu.s[1].i = math.random(0,game.numMenuNames-1)
		--game.characters[i].menu.s[0].i = goodMenus:pickRandom()
		game.characters[i].menu.s[1].i = goodMenus:pickRandom()
		--game.characters[i].menu.s[2].i = math.random(0,game.numMenuNames-1)		-- magic
		--game.characters[i].menu.s[3].i = math.random(0,game.numMenuNames-1)		-- item
		-- [==[
		game.characters[i].vigor = math.random(0,255)
		game.characters[i].speed = math.random(0,255)
        game.characters[i].stamina = math.random(0,255)
        game.characters[i].magicPower = math.random(0,255)
        game.characters[i].battlePower = math.random(0,255)
        game.characters[i].defense = math.random(0,255)
        game.characters[i].magicDefense = math.random(0,255)
        game.characters[i].evade = math.random(0,255)
        game.characters[i].magicBlock = math.random(0,255)
		--]==]
        -- [==[
		-- TODO verify that the item is equippable
		game.characters[i].lhand.i = math.random(0,255)
		game.characters[i].rhand.i = math.random(0,255)
		game.characters[i].head.i = math.random(0,255)
		game.characters[i].body.i = math.random(0,255)
		game.characters[i].relic.s[0].i = math.random(0,255)
		game.characters[i].relic.s[1].i = math.random(0,255)
		--]==]
		--game.characters[i].level = math.random(1,99)
		--]=]
	end
--]]

	for i=0,game.numShops-1 do
		for j=0,ffi.sizeof'shopinfo_t' do
			game.shops[i].s[j] = math.random(0,255)
		end
	end

	print'writing...'
	path(outfn):write(ffi.string(data, #data))
end
