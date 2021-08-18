# frozen_string_literal: true

require 'json'
require 'faye/websocket'
require 'eventmachine'

EM.run do
  ws = Faye::WebSocket::Client.new('ws://127.0.0.1:9292')

  ws.on :open do |_event|
    p [:open]
    ws.send(JSON.dump({
                        type: 'join',
                        name: 'client',
                        room: 'default'
                      }))
  end

  ws.on :message do |event|
    p [:message, event.data]
  end

  ws.on :close do |event|
    p [:close, event.code, event.reason]
    ws = nil
  end
end
