class Mjai {

  constructor(channel) {
    this._channel = channel;
  }

  received(mjaiMessage) {
    switch (mjaiMessage.type) {
      case 'hello':
        this.__joinGame(mjaiMessage);
        break;
      case 'join':
        this.__playerJoined(mjaiMessage);
        break;
      default:
        this.__defaultAction(mjaiMessage);
    }
  }

  __joinGame(mjaiMessage) {
    this._playerName = mjaiMessage.name
    this._channel.perform('join', {
      message: JSON.stringify({
        type: 'join',
        name: this._playerName,
        room: 'default'
      })
    });
  }

  __playerJoined(mjaiMessage) {
    document.querySelector(".player-list").innerText = mjaiMessage.players
  }

  __defaultAction(mjaiMessage) {
    this._channel.perform('test', {
      message: 'test message'
    });
  }
}

export default Mjai