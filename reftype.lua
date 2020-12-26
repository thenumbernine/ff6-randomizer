local ffi = require 'ffi'
--[[
args.name = typename
--]]
local function reftype(args)
	local name = assert(args.name)
	local options = args.options
	local getter = args.getter
	ffi.cdef([[
typedef struct {
	uint8_t i;
} ]]..name..[[;
]])
	local metatype = ffi.metatype(name, {
		__tostring = function(self)
			if self.i == 0xff then 
				if not (getter and args.getterSkipNone) then
					return nil	--'"(none)"' 
				end
			end
			if options then
				local s = options[self.i+1]
				if s == nil then
					s = '"('..tostring(self.i)..')"'
				end
				return s
			elseif getter then
				return '"'..tostring(getter(self.i))..'"'
			else
				return tostring(self.i)
			end
		end,
		__concat = function(a,b) return tostring(a)..tostring(b) end,
	})
	assert(ffi.sizeof(name) == 1)
	return metatype 
end
return reftype
