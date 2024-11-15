#!/usr/bin/env luajit
local ffi = require 'ffi'
require 'ext'

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

for i=0,game.numMonsterPalettes-1 do
	print('monster palette #'..i)
	print(game.monsterPalettes[i])
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
--[[
local writeMonsterSprite = require 'monstersprite'
for i=0,game.numMonsterSprites-1 do
	totalPixels = totalPixels + writeMonsterSprite(game, i)
end
print('wrote monster pixels', totalPixels)
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

--[[
local readCharSprite = require 'charsprite'
for i=0,game.numCharacterSprites-1 do
	totalPixels = totalPixels + readCharSprite(game, i)
end
print('wrote total pixels', totalPixels)
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
--print('menuPortraitPalette = '..game.menuPortraitPalette)
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

do
	local Image = require 'image'
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
	loopStartPtrs
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
	assert.eq(game.loopStartPtrs[i] % 9, 0, "why isn't the brr loop aligned to brr frames?")
	io.write(' loopStartPtr: '..('0x%04x'):format(tonumber(game.loopStartPtrs[i])))
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
		..range(0, len-1):mapi(function(i)
			local s = ('%02x'):format(rom[startAddr + i])
			if i % 9 == 0 then s = '['..s end
			if i % 9 == 8 then s = s..']' end
			return s
		end):concat' ')

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
				--[=[ BRRtools
				if sample < 0 then
					sample = -0x800
				else
					sample = 0x800
				end
				--]=]
				-- [=[ snesbrr
				sample = bit.band(sample, bit.bnot(0x7ff))
				--]=]
			else
				sample = bit.lshift(sample, shift)
				-- why is this? maybe to do with the filter using the post-sampled value for previous frame values?
				sample = bit.arshift(sample, 1)
			end
			--]]

			local sampleBeforeFilter = sample
			--[[ https://github.com/Optiroc/BRRtools/blob/master/src/brr.c#L153
			if decodeFilter == 0 then
			elseif decodeFilter == 1 then
				sample = sample + (
					  lastSample[0]
					- bit.arshift(lastSample[0], 4)
				)
			elseif decodeFilter == 2 then
				sample = sample + (
					  bit.arshift(-(lastSample[0] + bit.lshift(lastSample[0], 1)), 5)
					- lastSample[1]
					+ bit.arshift(lastSample[1], 4)
				)
			elseif decodeFilter == 3 then
				sample = sample + (
					  bit.lshift(lastSample[0], 1)
					+ bit.arshift(-(lastSample[0] + bit.lshift(lastSample[0], 2) + bit.lshift(lastSample[0], 3)), 6)
					- lastSample[1]
					+ bit.arshift(lastSample[1] + bit.lshift(lastSample[1], 1), 4)
				)
			else
				error'here'
			end
			--]]
			--[[ https://wiki.superfamicom.org/bit-rate-reduction-(brr)
			if decodeFilter == 0 then
			elseif decodeFilter == 1 then
				sample = sample + lastSample[0] * 15/16
			elseif decodeFilter == 2 then
				sample = sample + lastSample[0] * 61/32 - lastSample[0] * 15/16
			elseif decodeFilter == 3 then
				sample = sample + lastSample[0] * 115/64 - lastSample[1] * 13/16
			else
				error'here'
			end
			--]]
			sample = ffi.cast('int16_t', sample)

			-- [[ snesbrr: "wrap to 15 bits, sign-extend to 16 bits"
			sample = bit.arshift(bit.lshift(sample, 1), 1)
			sample = ffi.cast('int16_t', sample)
			--]]

			--[[ BRRtools:
			if sample > 0x7fff then
				sample = 0x7fff
			elseif sample < -0x8000 then
				sample = -0x8000
			end
			if sample > 0x3fff then
				sample = sample - 0x8000
			elseif sample < -0x4000 then
				sample = sample + 0x8000
			end
			--]]

			wavptr[0] = sample
			--wavptr[0] = bit.lshift(sample, 1)
			--lastSample[0], lastSample[1] = sampleBeforeFilter, lastSample[0]
			lastSample[0], lastSample[1] = wavptr[0], lastSample[0]
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
	local AudioWAV = require 'audio.io.wav'
	AudioWAV():save{
		filename = wavpath(i..'.wav').path,
		ctype = 'int16_t',
		channels = 1,
		data = wavData,
		size = numSamples * ffi.sizeof'int16_t',
		freq = 32000,
	}
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
