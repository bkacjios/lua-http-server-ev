package.path = package.path .. ';./?.lua;./?/init.lua'

local http = require("http")
local lua = require("http.lua")
local ev = require("ev")

local server = http.create("0.0.0.0", 8080)

server:hook("GET", function(request, response)
	if request:getpath() == "/" then
		response:setcontenttype("text/html")
		response:setdocument(lua.runluafile("index.lua"))
		return 200
	elseif request:getpath() == "/error" then
		error("Woops! This a error to test things.")
	end

	response:setcontenttype("text/html")
	response:setdocument(http.status_page(404))
	return 404
end)

local function exit(loop, sig, revents)
	print()
	loop:unloop()
end

ev.Signal.new(exit, ev.SIGINT):start(ev.Loop.default)
ev.Loop.default:loop()
server:close()