local lua = {}

local open = io.open
local gsub = string.gsub
local gmatch = string.gmatch
local format = string.format

if not print_orginal then
	print_orginal = print
end

function lua.runluafile(path, request, response)
	local func, err = loadfile(path)

	if not func then error(err) end

	local env = require("http.lua.env")
	env._RESPONSE = response
	env._REQUEST = request
	
	setfenv(func, env)
	func()

	return env._ECHO.BUFFER[1]
end

function lua.parsehtmlluafile(path, request, response)
	local f, err = open(path, "r")

	if err then return error(err) end

	local html = f:read("*a")
	f:close()

	--[[for pre, code, post in html:gmatch("(.*)<%?lua%s*(.-)%s*%?>(.*)") do
		print("pre", pre)
		print("code", code)
		print("post", post)
	end]]

	--html = gsub(html, "%{", "%%%{") -- Escape any brackets
	--html = gsub(html, "%}", "%%%}") -- Escape any brackets

	local code = ""
	local chunk_num = 0

	-- Convert shorthand to Lua code
	html = gsub(html, "<%?=%s*%$([^%d][%a%d_]+)%s*%?>", function(variable)
		return format("<?lua echo(%s) ?>", variable)
	end)

	-- Capture all code in our bracket things ex: "<?lua print'hello world!' ?>""
	html = gsub(html, "<%?lua%s*(.-)%s*%?>", function(chunk)
		chunk_num = chunk_num + 1
		code = format("%s_ECHO.SET_CHUNK(%d)\r\n%s\r\n", code, chunk_num, chunk)
		return format("{CHUNK:#%d}", chunk_num)
	end)

	local func, err = load(code)
	if not func then error(err) end

	local env = require("http.lua.env")
	env._RESPONSE = response
	env._REQUEST = request

	setfenv(func, env)
	func() -- Do we even need to pcall?

	-- Replace all echo buffers
	html = gsub(html, "%{%CHUNK:#(%d+)%}", function(num)
		return env._ECHO.BUFFER[tonumber(num)] or ""
	end)

	--html = gsub(html, "%%%{", "%{") -- Unescape any brackets
	--html = gsub(html, "%%%}", "%}") -- Unescape any brackets

	return html
end

return lua