#!/usr/bin/env luajit
local ffi = require 'ffi'
require 'ext'

local infn, outfn = ...
assert(infn, "missing filename")
local data = assert(file[infn])
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

for i=0,game.numCharacters-1 do
	print('character #'..i)
	print('Name="'..game.characterNames[i]..'"')
	print(game.characters[i])
	print()
end

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

--[[
args:
	name = section name
	data = uint8_t[?] buffer in memory for string data
	addrBase = (optional) base of offsets, data by default
	offsets = uint16_t[?] buffer in memory for offsets 
	compressed = boolean
--]]
local function printStrings(args)
	local name = assert(args.name)
	local offsets = assert(args.offsets)
	assert(type(offsets) == 'cdata')
	local numOffsets = tostring(ffi.typeof(offsets)):match'ctype<unsigned short %(&%)%[(%d+)%]>'
	assert(numOffsets)
	
	local data = assert(args.data)
	assert(type(data) == 'cdata')
	local numPtr = tostring(ffi.typeof(data)):match'ctype<unsigned char %(&%)%[(%d+)%]>'
	assert(numPtr)
	local addrMin = data - rom
	local addrMax = addrMin + numPtr
	local addrSize = addrMax - addrMin
	
	local addrBase = (args.addrBase and args.addrBase or data) - rom
	local strf = args.compressed and game.compzstr or game.gamezstr
	
	for i=0,numOffsets-1 do
		local offset = offsets[i]
		if offset ~= 0xffff then
			print(name..' #'..i..': '..('0x%04x'):format(offset)..' "'..strf(rom + addrBase + offset)..'"')
		end
	end
	
	-- track memory used
	local used = {}
	for i=0,numOffsets-1 do
		local offset = offsets[i]
		if offset ~= 0xffff then
			if not (addrBase + offset >= addrMin and addrBase + offset < addrMax) then
				error("offset "..i.." was out of bound")
			end
			local ptr = rom + addrBase + offset
			local pend = game.findnext(ptr, {0})
			local addrEnd = pend - rom
			for j=addrBase+offset, addrEnd do
				assert(j >= addrMin and j < addrMax)
				used[j] = true
			end
		end
	end
	local count = 0
	local show = false	-- true
	local showWidth = math.ceil(math.sqrt(addrSize))	--64
	for j=addrMin,addrMax-1 do
		if used[j] then count = count + 1 end

	if show then
		io.write(used[j] and '#' or '.')
		if (j-addrMin) % showWidth == (showWidth-1) then print() end
	end
	end
	if show then
		if (addrMax-addrMin) % showWidth ~= 0 then print() end
	end
	print(name..' % used: '..count..'/'..addrSize..' = '..('%.3f%%'):format(100*count/addrSize))
	print()
end

printStrings{
	name = 'location',
	data = game.locationNameBase,
	offsets = game.locationNameOffsets,
	compressed = true,
}

printStrings{
	name = 'dialog',
	data = game.dialogBase,
	offsets = game.dialogOffsets,
	compressed = true,
}

printStrings{
	name = 'battle dialog',
	data = game.battleDialogBase,
	offsets = game.battleDialogOffsets,
	addrBase = rom + 0x0f0000,
}

printStrings{
	name = 'battle dialog2',
	data = game.battleDialog2Base,
	offsets = game.battleDialog2Offsets,
	addrBase = rom + 0x100000,
}

printStrings{
	name = 'battle message',
	data = game.battleMessageBase,
	offsets = game.battleMessageOffsets,
	addrBase = rom + 0x110000,
}

printStrings{
	name = 'positioned text',
	data = game.positionedTextBase,
	offsets = game.positionedTextOffsets,
	addrBase = rom + 0x030000,
}

print('WoB palette = '..game.WoBpalettes)
print('WoR palette = '..game.WoRpalettes)
print('setzer airship palette = '..game.setzerAirshipPalette)
print('daryl airship palette = '..game.darylAirshipPalette)
print('menuWindowPalettes = '..game.menuWindowPalettes)
print('characterMenuImages = '..game.characterMenuImages)
print('menuPortraitPalette = '..game.menuPortraitPalette)
print('handCursorGraphics = '..game.handCursorGraphics)
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


--print('0x047aa0: ', game.padding_047aa0)

if outfn then
	math.randomseed(os.time())

	--[[ randomize ...
	here's my idea:
	make swords randomly cast.
	make espers only do stat-ups
	make later-equipment teach you spells ... and be super-weak ... and cursed-shield-break into some crap item (turn Paladin Shield into dried meat)

list of spells in order of power / when you should get them



°Osmose	1
°Scan	3
²Antdot	3
±Poison	3
±Fire	4
±Ice	5
²Cure	5
°Slow	5
°Sleep	5
±Bolt	6
°Muddle	8
°Mute	8
°Haste	10
°Stop	10
°Imp	10
²Regen	10
°Rasp	12
°Safe	12
°Shell	15
²Remedy	15
±Drain	15
°Bserk	16
°Float	17
°Vanish	18
°Warp	20
±Fire 2	20
±Ice 2	21
±Bolt 2	22
°Rflect	22
²Cure 2	25
°Dispel	25
±Break	25
°Slow 2	26
±Bio	26
²Life	30
±Demi	33
±Doom	35
°Haste2	38
²Cure 3	40
±Pearl	40
±Flare	45
±Quartr	48
²Life 3	50
±Quake	50
±Fire 3	51
±Ice 3	52
±Bolt 3	53
±X-Zone	53
²Life 2	60
±Meteor	62
±W Wind	75
±Ultima	80
±Merton	85
°Quick	99
	--]]

	local itemsForType = table()
	for i=0,game.numItems-1 do
		local key = game.items[i].itemType
		itemsForType[key] = itemsForType[key] or table()
		itemsForType[key]:insert(ffi.new('itemref_t', i))
	end
	print(tolua(itemsForType))
	print('number of swords: '..#itemsForType[1])

	local function pickrandom(t)
		return t[math.random(#t)]
	end

	
	-- swords
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
	
	-- equipment ... and relics?
	for itemType=2,5 do
		for _,ref in ipairs(itemsForType[itemType]) do
			local item = game.items[ref.i]
			item.spellLearnRate = math.random(1,100)
			item.spellLearned.i = math.random(0,53)
		end
	end

	game.items[game.itemForName.MithrilKnife].spellCast = game.spellForName.Quick

	-- espers: no spells and only stats
	local esperBonuses = range(0, 16)
	esperBonuses:removeObject(7)	-- not applicable
	esperBonuses:removeObject(8) 	-- nothing
	for i=0,game.numEspers-1 do
		local esper = game.espers[i]
		-- disable all spells
		esper.spellLearnRate1 = 255
		esper.spellLearnRate2 = 255
		esper.spellLearnRate3 = 255
		esper.spellLearnRate4 = 255
		esper.spellLearnRate5 = 255
		-- pick a random bonus
		esper.bonus.i = pickrandom(esperBonuses)
	end

	print'writing...'
	file[outfn] = ffi.string(data, #data)
end

--print(game.compstr(rom + 0x0f37c0, 0x0f3940 - 0x0f37c0))
--print(game.gamestr(rom + 0x03c2fc, 0x03c326 - 0x03c2fc))
--print(game.gamestr(rom + 0x03c2fc, 0x03c406 - 0x03c2fc))
