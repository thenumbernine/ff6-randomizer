local table = require 'ext.table'
local ffi = require 'ffi'
local struct = require 'struct'
local createVec = require 'vec-ffi.create_vec'

-- using 
-- http://www.rpglegion.com/ff6/hack/ff3info.txt
-- https://github.com/subtractionsoup/beyondchaos

return function(rom)
-- compstr uses game
local game

local function findnext(ptr, data)
	while true do
		local found = true
		for j=1,#data do
			if ptr[j-1] ~= data[j] then
				found = false
				break
			end
		end
		if found then return ptr end
		ptr = ptr + 1
	end
end


local gameToAscii = table{
'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
'w','x','y','z','0','1','2','3','4','5','6','7','8','9','!','?',
'/',':','"',"'",'-','.',',','…',';','#','+','(',')','%','~','*',
' ',' ','=','`','↑','→','↙',  1,  2,  3,  4,  5,  6,  7,  8,179,
180,181,182,183,184,185,186,187,178,177,176,' ',' ',' ',' ',' ',
188,189,190,191,192,193,194,195,196,'{','}',' ',' ',' ',' ',' '}
:mapi(function(v)
	if type(v) == 'number' then return string.char(v) end
	return v
end)
local function gamestr(ptr, len)
	assert(len, "did you want to use gamezstr?")
	local s = table()
	for i=0,len-1 do
		local ch = ptr[i]
		ch = bit.band(ch, 0x7f)
		local ascii = gameToAscii[ch+1]
		assert(ascii, "failed to find ascii for game char "..ptr[i])
		s:insert(ascii)
	end
	return s:concat()
end

local function gamezstr(ptr)
	local pend = findnext(ptr, {0})
	return gamestr(ptr, pend - ptr)
end

-- same as gameToAscii ... one uses single-chars the other uses []'s
local convertCompressedChar = {
"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P",
"Q","R","S","T","U","V","W","X","Y","Z","a","b","c","d","e","f",
"g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v",
"w","x","y","z","0","1","2","3","4","5","6","7","8","9","!","?",
"/",":",'"',"'","-",".",',',"...",";","#","+","(",")","%","~","*",
"[0]","[1]","=",'"',"[up arrow]","[right arrow]","[down left arrow]","[x]", "[dirk]", "[sword]","[lance]","[knife]","[rod]","[brush]","[stars]","[special]",
"[gambler]","[claw]","[shield]","[helmet]","[armor]","[tool]","[skean]","[relic]","[white]","[grey]","[black]","[2]","[3]","[4]","[5]","[6]",
"[swd 0]","[swd 1]","[swd 2]","[swd 3]","[swd 4]","[swd 5]","[swd 6]","[swd 7]","[swd 8]","{","}","[7]","[8]","[9]","[10]","[11]",
}

local convertCompressedDoubleChar = {
'e ',' t',': ','th','t ','he','s ','er',
' a','re','in','ou','d ',' w',' s','an',
'o ',' h',' o','r ','n ','at','to',' i',
', ','ve','ng','ha',' m','Th','st','on',
'yo',' b','me','y ','en','it','ar','ll',
'ea','I ','ed',' f',' y','hi','is','es',
'or','l ',' c','ne',"'s",'nd','le','se',
' I','a ','te',' l','pe','as','ur','u ',
'al',' p','g ','om',' d','f ',' g','ow',
'rs','be','ro','us','ri','wa','we','Wh',
'et',' r','nt','m ','ma',"I'",'li','ho',
'of','Yo','h ',' n','ee','de','so','gh',
'ca','ra',"n'",'ta','ut','el','! ','fo',
'ti','We','lo','e!','ld','no','ac','ce',
'k ',' u','oo','ke','ay','w ','!!','ag',
'il','ly','co','. ','ch','go','ge','e.',
}

local compstr_displayChars = true

local function compstr(p, size)
	assert(size)
	local c = table()
	local b = 0
	for a=0,size-1 do
		if p[0] < 0x80 then
			if p[0] == 0x7f then
				c:insert' '
			elseif p[0] < 32 then
--[[
				if p[0] == 22 and p[1] == 24 and p[2] == 18 then -- pause
					if compstr_displayChars then
						c:insert'[p]\n'
					else
						c:insert'\n'
					end
					p = p + 2
				else
--]]
				if p[0] == 0 then			 -- end of message
					c:insert'[END]'
				elseif p[0] == 1 then	-- line feed mid-message
					c:insert'\n'
				elseif p[0] < 16 then	-- 2-15 = char name
					c:insert'['
--					c:insert(('%02d-'):format(p[0]))
					c:insert(tostring(game.characterNames[p[0]-2]))
					c:insert']'
				elseif p[0] == 16 then
					c:insert'[PAUSE]'
				--elseif p[0] == 17 then -- read until 18
				--elseif p[0] == 18 then -- terminates a 17, or begins a message. 
				elseif p[0] == 19 then	-- clear and new message
					c:insert'\n[CLEAR]'
					c:insert'\n'
				--elseif p[0] == 20 then -- read 1 more char ... horizontal tab?
				elseif p[0] == 21 then
					c:insert'[PROMPT]'			
				--elseif p[0] == 22 then -- read until 18
				--23, 24, 29: only used between 17 and 18, specifically in opera scene dialog
				--25, 26, 27, 28, 30, 31: never used
				else
					if compstr_displayChars then
						c:insert(('[%02d]'):format(p[0]))
					else
						c:insert'\n'
					end
				end
			else
				c:insert(convertCompressedChar[p[0]-32+1])
			end
		else
			c:insert(convertCompressedDoubleChar[p[0] - 0x80 + 1])
		end
		p = p + 1
	end
	return c:concat()
end

local function compzstr(ptr)
	local pend = findnext(ptr, {0})
	return compstr(ptr, pend - ptr)
end



local reftype = require 'reftype'

local function gamestrtype(args)
	local name = assert(args.name)
	local size = assert(args.size)
	ffi.cdef([[
typedef struct ]]..name..[[ {
	uint8_t ptr[]]..size..[[];
} ]]..name..[[;
]])
	assert(ffi.sizeof(name)  == size)
	local metatype = ffi.metatype(name, {
		__tostring = function(self)
			return gamestr(self.ptr, size):trim()
		end,
		__concat = function(a,b) return tostring(a) .. tostring(b) end,
	})
	return metatype 
end

local function rawtype(args)
	local name = assert(args.name)
	local size = assert(args.size)
	ffi.cdef([[
typedef struct ]]..name..[[ {
	uint8_t ptr[]]..size..[[];
} ]]..name..[[;
]])
	assert(ffi.sizeof(name)  == size)
	local metatype = ffi.metatype(name, {
		__tostring = function(self)
			local s = table()
			for i=0,size-1 do
				s:insert(('%02x'):format(self.ptr[i]))
			end
			return s:concat' '
		end,
		__concat = function(a,b) return tostring(a) .. tostring(b) end,
	})
	return metatype 
end

--[[
args:
	name
	options
	type (optional) default uint8_t
--]]
local function bitflagtype(args)
	local ctype = args.type or 'uint8_t'
	return struct{
		name = assert(args.name),
		fields = table.mapi(assert(args.options), function(option)
			return {[assert(option)] = ctype..':1'}
		end),
	}
end 

local element_t = bitflagtype{
	name = 'element_t',
	options = {
		'fire',
		'ice',
		'thunder',
		'poison',
		'wind',
		'pearl',
		'earth',
		'water',
	},
}

local targetting_t = bitflagtype{
	name = 'targetting_t',
	options = {
		'one',
		'oneSideOnly',
		'everyone',
		'groupDefault',
		'automatic',
		'group',
		'enemyDefault',
		'random',
	},
}

local effect1_t = bitflagtype{
	name = 'effect1_t',
	options = {
		'dark',
		'zombie',
		'poison',
		'magitech',
		'invisible',
		'imp',
		'petrify',
		'mortal',
	},
}

local effect2_t = bitflagtype{
	name = 'effect2_t',
	options = {
		'countdown',
		'nearFatal',
		'image',
		'mute',
		'berzerk',
		'muddle',
		'hpLeak',
		'sleep',
	},
}
	
local effect3_t = bitflagtype{
	name = 'effect3_t',
	options = {
		'danceFloat',
		'regen',
		'slow',
		'haste',
		'stop',
		'shell',
		'safe',
		'reflect',
	},
}

local effect4_t = bitflagtype{
	name = 'effect4_t',
	options = {
		'raging',
		'frozen',	-- are you sure this isn't 'isRunic'?
		'reraise',
		'morphed',
		'casting',
		'removedFromBattle',
		'interceptor',
		'floating',
	},
}

local function makefixedstr(n)
	return gamestrtype{
		name = 'str'..n..'_t',
		size = n,
	}
end

makefixedstr(6)
makefixedstr(7)
makefixedstr(8)
makefixedstr(9)
makefixedstr(10)
makefixedstr(12)
makefixedstr(13)

local madefixedraw = {}
local function makefixedraw(n)
	local cache = madefixedraw[n]
	if cache then return table.unpack(cache) end
	local name = 'raw'..n..'_t'
	local mt = rawtype{
		name = name, 
		size = n,
	}
	madefixedraw[n] = {mt, name}
	return mt, name 
end

makefixedraw(12)

---------------- SPELLS ----------------

local numSpells = 0x100


local spellNamesAddr = 0x26f567
-- needs 'game' as a parameter ... but can't always get it there ... so look for a global instead
local function getSpellName(i)
	i = bit.band(i, 0xff)
	-- black, grey, white
	if i >= 0 and i < 54 then return tostring(game.spellNames_0to53[i]):trim() end
	i = i - 54
	-- esper
	if i >= 0 and i < 27 then return tostring(game.spellNames_54to80[i]):trim() end
	i = i - 27
	-- rest:
	if i >= 0 and i < 175 then return tostring(game.spellNames_81to255[i]):trim() end
	error'here'
end

-- needs 'game' to correctly call 'getSpellName' with a parameter
local spellref_t = reftype{
	name = 'spellref_t',
	getter = function(i)
		if i == 0xff then return nil end
		return getSpellName(i)
	end,
	getterSkipNone = true,
}

local spell_t = struct{
	name = 'spell_t',
	fields = {
		-- 00:
		{targetting = 'targetting_t'},
		-- 01:
		{elementDamage = 'element_t'},
		-- 02:
		{physical = 'uint8_t:1'},
		{isAMortalAttack = 'uint8_t:1'},	-- miss if protected from death
		{canTargetWounded = 'uint8_t:1'},
		{oppositeToUndead = 'uint8_t:1'},
		{randomizeTarget = 'uint8_t:1'},
		{undefendable = 'uint8_t:1'},
		{dontDivideDamageForMultipleTargets = 'uint8_t:1'},
		{onlyTargetEnemies = 'uint8_t:1'},
		-- 03:
		{canUseInMenu = 'uint8_t:1'},	-- rpglegion says this is use-in-battle
		{cannotReflect = 'uint8_t:1'},
		{isLore = 'uint8_t:1'},
		{enableRunic = 'uint8_t:1'},	-- ???
		{usedByWarpAndQuick = 'uint8_t:1'},	-- warp, quick
		{retargetDead = 'uint8_t:1'},	-- ???
		{killsCaster = 'uint8_t:1'},
		{damagesTargetsMP = 'uint8_t:1'},
		-- 04:
		{heals = 'uint8_t:1'},
		{drainsLife = 'uint8_t:1'},
		{removesEffects = 'uint8_t:1'},
		{invertsEffects = 'uint8_t:1'},	-- imp, vanish, imp song ... rpglegion says gives status conditions
		{evadeByStamina = 'uint8_t:1'},
		{unevadable = 'uint8_t:1'},
		{hitIfLevelDivisibleBySpellHitChance = 'uint8_t:1'},
		{damageIsPercentOfLifeTimesSpellPowerOver16 = 'uint8_t:1'},
		-- 05:
		{mp = 'uint8_t'},
		-- 06:
		{power = 'uint8_t'},
		-- 07:
		{maybe_noDamage = 'uint8_t:1'},
		{mabye_hitBasedOnLevel = 'uint8_t:1'},
		{unused_7_2 = 'uint8_t:6'},
		-- 08:
		{hitChance = 'uint8_t'},
		-- 09:
		{specialEffect = 'uint8_t'},
		-- 0x0a:
		{givesEffect1 = 'effect1_t'},
		-- 0x0b:
		{givesEffect2 = 'effect2_t'},
		-- 0x0c:
		{givesEffect3 = 'effect3_t'},
		-- 0x0d:
		{givesEffect4 = 'effect4_t'},
	},
	metatable = function(mt)
		local oldFieldToString = mt.fieldToString
		mt.fieldToString = function(self, name, ctype)
			if name == 'specialEffect' then
				if self[name] == 0xff then
					return nil
				end
			elseif name == 'unused_7_2' then
				if self[name] == 0 then
					return nil
				end
			end
			return oldFieldToString(self, name, ctype)
		end
	end,
}
assert(ffi.sizeof'spell_t' == 0x0e)

local spellsAddr = 0x046ac0
local spellDescOffsetsAddr = 0x18cf80
local spellDescBaseAddr = 0x18c9a0	-- spells 0-53

ffi.cdef[[typedef str9_t esperBonusDesc_t;]]
local numEsperBonuses = 17
local esperBonusDescsAddr = 0x0ffeae

local longEsperBonusDescOffsetsAddr =  0x2dffd0
local longEsperBonusDescBaseAddr =  0x2dfe00

-- another one that needs 'game'
local esperBonus_t = reftype{
	name = 'esperBonus_t',
	getter = function(i) return game.esperBonusDescs[i] end,
}

local esperAttackNamesAddr = 0x26fe8f
-- also needs a pointer to 'game'
local function getEsperName(i) return getSpellName(i + 54) end

local spellLearn_t = struct{
	name = 'spellLearn_t',
	fields = {
		{rate = 'uint8_t'},
		{spell = 'spellref_t'},
	},
}

local esper_t = struct{
	name = 'esper_t',
	fields = {
		{spellLearn1 = 'spellLearn_t'},
		{spellLearn2 = 'spellLearn_t'},
		{spellLearn3 = 'spellLearn_t'},
		{spellLearn4 = 'spellLearn_t'},
		{spellLearn5 = 'spellLearn_t'},
		{bonus = 'esperBonus_t'}, 
	},
}
assert(ffi.sizeof'esper_t' == 11)
local numEspers = 27
local espersAddr = 0x186e00

-- 0x0f3940 - 0x0f3c40
local esperDescBaseAddr = 0x0f3940

-- 0x0ffe40 - 0x0ffe76 = esper desc offsets
local esperDescOffsetsAddr = 0x0ffe40


---------------- MONSTERS HEADER ----------------

local numMonsters = 0x180

ffi.cdef[[typedef str10_t monsterName_t;]]
local monsterNamesAddr = 0x0fc050

-- This is a uint8_t even though there are 384 monsters.
-- If I find a uint16_t then I'll make reftype more flexible and make a second monsterRef16_t type.
local monsterRef_t = reftype{
	name = 'monsterRef_t',
	getter = function(i) return game.monsterNames[i] end,
}

local numFormations = 0x240
local numFormationMPs = 0x200

local formationAddr = 0xf6200		-- 576 in size
local formationMPAddr = 0x1fb400	-- 512 in size

local xy_t = struct{
	name = 'xy_t',
	fields = {
		{x = 'uint8_t:4'},
		{y = 'uint8_t:4'},
	},
}
local xy6_t = createVec{
	dim = 6,
	ctype = 'xy_t',
	vectype = 'xy6_t',
}

local formation_t = struct{
	name = 'formation_t',
	fields = {
		-- 0x00
		{unused_0_0 = 'uint8_t:1'},
		{unused_0_1 = 'uint8_t:1'},
		{unused_0_2 = 'uint8_t:1'},
		{unused_0_3 = 'uint8_t:1'},
		{formationSize = 'uint8_t:4'},	-- points to index in formationSizeOffsets
		-- 0x01
		{active1 = 'uint8_t:1'},
		{active2 = 'uint8_t:1'},
		{active3 = 'uint8_t:1'},
		{active4 = 'uint8_t:1'},
		{active5 = 'uint8_t:1'},
		{active6 = 'uint8_t:1'},
		{unused_1_6 = 'uint8_t:1'},
		{unused_1_7 = 'uint8_t:1'},
		
		-- 0x02
		{monster1 = 'uint8_t'},
		-- 0x03
		{monster2 = 'uint8_t'},
		-- 0x04
		{monster3 = 'uint8_t'},
		-- 0x05
		{monster4 = 'uint8_t'},
		-- 0x06
		{monster5 = 'uint8_t'},
		-- 0x07
		{monster6 = 'uint8_t'},
		
		-- 0x08 - 0x0d
		--{positions = 'xy6_t'},
		-- can't occlude if x,y are nested
		{pos1 = 'xy_t'},
		{pos2 = 'xy_t'},
		{pos3 = 'xy_t'},
		{pos4 = 'xy_t'},
		{pos5 = 'xy_t'},
		{pos6 = 'xy_t'},

		-- 0x0e
		{monster1hi = 'uint8_t:1'},
		{monster2hi = 'uint8_t:1'},
		{monster3hi = 'uint8_t:1'},
		{monster4hi = 'uint8_t:1'},
		{monster5hi = 'uint8_t:1'},
		{monster6hi = 'uint8_t:1'},
		{unused_e_6 = 'uint8_t:1'},
		{unused_e_7 = 'uint8_t:1'},
	},
	metatable = function(mt)
		local oldFieldToString = mt.fieldToString
		mt.fieldToString = function(self, key, ctype)
			if key:match'^monster%dhi$' then return nil end
			if key:match'^active%d$' then return nil end
			
			local i = key:match'^monster(%d)$'
			if i then
				if self['active'..i] == 0 then return nil end
				local v = self[key]
				if self['monster'..i..'hi'] ~= 0 then v = v + 0x100 end
				return '"'..game.monsterNames[v]..'"'
			end
			
			local i = key:match'^pos(%d)$'
			if i then
				if self['active'..i] == 0 then return nil end
			end
		
			if key == 'formationSize' then
				local v = self[key]
				local offset = game.formationSizeOffsets[v]
				local formationSize = ffi.cast('formationSize_t*', rom + 0x020000 + offset)
				return tolua(range(1,6):mapi(function(i)
					if self['active'..i] ~= 0 then
						return tostring(formationSize[i-1])
					end
				end))
			end

			return oldFieldToString(self, key, ctype)
		end
	end,
}
assert(ffi.sizeof'formation_t' == 0xf)

local formationIntroNames = {
	'none',	-- 0
	'smoke',
	'dropdown',
	'from left',
	'splash from below',
	'float down',
	'splash from below (sand?)',
	'from left (fast?)',
	'fade in (top-bottom)',
	'fade in (bottom-top)',
	'fade in (wavey)',
	'fade in (slicey)',
	'none',
	'blink in',
	'stay below screen',
	'slowly fall, play Dancing Mad',
}

local formationMusicNames = {
	'regular',
	'boss',
	'atmaweapon',
	'returners theme',
	'minecart',
	'dancing mad',
	'no change',
	'no change',
}

local formation2_t = struct{
	name = 'formation2_t',
	fields = {
		-- 0:
		{intro = 'uint8_t:4'},
		{normal = 'uint8_t:1'},
		{back = 'uint8_t:1'},
		{pincer = 'uint8_t:1'},
		{side = 'uint8_t:1'},
		-- 1:
		{unknown_1_0 = 'uint8_t:1'},
		{continuousMusic = 'uint8_t:1'},
		{unknown_1_2 = 'uint8_t:1'},
		{unknown_1_3 = 'uint8_t:1'},
		{unknown_1_4 = 'uint8_t:1'},
		{unknown_1_5 = 'uint8_t:1'},
		{unknown_1_6 = 'uint8_t:1'},
		{hasEvent = 'uint8_t:1'},
		-- 2:
		{event = 'uint8_t'},
		-- 3:
		{unknown_3_0 = 'uint8_t:1'},
		{unknown_3_1 = 'uint8_t:1'},
		{windows = 'uint8_t:1'},
		{music = 'uint8_t:3'},
		{unknown_3_6 = 'uint8_t:1'},
		{continuousMusic2 = 'uint8_t:1'},
	},
	metatable = function(mt)
		local oldFieldToString = mt.fieldToString
		mt.fieldToString = function(self, key, ctype)
			if key == 'intro' then
				return '"'..formationIntroNames[self[key]+1]..'"'
			end
			if key == 'music' then
				return '"'..formationMusicNames[self[key]+1]..'"'
			end
			return oldFieldToString(self, key, ctype)
		end
	end,
}

local numFormationSizeOffsets = 13

-- this is an arbitrary number, just like null-term string Base field sizes,
-- because it is referenced by offsets
local numFormationSizes = 48

local formationSize_t = struct{
	name = 'formationSize_t',
	fields = {
		{unknown_0 = 'uint8_t'},
		{unknown_1 = 'uint8_t'},
		{width = 'uint8_t'},
		{height = 'uint8_t'},
	},
}
assert(ffi.sizeof'formationSize_t' == 4)

---------------- ITEMS ----------------

local numItems = 0x100
local numItemTypes = 0x20

local itemNamesAddr = 0x12b300

local itemref_t = reftype{
	name = 'itemref_t',
	getter = function(i) 
		if i == 0xff then return nil end
		return game.itemNames[i] 
	end,
	getterSkipNone = true,
}

local itemUseAbilityNames = {
	'nothing',	-- 00
	'magicite',
	'superball',
	'smoke bomb',
	'elixer, megalixer',
	'warp stone',
	'dried meat',
}

local equipFlags_t, code = bitflagtype{
	name = 'equipFlags_t',
	type = 'uint16_t',
	options = {
		'terra',
		'locke',
		'cyan',
		'shadow',
		'edgar',
		'sabin',
		'celes',
		'strago',
		'relm',
		'setzer',
		'mog',
		'gau',
		'gogo',
		'umaro',
		'impItem',
		'meritAward',
	},
}
assert(ffi.sizeof'equipFlags_t' == 2)

local itemSpecialAbilityNames = {
	'nothing',	-- 00
	'randomally steals',
	'transforms at level up, grows as HP increases',
	'randomally dispatches an enemy',
	'double damage to humans',
	'absorbs damage as HP',
	'absorbs damage as MP',
	'uses MP for mortal blow',
	'whatever a hawk eye does ???',
	'dice - what dice do',
	'gains power as HP decreases',
	'randomally casts "wind slash"',
	'heals person',
	'randomally dices up an enemy',
	'uses MP for mortal blow, may break',
	'uses MP for mortal blow',
}

local item_t = struct{
	name = 'item_t',
	fields = {
		-- 0x00:
		{itemType = 'uint8_t:4'},		-- not the same as 'itemTypeNames'
		{canBeThrown = 'uint8_t:1'},
		{canUseInBattle = 'uint8_t:1'},
		{canUseInMenu = 'uint8_t:1'},
		{unused_0_7 = 'uint8_t:1'},		-- only here for the ptr union size calc in struct.lua
		-- 0x01:
		{equip = 'equipFlags_t'},
		-- 0x03:
		{spellLearn = 'spellLearn_t'},
		-- 0x05:
		{isCharmBangle = 'uint8_t:1'},
		{isMoogleCharm = 'uint8_t:1'},
		{unused_5_2 = 'uint8_t:1'},
		{unused_5_3 = 'uint8_t:1'},
		{unused_5_4 = 'uint8_t:1'},
		{isSprintShoes = 'uint8_t:1'},
		{unused_5_6 = 'uint8_t:1'},
		{isTintinabar = 'uint8_t:1'},
		-- 0x06:
		{immuneToEffect1 = 'effect1_t'},
		-- 0x07:
		{immuneToEffect2 = 'effect2_t'},	
		-- 0x08:
		{hasEffect3 = 'effect3_t'},
		-- 0x09:
		{raiseFightDamage = 'uint8_t:1'},
		{raiseMagicDamage = 'uint8_t:1'},
		{raiseHPByQuarter = 'uint8_t:1'},
		{raiseHPByHalf = 'uint8_t:1'},
		{raiseHPByEighth = 'uint8_t:1'},
		{raiseMagDef = 'uint8_t:1'},
		{raiseMPByHalf = 'uint8_t:1'},
		{raiseMPByEighth = 'uint8_t:1'},
		-- 0x0a:
		{raisePreEmptiveAttackRate = 'uint8_t:1'},
		{preventBackAttack = 'uint8_t:1'},
		{changeFightToJump = 'uint8_t:1'},
		{changeMagicToXMagic = 'uint8_t:1'},
		{changeSketchToControl = 'uint8_t:1'},
		{changeSlotToGPRain = 'uint8_t:1'},
		{changeStealToCapture = 'uint8_t:1'},
		{changeJumpToXJump = 'uint8_t:1'},
		-- 0x0b:
		{raiseStealChance = 'uint8_t:1'},
		{unused_b_1 = 'uint8_t:1'},
		{raiseSketchChance = 'uint8_t:1'},
		{raiseControlChance = 'uint8_t:1'},
		{fightAlwaysHits = 'uint8_t:1'},
		{halfMPConsumed = 'uint8_t:1'},
		{magicCosts1 = 'uint8_t:1'},
		{raiseVigorByHalf = 'uint8_t:1'},
		-- 0x0c:
		{changeFightToXFight = 'uint8_t:1'},
		{randomlyCounterattacks = 'uint8_t:1'},
		{randomlyEvadeAttacks = 'uint8_t:1'},
		{holdOneWeaponWithTwoHands = 'uint8_t:1'},
		{holdTwoWeapons = 'uint8_t:1'},
		{equipMeritAwardItems = 'uint8_t:1'},
		{protectPartyMembersLowOnHP = 'uint8_t:1'},
		{unused_c_7 = 'uint8_t:1'},
		-- 0x0d:
		{castShellWhenHPIsLow = 'uint8_t:1'},
		{castSafeWhenHPIsLow = 'uint8_t:1'},
		{unused_d_2 = 'uint8_t:1'},
		{doubleExpGained = 'uint8_t:1'},
		{pickUpMoreGP = 'uint8_t:1'},
		{unused_d_5 = 'uint8_t:1'},
		{unused_d_6 = 'uint8_t:1'},
		{makeUndead = 'uint8_t:1'},
		-- 0x0e:
		{targetting = 'targetting_t'},
		-- 0x0f:
		-- TODO UNION
		{element_weaponDamage_equipHalfDamage = 'uint8_t'},
		-- 0x10:
		{vigor = 'uint8_t:4'},
		{speed = 'uint8_t:4'},
		-- 0x11:
		{stamina = 'uint8_t:4'},
		{magicPower = 'uint8_t:4'},
		-- 0x12:
		{spellCast = 'uint8_t:6'},	-- should be spellref_t, but it looks like you can't use structs with bitfields
		{castOnAttack = 'uint8_t:1'},
		{castOnItemUse = 'uint8_t:1'},	-- "destroy if used"
		-- 0x13:
		{protectFromMortalBlows = 'uint8_t:1'},	-- memento ring
		{runicCompatible = 'uint8_t:1'},
		{unknown_13_2 = 'uint8_t:1'},
		{unknown_13_3 = 'uint8_t:1'},
		{unknown_13_4 = 'uint8_t:1'},
		{sameDamageFromBackRow = 'uint8_t:1'},
		{canEquipTwoHands = 'uint8_t:1'},
		{swdTechCompatible = 'uint8_t:1'},
		-- 0x14:
		-- TODO UNION
		{battlePower_defense = 'uint8_t'},	
		-- 0x15:
		{hitChance_magicDefense = 'uint8_t'},
		-- 0x16:
		{elementAbsorb = 'element_t'},
		-- 0x17:
		{elementNoEffect = 'element_t'},
		-- 0x18:
		{elementWeak = 'element_t'},
		-- 0x19:
		{givesEffect2 = 'effect2_t'},	
		-- 0x1a:
		{evade = 'uint8_t:4'},
		{magicBlock = 'uint8_t:4'},	-- 0..5 => 0..5, 6..10 => -1..-5
		-- 0x1b:
		-- item type: item ability
		-- non-item type: evade:4, special ability:4
		{itemUseAbility = 'uint8_t:4'},
		{itemSpecialAbility = 'uint8_t:4'},
		-- 0x1c:
		-- sell price is half of buy price
		{buyPrice = 'uint16_t'},
	},
	metatable = function(mt)
		local oldFieldToString = mt.fieldToString
		mt.fieldToString = function(self, name, ctype)
			if name == 'spellCast' then
				local i = self[name]
				if i == 0xff then return nil end
				return '"'..getSpellName(i)..'"'
			elseif name == 'itemUseAbility' then
				local s = itemUseAbilityNames[self[name]+1]  
				return s and '"'..s..'"' or tostring(self[name])
			elseif name == 'itemSpecialAbility' then
				local s = itemSpecialAbilityNames[self[name]+1]
				return s and '"'..s..'"' or tostring(self[name])
			end
			return oldFieldToString(self, name, ctype)
		end
	end,
}
assert(ffi.offsetof('item_t', 'itemType') == 0)
assert(ffi.offsetof('item_t', 'spellLearn') == 3)
assert(ffi.offsetof('item_t', 'raiseStealChance') == 0x0b)
assert(ffi.offsetof('item_t', 'changeFightToXFight') == 0x0c)
assert(ffi.sizeof'item_t' == 0x1e)

local itemColosseumInfo_t = struct{
	name = 'itemColosseumInfo_t',
	fields = {
		{monster = 'monsterRef_t'},
		{unknown = 'uint8_t'},
		{itemWon = 'itemref_t'},
		{hideName = 'uint8_t'},
	},
}
assert(ffi.sizeof'itemColosseumInfo_t' == 4)

local itemsAddr = 0x185000

local itemColosseumInfosAddr = 0x1fb600
local itemDescOffsetsAddr = 0x2d7aa0
local itemDescBaseAddr = 0x2d6400

ffi.cdef[[typedef str13_t rareItemName_t;]]
local numRareItems = 20
local rareItemDescOffsetAddr = 0x0efb60
local rareItemNamesAddr = 0x0efba0
local rareItemDescBaseAddr = 0x0efcb0

---------------- MONSTERS ----------------

-- monster_t 0x1f
local monsterSpecialAttackNames = {
	'None',
	'Steal Item',
	'Attack increases as HP increases',
	'Kill (with X)',
	'Cause 2x damage to humans',
	'Drain HP',
	'Drain MP',
	'Attack with MP',
	'',
	'Dice',
	'Attack increases as HP decreases',
	'Wind attack',
	'Recover HP',
	'Kill',
	'Uses MP to inflict mortal blow',
	'Uses (more) MP to inflict mortal blow',
}

local monsterAttackNamesAddr = 0x0fd0d0

local monster_t = struct{
	name = 'monster_t',
	fields = {
		-- 0x00:
		{speed = 'uint8_t'},		-- rpglegion says speed
		-- 0x01:
		{battlePower = 'uint8_t'},	-- rpglegion says battle power
		-- 0x02:
		{hitChance = 'uint8_t'},
		-- 0x03:
		{evade = 'uint8_t'},
		-- 0x04:
		{magicBlock = 'uint8_t'},
		-- 0x05:
		{defense = 'uint8_t'},
		-- 0x06:
		{magicDefense = 'uint8_t'},
		-- 0x07:
		{magicPower = 'uint8_t'},
		-- 0x08:
		{hp = 'uint16_t'},
		-- 0x0a:
		{mp = 'uint16_t'},
		-- 0x0c:
		{exp = 'uint16_t'},
		-- 0x0e:
		{gold = 'uint16_t'},
		-- 0x10:
		{level = 'uint8_t'},
		-- 0x11:
		{metamorphSet = 'uint8_t:5'},		-- TODO metamorphSetRef_t ?
		{metamorphResist = 'uint8_t:3'},
		-- 0x12:
		{diesIfRunOutOfMP = 'uint8_t:1'},
		{unknown_12_1 = 'uint8_t:1'},
		{hideName = 'uint8_t:1'},
		{unknown_12_3 = 'uint8_t:1'},
		{unknown_12_4 = 'uint8_t:1'},
		{unknown_12_5 = 'uint8_t:1'},
		{unknown_12_6 = 'uint8_t:1'},
		{undead = 'uint8_t:1'},
		-- 0x13:
		{unknown_13_0 = 'uint8_t:1'},
		{unknown_13_1 = 'uint8_t:1'},
		{cantSuplex = 'uint8_t:1'},	-- rpglegion says can't run
		{cantRun = 'uint8_t:1'},	-- rpglegion says can't scan
		{unknown_13_4 = 'uint8_t:1'},
		{unknown_13_5 = 'uint8_t:1'},
		{unknown_13_6 = 'uint8_t:1'},
		{cantControl = 'uint8_t:1'},
		-- 0x14:
		{immuneToEffect1 = 'effect1_t'},
		-- 0x15:
		{unknown_15 = 'uint8_t'},
		-- 0x16:
		{elementHalfDamage = 'element_t'},	
		-- 0x17:
		{elementAbsorb = 'element_t'},	
		-- 0x18:
		{elementNoEffect = 'element_t'},	
		-- 0x19:
		{elementWeak = 'element_t'},	
		-- 0x1a:
		{fightAnimation = 'uint8_t'},
		-- 0x1b:
		{hasEffect1 = 'effect1_t'},
		-- 0x1c:
		{hasEffect2 = 'effect2_t'},
		-- 0x1d:
		{hasEffect3 = 'effect3_t'},
		-- 0x1e:
		{hasEffect4 = 'effect4_t'},
		-- 0x1f:
		{specialAttack = 'uint8_t:7'},
		{specialAttackDealsNoDamage = 'uint8_t:1'},
	},
	metatable = function(mt)
		local oldFieldToString = mt.fieldToString
		mt.fieldToString = function(self, name, ctype)
			if name == 'specialAttack' then
				local s = monsterSpecialAttackNames[self[name]+1]
				return s and '"'..s..'"' or tostring(self[name])
			end
			return oldFieldToString(self, name, ctype)
		end
	end,
}
assert(ffi.sizeof'monster_t' == 0x20)
local monstersAddr = 0x0f0000

local monsterItem_t = struct{
	name = 'monsterItem_t',
	fields = {
		{rareSteal = 'itemref_t'},
		{commonSteal = 'itemref_t'},
		{rareDrop = 'itemref_t'},
		{commonDrop = 'itemref_t'},
	},
}
local monsterItemsAddr = 0x0f3000

local monsterSketchesAddr = 0x0f4300

local spellref2_t = createVec{
	dim = 2,
	ctype = 'spellref_t',
	vectype = 'spellref2_t',
}
assert(ffi.sizeof'spellref2_t' == 2)
local monsterRagesAddr = 0x0f4600
local numRages = 0x100

local spellref4_t = createVec{
	dim = 4,
	ctype = 'spellref_t',
	vectype = 'spellref4_t',
}
assert(ffi.sizeof'spellref4_t' == 4)
local monsterSpellsAddr = 0x0f3d00

local itemref4_t = createVec{
	dim = 4,
	ctype = 'itemref_t',
	vectype = 'itemref4_t',
}
assert(ffi.sizeof'itemref4_t' == 4)

local metamorphSetsAddr = 0x047f40
local numMetamorphSets = 0x1a

---------------- CHARACTERS ----------------

local numExpLevelUps = 106
local numLevels = 98

ffi.cdef[[typedef str7_t menuName_t;]]
local numMenuNames = 32
local menuNamesAddr = 0x018cea0

local menuref_t = reftype{
	name = 'menuref_t',
	getter = function(i) return game.menuNames[i] end,
}

ffi.cdef[[typedef str6_t characterName_t;]]
local characterNamesAddr = 0x0478c0

local menuref4_t = createVec{
	dim = 4,
	ctype = 'menuref_t',
	vectype = 'menuref4_t',
}

local itemref2_t = createVec{
	dim = 2,
	ctype = 'itemref_t',
	vectype = 'itemref2_t',
}

local character_t = struct{
	name = 'character_t',
	fields = {
		{hp = 'uint8_t'},
		{mp = 'uint8_t'},
		{menu = 'menuref4_t'},
		{vigor = 'uint8_t'},
		{speed = 'uint8_t'},
		{stamina = 'uint8_t'},
		{magicPower = 'uint8_t'},
		{battlePower = 'uint8_t'},	-- note: equipping nothing gives +10 to battle power
		{defense = 'uint8_t'},
		{magicDefense = 'uint8_t'},
		{evade = 'uint8_t'},
		{magicBlock = 'uint8_t'},
		-- or should these all be an itemref6_t?
		{lhand = 'itemref_t'},
		{rhand = 'itemref_t'},
		{head = 'itemref_t'},
		{body = 'itemref_t'},
		{relic = 'itemref2_t'},
		{level = 'uint8_t'},
	},
}
assert(ffi.sizeof'character_t' == 22)

local numCharacters = 0x40	-- allegedly...
local charactersAddr = 0x2d7ca0

ffi.cdef[[typedef str12_t mogDanceName_t;]]
local numMogDances = 8
local mogDanceNamesAddr = 0x26ff9d

ffi.cdef[[typedef str12_t swordTechName_t;]]
local numSwordTechs = 8
local swordTechNamesAddr = 0x0f3c40
local swordTechDescBaseAddr = 0x0ffd00
local swordTechDescOffsetsAddr = 0x0fffae

local numBlitzes = 8
local blitzDescBaseAddr = 0x0ffc00
local blitzDescOffsetsAddr = 0x0fff9e

local numLores = 24
local loreDescBaseAddr = 0x2d77a0
local loreDescOffsetsAddr = 0x2d7a70

---------------- MAP ----------------

local shopTypes = {
	'(none)',
	'weapon',
	'armor',
	'item',
	'relic',
	'vendor',
}

local shopPriceTypes = {
	'(none)',
	'2x',
	'1.5x',
	'0.5x with Sabin or Edgar',
}

local shopinfo_t = struct{
	name = 'shopinfo_t',
	fields = {
		{shopType = 'uint8_t:4'},
		{priceType = 'uint8_t:4'},
	},
	metatable = function(mt)
		local oldFieldToString = mt.fieldToString
		mt.fieldToString = function(self, name, ctype)
			if name == 'shopType' then
				local v = self[name]
				if v == 0 then return nil end
				local s = shopTypes[v+1]  
				return s and '"'..s..'"' or tostring(self[name])
			elseif name == 'priceType' then
				local v = self[name]
				if v == 0 then return nil end
				local s = shopPriceTypes[v+1]  
				return s and '"'..s..'"' or tostring(self[name])
			end
			return oldFieldToString(self, name, ctype)
		end
	end,
}

local itemref8_t = createVec{
	dim = 8,
	ctype = 'itemref_t',
	vectype = 'itemref8_t',
}
local numShops = 0x80
local shop_t = struct{
	name = 'shop_t',
	fields = {
		{shopinfo = 'shopinfo_t'},
		{items = 'itemref8_t'},
	}
}
assert(ffi.sizeof'shop_t' == 9)

local shopsAddr = 0x047ac0

local numLocationNames = 448	-- 146 entries are used, the rest are 0xffff

local numDialogs = 3328
local numBattleDialogs = 0x100
local numBattleDialog2s = 0x100
local numBattleMessages = 0x100

local numPositionedText = 5	-- might actually be lower

---------------- GRAPHICS ----------------

local color_t = struct{
	name = 'color_t',
	fields = {
		{r = 'uint16_t:5'},
		{g = 'uint16_t:5'},
		{b = 'uint16_t:5'},
		{a = 'uint16_t:1'},
	},
}
assert(ffi.sizeof'color_t' == 2)

local palette4_t = createVec{
	dim = 4,
	ctype = 'color_t',
	vectype = 'palette4_t',
}
assert(ffi.sizeof'palette4_t' == 2*4)

local palette16_t = createVec{
	dim = 16,
	ctype = 'color_t',
	vectype = 'palette16_t',
}
assert(ffi.sizeof'palette16_t' == 2*16)

local palette16_8_t = createVec{
	dim = 8,
	ctype = 'palette16_t',
	vectype = 'palette16_8_t',
}
assert(ffi.sizeof'palette16_8_t' == 2*16*8)

---------------- GAME ----------------

local game_t = struct{
	name = 'game_t',
	fields = {
		-- 0x00c27f - 0x00c28f = something to do with battle background? -rpglegion
		-- 0x00ce3a - ? = offset of map character sprite parts (2x2, 2 bytes each)
		-- 0x00d0f2 - ? = pointer to map character graphics (2 bytes each)
		-- 0x00d23c - ? = bank pointer & # bytes to copy for map char gfx (2 bytes each)
		-- 0x00dfa0 - 0x00e0a0 = 'DTE table' -rgplegion
		-- 0x02ce2b - ? = battle character palette assignment (1 byte each)
		{padding_000000 = 'uint8_t['..(0x02d01a - 0x000000)..']'},			-- 0x000000 - 0x02d01a
		
		{formationSizeOffsets = 'uint16_t['..numFormationSizeOffsets..']'},	-- 0x02d01a - 0x02d034
		{formationSizes = 'formationSize_t['..numFormationSizes..']'},		-- 0x02d034 - 0x02d0f4

		-- 0x036f00 - ? = menu portrait palette assignment (1 byte each)
		-- 0x036f1b - ? = pointer to menu portrait graphics (2 bytes each)
		{padding_02d0f4 = 'uint8_t['..(0x03c00e - 0x02d0f4)..']'},			-- 0x02d0f4 - 0x03c00e

		{positionedTextOffsets = 'uint16_t['..numPositionedText..']'},		-- 0x03c00e - 0x03c018
		
		{padding = 'uint8_t['..(0x03c2fc - 0x03c018)..']'},					-- 0x03c018 - 0x03c2fc
		
		{positionedTextBase = 'uint8_t['..(0x03c406 - 0x03c2fc)..']'},		-- 0x03c2fc - 0x03c406
		
		-- 0x03c326 - 0x03c406 = more positioned text (N items, var length) ... where are the offsets for this?
		-- "P}BUY  SELL  EXITA:}GPAr GPAz}Owned:Az Equipped:AP Bat PwrAP DefenseAl â¦Af{Hi! Can I help you?Af{Help yourself!Af{How many?Af{Whatcha got?Af{How many?Af{Bye!          Af{You need more GP!Af{Too many!       Af{One's plenty! A"

		-- 0x040000 - 0x040342 = map event trigger pointers (+0x040000)
		-- 0x040342 - 0x0419fe = map event triggers (5 bytes each)
		-- 0x0419fe - 0x041a10 = unused
		-- 0x041a10 - 0x041d52 = npc data pointers (+0x041a10)
		-- 0x041d52 - 0x046a6c = npc data
		-- 0x046a6c - 0x046ac0 = unused
		{padding_03c406 = 'uint8_t['..(0x046ac0 - 0x03c406)..']'},			-- 0x03c406 - 0x046ac0
		
		{spells = 'spell_t['..numSpells..']'},								-- 0x046ac0 - 0x0478c0
		{characterNames = 'characterName_t['..numCharacters..']'},			-- 0x0478c0 - 0x047a40
		{blitzData = 'raw12_t['..numBlitzes..']'},							-- 0x047a40 - 0x047aa0
		
		{padding_047aa0 = select(2, makefixedraw(0x047ac0 - 0x047aa0))},	-- 0x047aa0 - 0x047ac0 
		
		{shops = 'shop_t['..numShops..']'},									-- 0x047ac0 - 0x047f40
		{metamorphSets = 'itemref4_t['..numMetamorphSets..']'},			-- 0x047f40 - 0x047fa8
	
		-- 0x0487c0 - 0x048fc0 = font graphics (8x8x2, 8 bytes each, 0x80-0xff)
		-- 0x048fc0 - 0x049040 = font character cell widths (0x00 - 0x7f)
		
		-- 0x0490c0 - 0x049900 = font graphics data (16x11x1, 22 bytes each, 0x20-0x7f)
		
		-- 0x05070e - 0x050710 = length of main SPC code loop
		-- 0x050710 - 0x051ec7 = main SPC code loop

		-- 0x0a0000 - 0x0ce600 = event code
		{padding_047fa8 = 'uint8_t['..(0x0ce600 - 0x047fa8)..']'},			-- 0x047fa8 - 0x0ce600

		-- the first dialog offset points to the dialog which needs the bank byte to increment
		{dialogOffsets = 'uint16_t['..numDialogs..']'},						-- 0x0ce600 - 0x0d0000
		{dialogBase = 'uint8_t['..(0x0ef100 - 0x0d0000)..']'},				-- 0x0d0000 - 0x0ef100
		{locationNameBase = 'uint8_t['..(0x0ef600 - 0x0ef100)..']'},		-- 0x0ef100 - 0x0ef600
	
		-- 0x0ef600 - 0x0ef648 looks like offsets into something
		-- 0x0ef648 - 0x0ef678 looks like arbitrary values
		-- 0x0ef678 - 0x0efb60 is mostly '06' repeated
		{padding_0ef600 = 'uint8_t['..(0x0efb60 - 0x0ef600)..']'},			-- 0x0ef600 - 0x0efb60

		{rareItemDescOffsets = 'uint16_t['..numRareItems..']'},				-- 0x0efb60 - 0x0efb88
		
		-- all 'ff' repeated ... enough for 12 extra offsets ... there are 20 rare items ... 20+12=32
		{unused_0efb88  = select(2, makefixedraw(0x18))},					-- 0x0efb88 - 0x0efba0
	
		-- rare item names are 13 chars
		{rareItemNames = 'rareItemName_t['..numRareItems..']'},				-- 0x0efba0 - 0x0efca4
	
		-- all 'ff' repeated, for 12 bytes, not quite 1 more name 
		{padding5 = select(2, makefixedraw(0x0efcb0 - 0x0efca4))},			-- 0x0efca4 - 0x0efcb0 
		
		{rareItemDescBase = 'uint8_t['..(0x0f0000 - 0x0efcb0)..']'},		-- 0x0efcb0 - 0x0f0000
		{monsters = 'monster_t['..numMonsters..']'},						-- 0x0f0000 - 0x0f3000
		{monsterItems = 'monsterItem_t['..numMonsters..']'},				-- 0x0f3000 - 0x0f3600
		
		-- 0x0f3600 - 0x0f37c0 is mostly zeroes
		-- 0x0f37c0 - 0x0f3940 is something 
		{padding6 = 'uint8_t['..(0x0f3940 - 0x0f3600)..']'},				-- 0x0f3600 - 0x0f3940
		
		{esperDescBase = 'uint8_t['..(0x0f3c40 - 0x0f3940)..']'},			-- 0x0f3940 - 0x0f3c40
		{swordTechNames = 'swordTechName_t['..numSwordTechs..']'},			-- 0x0f3c40 - 0x0f3ca0

		-- all ff
		{padding7 = 'uint8_t['..(0x0f3d00 - 0x0f3ca0)..']'},				-- 0x0f3ca0 - 0x0f3d00
		
		{monsterSpells = 'spellref4_t['..numMonsters..']'},				-- 0x0f3d00 - 0x0f4300
		{monsterSketches = 'spellref2_t['..numMonsters..']'},			-- 0x0f4300 - 0x0f4600
		{monsterRages = 'spellref2_t['..numRages..']'},					-- 0x0f4600 - 0x0f4800 
		
		{padding_0f4800 = 'uint8_t['..(0x0f5900 - 0x0f4800)..']'},			-- 0x0f4800 - 0x0f5900
		
		{formation2s = 'formation2_t['..numFormations..']'},				-- 0x0f5900 - 0x0f6200
		{formations = 'formation_t['..numFormations..']'},					-- 0x0f6200 - 0x0f83c0
		
		{padding_0f83c0 = 'uint8_t['..(0x0fc050 - 0x0f83c0)..']'},			-- 0x0f83c0 - 0x0fc050

		{monsterNames = 'monsterName_t['..numMonsters..']'},				-- 0x0fc050 - 0x0fcf50
		
		{padding8 = 'uint8_t[384]'},										-- 0x0fcf50 - 0x0fd0d0 
		
		{monsterAttackNames = 'monsterName_t['..numMonsters..']'},			-- 0x0fd0d0 - 0x0fdfd0
		
		{padding_0fdfd0 = 'uint8_t['..(0x0fdfe0 - 0x0fdfd0)..']'},			-- 0x0fdfd0 - 0x0fdfe0

		{battleDialogOffsets = 'uint16_t['..numBattleDialogs..']'},			-- 0x0fdfe0 - 0x0fe1e0
		{battleDialogBase = 'uint8_t['..(0x0ff450 - 0x0fe1e0)..']'},		-- 0x0fe1e0 - 0x0ff450
		
		{padding_0ff450  = 'uint8_t['..(0x0ffc00 - 0x0ff450)..']'},			-- 0x0ff450 - 0x0ffc00

		{blitzDescBase = 'uint8_t['..(0x0ffd00 - 0x0ffc00)..']'},			-- 0x0ffc00 - 0x0ffd00
		{swordTechDescBase = 'uint8_t['..(0x0ffe00 - 0x0ffd00)..']'},		-- 0x0ffd00 - 0xfffe00
		
		{paddinga = 'uint8_t['..(0x0ffe40 - 0x0ffe00)..']'},				-- 0x0ffe00 - 0x0ffe40 
		
		{esperDescOffsets = 'uint16_t['..numEspers..']'},					-- 0x0ffe40 - 0x0ffe76
		
		{padding12 = 'uint8_t['..(0x0ffeae - 0x0ffe76)..']'},				-- 0x0ffe76 - 0x0ffeae
		
		{esperBonusDescs = 'esperBonusDesc_t['..numEsperBonuses..']'},		-- 0x0ffeae - 0x0fff47
		
		{paddingb = 'uint8_t[87]'},											-- 0x0fff47 - 0x0fff9e
		
		{blitzDescOffsets = 'uint16_t['..numBlitzes..']'},					-- 0x0fff9e - 0x0fffae 
		{swordTechDescOffsets = 'uint16_t['..numSwordTechs..']'},			-- 0x0fffae - 0x0fffbe 
		
		{padding_0fffbe = 'uint8_t['..(0x10d000 - 0x0fffbe)..']'},			-- 0x0fffbe - 0x10d000

		{battleDialog2Offsets = 'uint16_t['..numBattleDialog2s..']'},		-- 0x10d000 - 0x10d200
		{battleDialog2Base = 'uint8_t['..(0x10fd00 - 0x10d200)..']'},		-- 0x10d200 - 0x10fd00
		
		{padding_10fd00 = 'uint8_t['..(0x11f000 - 0x10fd00)..']'},			-- 0x10fd00 - 0x11f000 

		{battleMessageBase = 'uint8_t['..(0x11f7a0 - 0x11f000)..']'},		-- 0x11f000 - 0x11f7a0
		{battleMessageOffsets = 'uint16_t['..numBattleMessages..']'},		-- 0x11f7a0 - 0x11f9a0
		
		{padding_11f9a0 = 'uint8_t['..(0x126f00 - 0x11f9a0)..']'},			-- 0x11f9a0 - 0x126f00

		{itemTypeNames = 'str7_t['..numItemTypes..']'},						-- 0x126f00 - 0x126fe0
	
		-- 0x127000 - 0x12a780 = monster visual specifications (384 elements, 5 bytes each)
		-- 0x12a820 - 0x12a822 = pointer to 8-high monster composition data
		-- 0x12a822 - 0x12a824 = pointer to 16-high monster composition data
		-- 0x12a824 - 0x12ac24 = monster 8-high composition data (128 elemets, 8 bytes each)
		-- 0x12ac24 - 0x12b224 = monster 16-high composition data (48 elements, 32 bytes each)
		-- 0x12b224 - 0x12b300 = unused
		{padding_126fe0 = 'uint8_t['..(0x12b300 - 0x126fe0)..']'},			-- 0x126fe0 - 0x12b300

		{itemNames = 'str13_t['..numItems..']'},							-- 0x12b300 - 0x12c000

		{padding_12c000 = 'uint8_t['..(0x12ec00 - 0x12c000)..']'},			-- 0x12c000 - 0x12ec00

		{WoBpalettes = 'palette16_8_t'},									-- 0x12ec00 - 0x12ed00
		{WoRpalettes = 'palette16_8_t'},									-- 0x12ed00 - 0x12ee00
		{setzerAirshipPalette = 'palette16_t'},								-- 0x12ee00 - 0x12ee20 
		
		{padding_12ee20 = 'uint8_t['..(0x12ef00 - 0x12ee20)..']'},			-- 0x12ee20 - 0x12ef00
		
		{darylAirshipPalette = 'palette16_t'},								-- 0x12ef00 - 0x12ef20
		
		-- 0x150000 - ? = character images, 0x16a0 bytes each
		{padding_12ef20 = 'uint8_t['..(0x185000 - 0x12ef20)..']'},			-- 0x12ef20 - 0x185000

		{items = 'item_t['..numItems..']'},									-- 0x185000 - 0x186e00
		{espers = 'esper_t['..numEspers..']'},								-- 0x186e00 - 0x186f29
		
		{paddinge = 'uint8_t['..(0x18c9a0 - 0x186f29)..']'},				-- 0x186f29 - 0x18c9a0
		
		{spellDescBase = 'uint8_t['..(0x18cea0 - 0x18c9a0)..']'},			-- 0x18c9a0 - 0x18cea0
		{menuNames = 'menuName_t['..numMenuNames..']'},						-- 0x18cea0 - 0x18cf80
		{spellDescOffsets = 'uint16_t[54]'},								-- 0x18cf80 - 0x18cfec
	
		-- 0x19a800 - 0x19cd10 = location tile properties
		-- 0x19cd10 - 0x19cd90 = pointers to location tile properties (+0x19a800)
		-- 0x19cd90 - 0x19d1b0 = pointers to location map data (352 items), (+0x19d1b0)
		-- 0x19d1b0 - 0x1e0000 = location map data
		-- 0x1e0000 - ? = location tile formation
		{paddingf = 'uint8_t['..(0x1fb400  - 0x18cfec)..']'},				-- 0x18cfec - 0x1fb400
	
		{formationMPs = 'uint8_t['..numFormationMPs..']'},					-- 0x1fb400 - 0x1fb600
		{itemColosseumInfos = 'itemColosseumInfo_t['..numItems..']'},		-- 0x1fb600 - 0x1fba00
	
		-- 0x1fba00 - 0x1fbb00 = pointer to location tile formation (128 items) (+0x1e0000)
		-- 0x1fbb00 - 0x1fbf02 = pointer to entrance triggers (+0x1fbb00)
		-- 0x1fbf02 - 0x1fda00 = entrance triggers (6 bytes each)
		-- 0x1fda00 - 0x1fdb00 = town tile graphics pointers (128 items) (+0x1fdb00)
		-- 0x1fdb00 - 0x25f400 = town tile graphics
		-- (within it) 0x21c4c0 - 0x21e4c0 = battle background top graphics: building
		-- 0x25f400 - 0x268000 = ???
		-- 0x268000 - 0x268400 = map character & town person sprites (16 colors each)
		{padding_1fba00 = 'uint8_t['..(0x268400 - 0x1fba00)..']'},			-- 0x1fba00 - 0x268400
		
		{locationNameOffsets = 'uint16_t['..numLocationNames..']'},			-- 0x268400 - 0x268780

		{padding_268780 = 'uint8_t['..(0x26f4a0 - 0x268780)..']'},			-- 0x268780 - 0x26f4a0 

		{hpIncPerLevelUp = 'uint8_t['..numLevels..']'},						-- 0x26f4a0 - 0x26f502
		{mpIncPerLevelUp = 'uint8_t['..numLevels..']'},						-- 0x26f502 - 0x26f564

		{padding_26f564 = 'uint8_t['..(0x26f567 - 0x26f564)..']'},			-- 0x26f564 - 0x26f567
		
		{spellNames_0to53 = 'str7_t[54]'}, 									-- 0x26f567 - 0x26f6e1
		{spellNames_54to80 = 'str8_t[27]'},                             	-- 0x26f6e1 - 0x26f7b9
		{spellNames_81to255 = 'str10_t[175]'},								-- 0x26f7b9 - 0x26fe8f
		{esperAttackNames = 'str10_t['..numEspers..']'},					-- 0x26fe8f - 0x26ff9d
		{mogDanceNames = 'str12_t['..numMogDances..']'},					-- 0x26ff9d - 0x26fffd

		{padding_26fffd = 'uint8_t['..(0x271650 - 0x26fffd)..']'},			-- 0x26fffd - 0x271650
		
		-- 0x270150 - = bottom battle background palettes (16 colors each)
		
		{topBackgroundPaletteOffset = 'uint16_t[252]'},						-- 0x271650 - 0x271848	-- pointers to top background palettes (168 elements, 75 used)
	
		{padding_271848 = 'uint8_t['..(0x297000 - 0x271848)..']'},			-- 0x271848	- 0x297000

		{monsterGraphics = 'uint8_t['..(0x2d0000 - 0x297000)..']'},			-- 0x297000 - 0x2d0000 ? = monster graphics
		
		{menuImages = 'uint8_t['..(0x2d0e00 - 0x2d0000)..']'},				-- 0x2d0000 - 0x2d0e00 = menu images 0x200 = bg pattern, 0x180 = borders, so 0x380 total ... x8 per menu scheme

		{padding_2d0e00 = 'uint8_t['..(0x2d1c00 - 0x2d0e00)..']'},			-- 0x2d0e00 - 0x2d1c00

		{menuWindowPalettes = 'palette16_8_t'},							-- 0x2d1c00 - 0x2d1d00 = menu window palettes, x8, 16 colors each, 2 bytes per color
		{characterMenuImages = 'uint8_t['..(0x2d5860 - 0x2d1d00)..']'},		-- 0x2d1d00 - 0x2d5860 = character menu images = 0x320 per character
		{menuPortraitPalette = 'palette16_t[19]'},							-- 0x2d5860 - 0x2d5ac0 = menu portrait palettes (16 colors each)
		{handCursorGraphics = 'uint8_t['..(0x2d62c0 - 0x2d5ac0)..']'},		-- 0x2d5ac0 - 0x2d62c0 ? = hand cursor graphics
		{battleWhitePalette = 'palette4_t'},								-- 0x2d62c0 - 0x2d62c8 = battle standard (white) text palette, 4 colors
		{battleGrayPalette = 'palette4_t'},									-- 0x2d62c8 - 0x2d62d0 = battle disabled (grey) text palette, 4 colors
		{battleYellowPalette = 'palette4_t'},								-- 0x2d62d0 - 0x2d62d8 = battle active (yellow) text palette, 4 colors
		{battleBluePalette = 'palette4_t'},									-- 0x2d62d8 - 0x2d62e0 = battle blue text palette, 4 colors
		{battleEmptyPalette = 'palette4_t'},								-- 0x2d62e0 - 0x2d62e8 = empty color palette, 4 colors
		{battleGrayPalette = 'palette4_t'},									-- 0x2d62e8 - 0x2d62f0 = battle gauge (grey) text palette, 4 colors
		{battleGreenPalette = 'palette4_t'},								-- 0x2d62f0 - 0x2d62f8 = battle green text palette, 4 colors
		{battleRedPalette = 'palette4_t'},									-- 0x2d62f8 - 0x2d6300 = battle red text palette, 4 colors
		{battleMenuPalettes = 'palette16_8_t'},							-- 0x2d6300 - 0x2d6400 = battle/menu character sprite palettes, 8 palettes, 16 colors each
		{itemDescBase = 'uint8_t['..(0x2d77a0 - 0x2d6400)..']'},			-- 0x2d6400 - 0x2d77a0
		{loreDescBase = 'uint8_t['..(0x2d7a70 - 0x2d77a0)..']'},			-- 0x2d77a0 - 0x2d7a70
		{loreDescOffsets = 'uint16_t['..numLores..']'},						-- 0x2d7a70 - 0x2d7aa0
		{itemDescOffsets = 'uint16_t['..numItems..']'},						-- 0x2d7aa0 - 0x2d7ca0
		{characters = 'character_t['..numCharacters..']'},					-- 0x2d7ca0 - 0x2d8220
		{expForLevelUp = 'uint16_t['..numExpLevelUps..']'},					-- 0x2d8220 - 0x2d82f4
	
		-- 0x2d8f00 - 0x2dc47f = location propeties (416 elements, 33 bytes each)
		-- 0x2dc47f - 0x2dc480 = unused
		-- 0x2dc480 - 0x2dca80 = location map palettes (48 elements, 16 colors each)
		{padding11 = 'uint8_t['..(0x2dfe00 - 0x2d82f4)..']'},				-- 0x2d82f4 - 0x2dfe00

		{longEsperBonusDescBase = 'uint8_t['..(0x2dffd0 - 0x2dfe00)..']'},	-- 0x2dfe00 - 0x2dffd0 
		{longEsperBonusDescOffsets = 'uint16_t['..numEsperBonuses..']'},	-- 0x2dffd0 - 0x2dfff2
	
	-- 0x2e4842 - 0x2e4851     Sprites used for various positions of map character

	-- 0x2e9b14 - 0x2e9d13     World of Balance Tile Properties
	-- 0x2e9d14 - 0x2e9f13     World of Ruin Tile Properties

	-- 0x2ed434 - 0x2f114e     World of Balance Map Data (compressed)
	-- 0x2f114f - 0x2f324f     World of Balance Tile Graphics (compressed)

	-- 0x2f4a46 - 0x2f6a55     World of Ruin Tile Graphics (compressed)
	-- 0x2f6a56 - 0x2f9d16     World of Ruin Map Data (compressed)

	-- 0x2fe49b - 0x2fe8b2     World of Balance Miniature Map (compressed)
	-- 0x2fe8b3 - 0x2fed25     World of Ruin Miniature Map (compressed)
	},
}
local function asserteq(a,b) if a ~= b then error(("expected %x == %x"):format(a, b)) end end
asserteq(ffi.offsetof('game_t', 'spells'), spellsAddr)
asserteq(ffi.offsetof('game_t', 'characterNames'), characterNamesAddr)
asserteq(ffi.offsetof('game_t', 'shops'), shopsAddr)
asserteq(ffi.offsetof('game_t', 'metamorphSets'), metamorphSetsAddr)
asserteq(ffi.offsetof('game_t', 'rareItemDescOffsets'), rareItemDescOffsetAddr)
asserteq(ffi.offsetof('game_t', 'rareItemNames'), rareItemNamesAddr)
asserteq(ffi.offsetof('game_t', 'rareItemDescBase'), rareItemDescBaseAddr)
asserteq(ffi.offsetof('game_t', 'monsters'), monstersAddr)
asserteq(ffi.offsetof('game_t', 'monsterItems'), monsterItemsAddr)
asserteq(ffi.offsetof('game_t', 'esperDescBase'), esperDescBaseAddr)
asserteq(ffi.offsetof('game_t', 'swordTechNames'), swordTechNamesAddr)
asserteq(ffi.offsetof('game_t', 'monsterSpells'), monsterSpellsAddr)
asserteq(ffi.offsetof('game_t', 'monsterSketches'), monsterSketchesAddr)
asserteq(ffi.offsetof('game_t', 'monsterRages'), monsterRagesAddr)
asserteq(ffi.offsetof('game_t', 'monsterNames'), monsterNamesAddr)
asserteq(ffi.offsetof('game_t', 'monsterAttackNames'), monsterAttackNamesAddr)
asserteq(ffi.offsetof('game_t', 'blitzDescBase'), blitzDescBaseAddr)
asserteq(ffi.offsetof('game_t', 'swordTechDescBase'), swordTechDescBaseAddr)
asserteq(ffi.offsetof('game_t', 'esperDescOffsets'), esperDescOffsetsAddr)
asserteq(ffi.offsetof('game_t', 'esperBonusDescs'), esperBonusDescsAddr)
asserteq(ffi.offsetof('game_t', 'blitzDescOffsets'), blitzDescOffsetsAddr)
asserteq(ffi.offsetof('game_t', 'swordTechDescOffsets'), swordTechDescOffsetsAddr)
asserteq(ffi.offsetof('game_t', 'itemNames'), itemNamesAddr)
asserteq(ffi.offsetof('game_t', 'WoBpalettes'), 0x12ec00)
asserteq(ffi.offsetof('game_t', 'WoRpalettes'), 0x12ed00)
asserteq(ffi.offsetof('game_t', 'setzerAirshipPalette'), 0x12ee00)
asserteq(ffi.offsetof('game_t', 'darylAirshipPalette'), 0x12ef00)
asserteq(ffi.offsetof('game_t', 'items'), itemsAddr)
asserteq(ffi.offsetof('game_t', 'espers'), espersAddr)
asserteq(ffi.offsetof('game_t', 'spellDescBase'), spellDescBaseAddr)
asserteq(ffi.offsetof('game_t', 'menuNames'), menuNamesAddr)
asserteq(ffi.offsetof('game_t', 'spellDescOffsets'), spellDescOffsetsAddr)
asserteq(ffi.offsetof('game_t', 'itemColosseumInfos'), itemColosseumInfosAddr)
asserteq(ffi.offsetof('game_t', 'spellNames_0to53'), spellNamesAddr)
asserteq(ffi.offsetof('game_t', 'esperAttackNames'), esperAttackNamesAddr)
asserteq(ffi.offsetof('game_t', 'mogDanceNames'), mogDanceNamesAddr)
asserteq(ffi.offsetof('game_t', 'topBackgroundPaletteOffset'), 0x271650)
asserteq(ffi.offsetof('game_t', 'monsterGraphics'), 0x297000)
asserteq(ffi.offsetof('game_t', 'menuImages'), 0x2d0000)
asserteq(ffi.offsetof('game_t', 'menuWindowPalettes'), 0x2d1c00)
asserteq(ffi.offsetof('game_t', 'characterMenuImages'), 0x2d1d00)
asserteq(ffi.offsetof('game_t', 'itemDescBase'), itemDescBaseAddr)
asserteq(ffi.offsetof('game_t', 'loreDescBase'), loreDescBaseAddr)
asserteq(ffi.offsetof('game_t', 'loreDescOffsets'), loreDescOffsetsAddr)
asserteq(ffi.offsetof('game_t', 'itemDescOffsets'), itemDescOffsetsAddr)
asserteq(ffi.offsetof('game_t', 'characters'), charactersAddr)
--asserteq(ffi.offsetof('game_t', 'expForLevelUp'), expForLevelUpAddr)
asserteq(ffi.offsetof('game_t', 'longEsperBonusDescBase'), longEsperBonusDescBaseAddr)
asserteq(ffi.offsetof('game_t', 'longEsperBonusDescOffsets'), longEsperBonusDescOffsetsAddr)

game = ffi.cast('game_t*', rom)

local obj = setmetatable({}, {
	__index = game,
})
		
obj.numSpells = numSpells
obj.numEsperBonuses = numEsperBonuses
obj.numEspers = numEspers
obj.numMonsters = numMonsters
obj.numItems = numItems
obj.numItemTypes = numItemTypes
obj.numRareItems = numRareItems
obj.numRages = numRages
obj.numMetamorphSets = numMetamorphSets
obj.numExpLevelUps = numExpLevelUps
obj.numLevels = numLevels
obj.numMenuNames = numMenuNames
obj.numCharacters = numCharacters
obj.numMogDances = numMogDances
obj.numSwordTechs = numSwordTechs
obj.numBlitzes = numBlitzes
obj.numLores = numLores
obj.numShops = numShops
obj.numLocationNames = numLocationNames
obj.numDialogs = numDialogs
obj.numBattleDialogs = numBattleDialogs
obj.numBattleDialog2s = numBattleDialog2s
obj.numBattleMessages = numBattleMessages
obj.numFormations = numFormations
obj.numFormationMPs = numFormationMPs
obj.numFormationSizeOffsets = numFormationSizeOffsets 
obj.numFormationSizes = numFormationSizes 
obj.numPositionedText = numPositionedText 

obj.findnext = findnext
obj.gamezstr = gamezstr
obj.compzstr = compzstr
obj.gamestr = gamestr
obj.compstr = compstr
obj.getSpellName = getSpellName
obj.getEsperName = getEsperName

obj.itemForName = {}
for i=0,numItems-1 do
	local name = tostring(game.itemNames[i])
	if i < 231 then name = name:sub(2) end
	obj.itemForName[name] = i
end

obj.spellForName = {}
for i=0,numItems-1 do
	local name = getSpellName(i)
	if i < 54 then name = name:sub(2) end
	obj.spellForName[name] = i
end

obj.character_t = character_t

return obj

end
