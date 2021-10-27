class MjaiChannel < ApplicationCable::Channel
  @@counter = 0

  def subscribed
    # stream_from "some_channel"
    puts "current_user = #{current_user}"
    stream_for current_user
    MjaiChannel.broadcast_to current_user, message: "Hello #{current_user.name}, #{@@counter}"
    @@counter += 1
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
    stop_all_streams
  end

  def test(data)
    puts data
  end
end
