import consumer from './consumer'
import Mjai from './mjai'

const mjai = new Mjai(consumer.subscriptions.create('MjaiChannel', {
  connected() {
    // Called when the subscription is ready for use on the server
    console.log('Connected to server');
  },

  disconnected() {
    // Called when the subscription has been terminated by the server
    console.log('Disconnected from server');
  },

  received(data) {
    // Called when there's incoming data on the websocket for this channel
    console.log(data['message']);
    mjai.received(JSON.parse(data['message']))
  }
}));