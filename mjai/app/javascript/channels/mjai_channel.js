import consumer from "./consumer"

const channel = consumer.subscriptions.create("MjaiChannel", {
  connected() {
    // Called when the subscription is ready for use on the server
    console.log('connected');
    channel.send({
      message: 'Hi'
    });
  },

  disconnected() {
    // Called when the subscription has been terminated by the server
    console.log('disconnected');
  },

  received(data) {
    // Called when there's incoming data on the websocket for this channel
    console.log(data['message']);
    channel.perform('test', {
      message: 'test message'
    });
  }
});