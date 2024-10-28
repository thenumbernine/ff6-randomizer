local table = require 'ext.table'
local struct = require 'struct'
return function(args)
	return struct{
		notostring = args.notostring,
		tostringFields = true,
		tostringOmitFalse = true,
		tostringOmitNil = true,
		tostringOmitEmpty = true,
		name = args.name,
		union = true,
		fields = {
			{name='s', type='uint8_t[1]', no_iter=true},
			{type=struct{
				notostring = args.notostring,
				tostringFields = true,
				tostringOmitFalse = true,
				tostringOmitNil = true,
				tostringOmitEmpty = true,
				anonymous = true,
				packed = true,
				fields = table.mapi(args.fields, function(kv)
					local name, ctype = next(kv)
					return {
						name = name,
						type = ctype,
					}
				end),
			}},
		},
		metatable = args.metatable,
	}
end
