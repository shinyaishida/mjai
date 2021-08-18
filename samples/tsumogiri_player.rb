#!/usr/bin/env ruby
# frozen_string_literal: true

require 'socket'
require 'json'
require 'uri'

uri = URI.parse(ARGV[0])
socket = TCPSocket.new(uri.host, uri.port)
socket.sync = true
id = nil

socket.each_line do |line|
  warn("<-\t%s" % line.chomp)
  action = JSON.parse(line.chomp)
  case action['type']
  when 'hello'
    response = {
      'type' => 'join',
      'name' => 'tsumogiri',
      'room' => uri.path[1..]
    }
  when 'start_game'
    id = action['id']
    response = { 'type' => 'none' }
  when 'end_game'
    break
  when 'tsumo'
    response = if action['actor'] == id
                 {
                   'type' => 'dahai',
                   'actor' => id,
                   'pai' => action['pai'],
                   'tsumogiri' => true
                 }
               else
                 { 'type' => 'none' }
               end
  when 'error'
    break
  else
    response = { 'type' => 'none' }
  end
  warn("->\t%s" % JSON.dump(response))
  socket.puts(JSON.dump(response))
end
