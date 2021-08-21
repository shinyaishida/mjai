/* eslint func-names: ["error", "as-needed"] */

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

const BAKAZE_TO_STR = {
  E: '東',
  S: '南',
  W: '西',
  N: '北',
};

let kyokus = [];
let currentKyokuId = -1;
let currentActionId = -1;
let currentViewpoint = 0;
let playerInfos = [{}, {}, {}, {}];
let gameEnded = false;
// TODO: parse start_game action message to extract the exact player ID.
let playerId = 0;
let myPlayerId;
let haiIndex;
let waitingDahai = false;

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
    return `http://gimite.net/mjai/images/p_${name}_${pose}.${ext}`;
  }
  return 'http://gimite.net/mjai/images/blank.png';
};

const cloneBoard = function (board) {
  const newBoard = {};
  for (let bk in board) {
    const bv = board[bk];
    if (bk === 'players') {
      newBoard[bk] = [];
      for (let i = 0; i < bv.length; i += 1) {
        const player = bv[i];
        const newPlayer = {};
        for (let pk in player) {
          newPlayer[pk] = player[pk];
        }
        newBoard[bk].push(newPlayer);
      }
    } else {
      newBoard[bk] = bv;
    }
  }
  return newBoard;
};

const initPlayers = function (board) {
  const ref = board.players;
  const results = [];
  for (let i = 0; i < ref.length; i += 1) {
    const player = ref[i];
    player.tehais = null;
    player.furos = [];
    player.ho = [];
    player.reach = false;
    results.push(player.reachHoIndex = null);
  }
  return results;
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

const ripai = function (player) {
  if (player.tehais) {
    player.tehais = (function removeNullTiles() {
      const ref = player.tehais;
      const results = [];
      for (let i = 0; i < ref.length; i += 1) {
        const pai = ref[i];
        if (pai) {
          results.push(pai);
        }
      }
      return results;
    }());
    return sortPais(player.tehais);
  }
};

const loadAction = function (action) {
  console.log(action);
  let board;
  let kyoku;
  if (kyokus.length > 0) {
    kyoku = kyokus[kyokus.length - 1];
    board = cloneBoard(kyoku.actions[kyoku.actions.length - 1].board);
  } else {
    kyoku = null;
    board = null;
  }
  const actorPlayer = (board && ('actor' in action)) ? board.players[action.actor] : null;
  const targetPlayer = (board && ('target' in action)) ? board.players[action.target] : null;
  switch (action.type) {
    case 'start_game':
      for (let i = 0; i < 4; i += 1) {
        playerInfos[i].name = action.names[i];
      }
      break;
    case 'end_game':
      gameEnded = true;
      break;
    case 'start_kyoku':
      currentKyokuId += 1;
      kyoku = {
        actions: [],
        bakaze: action.bakaze,
        kyokuNum: action.kyoku,
        honba: action.honba,
      };
      kyokus.push(kyoku);
      const prevBoard = board;
      board = {
        players: [{}, {}, {}, {}],
        doraMarkers: [action.dora_marker],
      };
      initPlayers(board);
      for (let i = 0; i < 4; i += 1) {
        board.players[i].tehais = action.tehais[i];
        if (prevBoard) {
          board.players[i].score = prevBoard.players[i].score;
        } else {
          board.players[i].score = 25000;
        }
      }
      break;
    case 'end_kyoku':
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
      const ref = action.consumed;
      for (let i = 0; i < ref.length; i += 1) {
        deleteTehai(actorPlayer, ref[i]);
      }
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
      const ref1 = action.consumed;
      for (let i = 0; i < ref1.length; i += 1) {
        deleteTehai(actorPlayer, ref1[i]);
      }
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
      const furos = actorPlayer.furos;
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
    case 'hora':
    case 'ryukyoku':
      break;
    case 'dora':
      board.doraMarkers = board.doraMarkers.concat([action.dora_marker]);
      break;
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
    return kyoku.actions.push(action);
  }
};

const renderPai = function (pai, view, index, pose = undefined, mypai = false) {
  if (pose === undefined) {
    pose = 1;
  }
  view.attr('src', paiToImageUrl(pai, pose));
  view.attr('index', index);
  if (mypai) {
    view.addClass('mypai');
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
  const results = [];
  const ref = pais.length;
  for (let i = 0; ref >= 0 ? i < ref : i > ref; i += ref >= 0 ? 1 : -1) {
    results.push(renderPai(pais[i], view.at(i), i, poses[i], mypai));
  }
  return results;
};

const renderHo = function (player, offset, pais, view) {
  const reachIndex = (player.reachHoIndex === null) ? null : player.reachHoIndex - offset;
  view.resize(pais.length);
  const results = [];
  const ref = pais.length;
  for (let i = 0; ref >= 0 ? i < ref : i > ref; i += ref >= 0 ? 1 : -1) {
    results.push(renderPai(pais[i], view.at(i), i, i === reachIndex ? 3 : 1));
  }
  return results;
};

const getCurrentKyoku = function () {
  return kyokus[currentKyokuId];
};

const renderAction = function (action) {
  console.log(action);
  const displayAction = {};
  for (let k in action) {
    if (k !== 'board' && k !== 'logs') {
      displayAction[k] = action[k];
    }
  }
  $('#action-label').text(JSON.stringify(displayAction));
  $('#log-label').text((action.logs && action.logs[currentViewpoint]) || '');
  const kyoku = getCurrentKyoku();
  for (let i = 0; i < 4; i += 1) {
    const player = action.board.players[i];
    const view = Dytem.players.at((i - currentViewpoint + 4) % 4);
    const infoView = Dytem.playerInfos.at(i);
    infoView.score.text(player.score);
    infoView.viewpoint.text(i === currentViewpoint ? '+' : '');
    if (!player.tehais) {
      renderPais([], view.tehais);
      view.tsumoPai.hide();
    } else if (player.tehais.length % 3 === 2) {
      const myHais = i === myPlayerId;
      const maxTehaiId = player.tehais.length - 1;
      renderPais(player.tehais.slice(0, maxTehaiId), view.tehais, [], myHais);
      view.tsumoPai.show();
      renderPai(player.tehais[maxTehaiId], view.tsumoPai, maxTehaiId, 1, myHais);
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
  return renderPais(wanpais, Dytem.wanpais);
};

const initPlayerInfo = async function () {
  Dytem.init();
  // i: player id   0 <= i <= 3
  // j: ho row id   0 <= j <= 2
  for (let i = 0; i < 4; i += 1) {
    const playerView = Dytem.players.append();
    playerView.addClass(`player-${i}`);
    for (let j = 0; j < 3; j += 1) {
      playerView.hoRows.append();
    }
    const playerInfoView = Dytem.playerInfos.append();
    playerInfoView.index.text(i);
    playerInfoView.name.text(playerInfos[i].name);
  }
};

const startGame = async function () {
  console.log('Connecting');
  const serverName = '127.0.0.1';
  const serverPort = 9292;
  const socket = new WebSocket(`ws://${serverName}:${serverPort}`);
  socket.onopen = function joinGame(event) {
    console.log(`Connected to server ${serverName}:${serverPort}`);
    socket.send(JSON.stringify({
      type: 'join',
      name: 'kkri-client',
      room: 'default',
    }));
  };
  socket.onmessage = async function takeAction(event) {
    const msg = JSON.parse(event.data);
    console.log(`Received '${msg}'`);
    if (msg.type === 'hello') {
      socket.send(JSON.stringify({
        type: 'join',
        name: 'kkri-client',
        room: 'default',
      }));
    } else if (msg.type === 'error') {
      socket.close();
    } else if (msg.type === 'start_game') {
      myPlayerId = msg.id;
      // names = msg.names;
      socket.send(JSON.stringify({ type: 'none' }));
      initPlayerInfo();
    } else {
      loadAction(msg);
      if (currentKyokuId >= 0) {
        renderAction(msg);
      }
      if (msg.type === 'start_kyoku') {
        socket.send(JSON.stringify({ type: 'none' }));
      } else if (msg.type === 'tsumo') {
        if (msg.actor === myPlayerId) {
          haiIndex = -1;
          waitingDahai = true;
          while (haiIndex < 0) {
            await sleep(200);
          }
          waitingDahai = false;
          const tehais = msg.tehais;
          const tehaiLength = tehais.length;
          let dahai = null;
          if (haiIndex < tehaiLength) {
            dahai = tehais[haiIndex];
            console.log(`dahai ${dahai}`);
          } else {
            console.error(`pai index ${haiIndex} is out of ${tehais}`);
          }
          socket.send(JSON.stringify({
            type: 'dahai',
            actor: myPlayerId,
            pai: dahai,
            tsumogiri: haiIndex === (tehaiLength - 1),
          }));
        } else {
          socket.send(JSON.stringify({ type: 'none' }));
        }
      } else if (msg.type === 'dahai') {
        socket.send(JSON.stringify({ type: 'none' }));
      }
    }
  };
  socket.onclose = function quitGame(event) {
    console.log(event.data);
  };
  socket.onerror = function abortGame(event) {
    alert(event.data);
  };
};

const sleep = (msec) => new Promise((resolve) => setTimeout(resolve, msec));

$('img.mypai').on('click', function dahai() {
  console.log('clicked!', $(this));
  if (waitingDahai) {
    haiIndex = $(this).index;
    waitingDahai = false;
  }
});
