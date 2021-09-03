/* eslint func-names: ["error", "as-needed"] */

// const IMAGE_PATH = 'http://gimite.net/mjai/images';
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

let Kyokus = [];
let CurrentKyokuId = -1;
let CurrentViewpoint = 0;
let PlayersInfo = [{}, {}, {}, {}];
// TODO: parse start_game action message to extract the exact player ID.
let MyPlayerId;
let TileIndex;
let WaitingDiscard = false;
let AutoPlay = false;

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

const sortPais = function (pais) {
  return pais.sort(comparePais);
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

function createBoard(action, previousBoard) {
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
      reach: false,
      reachHoIndex: null,
    });
  }
  return board;
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

const ripai = function (player) {
  if (player.tehais) {
    player.tehais = (function removeNullTiles() {
      const results = [];
      player.tehais.forEach((pai) => {
        if (pai) {
          results.push(pai);
        }
      });
      return results;
    }());
    return sortPais(player.tehais);
  }
};

function gameStarted(action) {
  CurrentViewpoint = action.id;
  for (let i = 0; i < 4; i += 1) {
    PlayersInfo[i].name = action.names[i];
  }
}

const loadAction = function (action) {
  console.log(action);
  let board = null;
  let kyoku = null;
  let actorPlayer = null;
  let targetPlayer = null;
  if (Kyokus.length > 0) {
    kyoku = Kyokus[Kyokus.length - 1];
    board = cloneBoard(kyoku.actions[kyoku.actions.length - 1].board);
    actorPlayer = ('actor' in action) ? board.players[action.actor] : null;
    targetPlayer = ('target' in action) ? board.players[action.target] : null;
  }
  switch (action.type) {
    case 'start_game':
      gameStarted(action);
      break;
    case 'start_kyoku':
      CurrentKyokuId += 1;
      kyoku = {
        actions: [],
        bakaze: action.bakaze,
        kyokuNum: action.kyoku,
        honba: action.honba,
      };
      Kyokus.push(kyoku);
      board = createBoard(action, board);
      break;
    case 'tsumo':
      actorPlayer.tehais = actorPlayer.tehais.concat([action.pai]);
      break;
    case 'dahai':
      deleteTehai(actorPlayer, action.pai);
      actorPlayer.ho = actorPlayer.ho.concat([action.pai]);
      break;
    case 'reach':
      actorPlayer.reachHoIndex = actorPlayer.ho.length;
      break;
    case 'reach_accepted':
      actorPlayer.reach = true;
      break;
    case 'chi':
    case 'pon':
    case 'daiminkan': {
      targetPlayer.ho = targetPlayer.ho.slice(0, targetPlayer.ho.length - 1);
      action.consumed.forEach((tile) => {
        deleteTehai(actorPlayer, tile);
      });
      actorPlayer.furos = actorPlayer.furos.concat([
        {
          type: action.type,
          taken: action.pai,
          consumed: action.consumed,
          target: action.target,
        },
      ]);
      break;
    }
    case 'ankan': {
      action.consumed.forEach((tile) => {
        deleteTehai(actorPlayer, tile);
      });
      actorPlayer.furos = actorPlayer.furos.concat([
        {
          type: action.type,
          consumed: action.consumed,
        },
      ]);
      break;
    }
    case 'kakan': {
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
      break;
    }
    case 'dora':
      board.doraMarkers = board.doraMarkers.concat([action.dora_marker]);
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
  if (action.scores) {
    for (let i = 0; i < 4; i += 1) {
      board.players[i].score = action.scores[i];
    }
  }
  if (kyoku) {
    for (let i = 0; i < 4; i += 1) {
      if (action.actor !== undefined && i !== action.actor) {
        ripai(board.players[i]);
      }
    }
    action.board = board;
    kyoku.actions.push(action);
  }
};

const renderPai = function (pai, view, index, pose = undefined, mypai = false, cannot_dahai = undefined) {
  if (pose === undefined) {
    pose = 1;
  }
  view.attr('src', paiToImageUrl(pai, pose));
  view.attr('index', index);
  if (mypai && !view.hasClass('mypai')) {
    view.addClass('mypai');
    view.on('click', function dahai() {
      console.log('clicked!', $(this));
      if (WaitingDiscard) {
        TileIndex = parseInt($(this).attr('index'), 10);
        WaitingDiscard = false;
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

const renderPais = function (pais, view, poses, mypai = false, cannotDahai = undefined) {
  pais || (pais = []);
  poses || (poses = []);
  view.resize(pais.length);
  const ref = pais.length;
  for (let i = 0; ref >= 0 ? i < ref : i > ref; i += ref >= 0 ? 1 : -1) {
    const tile = pais[i];
    const canDiscard = !cannotDahai || !cannotDahai.includes(tile);
    renderPai(pais[i], view.at(i), i, poses[i], canDiscard && mypai);
  }
};

const renderHo = function (player, offset, pais, view) {
  const reachIndex = (player.reachHoIndex === null) ? null : player.reachHoIndex - offset;
  view.resize(pais.length);
  const ref = pais.length;
  for (let i = 0; ref >= 0 ? i < ref : i > ref; i += ref >= 0 ? 1 : -1) {
    renderPai(pais[i], view.at(i), i, i === reachIndex ? 3 : 1);
  }
};

const getCurrentKyoku = function () {
  return Kyokus[CurrentKyokuId];
};

const renderAction = function (action) {
  console.log(action);
  // const displayAction = {};
  const actionList = document.querySelector('#action-elements');
  actionList.innerHTML = '';
  Object.keys(action).forEach((k) => {
    if (k !== 'board' && k !== 'logs') {
      // displayAction[k] = action[k];
      const termItem = document.createElement('dt');
      termItem.appendChild(document.createTextNode(k));
      const descItem = document.createElement('dd');
      descItem.appendChild(document.createTextNode(JSON.stringify(action[k])));
      actionList.appendChild(termItem);
      actionList.appendChild(descItem);
    }
  });
  if (action.logs) {
    const termItem = document.createElement('dt');
    termItem.appendChild(document.createTextNode('logs'));
    const descItem = document.createElement('dd');
    descItem.appendChild(document.createTextNode(action.logs));
    actionList.appendChild(termItem);
    actionList.appendChild(descItem);
  }
  // $('#action-label').text(JSON.stringify(displayAction));
  // $('#log-label').text((action.logs && action.logs[CurrentViewpoint]) || '');
  const kyoku = getCurrentKyoku();
  for (let i = 0; i < 4; i += 1) {
    const player = action.board.players[i];
    const view = window.Dytem.players.at((i - CurrentViewpoint + 4) % 4);
    const infoView = window.Dytem.playerInfos.at(i);
    infoView.score.text(player.score);
    infoView.viewpoint.text(i === CurrentViewpoint ? '+' : '');
    if (!player.tehais) {
      renderPais([], view.tehais);
      view.tsumoPai.hide();
    } else if (player.tehais.length % 3 === 2) {
      const myHais = i === MyPlayerId;
      const maxTehaiId = player.tehais.length - 1;
      renderPais(player.tehais.slice(0, maxTehaiId), view.tehais, [], myHais, action.cannot_dahai);
      view.tsumoPai.show();
      const tile = player.tehais[maxTehaiId];
      const canDiscard = !action.cannot_dahai || !action.cannot_dahai.includes(tile);
      renderPai(player.tehais[maxTehaiId], view.tsumoPai, maxTehaiId, 1, canDiscard && myHais);
    } else {
      renderPais(player.tehais, view.tehais);
      view.tsumoPai.hide();
    }
    const ho = player.ho || [];
    renderHo(player, 0, ho.slice(0, 6), view.hoRows.at(0).pais);
    renderHo(player, 6, ho.slice(6, 12), view.hoRows.at(1).pais);
    renderHo(player, 12, ho.slice(12), view.hoRows.at(2).pais);
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
          const dir = (4 + furo.target - i) % 4;
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
  const wanpais = ['?', '?', '?', '?', '?', '?'];
  const ref3 = action.board.doraMarkers.length;
  for (let i = 0; ref3 >= 0 ? i < ref3 : i > ref3; i += ref3 >= 0 ? 1 : -1) {
    wanpais[i + 2] = action.board.doraMarkers[i];
  }
  renderPais(wanpais, window.Dytem.wanpais);
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
    const playerInfoView = window.Dytem.playerInfos.append();
    playerInfoView.index.text(BAKAZE[i]);
    playerInfoView.name.text(PlayersInfo[i].name);
  }
};

const joinGame = async function () {
  console.log('Connecting');
  const serverName = '127.0.0.1';
  const serverPort = 9292;
  const socket = new WebSocket(`ws://${serverName}:${serverPort}`);
  socket.onopen = function serverConnected(event) {
    console.log(`Connected to server ${serverName}:${serverPort}`);
    AutoPlay = document.querySelector('#autoplay').checked;
    console.log(`Autoplay: ${AutoPlay}`);
    socket.send(JSON.stringify({
      type: 'join',
      name: 'kkri-client',
      room: 'default',
    }));
  };

  socket.onmessage = async function messageReceived(event) {
    const msg = JSON.parse(event.data);
    if (msg.type === 'hello') {
      socket.send(JSON.stringify({
        type: 'join',
        name: 'kkri-client',
        room: 'default',
      }));
    } else if (msg.type === 'error') {
      socket.close();
    } else if (msg.type === 'start_game') {
      MyPlayerId = msg.id;
      console.log(msg);
      // names = msg.names;
      loadAction(msg);
      socket.send(JSON.stringify({ type: 'none' }));
      initPlayerInfo();
    } else {
      loadAction(msg);
      if (CurrentKyokuId >= 0) {
        renderAction(msg);
      }
      if (msg.type === 'start_kyoku') {
        socket.send(JSON.stringify({ type: 'none' }));
      } else if (msg.type === 'tsumo') {
        if (msg.actor === MyPlayerId) {
          if (AutoPlay) {
            socket.send(JSON.stringify({
              type: 'dahai',
              actor: MyPlayerId,
              pai: msg.pai,
              tsumogiri: true,
            }));
          } else {
            for (action of msg.possible_actions) {
              if (action.type === 'hora') {
                socket.send(JSON.stringify(action));
                return;
              }
              if (action.type === 'reach') {
                socket.send(JSON.stringify(action));
                return;
              }
            }
            TileIndex = -1;
            WaitingDiscard = true;
            while (TileIndex < 0) {
              await sleep(200);
            }
            WaitingDiscard = false;
            const { actions } = getCurrentKyoku();
            const { tehais } = actions[actions.length - 1].board.players[MyPlayerId];
            const tehaiLength = tehais.length;
            let dahai = null;
            if (TileIndex < tehaiLength) {
              dahai = tehais[TileIndex];
              console.log(`dahai ${dahai}`);
            } else {
              console.error(`pai index ${TileIndex} is out of ${tehais}`);
            }
            socket.send(JSON.stringify({
              type: 'dahai',
              actor: MyPlayerId,
              pai: dahai,
              tsumogiri: TileIndex === (tehaiLength - 1),
            }));
          }
        } else {
          socket.send(JSON.stringify({ type: 'none' }));
        }
      } else if (msg.type === 'dahai' && msg.actor !== MyPlayerId) {
        let called = false;
        msg.possible_actions.forEach((action) => {
          if (!called && action.type === 'hora') {
            called = true;
            socket.send(JSON.stringify({
              type: 'hora',
              actor: MyPlayerId,
              target: msg.actor,
              pai: action.pai,
            }));
          }
        });
        if (!called) {
          socket.send(JSON.stringify({ type: 'none' }));
        }
      } else if (msg.type === 'reach' && msg.actor === MyPlayerId) {
        TileIndex = -1;
        WaitingDiscard = true;
        while (TileIndex < 0) {
          await sleep(200);
        }
        WaitingDiscard = false;
        const { actions } = getCurrentKyoku();
        const { tehais } = actions[actions.length - 1].board.players[MyPlayerId];
        const tehaiLength = tehais.length;
        let dahai = null;
        if (TileIndex < tehaiLength) {
          dahai = tehais[TileIndex];
          console.log(`dahai ${dahai}`);
        } else {
          console.error(`pai index ${TileIndex} is out of ${tehais}`);
        }
        socket.send(JSON.stringify({
          type: 'dahai',
          actor: MyPlayerId,
          pai: dahai,
          tsumogiri: TileIndex === (tehaiLength - 1),
        }));
      } else {
        socket.send(JSON.stringify({ type: 'none' }));
      }
    }
  };

  socket.onclose = function gameClosed(event) {
    console.log(event.data);
  };

  socket.onerror = function gameAborted(event) {
    alert(event.data);
  };
};

const sleep = (msec) => new Promise((resolve) => setTimeout(resolve, msec));
