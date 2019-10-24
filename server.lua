package.path = package.path .. ';./?.lua;./?/init.lua'

local http = require("http")
local lua = require("http.lua")
local ev = require("ev")

local params = {
	mode = "server",
	protocol = "any",
	key = "/srv/http/private.key",
	certificate = "/srv/http/cert.pem",
	cafile = "/srv/http/cloudflare_origin_rsa.pem",
	verify = {"none"},
	options = "all",
}

local server = http.create("0.0.0.0", 8080, params)

server:hook("GET", function(request, response)
	if request:getpath() == "/index.lua" then
		response:setcontenttype("text/html")
		response:setdocument(lua.runluafile("index.lua", request, response)) -- Run the file normally, print function outputs to return value
		return 200
	elseif request:getpath() == "/index.html" then
		response:setcontenttype("text/html")
		response:setdocument(lua.parsehtmlluafile("index.html", request, response)) -- Parse the HTML with embeded <?lua ?> tags and serve
		return 200
	elseif request:getpath() == "/error" then
		error("Woops! This an error to test things.")
	end

	response:setcontenttype("text/html")
	response:displaystatuspage(404)
	return 404
end)

server:start(ev.Loop.default)

ev.Signal.new(function(loop, sig, revents)
	print()
	loop:unloop()
end, ev.SIGINT):start(ev.Loop.default)

ev.Loop.default:loop()

server:close()