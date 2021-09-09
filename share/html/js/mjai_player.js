/* eslint func-names: ["error", "as-needed"] */

const IMAGE_PATH = './images';

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
let TileIndex = -1;
let DrawnTileIndex = -1;
let WaitingTileDiscarded = false;
let AutoPlay = false;

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
        Object.keys(player).forEach((pk) => {
          newPlayer[pk] = player[pk];
        });
        newBoard[bk].push(newPlayer);
      });
    } else {
      newBoard[bk] = bv;
    }
  });
  return newBoard;
};

const removeRed = function (pai) {
  if (!pai) {
    return null;
  }
  if (pai.match(/^(.+)r$/)) {
    return RegExp.$1;
  }
  return pai;
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

const ripai = function (player) {
  if (!player.tehais) return;

  player.tehais = (function removeNullTiles() {
    const results = [];
    player.tehais.forEach((pai) => {
      if (pai) {
        results.push(pai);
      }
    });
    return results;
  }());
  player.tehais.sort(comparePais);
};

const renderPai = function (pai, view, index, pose = undefined, mypai = false) {
  if (pose === undefined) {
    pose = 1;
  }
  view.attr('src', paiToImageUrl(pai, pose));
  view.attr('index', index);
  if (mypai && !view.hasClass('mypai')) {
    view.addClass('mypai');
    view.on('click', function dahai() {
      console.log('clicked!', $(this));
      if (WaitingTileDiscarded) {
        TileIndex = parseInt($(this).attr('index'), 10);
        WaitingTileDiscarded = false;
      }
    });
  }
  switch (pose) {
    case 1:
      view.addClass('pai');
      return view.removeClass('laid-pai');
    case 3:
      view.addClass('laid-pai');
      return view.removeClass('pai');
    default:
      throw new Error('unknown pose');
  }
};

const renderPais = function (pais, view, poses, mypai = false) {
  pais || (pais = []);
  poses || (poses = []);
  view.resize(pais.length);
  const ref = pais.length;
  for (let i = 0; ref >= 0 ? i < ref : i > ref; i += ref >= 0 ? 1 : -1) {
    renderPai(pais[i], view.at(i), i, poses[i], mypai);
  }
};

const renderHo = function (player, offset, pais, view) {
  const riichiIndex = (player.riichiHoIndex === null)
    ? null
    : player.riichiHoIndex - offset;
  view.resize(pais.length);
  const ref = pais.length;
  for (let i = 0; ref >= 0 ? i < ref : i > ref; i += ref >= 0 ? 1 : -1) {
    renderPai(pais[i], view.at(i), i, i === riichiIndex ? 3 : 1);
  }
};

const getCurrentKyoku = function () {
  return Kyokus[CurrentKyokuId];
};

function getCurrentBoard() {
  const kyoku = getCurrentKyoku();
  return (kyoku && kyoku.actions.length > 0)
    ? kyoku.actions[kyoku.actions.length - 1].board
    : null;
}

function getCurrentPlayer() {
  const { actions } = getCurrentKyoku();
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

function getClickedTile() {
  const tehais = getCurrentTehais();
  const tehaiLength = tehais.length;
  let dahai = null;
  if (TileIndex < tehaiLength) {
    dahai = tehais[TileIndex];
  } else {
    console.error(`pai index ${TileIndex} is out of ${tehais}`);
  }
  return dahai;
}

function discardedDrawnTile() {
  return TileIndex === DrawnTileIndex;
}

function renderActionLog(action) {
  const actionList = document.querySelector('#action-elements');
  actionList.innerHTML = '';
  Object.keys(action).forEach((k) => {
    if (k !== 'board' && k !== 'logs') {
      const termItem = document.createElement('dt');
      termItem.appendChild(document.createTextNode(k));
      const descItem = document.createElement('dd');
      descItem.appendChild(document.createTextNode(JSON.stringify(action[k])));
      actionList.appendChild(termItem);
      actionList.appendChild(descItem);
    }
  });
  if (action.logs) {
    actionList.appendChild(document.createElement('br'));
    Object.keys(action.logs).forEach((k) => {
      const termItem = document.createElement('dt');
      termItem.appendChild(document.createTextNode('logs'));
      const descItem = document.createElement('dd');
      descItem.appendChild(document.createTextNode(action.logs[k]));
      actionList.appendChild(termItem);
      actionList.appendChild(descItem);
    });
  }
}

function renderPlayerStatus(view, player, playerId) {
  view.status.text(`${BAKAZE[playerId]}  ${PlayersInfo[playerId].name}  ${player.score}`);
}

function renderPlayerPossibleActions(view, socket, possible_actions) {
  view.calls.html('');
  possible_actions.forEach((pa) => {
    view.calls.append(
      $(document.createElement('input')).prop({
        type: 'button',
        id: pa.type,
        value: pa.type,
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

function renderPlayerTehais(view, player, playerId) {
  if (!player.tehais) {
    renderPais([], view.tehais);
    view.tsumoPai.hide();
  } else if (player.tehais.length % 3 === 2) {
    const myHais = playerId === MyPlayerId;
    const maxTehaiId = player.tehais.length - 1;
    renderPais(player.tehais.slice(0, maxTehaiId), view.tehais, [], myHais);
    view.tsumoPai.show();
    renderPai(player.tehais[maxTehaiId], view.tsumoPai, maxTehaiId, 1, myHais);
  } else {
    renderPais(player.tehais, view.tehais);
    view.tsumoPai.hide();
  }
}

function renderPlayerHo(view, player) {
  const ho = player.ho || [];
  renderHo(player, 0, ho.slice(0, 6), view.hoRows.at(0).pais);
  renderHo(player, 6, ho.slice(6, 12), view.hoRows.at(1).pais);
  renderHo(player, 12, ho.slice(12), view.hoRows.at(2).pais);
}

function renderPlayerFuro(view, player, playerId) {
  view.furos.resize(player.furos.length);
  if (player.furos) {
    let j = player.furos.length - 1;
    let pais;
    let poses;
    while (j >= 0) {
      const furo = player.furos[j];
      const furoView = view.furos.at(player.furos.length - 1 - j);
      if (furo.type === 'ankan') {
        pais = ['?'].concat(furo.consumed.slice(0, 2)).concat(['?']);
        poses = [1, 1, 1, 1];
      } else {
        const dir = (4 + furo.target - playerId) % 4;
        const laidPos = (furo.type === 'daiminkan' || furo.type === 'kakan')
          ? [null, 3, 1, 0][dir] : [null, 2, 1, 0][dir];
        pais = furo.consumed.concat([]);
        poses = [1, 1, 1];
        [].splice.apply(pais, [laidPos, laidPos - laidPos].concat([furo.taken]));
        [].splice.apply(poses, [laidPos, laidPos - laidPos].concat([3]));
      }
      renderPais(pais, furoView.pais, poses);
      j -= 1;
    }
  }
}

function renderPlayerBoard(player, playerId, action, socket) {
  const view = window.Dytem.players.at((playerId - CurrentViewpoint + 4) % 4);
  renderPlayerStatus(view, player, playerId);
  if (playerId === MyPlayerId) {
    renderPlayerPossibleActions(view, socket,
      (action.possible_actions) ? action.possible_actions : []);
  }
  renderPlayerTehais(view, player, playerId);
  renderPlayerHo(view, player);
  renderPlayerFuro(view, player, playerId);
}

function renderWanpais(action) {
  const wanpais = ['?', '?', '?', '?', '?', '?'];
  const ref3 = action.board.doraMarkers.length;
  for (let i = 0; ref3 >= 0 ? i < ref3 : i > ref3; i += ref3 >= 0 ? 1 : -1) {
    wanpais[i + 2] = action.board.doraMarkers[i];
  }
  renderPais(wanpais, window.Dytem.wanpais);
}

function renderGameState(action) {
  if (action.type == 'start_kyoku') {
    const kyoku = getCurrentKyoku();
    $('#round-state').text(`${BAKAZE_TO_STR[kyoku.bakaze]}${kyoku.kyokuNum}局  ${kyoku.honba}本場`);
    $('#riichi-deposit').text(`供託${parseInt(action.kyotaku, 10) * 1000}`);
  } else if (action.type == 'riichi_accepted') {
    $('#riichi-deposit').text(`供託${parseInt(action.kyotaku, 10) * 1000}`);
  }
}

const renderAction = function (action, socket) {
  console.log(action);
  renderActionLog(action);
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
  actorPlayer = action.board.players[action.actor];
  DrawnTileIndex = actorPlayer.tehais.length;
  actorPlayer.tehais.push(action.pai);
}

function tileDiscarded(action) {
  actorPlayer = action.board.players[action.actor];
  deleteTehai(actorPlayer, action.pai);
  actorPlayer.ho.push(action.pai);
}

function riichiCalled(action) {
  actorPlayer = action.board.players[action.actor];
  actorPlayer.riichiHoIndex = actorPlayer.ho.length;
}

function riichiAccepted(action) {
  actorPlayer = action.board.players[action.actor];
  actorPlayer.riichi = true;
}

function openMeldingCalled(action) {
  actorPlayer = action.board.players[action.actor];
  targetPlayer = action.board.players[action.target];
  targetPlayer.ho = targetPlayer.ho.slice(0, targetPlayer.ho.length - 1);
  action.consumed.forEach((tile) => { deleteTehai(actorPlayer, tile); });
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
  actorPlayer = action.board.players[action.actor];
  action.consumed.forEach((tile) => {
    deleteTehai(actorPlayer, tile);
  });
  actorPlayer.furos.push({
    type: action.type,
    consumed: action.consumed,
  });
}

function kakanCalled(action) {
  actorPlayer = action.board.players[action.actor];
  deleteTehai(actorPlayer, action.pai);
  actorPlayer.furos = actorPlayer.furos.concat([]);
  const { furos } = actorPlayer;
  const ref2 = furos.length;
  for (let i = 0; ref2 >= 0 ? i < ref2 : i > ref2; i += ref2 >= 0 ? 1 : -1) {
    if (furos[i].type === 'pon' && removeRed(furos[i].taken) === removeRed(action.pai)) {
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
  TileIndex = -1;
  DrawnTileIndex = -1;
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

const initPlayerInfo = async function () {
  window.Dytem.init();
  // i: player id   0 <= i <= 3
  // j: ho row id   0 <= j <= 2
  for (let i = 0; i < 4; i += 1) {
    const playerView = window.Dytem.players.append();
    playerView.addClass(`player-${i}`);
    for (let j = 0; j < 3; j += 1) {
      playerView.hoRows.append();
    }
    playerView.status.append();
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
  initPlayerInfo();
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
  TileIndex = -1;
  while (TileIndex < 0) {
    // eslint-disable-next-line no-await-in-loop
    await sleep(200);
  }
  WaitingTileDiscarded = false;
}

function discardClickedTile(socket) {
  socket.send(JSON.stringify({
    type: 'dahai',
    actor: MyPlayerId,
    pai: getClickedTile(),
    tsumogiri: discardedDrawnTile(),
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
        tsumogiri: true,
      }));
      done = true;
    }
  } else {
    action.possible_actions.forEach((pa) => {
      if (!done) {
        switch (pa.type) {
          case 'hora':
          case 'riichi':
            socket.send(JSON.stringify(pa));
            done = true;
            break;
          default:
        }
      }
    });
  }
  if (!done) {
    waitTileClicked().then(() => { discardClickedTile(socket); });
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
      if (TileIndex >= 0) {
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
  TileIndex = -1;
  WaitingTileDiscarded = true;
  while (TileIndex < 0) {
    // eslint-disable-next-line no-await-in-loop
    await sleep(200);
    if (TileIndex >= 0) {
      const clickedTile = getCurrentTehais()[TileIndex];
      if (action.cannot_dahai && action.cannot_dahai.includes(clickedTile)) {
        console.log(`cannot discard ${clickedTile} to keep tenpai`);
        TileIndex = -1;
        WaitingTileDiscarded = true;
      }
    }
  }
  WaitingTileDiscarded = false;
}

function takeActionOnCall(action, socket) {
  if (myAction(action)) {
    waitDiscardableTileClicked(action).then(() => { discardClickedTile(socket); });
  } else {
    replyNone(socket);
  }
}

function acknowledgeResult(socket) {
  waitTileClicked().then(() => { replyNone(socket); });
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
    case 'daiminkan':
    case 'riichi':
      takeActionOnCall(action, socket);
      break;
    case 'hora':
    case 'ryukyoku':
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
  console.log(event.data);
}

function gameAborted(event) {
  alert(event.data);
}

function startGame() {
  const url = `ws://${ServerName}:${ServerPort}`;
  console.log(`Connecting ${url}`);
  const socket = new WebSocket(url);
  socket.onopen = (event) => serverConnected(event, socket);
  socket.onmessage = (event) => messageReceived(event, socket);
  socket.onclose = (event) => gameClosed(event);
  socket.onerror = (event) => gameAborted(event);
}

function toggleAutoPlay() {
  AutoPlay = document.querySelector('#autoplay').checked;
}
