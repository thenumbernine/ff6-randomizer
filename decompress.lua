local ffi = require 'ffi'
local vector = require 'ffi.cpp.vector-lua'
-- decompress one block of 2048 bytes
local function decompress0x800(ptr, len)
	local out = vector'uint8_t'
	local buf = ffi.new('uint8_t[0x800]')
	ffi.fill(buf, ffi.sizeof(buf))
	local bufOfs = 0x7de
print('decompressing len', len)
	local compressedSize = ffi.cast('uint16_t*', ptr)[0]
	ffi.cast('uint16_t*', buf + bufOfs)[0] = compressedSize
	local endptr = ptr + compressedSize	-- end relative to start before size
	ptr = ptr + 2
print('compressed stored len', compressedSize)
	while ptr < endptr do
		local header = ptr[0]
		ptr = ptr + 1
		for i=0,7 do
			if bit.band(bit.rshift(header, i), 1) == 1 then
--print('writing', ptr[0])
				local src = ptr[0]
				ptr = ptr + 1
				out:emplace_back()[0] = src
				buf[bufOfs] = src
				bufOfs = bit.band(bufOfs + 1, 0x7ff)
			else
				local w = ffi.cast('uint16_t*', ptr)[0]
				ptr = ptr + 2
				local ofs = bit.band(w, 0x7ff)
				local size = bit.rshift(w, 11) + 3
--print('decompress block ofs', ofs, 'size', size)
				for j=0,size-1 do
					local src = buf[bit.band(ofs + j, 0x7ff)]
					out:emplace_back()[0] = src
					buf[bufOfs] = src
					bufOfs = bit.band(bufOfs + 1, 0x7ff)
				end
			end
		end
	end
	--return ffi.string(buf, ffi.sizeof(buf)), ptr
	return out:dataToStr(), ptr
end

local function decompress(ptr, len)
	local endptr = ptr + len
	local s = table()
	while ptr < endptr do
		local row
		row, ptr = decompress0x800(ptr, endptr - ptr)
		s:insert(row)
	end
	return s:concat()
end

return {
	decompress = decompress,
	decompress0x800 = decompress0x800,
}
