local http = {}

local HTTP_VERSION = "HTTP/2.0"
local HTTP_LINE_ENDINGS = "\r\n"
local HTTP_KEEP_ALIVE_TIMEOUT = 30
local HTTP_RESPOND_WITH_ERRORS = true

local ev = require("ev")
local log = require("log")
local socket = require("socket")
local url = require("socket.url")

local insert = table.insert
local remove = table.remove
local concat = table.concat

local format = string.format
local match = string.match
local gsub = string.gsub
local gmatch = string.gmatch
local char = string.char

local date = os.date

local bind = socket.bind
local gettime = socket.gettime

local CLIENT = {}
CLIENT.__index = CLIENT

local REQUEST = {}
--REQUEST.__index = REQUEST

function REQUEST:__index(key)
	return rawget(REQUEST, key) or rawget(self, "headers")[key]
end

function CLIENT:createrequest(method, uri, headers)
	return setmetatable({
		method = method,
		url = url.parse(uri), 
		headers = headers,
	}, REQUEST)
end

function REQUEST:getmethod()
	return self.method
end

function REQUEST:geturl()
	return self.url
end

function REQUEST:getpath()
	return self.url.path
end

function REQUEST:getheaders()
	return self.headers
end

function REQUEST:getheader(key)
	return self.headers[key]
end

local RESPONSE = {}
RESPONSE.__index = RESPONSE

function CLIENT:createresponse()
	return setmetatable({
		code = 200,
		headers = {
			["Server"] = http.server_version_string(),
			["Connection"] = "Keep-Alive",
			["Keep-Alive"] = self:gettimeout(),
			["Date"] = date("!%a, %d %b %Y %H:%M:%S %Z"),
			["Content-Length"] = 0,
		},
		document = "",
	}, RESPONSE)
end

function RESPONSE:setcode(code)
	self.code = code
end

function RESPONSE:getcode()
	return self.code
end

function RESPONSE:setdocument(data)
	self.document = data or ""
	self.headers["Content-Length"] = #self.document
end

function RESPONSE:setcontenttype(mime)
	self.headers["Content-Type"] = mime
end

function RESPONSE:getdocument()
	return self.document
end

function RESPONSE:setheader(key, value)
	self.headers[key] = value
end

function RESPONSE:getheaders()
	return self.headers
end

function RESPONSE:format()
	--[[local response = concat({
		format("%s %s", HTTP_VERSION, http.status(code)),
		format("Server: %s", http.server_version_string()),
		format("Content-Type: %s", (mime or "text/html")),
		format("Content-Length: %d", #document),
		"Connection: Keep-Alive",
		format("Keep-Alive: timeout=%d", self:gettimeout()),
		format("Date: %s", date("!%a, %d %b %Y %H:%M:%S %Z")),
		"",
		document
	}, HTTP_LINE_ENDINGS)]]

	local response = {
		format("%s %s", HTTP_VERSION, http.status(self:getcode()))
	}

	for key, value in pairs(self:getheaders()) do
		insert(response, format("%s: %s", key, value))
	end

	insert(response, "") -- Signal for document
	insert(response, self:getdocument())

	local response_str = concat(response, HTTP_LINE_ENDINGS)

	log.debug("RESPONSE %s", response_str)

	return response_str
end

function CLIENT:settimeout(time)
	self.timeout = time
end

function CLIENT:gettimeout()
	return self.timeout
end

function CLIENT:readrequest()
	local line, err = self.socket:receive("*l")

	if err then return end

	-- Split the line into the method, uri, and version
	local method, uri, httpver = match(line, "^(%S+)%s(%S+)%s(%S+)")

	if not method then return end

	log.debug("REQUEST %s %s %s", method, uri, httpver)

	local headers = self:readheaders()

	local request = self:createrequest(method, uri, headers)
	local response = self:createresponse()

	-- Call our hook handler to get the response code and document data
	self.server:call(request, response)

	-- Send the response to the client
	self:send(response:format())
end

function CLIENT:getfd()
	return self.socket:getfd()
end

function CLIENT:readheaders()
	self.headers = {}
	while true do
		local line, err = self.socket:receive("*l")
		if err == "closed" or (line == "" and not err) then
			-- End of request via a closed connection or the line being blank
			return self.headers
		elseif line and not err then
			-- Add line to buffer
			local key, value = match(line, "^([^: ]+)%s*:%s*(.+)")

			if key then
				self.headers[key] = value
			else
				log.warn("discarding invalid header %q", line)
				--self.headers[line] = ""
			end
			--insert(self.headers, line)

			-- Reset the timeout timer back to the start
			self.timer:again(ev.Loop.default, self.timeout)
		elseif err == "timeout" then
			-- Waiting for data
			break
		end
	end
end

function CLIENT:send(...)
	self.socket:send(...)
end

function CLIENT:close()
	-- End the timeout event
	self.timer:stop(ev.Loop.default)

	-- Send a 408 Request Timeout
	-- self:sendresponse(408)

	-- Close the connection
	self.socket:close()
	log.info("http client [%s:%i] connection closed", self.ip, self.port)
end

local SERVER = {}
SERVER.__index = SERVER

function SERVER:getfd()
	return self.socket:getfd()
end

function SERVER:acceptclients()
	if not self.socket then return end

	while true do
		local client, err = self.socket:accept()

		if not client then break end

		-- Make non-blocking
		client:settimeout(0)

		local ip, port = client:getpeername()

		local client = setmetatable({
			ip = ip,
			port = port,
			socket = client,
			server = self,
			headers = {},
			keepalive = true,
			timeout = HTTP_KEEP_ALIVE_TIMEOUT,
		}, CLIENT)

		-- Create an event timer to timeout the connection
		client.timer = ev.Timer.new(function()
			local succ, err = xpcall(client.close, debug.traceback, client)
			if not succ then log.error(err) end
		end, client.timeout, 0)

		-- Register the timer
		client.timer:start(ev.Loop.default)

		-- Create an event using the sockets file desciptor for when client is ready to read data
		client.onread = ev.IO.new(function()
			-- Read the request safely using xpcall
			local succ, err = xpcall(client.readrequest, debug.traceback, client)
			if not succ then log.error(err) end
		end, client:getfd(), ev.READ)

		-- Register the event
		client.onread:start(ev.Loop.default)

		log.info("http client [%s:%i] connected", ip, port)
	end
end

function SERVER:hook(method, callback)
	self.hooks[method] = callback
end

function SERVER:call(request, response)
	local method = request:getmethod()

	if self.hooks[method] then
		local succ, code = xpcall(self.hooks[method], debug.traceback, request, response)
		if not succ then
			log.error("%s error: %s", method, code)

			response:setcode(500) -- Set response code to "Internal Server Error"

			if HTTP_RESPOND_WITH_ERRORS then
				-- Respond with a detailed error page
				response:setdocument(http.error_page(500, code)) -- The "code" variable is actually the error string
			else
				-- Respond with a generic/nondescript error page
				response:setdocument(http.status_page(500))
			end
		elseif code then
			response:setcode(code)
		end
	else
		response:setcode(501) -- Set response code to "Not Implemented"
		response:setdocument(http.status_page(501))
	end
end

function SERVER:close()
	self.socket:close()
	log.info("http server closed")
end

local status_translate = {
	[100] = "Continue",
	[101] = "Switching Protocol",
	[102] = "Processing",
	[103] = "Early Hints",

	[200] = "OK",
	[201] = "Created",
	[202] = "Accepted",
	[203] = "Non-Authoritative Information",
	[204] = "No Content",
	[205] = "Reset Content",
	[206] = "Partial Content",
	[207] = "Multi-Status",
	[208] = "Multi-Status",
	[226] = "IM Used",

	[300] = "Multiple Choice",
	[301] = "Moved Permanently",
	[302] = "Found",
	[303] = "See Other",
	[304] = "Not Modified",
	[305] = "Use Proxy", -- Deprecated
	[306] = "Unused", -- Unused
	[307] = "Temporary Redirect",
	[308] = "Permanent Redirect",

	[400] = "Bad Request",
	[401] = "Unauthorized",
	[402] = "Payment Required",
	[403] = "Forbidden",
	[404] = "Not Found",
	[405] = "Method Not Allowed",
	[406] = "Not Acceptable",
	[407] = "Proxy Authentication Required",
	[408] = "Request Timeout",
	[409] = "Conflict",
	[410] = "Gone",
	[411] = "Length Required",
	[412] = "Precondition Failed",
	[413] = "Payload Too Large",
	[414] = "URI Too Long",
	[415] = "Unsupported Media Type",
	[416] = "Requested Range Not Satisfiable",
	[417] = "Expectation Failed",
	[418] = "I'm a teapot",
	[421] = "Misdirected Request",
	[422] = "Unprocessable Entity",
	[423] = "Locked",
	[424] = "Failed Dependency",
	[425] = "Too Early",
	[426] = "Upgrade Required",
	[428] = "Precondition Required",
	[429] = "Too Many Requests",
	[431] = "Request Header Fields Too Large",
	[451] = "Unavailable For Legal Reasons",

	[500] = "Internal Server Error",
	[501] = "Not Implemented",
	[502] = "Bad Gateway",
	[503] = "Service Unavailable",
	[504] = "Gateway Timeout",
	[505] = "HTTP Version Not Supported",
	[506] = "Variant Also Negotiates",
	[507] = "Insufficient Storage",
	[508] = "Loop Detected",
	[510] = "Not Extended",
	[511] = "Network Authentication Required",
}

function http.status(code)
	if not status_translate[code] then
		return http.status(500) -- Return "500 Internal Server Error"
	end
	return format("%d %s", code, status_translate[code])
end

function http.server_version_string()
	return format("%s (%s; %s; %s)", gsub(_VERSION, " ", "/"), jit.os, jit.arch, jit.version)
end

function http.urldecode(str)
	str = gsub(str, "+", " ")
	str = gsub(str, "%%(%x%x)", function(hex)
		return char(tonumber(hex, 16))
	end)
	return str
end

function http.parseurl(str)
	str = str:match("%s+(.+)")
	local params = {}
	for key, value in gmatch(str, "([^&=?]-)=([^&=?]+)") do
		params[key] = http.urldecode(value)
	end
	return params
end

function http.serve_file(path, mime)
	local f = open(path, "r")
	local document = f:read("*a")
	if f then
		f:close()
		return 200, document, mime or "text/html"
	end
end

function http.error_page(code, err)
	local document = [[<html>
<head><title>{status}</title>
<style>.container{text-align:center;}.container pre{display:inline-block;text-align:left;}
</style></head>
<body>
<center><h1>{status}</h1></center>
<div class="container"><pre>{error}</pre></div>
<hr><center>{server-version}</center>
</body>
</html>]]

	-- Replace some keys with their values
	document = document:gsub("%{error%}", err)
	document = document:gsub("%{status%}", http.status(code))
	document = document:gsub("%{server%-version%}", http.server_version_string())

	return document
end

function http.status_page(code)
	local document = [[<html>
<head><title>{status}</title></head>
<body>
<center><h1>{status}</h1></center>
<hr><center>{server-version}</center>
</body>
</html>]]

	-- Replace some keys with their values
	document = document:gsub("%{status%}", http.status(code))
	document = document:gsub("%{server%-version%}", http.server_version_string())

	return document
end

function http.create(ip, port)
	local socket = assert(bind(ip, port))
	socket:settimeout(0)

	local ip, port = socket:getsockname()

	log.info("http server started @%s:%i", ip, port)

	local server = setmetatable({
			ip = ip,
			port = port,
			socket = socket,
			hooks = {},
	}, SERVER)

	-- Create an event using the sockets file desciptor for when client is ready to read data
	server.onread = ev.IO.new(function()
		local succ, err = xpcall(server.acceptclients, debug.traceback, server)
		if not succ then log.error(err) end
	end, server:getfd(), ev.READ)

	-- Register the event
	server.onread:start(ev.Loop.default)

	return server
end

return http