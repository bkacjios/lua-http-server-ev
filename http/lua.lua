local lua = {
	document = "",
}

local open = io.open
local gsub = string.gsub
local gmatch = string.gmatch
local format = string.format

local print_orginal = _G.print

local PRINT_CHUNK = 1
local PRINT_CHUNKS = {}

function lua.HTTP_SET_PRINT_CHUNK(num)
	PRINT_CHUNK = num
	PRINT_CHUNKS[num] = ""
end

function lua.print(...)
	local num = select("#", ...)

	for i=1, num do
		if i > 1 then
			PRINT_CHUNKS[PRINT_CHUNK] = PRINT_CHUNKS[PRINT_CHUNK] .. "\t"
		end
		PRINT_CHUNKS[PRINT_CHUNK] = PRINT_CHUNKS[PRINT_CHUNK] .. tostring(select(i, ...))
	end

	-- Allow using $variable_name in the print like php
	PRINT_CHUNKS[PRINT_CHUNK] = gsub(PRINT_CHUNKS[PRINT_CHUNK], "%$([%w%d_]+)", function(variable)
		local index = 1
	    while true do
			local var_name, var_value = debug.getlocal(4, index)
			if not var_name then break end
			if var_name == variable then
				return tostring(var_value)
			end
			index = index + 1
		end
		return tostring(_G[variable])
	end)
end

function lua.create()
	lua.document = "" -- Clear the document
	-- Run any Lua code
end

function lua.runluafile(path, request, response)
	local func, err = loadfile(path)

	if not func then error(err) end

	_RESPONSE = response
	_REQUEST = request
	HTTP_SET_PRINT_CHUNK = lua.HTTP_SET_PRINT_CHUNK
	lua.HTTP_SET_PRINT_CHUNK(1)
	print = lua.print
	func()
	print = print_orginal
	HTTP_SET_PRINT_CHUNK = nil
	_REQUEST = nil
	_RESPONSE = nil

	return PRINT_CHUNKS[1]
end

function lua.parsehtmlfile(path, request, response)
	local f, err = open(path, "r")

	if err then return error(err) end

	local html = f:read("*a")
	f:close()

	--[[for code in html:gmatch("<%?lua%s(.-)%s%?>") do
	end]]

	--html = gsub(html, "%{", "%%%{") -- Escape any brackets
	--html = gsub(html, "%}", "%%%}") -- Escape any brackets

	local code = ""
	local chunk_num = 0

	-- Capture all code in our bracket things ex: "<?lua print'hello world!' ?>""
	html = gsub(html, "<%?lua%s(.-)%s%?>", function(chunk)
		chunk_num = chunk_num + 1
		code = format("%sHTTP_SET_PRINT_CHUNK(%d)\r\n%s\r\n", code, chunk_num, chunk)
		return format("{HTTP_LUA_CHUNK_OUTPUT:%d}", chunk_num)
	end)

	local func, err = load(code)
	if not func then error(err) end

	_RESPONSE = response
	_REQUEST = request
	HTTP_SET_PRINT_CHUNK = lua.HTTP_SET_PRINT_CHUNK
	print = lua.print
	func()
	print = print_orginal
	HTTP_SET_PRINT_CHUNK = nil
	_REQUEST = nil
	_RESPONSE = nil

	html = gsub(html, "%{%HTTP_LUA_CHUNK_OUTPUT:(%d+)%}", function(num)
		num = tonumber(num)
		return PRINT_CHUNKS[num] or ""
	end)

	--html = gsub(html, "%%%{", "%{") -- Unescape any brackets
	--html = gsub(html, "%%%}", "%}") -- Unescape any brackets

	return html
end

return lua