local websocket = require("websocket").client.ev()

websocket:on_open(function()
	print('connected')
end)

websocket:connect("wss://pubsub-edge.twitch.tv")

websocket:on_message(function(ws, msg)
	print(ws, message)

	local data = json.decode(message)

	if not data then return end

	--ws:send(message)
end)

websocket:on_close(function()

end)