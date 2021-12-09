# frozen_string_literal: true

require 'json'

class MjaiChannel < ApplicationCable::Channel
  def subscribed
    puts "current_user = #{current_user}"
    stream_for current_user
    message = {
      type: 'hello',
      protocol: 'mjsonp',
      protocol_version: 3,
      name: current_user.name
    }
    MjaiChannel.broadcast_to current_user, message: message.to_json
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
    stop_all_streams
  end

  def join(data)
    mjai_msg = JSON.parse(data['message'])
    if mjai_msg['type'] == 'join'
      puts "#{mjai_msg['name']} joins room #{mjai_msg['room']}"
      puts User.all.collect(&:name).to_s
      players = User.all
      message = {
        type: 'join',
        players: players.collect(&:name)
      }
      players.each do |player|
        MjaiChannel.broadcast_to player, message: message.to_json
      end
      delta = 4 - User.count
      if delta.positive?
        puts "Waiting for #{delta} more players..."
      else
        puts "start game among #{User.all.collect(&:name)}"
      end
    else
      puts "unexpected action: #{mjai_msg['type']}"
    end
  end

  def test(data)
    puts data
  end
end
