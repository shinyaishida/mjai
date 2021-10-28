/* eslint func-names: ["error", "as-needed"] */

import $ from 'jquery';

const IMAGE_PATH = '/images';

const TSUPAIS = [null, 'E', 'S', 'W', 'N', 'P', 'F', 'C'];

const TSUPAI_TO_IMAGE_NAME = {
  E: 'ji_e',
  S: 'ji_s',
  W: 'ji_w',
  N: 'ji_n',
  P: 'no',
  F: 'ji_h',
  C: 'ji_c',
};

const BAKAZE = ['東', '南', '西', '北'];
const BAKAZE_TO_STR = {
  E: '東',
  S: '南',
  W: '西',
  N: '北',
};

const ServerName = '127.0.0.1';
const ServerPort = 9292;
const Kyokus = [];
let CurrentKyokuId = -1;
let CurrentViewpoint = 0;
const PlayersInfo = [{}, {}, {}, {}];
// TODO: parse start_game action message to extract the exact player ID.
let PlayerName = 'kkri-client';
let MyPlayerId;
let GameRoom = 'default';
let DrawnTileClicked = false;
let ClickedTileType = null;
let ClickedTileIndex = -1;
let WaitingTileDiscarded = false;
let AutoPlay = false;
let RoundEnded = false;

const sleep = (msec) => new Promise((resolve) => setTimeout(resolve, msec));

const parsePai = function (pai) {
  if (pai.match(/^([1-9])(.)(r)?$/)) {
    return {
      type: RegExp.$2,
      number: parseInt(RegExp.$1, 10),
      red: RegExp.$3,
    };
  }
  return {
    type: 't',
    number: TSUPAIS.indexOf(pai),
    red: false,
  };
};

const paiToImageUrl = function (pai, pose) {
  let ext;
  let name;
  if (pai) {
    if (pai === '?') {
      name = 'bk';
      ext = 'gif';
    } else {
      const parsedPai = parsePai(pai);
      if (parsedPai.type === 't') {
        name = TSUPAI_TO_IMAGE_NAME[pai];
      } else {
        name = `${parsedPai.type}s${parsedPai.number}${parsedPai.red ? 'r' : ''}`;
      }
      ext = parsedPai.red ? 'png' : 'gif';
    }
    if (pose === undefined) {
      pose = 1;
    }
    return `${IMAGE_PATH}/p_${name}_${pose}.${ext}`;
  }
  return `${IMAGE_PATH}/blank.png`;
};

const cloneBoard = function (board) {
  const newBoard = {};
  Object.keys(board).forEach((bk) => {
    const bv = board[bk];
    if (bk === 'players') {
      newBoard[bk] = [];
      bv.forEach((player) => {
        const newPlayer = {};
        Object.keys(player).forEach((pk) => newPlayer[pk] = player[pk]);
        newBoard[bk].push(newPlayer);
      });
    } else {
      newBoard[bk] = bv;
    }
  });
  return newBoard;
};

const deleteTehai = function (player, pai) {
  player.tehais = player.tehais.concat([]);
  let idx = player.tehais.lastIndexOf(pai);
  if (idx < 0) {
    idx = player.tehais.lastIndexOf('?');
  }
  if (idx < 0) {
    throw new Error('pai not in tehai');
  }
  player.tehais[idx] = null;
  return player.tehais[idx];
};

const comparePais = function (lhs, rhs) {
  const parsedLhs = parsePai(lhs);
  const lhsRep = parsedLhs.type + parsedLhs.number + (parsedLhs.red ? '1' : '0');
  const parsedRhs = parsePai(rhs);
  const rhsRep = parsedRhs.type + parsedRhs.number + (parsedRhs.red ? '1' : '0');
  if (lhsRep < rhsRep) {
    return -1;
  }
  if (lhsRep > rhsRep) {
    return 1;
  }
  return 0;
};

function removeNullTiles(tehais) {
  const results = [];
  tehais.forEach((pai) => {
    if (pai) {
      results.push(pai);
    }
  });
  return results;
}

const ripai = function (player) {
  if (!player.tehais) return;
  player.tehais = removeNullTiles(player.tehais);
  player.tehais.sort(comparePais);
};

function attachClickListener(tileImage) {
  tileImage.classList.add('mypai');
  tileImage.addEventListener('click', function () {
    ClickedTileType = this.getAttribute('type');
    ClickedTileIndex = parseInt(this.getAttribute('index'), 10);
    console.log(`clicked ${ClickedTileType} at ${ClickedTileIndex}`);
    DrawnTileClicked = this.classList.contains('tsumo-hai');
    if (ClickedTileType !== 'null' && WaitingTileDiscarded) {
      WaitingTileDiscarded = false;
    }
  });
}

function createTileImage(pai, index, mypai = false) {
  const image = document.createElement('img');
  image.setAttribute('src', paiToImageUrl(pai, 1));
  image.classList.add('pai');
  image.setAttribute('type', pai);
  image.setAttribute('index', index);
  image.classList.add('tile');
  if (mypai) {
    attachClickListener(image);
  }
  return image;
}

function renderTile(tileView, tile, index, pose = undefined, myTile = false) {
  if (pose === undefined) {
    pose = 1;
  }
  tileView.setAttribute('src', paiToImageUrl(tile, pose));
  switch (pose) {
    case 1:
      tileView.classList.add('pai');
      break;
    case 3:
      tileView.classList.add('laid-pai');
      break;
    default:
      throw new Error('Unknown tile pose');
  }
  tileView.setAttribute('type', tile);
  tileView.setAttribute('index', index);
  tileView.classList.remove('tsumo-hai');
  if (myTile) {
    tileView.classList.add('mypai');
  }
}

function adjustTileArray(tilesView, length, mypai = false) {
  const tileImages = tilesView.find('img').get();
  if (tileImages.length > length) {
    const toBeRemoved = tileImages.slice(length);
    for (let i = toBeRemoved.length - 1; i >= 0; i -= 1) {
      toBeRemoved[i].parentNode.removeChild(toBeRemoved[i]);
    }
  } else if (tileImages.length < length) {
    for (let i = length - tileImages.length - 1; i >= 0; i -= 1) {
      const tileImage = document.createElement('img');
      tileImage.classList.add('tile');
      if (mypai) {
        attachClickListener(tileImage);
      }
      tilesView.append($(tileImage));
    }
  }
}

const renderPais = function (pais, view, poses, mypai = false) {
  pais || (pais = []);
  poses || (poses = []);
  adjustTileArray(view, pais.length, mypai);
  const tileImages = view.find('img');
  for (let i = 0; i < pais.length; i += 1) {
    renderTile(tileImages.get(i), pais[i], i, poses[i], mypai);
  }
};

const renderHo = function (player, offset, pais, view) {
  const riichiIndex = (player.riichiHoIndex === null) ?
    null :
    player.riichiHoIndex - offset;
  adjustTileArray(view, pais.length);
  const tileImages = view.find('img');
  for (let i = 0; i < pais.length; i += 1) {
    renderTile(tileImages.get(i), pais[i], i, i === riichiIndex ? 3 : 1);
  }
};

const getCurrentKyoku = function () {
  return Kyokus[CurrentKyokuId];
};

function getCurrentBoard() {
  const kyoku = getCurrentKyoku();
  return (kyoku && kyoku.actions.length > 0) ?
    kyoku.actions[kyoku.actions.length - 1].board :
    null;
}

function getCurrentPlayer() {
  const {
    actions
  } = getCurrentKyoku();
  return actions[actions.length - 1].board.players[MyPlayerId];
}

function getCurrentTehais() {
  return getCurrentPlayer().tehais;
};

function createBoard(action) {
  let previousBoard = null;
  if (CurrentKyokuId > 0) {
    const previousKyokuActions = Kyokus[CurrentKyokuId - 1].actions;
    previousBoard = previousKyokuActions[previousKyokuActions.length - 1].board;
  }
  const board = {
    players: [],
    doraMarkers: [action.dora_marker],
  };
  for (let i = 0; i < 4; i += 1) {
    board.players.push({
      tehais: action.tehais[i],
      furos: [],
      ho: [],
      score: (previousBoard) ? previousBoard.players[i].score : 25000,
      riichi: false,
      riichiHoIndex: null,
    });
  }
  return board;
}

function cloneCurrentBoard() {
  return cloneBoard(getCurrentBoard());
}

function renderPlayerStatus(statusView, player, playerId, scoreDelta) {
  let windId = (playerId - getCurrentKyoku().kyokuNum + 5) % 4;
  statusView.text(scoreDelta === 0
    ? `${BAKAZE[windId]}  ${PlayersInfo[playerId].name}  ${player.score}`
    : `${BAKAZE[windId]}  ${PlayersInfo[playerId].name}  ${player.score}  (${scoreDelta > 0 ? '+' : ''}${scoreDelta})`);
}

function renderPlayerPossibleActions(callsView, socket, possible_actions) {
  possible_actions.forEach((pa) => {
    let consumedTiles = (pa.consumed) ? ` + ${pa.consumed}` : "";
    callsView.append(
      $(document.createElement('input')).prop({
        type: 'button',
        id: pa.type,
        value: pa.type,
        title: `${pa.pai}${consumedTiles}`,
        className: 'possible-action'
      }).on('click', () => {
        if (WaitingTileDiscarded) {
          WaitingTileDiscarded = false;
          socket.send(JSON.stringify(pa));
        }
      })
    );
    WaitingTileDiscarded = true;
  });
}

function renderPlayerTehais(tehaiView, player, playerId, drawn = false) {
  const tehaisView = tehaiView.find('.tehais');
  if (!player.tehais) {
    renderPais([], tehaisView);
  } else {
    const myHais = playerId === MyPlayerId;
    if (drawn && player.tehais.filter(val => val).length % 3 === 2) {
      const maxTehaiId = player.tehais.length - 1;
      renderPais(player.tehais.slice(0, maxTehaiId), tehaisView, [], myHais);
      const drawnTile = createTileImage(player.tehais[maxTehaiId], maxTehaiId, myHais);
      drawnTile.classList.add('tsumo-hai');
      tehaisView.append($(drawnTile));
    } else {
      renderPais(player.tehais, tehaisView, [], myHais);
    }
  }
}

function renderYakus(yakuView, yakus) {
  yakuView.text(yakus.map(yaku => yaku[0]).join('  '));
}

function renderTenpaiTehais(tehaiView, tiles) {
  const tehaisView = tehaiView.find('.tehais');
  renderPais(tiles, tehaisView, []);
}

function renderPlayerHo(view, player) {
  const ho = player.ho || [];
  const hoRows = view.find('.ho-row')
  renderHo(player, 0, ho.slice(0, 6), hoRows.eq(0));
  renderHo(player, 6, ho.slice(6, 12), hoRows.eq(1));
  renderHo(player, 12, ho.slice(12), hoRows.eq(2));
}

function extendFuroArray(furoView, length) {
  const tileImages = furoView.find('img').get();
  if (tileImages.length < length) {
    for (let i = length - tileImages.length - 1; i >= 0; i -= 1) {
      const tileImage = document.createElement('img');
      tileImage.classList.add('tile');
      furoView.prepend($(tileImage));
    }
  }
}

function renderPlayerFuro(view, player, playerId) {
  const furoLength = player.furos.length;
  if (player.furos) {
    let j = furoLength - 1;
    const furoTiles = [];
    const furoTilePoses = [];
    let pais;
    let poses;
    while (j >= 0) {
      const furo = player.furos[j];
      if (furo.type === 'ankan') {
        pais = ['?'].concat(furo.consumed.slice(0, 2)).concat(['?']);
        poses = [1, 1, 1, 1];
      } else {
        const dir = (4 + furo.target - playerId) % 4;
        const laidPos = (furo.type === 'daiminkan' || furo.type === 'kakan')
          ? [null, 3, 1, 0][dir]
          : [null, 2, 1, 0][dir];
        pais = furo.consumed.concat([]);
        poses = [1, 1, 1];
        [].splice.apply(pais, [laidPos, laidPos - laidPos].concat([furo.taken]));
        [].splice.apply(poses, [laidPos, laidPos - laidPos].concat([3]));
      }
      furoTiles.push(...pais);
      furoTilePoses.push(...poses);
      j -= 1;
    }
    const furoView = view.find('.furos');
    extendFuroArray(furoView, furoLength);
    renderPais(furoTiles, furoView, furoTilePoses);
  }
}

function renderPlayerBoard(player, playerId, action, socket) {
  const position = (playerId - CurrentViewpoint + 4) % 4;
  const view = $(`#player-${position}`);
  const drawn = ['tsumo', 'riichi', 'ankan', 'daiminkan', 'kakan'].includes(action.type);
  const scoreDelta = action.deltas ? action.deltas[playerId] : 0;
  renderPlayerStatus(view.find('.status'), player, playerId, scoreDelta);
  const notificationView = view.find('.notification');
  notificationView.html('');
  if (playerId === MyPlayerId) {
    if (action.possible_actions) {
      renderPlayerPossibleActions(notificationView, socket, action.possible_actions);
    } else if (action.type === 'hora' && action.actor === MyPlayerId) {
      renderYakus(notificationView, action.yakus);
    }
    renderPlayerTehais(view, player, playerId, drawn);
  } else {
    if (action.type === 'hora' && action.actor === playerId) {
      renderYakus(notificationView, action.yakus);
      renderTenpaiTehais(view, action.hora_tehais);
    } else if (action.type === 'ryukyoku' && action.tenpais[playerId]) {
      renderTenpaiTehais(view, action.tehais[playerId]);
    } else {
      renderPlayerTehais(view, player, playerId, drawn);
    }
  }
  renderPlayerHo(view, player);
  renderPlayerFuro(view, player, playerId);
}

function renderWanpais(action) {
  const wanpais = ['?', '?', '?', '?', '?', '?'];
  for (let i = 0; i < action.board.doraMarkers.length; i += 1) {
    wanpais[i + 2] = action.board.doraMarkers[i];
  }
  renderPais(wanpais, $('.wanpai-row'));
  const uradoras = []
  if (action.type === 'hora') {
    for (let i = 0; i < action.uradora_markers.length; i += 1) {
      uradoras.push(action.uradora_markers[i]);
    }
  }
  renderPais(uradoras, $('.uradora-row'));
}

function renderGameState(action) {
  if (action.type === 'start_kyoku') {
    const kyoku = getCurrentKyoku();
    $('#round-state').text(`${BAKAZE_TO_STR[kyoku.bakaze]}${kyoku.kyokuNum}局  ${kyoku.honba}本場`);
    $('#riichi-deposit').text(`供託${parseInt(action.kyotaku, 10) * 1000}`);
    $('#round-end').text('');
  } else if (action.type === 'riichi_accepted') {
    $('#riichi-deposit').text(`供託${parseInt(action.kyotaku, 10) * 1000}`);
  } else if (action.type === 'hora') {
    $('#round-end').text(`和了  ${action.fu}符${action.fan}翻  ${action.hora_points}`)
  } else if (action.type === 'ryukyoku') {
    $('#round-end').text('流局')
  }
}

const renderAction = function (action, socket) {
  console.log(action);
  for (let i = 0; i < 4; i += 1) {
    const player = action.board.players[i];
    renderPlayerBoard(player, i, action, socket);
  }
  renderWanpais(action);
  renderGameState(action);
};

function gameStarted(action) {
  CurrentViewpoint = action.id;
  for (let i = 0; i < 4; i += 1) {
    PlayersInfo[i].name = action.names[i];
  }
  action.board = null;
}

function roundStarted(action) {
  RoundEnded = false;
  CurrentKyokuId += 1;
  Kyokus.push({
    actions: [],
    bakaze: action.bakaze,
    kyokuNum: action.kyoku,
    honba: action.honba,
  });
  action.board = createBoard(action);
}

function tileDrawn(action) {
  const actorPlayer = action.board.players[action.actor];
  actorPlayer.tehais.push(action.pai);
}

function tileDiscarded(action) {
  const actorPlayer = action.board.players[action.actor];
  deleteTehai(actorPlayer, action.pai);
  actorPlayer.ho.push(action.pai);
}

function riichiCalled(action) {
  const actorPlayer = action.board.players[action.actor];
  actorPlayer.riichiHoIndex = actorPlayer.ho.length;
}

function riichiAccepted(action) {
  const actorPlayer = action.board.players[action.actor];
  actorPlayer.riichi = true;
}

function openMeldingCalled(action) {
  const actorPlayer = action.board.players[action.actor];
  const targetPlayer = action.board.players[action.target];
  targetPlayer.ho = targetPlayer.ho.slice(0, targetPlayer.ho.length - 1);
  action.consumed.forEach((tile) => deleteTehai(actorPlayer, tile));
  actorPlayer.furos.push({
    type: action.type,
    taken: action.pai,
    consumed: action.consumed,
    target: action.target,
  });
  if (myAction(action)) {
    WaitingTileDiscarded = true;
  }
}

function ankanCalled(action) {
  const actorPlayer = action.board.players[action.actor];
  action.consumed.forEach((tile) => deleteTehai(actorPlayer, tile));
  actorPlayer.furos.push({
    type: action.type,
    consumed: action.consumed,
  });
}

const removeRed = function (pai) {
  if (!pai) {
    return null;
  }
  if (pai.match(/^(.+)r$/)) {
    return RegExp.$1;
  }
  return pai;
};

function same(tileA, tileB) {
  return removeRed(tileA) === removeRed(tileB);
}

function kakanCalled(action) {
  const actorPlayer = action.board.players[action.actor];
  deleteTehai(actorPlayer, action.pai);
  actorPlayer.furos = actorPlayer.furos.concat([]);
  const { furos } = actorPlayer;
  for (let i = 0; i < furos.length; i += 1) {
    if (furos[i].type === 'pon' && same(furos[i].taken, action.pai)) {
      furos[i] = {
        type: 'kakan',
        taken: action.pai,
        consumed: action.consumed,
        target: furos[i].target,
      };
    }
  }
}

function doraAdded(action) {
  action.board.doraMarkers.push(action.dora_marker);
}

function applyRoundAction(action) {
  action.board = cloneCurrentBoard();
  ClickedTileIndex = -1;
  switch (action.type) {
    case 'tsumo':
      tileDrawn(action);
      break;
    case 'dahai':
      tileDiscarded(action);
      break;
    case 'riichi':
      riichiCalled(action);
      break;
    case 'riichi_accepted':
      riichiAccepted(action);
      break;
    case 'chi':
    case 'pon':
    case 'daiminkan':
      openMeldingCalled(action);
      break;
    case 'ankan':
      ankanCalled(action);
      break;
    case 'kakan':
      kakanCalled(action);
      break;
    case 'dora':
      doraAdded(action);
      break;
    case 'end_game':
    case 'end_kyoku':
    case 'hora':
    case 'ryukyoku':
    case 'error':
      break;
    default:
      throw new Error(`unknown action: ${action.type}`);
  }
}

function applyAction(action) {
  if (action.type === 'start_game') {
    gameStarted(action);
  } else if (action.type === 'start_kyoku') {
    roundStarted(action);
  } else {
    applyRoundAction(action);
  }
}

function updateScores(action) {
  if (action.scores) {
    for (let i = 0; i < 4; i += 1) {
      action.board.players[i].score = action.scores[i];
    }
  }
}

function sortTiles(action) {
  for (let i = 0; i < 4; i += 1) {
    if (action.actor !== undefined && i !== action.actor) {
      ripai(action.board.players[i]);
    }
  }
}

const loadAction = function (action, socket) {
  console.log(action);
  applyAction(action);
  const kyoku = getCurrentKyoku();
  if (kyoku) {
    updateScores(action);
    sortTiles(action);
    kyoku.actions.push(action);
    renderAction(action, socket);
  }
};

function joinGame(socket, playerName, gameRoom) {
  socket.send(JSON.stringify({
    type: 'join',
    name: playerName,
    room: gameRoom,
  }));
}

function replyNone(socket) {
  socket.send(JSON.stringify({ type: 'none' }));
}

function initGame(action, socket) {
  MyPlayerId = action.id;
  CurrentKyokuId = -1;
  console.log(action);
  loadAction(action);
  replyNone(socket);
}

function handleError(action, socket) {
  socket.close();
}

function myAction(action) {
  return action.actor === MyPlayerId;
}

function discardTileAutomatically(action, socket) {
  socket.send(JSON.stringify({
    type: 'dahai',
    actor: MyPlayerId,
    pai: action.pai,
    tsumogiri: true,
  }));
}

async function waitTileClicked() {
  WaitingTileDiscarded = true;
  ClickedTileIndex = -1;
  while (ClickedTileIndex < 0) {
    // eslint-disable-next-line no-await-in-loop
    await sleep(200);
    if (ClickedTileIndex >= 0 && ClickedTileType === 'null') {
      ClickedTileIndex = -1;
    }
  }
  WaitingTileDiscarded = false;
}

function discardClickedTile(socket) {
  socket.send(JSON.stringify({
    type: 'dahai',
    actor: MyPlayerId,
    pai: ClickedTileType,
    tsumogiri: DrawnTileClicked
  }));
}

function takePossibleActionToDrawnTile(action, socket) {
  let done = false;
  if (action.possible_actions.length == 0) {
    if (getCurrentPlayer().riichi) {
      socket.send(JSON.stringify({
        type: 'dahai',
        actor: MyPlayerId,
        pai: action.pai,
        tsumogiri: true
      }));
      done = true;
    }
  }
  if (!done) {
    waitTileClicked().then(() => {
      if (!RoundEnded) {
        discardClickedTile(socket);
      }
    });
  }
}

function takeActionOnTileDrawn(action, socket) {
  if (myAction(action)) {
    if (AutoPlay) {
      discardTileAutomatically(action, socket);
    } else {
      takePossibleActionToDrawnTile(action, socket);
    }
  } else {
    replyNone(socket);
  }
}

async function waitClicked() {
  while (WaitingTileDiscarded) {
    // eslint-disable-next-line no-await-in-loop
    await sleep(200);
  }
  WaitingTileDiscarded = false;
}

function takePossibleActionToDiscardedTile(action, socket) {
  if (action.possible_actions && action.possible_actions.length > 0) {
    waitClicked().then(() => {
      if (ClickedTileIndex >= 0) {
        replyNone(socket);
      }
    });
  } else {
    replyNone(socket);
  }
}

function takeActionOnTileDiscarded(action, socket) {
  if (myAction(action)) {
    replyNone(socket);
  } else {
    takePossibleActionToDiscardedTile(action, socket);
  }
}

async function waitDiscardableTileClicked(action) {
  ClickedTileIndex = -1;
  WaitingTileDiscarded = true;
  while (ClickedTileIndex < 0) {
    // eslint-disable-next-line no-await-in-loop
    await sleep(200);
    if (ClickedTileIndex >= 0) {
      if (ClickedTileType === 'null') {
        ClickedTileIndex = -1;
      } else {
        const clickedTile = getCurrentTehais()[ClickedTileIndex];
        if (action.cannot_dahai && action.cannot_dahai.includes(clickedTile)) {
          console.log(`cannot discard ${clickedTile} to keep tenpai`);
          ClickedTileIndex = -1;
          WaitingTileDiscarded = true;
        }
      }
    }
  }
  WaitingTileDiscarded = false;
}

function takeActionOnCall(action, socket) {
  if (myAction(action)) {
    waitDiscardableTileClicked(action).then(() => discardClickedTile(socket));
  } else {
    replyNone(socket);
  }
}

function acknowledgeResult(socket) {
  waitTileClicked().then(() => replyNone(socket));
}

function takeAction(action, socket) {
  switch (action.type) {
    case 'tsumo':
      takeActionOnTileDrawn(action, socket);
      break;
    case 'dahai':
      takeActionOnTileDiscarded(action, socket);
      break;
    case 'chi':
    case 'pon':
    case 'riichi':
      takeActionOnCall(action, socket);
      break;
    case 'hora':
    case 'ryukyoku':
      RoundEnded = true;
      acknowledgeResult(socket);
      break;
    default:
      replyNone(socket);
  }
}

function serverConnected(event, socket) {
  console.log(`Connected to server ${ServerName}:${ServerPort}`);
  console.log(`Autoplay: ${AutoPlay}`);
  socket.send(JSON.stringify({
    type: 'join',
    name: PlayerName,
    room: GameRoom,
  }));
}

function messageReceived(event, socket) {
  const action = JSON.parse(event.data);
  switch (action.type) {
    case 'hello':
      joinGame(socket, PlayerName, GameRoom);
      break;
    case 'start_game':
      initGame(action, socket);
      break;
    case 'error':
      handleError(action, socket);
      break;
    default:
      loadAction(action, socket);
      takeAction(action, socket);
  }
}

function gameClosed(event) {
  console.log('game ended');
}

function gameAborted(event) {
  alert(event.data);
}

$(() => {
  $('#join-button').on('click', () => {
    const url = `ws://${ServerName}:${ServerPort}`;
    console.log(`Connecting ${url}`);
    const socket = new WebSocket(url);
    socket.onopen = (event) => serverConnected(event, socket);
    socket.onmessage = (event) => messageReceived(event, socket);
    socket.onclose = (event) => gameClosed(event);
    socket.onerror = (event) => gameAborted(event);
  });
  $('#autoplay').on('click', () => {
    AutoPlay = document.querySelector('#autoplay').checked;
  });
});
