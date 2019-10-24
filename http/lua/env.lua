-- This is the environment used when running Lua scripts within a webpage
-- We don't really care if we're using unsafe functions to escape from the environment

local env = {
	arg = arg,

	--print = print,

	_ECHO = {
		CHUNK = 1,
		BUFFER = {},
	},

	module = module,
	require = require,
	dofile = dofile,
	load = load,
	loadile = loadfile,
	loadstring = loadstring,

	setfenv = setfenv,
	getfenv = setfenv,
	getmetatable = getmetatable,
	setmetatable = setmetatable,

	gcinfo = gcinfo,

	coroutine = {
		create = coroutine.create,
		resume = coroutine.resume,
		running = coroutine.running,
		status = coroutine.status,
		wrap = coroutine.wrap,
		yield = coroutine.yield,
	},

	package = {
		loaded = package.loaded,
		loaders = package.loaders,
		loadlib = package.loadlib,
		path = package.path,
		cpath = package.cpath,
		preload = package.preload,
		seeall = package.seeall,
	},

	rawequal = rawequal,
	rawget = rawget,
	rawset = rawset,
	rawlen = rawlen,

	newproxy = newproxy,
	assert = assert,
	collectgarbage = collectgarbage,
	error = error,
	ipairs = ipairs,
	next = next,
	pairs = pairs,
	pcall = pcall,
	select = select,
	tonumber = tonumber,
	tostring = tostring,
	type = type,
	unpack = unpack,
	_VERSION = _VERSION,
	xpcall = xpcall,
	
	bit = {
		tobit = bit.tobit,
		tohex = bit.tohex,
		bnot = bit.bnot,
		band = bit.band,
		bor = bit.bor,
		bxor = bit.bxor,
		lshift = bit.lshift,
		rshift = bit.rshift,
		arshift = bit.arshift,
		rol = bit.rol,
		ror = bit.ror,
		bswap = bit.bswap,
	},

	debug = {
		setupvalue = debug.setupvalue,
		getregistry = debug.getregistry,
		traceback = debug.traceback,
		setlocal = debug.setlocal,
		getupvalue = debug.getupvalue,
		gethook = debug.gethook,
		sethook = debug.sethook,
		getlocal = debug.getlocal,
		upvaluejoin = debug.upvaluejoin,
		getinfo = debug.getinfo,
		getfenv = debug.getfenv,
		setmetatable = debug.setmetatable,
		upvalueid = debug.upvalueid,
		getuservalue = debug.getuservalue,
		debug = debug,
		getmetatable = debug.getmetatable,
		setfenv = debug.setfenv,
		setuservalue = debug.setuservalue,
	},

	math = {
		abs = math.abs, acos = math.acos, asin = math.asin, 
		atan = math.atan, atan2 = math.atan2, ceil = math.ceil, cos = math.cos, 
		cosh = math.cosh, deg = math.deg, exp = math.exp, floor = math.floor, 
		fmod = math.fmod, frexp = math.frexp, huge = math.huge, 
		ldexp = math.ldexp, log = math.log, log10 = math.log10, max = math.max, 
		min = math.min, modf = math.modf, pi = math.pi, pow = math.pow, 
		rad = math.rad, random = math.random, sin = math.sin, sinh = math.sinh, 
		sqrt = math.sqrt, tan = math.tan, tanh = math.tanh,
	},
	string = {
		byte = string.byte, char = string.char, dump = string.dump, find = string.find, 
		format = string.format, gmatch = string.gmatch, gsub = string.gsub, 
		len = string.len, lower = string.lower, match = string.match, 
		rep = string.rep, reverse = string.reverse, sub = string.sub, 
		upper = string.upper,
	},
	table = {
		concat = table.concat,
		foreach = table.foreach,
		foreachi = table.foreachi,
		getn = table.getn,
		insert = table.insert,
		maxn = table.maxn,
		pack = table.pack,
		unpack = table.unpack or unpack,
		remove = table.remove, 
		sort = table.sort,
	},
	coroutine = {
		create = coroutine.create,
		resume = coroutine.resume,
		running = coroutine.running,
		status = coroutine.status,
		wrap = coroutine.wrap,
		yield = coroutine.yield,
	},
	io = {
		stdin = io.stdin,
		stdout = io.stdout,
		stderr = io.stderr,
		read = io.read,
		write = io.write,
		flush = io.flush,
		type = io.type,
		open = io.open,
		close = io.close,
	},
	jit = {
		version = jit.version,
		version_num = jit.version_num,
		os = jit.os,
		arch = jit.arch,
	},
	os = {
		clock = os.clock,
		date = os.date,
		difftime = os.difftime,
		time = os.time,
		execute = os.execute,
		exit = os.exit,
		getenv = os.getenv,
		remove = os.remove,
		rename = os.rename,
		setlocale = os.setlocale,
	},
}
env._G = env

env._ECHO.SET_CHUNK = function(chunk)
	_ECHO.CHUNK = chunk
	_ECHO.BUFFER[chunk] = ""
end
setfenv(env._ECHO.SET_CHUNK, env)

env.echo = function(...)
	local num = select("#", ...)

	local chunk = _ECHO.CHUNK

	_ECHO.BUFFER[chunk] = _ECHO.BUFFER[chunk] or ""

	local buffer = _ECHO.BUFFER

	for i=1, num do
		buffer[chunk] = buffer[chunk] .. tostring(select(i, ...))
	end

	-- Allow using $variable_name in the print like php
	-- TODO: Allow indexing? Example: "$jit.os"

	-- Variable names in lua can't have numbers at the start
	buffer[chunk] = string.gsub(buffer[chunk], "%$([^%d][%a%d_]+)", function(variable)
		local index = 1
	    while true do
	    	-- Loop through all local variables 4 scopes up
			local var_name, var_value = debug.getlocal(4, index)
			if not var_name then break end
			if var_name == variable then
				-- We found a local variable that matches the name, use its value as a string
				return tostring(var_value)
			end
			index = index + 1
		end

		-- Fallback to global variables
		if _G[variable] then
			return tostring(_G[variable])
		end

		-- We couldn't find the variable, return "nil"
		return "nil"
	end)
end
setfenv(env.echo, env)

env.print = env.echo
setfenv(env.print, env)

return env