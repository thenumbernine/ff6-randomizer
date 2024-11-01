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
local writeMonsterSprite = require 'monstersprite'
for i=0,game.numMonsterSprites-1 do
	totalPixels = totalPixels + writeMonsterSprite(game, i)
end
print('wrote monster pixels', totalPixels)

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

local readCharSprite = require 'charsprite'
for i=0,game.numCharacterSprites-1 do
	totalPixels = totalPixels + readCharSprite(game, i)
end
print('wrote total pixels', totalPixels)

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

-- [[ spells ... gobbleygook
	for i=0,game.numSpells-1 do
		for j=0,ffi.sizeof'spell_t'-1 do
			game.spells[i].ptr[j] = math.random(0,255)
		end
		-- should this be a percent?
		game.spells[i].killsCaster = 0
	end
--]]

-- [[ swords
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

	game.items[game.itemForName.MithrilKnife].spellCast = game.spellForName.Quick
--]]

--[[ espers ... gobbleygook everywhere
	for i=0,game.numEspers-1 do
		for j=0,ffi.sizeof'esper_t'-1 do
			game.espers[i].ptr[j] = math.random(0,255)
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



-- [[ items ... gobbleygook
-- all the monsto death, countdown, etc is done through here it seems
-- this makes countdown often
	for i=0,game.numItems-1 do		-- is numItems 256 or 255?
		for j=0,ffi.sizeof'item_t'-1 do
			game.items[i].ptr[j] = math.random(0,255)
		end
		game.items[i].givesEffect2.countdown = 0
	end
--]]

-- [[ I think it's a monster_t stat that makes monsters insta-die ... like maybe negative life?
-- for that matter, maybe health can only exceed 32k if it has some extra magic flag set?
-- likewise there is some perma-confused in here
	for i=0,game.numMonsters-1 do
		--[=[ all fields
		for j=0,ffi.sizeof'monster_t'-1 do
			game.monsters[i].ptr[j] = math.random(0,255)
		end
		--]=]
		-- [=[ each individually
		game.monsters[i].speed = math.random(0,255)
		game.monsters[i].battlePower = math.random(0,255)
		game.monsters[i].hitChance = math.random(0,255)
		game.monsters[i].evade = math.random(0,255)
        game.monsters[i].magicBlock = math.random(0,255)
        game.monsters[i].defense = math.random(0,255)
        game.monsters[i].magicDefense = math.random(0,255)
        game.monsters[i].magicPower = math.random(0,255)
        game.monsters[i].hp = math.random(0,65535)
        game.monsters[i].mp = math.random(0,65535)
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
		game.monsters[i].immuneToEffect1.ptr[0] = math.random(0,255)

		game.monsters[i].elementHalfDamage.ptr[0] = math.random(0,255)
		game.monsters[i].elementAbsorb.ptr[0] = math.random(0,255)
		game.monsters[i].elementNoEffect.ptr[0] = math.random(0,255)
		game.monsters[i].elementWeak.ptr[0] = math.random(0,255)

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

-- [[ equipping items in the wrong spot has adverse effects
	for i=0,game.numCharacters-1 do
		--[=[
		for j=0,ffi.sizeof'character_t'-1 do
			game.characters[i].ptr[j] = math.random(0,255)
		end
		--]=]
		-- [=[
		game.characters[i].hp = math.random(0,255)
		game.characters[i].mp = math.random(0,255)
		--game.characters[i].menu.s[0].i = math.random(0,game.numMenuNames-1)		-- fight
		game.characters[i].menu.s[1].i = math.random(0,game.numMenuNames-1)
		--game.characters[i].menu.s[2].i = math.random(0,game.numMenuNames-1)		-- magic
		--game.characters[i].menu.s[3].i = math.random(0,game.numMenuNames-1)		-- item
		--[==[
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
        -- TODO verify that the item is equippable
		game.characters[i].lhand.i = 255
		game.characters[i].rhand.i = 255
		game.characters[i].head.i = 255
		game.characters[i].body.i = 255
		game.characters[i].relic.s[0].i = 255
		game.characters[i].relic.s[1].i = 255
		--game.characters[i].level = math.random(1,99)
	end
--]]

	for i=0,game.numShops-1 do
		for j=0,ffi.sizeof'shopinfo_t' do
			game.shops[i].ptr[j] = math.random(0,255)
		end
	end

	print'writing...'
	path(outfn):write(ffi.string(data, #data))
end
