const dui = document.getElementById('dui');
const boardEl = document.getElementById('mini-board');
const matchLabel = document.getElementById('match-label');
const turnLabel = document.getElementById('turn-label');
const modePill = document.getElementById('mode-pill');
const lastMoveEl = document.getElementById('last-move');
const lastMovePieceEl = document.getElementById('last-move-piece');
const animationLayer = document.getElementById('animation-layer');
const betWhiteEl = document.getElementById('bet-white');
const betBlackEl = document.getElementById('bet-black');
const betStatusEl = document.getElementById('bet-status');
const bettingEl = document.getElementById('betting');
const playerEls = {
    white: document.getElementById('white-player'),
    black: document.getElementById('black-player')
};

let snapshot = null;
let perspective = 'white';
let snapshotReceivedAt = performance.now();
let lastMoveAnimationKey = null;
let resultAnimationKey = null;
let boardGridEl = null;
let pieceLayerEl = null;
let renderedPerspective = null;
const pieceElements = new Map();

const pieceLetters = {
    wK: 'K',
    wQ: 'Q',
    wR: 'R',
    wB: 'B',
    wN: 'N',
    wP: 'P',
    bK: 'K',
    bQ: 'Q',
    bR: 'R',
    bB: 'B',
    bN: 'N',
    bP: 'P'
};

const pieceIcons = {
    wK: '\u265A',
    wQ: '\u265B',
    wR: '\u265C',
    wB: '\u265D',
    wN: '\u265E',
    wP: '\u265F',
    bK: '\u265A',
    bQ: '\u265B',
    bR: '\u265C',
    bB: '\u265D',
    bN: '\u265E',
    bP: '\u265F'
};

const pieceSymbols = {
    wK: '\u2654',
    wQ: '\u2655',
    wR: '\u2656',
    wB: '\u2657',
    wN: '\u2658',
    wP: '\u2659',
    bK: '\u265A',
    bQ: '\u265B',
    bR: '\u265C',
    bB: '\u265D',
    bN: '\u265E',
    bP: '\u265F'
};

const pieceNames = {
    wK: 'White King',
    wQ: 'White Queen',
    wR: 'White Rook',
    wB: 'White Bishop',
    wN: 'White Knight',
    wP: 'White Pawn',
    bK: 'Black King',
    bQ: 'Black Queen',
    bR: 'Black Rook',
    bB: 'Black Bishop',
    bN: 'Black Knight',
    bP: 'Black Pawn'
};

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    }[char]));
}

function formatClock(ms) {
    const totalSeconds = Math.max(0, Math.ceil(Number(ms || 0) / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${String(seconds).padStart(2, '0')}`;
}

function clockRemaining(color) {
    const clock = snapshot?.clock;

    if (!clock?.enabled || !clock.remaining) return null;

    let remaining = Number(clock.remaining[color] || 0);

    if (snapshot?.state === 'active' && clock.activeColor === color) {
        remaining -= performance.now() - snapshotReceivedAt;
    }

    return Math.max(0, remaining);
}

function moveText(move) {
    if (!move) return 'No moves yet';
    const capture = move.capturedPiece ? 'x' : '-';
    const suffix = move.promotion ? `=${String(move.promotion).toUpperCase()}` : '';
    return `${move.from}${capture}${move.to}${suffix}`;
}

function moneyText(amount) {
    return `$${Math.max(0, Math.floor(Number(amount) || 0)).toLocaleString()}`;
}

function spectatorBetSecondsRemaining() {
    const bets = snapshot?.spectatorBets;

    if (!bets) return 0;

    if (bets.closesAt && bets.serverNow) {
        const elapsedSeconds = (performance.now() - snapshotReceivedAt) / 1000;
        const remaining = Number(bets.closesAt) - Number(bets.serverNow) - elapsedSeconds;
        return Math.max(0, Math.ceil(remaining));
    }

    return Math.max(0, Math.ceil(Number(bets.secondsRemaining || 0)));
}

function moveKey(move) {
    if (!move) return null;
    return [
        move.from,
        move.to,
        move.piece,
        move.finalPiece || '',
        move.capturedPiece || '',
        move.promotion || '',
        move.fen || ''
    ].join(':');
}

function resultKey(data) {
    if (!data || data.state !== 'finished') return null;
    return `${data.id}:${data.result || 'draw'}:${data.finishReason || 'finished'}`;
}

function clearAnimationAfter(node, ms) {
    setTimeout(() => {
        if (node.parentElement === animationLayer) node.remove();

        if (!animationLayer.querySelector('.capture-anim, .king-anim')) {
            animationLayer.classList.remove('spotlight');
        }
    }, ms);
}

function playCaptureAnimation(move) {
    if (!move?.capturedPiece) return;

    animationLayer.innerHTML = '';
    animationLayer.classList.add('spotlight');

    const piece = move.capturedPiece;
    const wrapper = document.createElement('div');
    wrapper.className = 'capture-anim';

    const breakPiece = document.createElement('div');
    breakPiece.className = `break-piece ${piece.charAt(0) === 'w' ? 'white' : 'black'}`;

    for (const slice of ['left', 'middle', 'right']) {
        const pieceSlice = document.createElement('span');
        pieceSlice.className = `piece-slice ${slice}`;
        pieceSlice.textContent = pieceSymbols[piece] || pieceLetters[piece] || piece;
        breakPiece.append(pieceSlice);
    }

    for (const shardName of ['one', 'two', 'three']) {
        const shard = document.createElement('span');
        shard.className = `shard ${shardName}`;
        breakPiece.append(shard);
    }

    const label = document.createElement('div');
    label.className = 'capture-label';

    const title = document.createElement('strong');
    title.textContent = 'Piece captured';

    const detail = document.createElement('span');
    const square = move.captureSquare || move.to;
    detail.textContent = `${pieceNames[piece] || 'Piece'} removed on ${square}`;

    label.append(title, detail);

    wrapper.append(breakPiece, label);
    animationLayer.append(wrapper);
    clearAnimationAfter(wrapper, 1650);
}

function playKingFallAnimation(data) {
    if (!data || data.finishReason !== 'resignation' || !data.winner) return;

    const losingColor = data.winner === 'white' ? 'black' : 'white';
    const piece = losingColor === 'white' ? 'wK' : 'bK';

    animationLayer.innerHTML = '';
    animationLayer.classList.add('spotlight');

    const wrapper = document.createElement('div');
    wrapper.className = 'king-anim';

    const king = document.createElement('div');
    king.className = `king-piece ${losingColor}`;
    king.textContent = pieceSymbols[piece];

    const label = document.createElement('div');
    label.className = 'king-label';

    const title = document.createElement('strong');
    title.textContent = 'King falls';

    const detail = document.createElement('span');
    detail.textContent = `${losingColor.charAt(0).toUpperCase()}${losingColor.slice(1)} resigned`;

    label.append(title, detail);

    wrapper.append(king, label);
    animationLayer.append(wrapper);
    clearAnimationAfter(wrapper, 1700);
}

function maybePlaySnapshotAnimations(nextSnapshot) {
    const nextMoveKey = moveKey(nextSnapshot?.lastMove);

    if (nextMoveKey && nextMoveKey !== lastMoveAnimationKey) {
        lastMoveAnimationKey = nextMoveKey;

        if (nextSnapshot.lastMove?.capturedPiece) {
            playCaptureAnimation(nextSnapshot.lastMove);
        }
    }

    const nextResultKey = resultKey(nextSnapshot);

    if (nextResultKey && nextResultKey !== resultAnimationKey) {
        resultAnimationKey = nextResultKey;
        playKingFallAnimation(nextSnapshot);
    }
}

function playerProfile(color) {
    const profile = snapshot?.players?.[color] || {};
    const prefix = color === 'white' ? 'white' : 'black';

    return {
        name: profile.name || snapshot?.[`${prefix}Name`] || color,
        rating: profile.rating ?? snapshot?.[`${prefix}Rating`],
        rankName: profile.rankName || snapshot?.[`${prefix}Rank`] || (profile.rating ? 'Rated' : 'Unrated')
    };
}

function rankText(profile) {
    if (profile.rating === null || profile.rating === undefined) {
        return profile.rankName || 'Unrated';
    }

    return `${profile.rankName || 'Rated'} ${profile.rating}`;
}

function resultLabel(data) {
    if (!data || data.state !== 'finished') return '';
    if (!data.winner) return 'Draw';

    const winnerProfile = playerProfile(data.winner);
    const reason = data.finishReason === 'resignation'
        ? 'wins by resignation'
        : data.finishReason === 'timeout'
            ? 'wins on time'
            : data.finishReason === 'checkmate'
                ? 'wins by checkmate'
                : 'wins';

    return `${winnerProfile.name} ${reason}`;
}

function statusLabel(data) {
    if (!data) return 'Waiting';

    if (data.state === 'finished') {
        return resultLabel(data);
    }

    if (data.state === 'idle') {
        return 'Open table';
    }

    if (data.state === 'waiting') {
        return 'Waiting for players';
    }

    return `${data.turn || 'white'} to move`;
}

function renderPlayers() {
    for (const color of ['white', 'black']) {
        const el = playerEls[color];
        const profile = playerProfile(color);
        const remaining = clockRemaining(color);

        el.classList.toggle('active', snapshot?.state === 'active' && snapshot?.turn === color);
        el.querySelector('.name').textContent = profile.name;
        el.querySelector('.rank').textContent = rankText(profile);
        el.querySelector('time').textContent = remaining === null ? '--:--' : formatClock(remaining);
    }
}

function boardRanks() {
    return perspective === 'black'
        ? [1, 2, 3, 4, 5, 6, 7, 8]
        : [8, 7, 6, 5, 4, 3, 2, 1];
}

function boardFiles() {
    return perspective === 'black'
        ? ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a']
        : ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
}

function squarePosition(square) {
    const file = square?.charAt(0);
    const rank = Number(square?.charAt(1));
    const files = boardFiles();
    const ranks = boardRanks();
    const col = files.indexOf(file);
    const row = ranks.indexOf(rank);

    if (col < 0 || row < 0) return null;

    return { col, row };
}

function pieceTransform(square) {
    const pos = squarePosition(square);

    if (!pos) return 'translate(0%, 0%)';

    return `translate(${pos.col * 100}%, ${pos.row * 100}%) scale(0.76)`;
}

function ensureBoardStructure() {
    if (!boardGridEl || !pieceLayerEl) {
        boardEl.innerHTML = '';

        boardGridEl = document.createElement('div');
        boardGridEl.className = 'board-grid';

        pieceLayerEl = document.createElement('div');
        pieceLayerEl.className = 'piece-layer';

        boardEl.append(boardGridEl, pieceLayerEl);
        renderedPerspective = null;
    }

    if (renderedPerspective === perspective && boardGridEl.children.length === 64) {
        return;
    }

    renderedPerspective = perspective;
    boardGridEl.innerHTML = '';

    const ranks = boardRanks();
    const files = boardFiles();

    for (const rank of ranks) {
        for (const file of files) {
            const fileNumber = file.charCodeAt(0) - 97;
            const square = `${file}${rank}`;
            const cell = document.createElement('div');
            cell.dataset.square = square;
            cell.className = `square ${((fileNumber + rank) % 2 === 0) ? 'dark' : 'light'}`;
            boardGridEl.append(cell);
        }
    }

    for (const [square, el] of pieceElements) {
        el.style.transform = pieceTransform(square);
    }
}

function updateBoardHighlights(lastMove) {
    if (!boardGridEl) return;

    for (const cell of boardGridEl.children) {
        const square = cell.dataset.square;

        cell.classList.toggle('last-from', lastMove?.from === square);
        cell.classList.toggle('last-to', lastMove?.to === square);
    }
}

function updatePieceElement(el, piece) {
    const wasVisible = el.classList.contains('visible');
    el.dataset.piece = piece;
    el.className = `board-piece ${piece.charAt(0) === 'w' ? 'white' : 'black'}`;

    if (wasVisible) {
        el.classList.add('visible');
    }

    el.textContent = pieceIcons[piece] || pieceLetters[piece] || piece;
}

function createPieceElement(piece, square) {
    const el = document.createElement('span');
    updatePieceElement(el, piece);
    el.dataset.square = square;
    el.style.transform = pieceTransform(square);
    pieceLayerEl.append(el);

    requestAnimationFrame(() => {
        el.classList.add('visible');
    });

    return el;
}

function removePieceElement(square, animate = true) {
    const el = pieceElements.get(square);

    if (!el) return;

    pieceElements.delete(square);

    if (!animate) {
        el.remove();
        return;
    }

    el.classList.add('captured');
    setTimeout(() => el.remove(), 260);
}

function movePieceElement(from, to, piece) {
    if (!from || !to || !piece) return false;

    const moving = pieceElements.get(from);

    if (!moving) return false;

    const target = pieceElements.get(to);

    if (target && target !== moving) {
        removePieceElement(to, true);
    }

    pieceElements.delete(from);
    pieceElements.set(to, moving);
    moving.dataset.square = to;
    updatePieceElement(moving, piece);

    requestAnimationFrame(() => {
        moving.style.transform = pieceTransform(to);
    });

    return true;
}

function applyAnimatedMove(board, lastMove) {
    if (!lastMove) return;

    if (lastMove.captureSquare && lastMove.captureSquare !== lastMove.to) {
        removePieceElement(lastMove.captureSquare, true);
    }

    if (lastMove.castle && lastMove.rookFrom && lastMove.rookTo && board[lastMove.rookTo]) {
        movePieceElement(lastMove.rookFrom, lastMove.rookTo, board[lastMove.rookTo]);
    }

    if (lastMove.from && lastMove.to && board[lastMove.to]) {
        movePieceElement(lastMove.from, lastMove.to, board[lastMove.to]);
    }
}

function renderBoard() {
    ensureBoardStructure();

    const board = snapshot?.board || {};
    const lastMove = snapshot?.lastMove || null;
    const activeSquares = new Set(Object.keys(board));

    updateBoardHighlights(lastMove);
    applyAnimatedMove(board, lastMove);

    for (const [square, piece] of Object.entries(board)) {
        const existing = pieceElements.get(square);

        if (existing) {
            updatePieceElement(existing, piece);
            existing.style.transform = pieceTransform(square);
        } else {
            pieceElements.set(square, createPieceElement(piece, square));
        }
    }

    for (const square of Array.from(pieceElements.keys())) {
        if (!activeSquares.has(square)) {
            removePieceElement(square, true);
        }
    }
}

function renderLastMove() {
    const move = snapshot?.lastMove || null;
    const piece = move?.finalPiece || move?.piece || null;

    lastMovePieceEl.textContent = piece ? (pieceIcons[piece] || pieceLetters[piece] || piece) : '·';
    lastMovePieceEl.className = `move-piece-icon ${piece ? (piece.charAt(0) === 'w' ? 'white' : 'black') : 'empty'}`;

    if (!move) {
        lastMoveEl.textContent = 'No moves yet';
        return;
    }

    lastMoveEl.textContent = moveText(move);
}

function renderBetting() {
    const bets = snapshot?.spectatorBets;

    if (!bets?.enabled) {
        bettingEl.classList.add('hidden');
        return;
    }

    bettingEl.classList.remove('hidden');

    const whitePool = Number(bets.pools?.white || 0);
    const blackPool = Number(bets.pools?.black || 0);
    const remainingSeconds = spectatorBetSecondsRemaining();
    const open = !!(bets.open && snapshot?.state === 'active' && remainingSeconds > 0);
    const status = open ? `${remainingSeconds}s left` : 'Closed';

    betWhiteEl.textContent = moneyText(whitePool);
    betBlackEl.textContent = moneyText(blackPool);
    betStatusEl.textContent = status;
    betStatusEl.parentElement.classList.toggle('open', open);
}

function render() {
    if (!snapshot) {
        dui.classList.add('hidden');
        return;
    }

    dui.classList.remove('hidden');
    matchLabel.textContent = snapshot.label || `Match ${snapshot.id || ''}`.trim();
    modePill.textContent = snapshot.mode || 'casual';
    turnLabel.textContent = statusLabel(snapshot);

    renderPlayers();
    renderBetting();
    renderBoard();
    renderLastMove();
}

function setSnapshot(data) {
    const nextSnapshot = data.snapshot || data;
    snapshot = nextSnapshot;
    perspective = data.perspective || perspective || 'white';
    snapshotReceivedAt = performance.now();
    render();
    maybePlaySnapshotAnimations(nextSnapshot);
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'snapshot') {
        setSnapshot(data);
    }

    if (data.action === 'hide') {
        snapshot = null;
        render();
    }
});

setInterval(() => {
    if (snapshot) {
        renderPlayers();
        renderBetting();
    }
}, 250);

function devSnapshot() {
    const devParams = new URLSearchParams(window.location.search);
    const devAnim = devParams.get('anim');
    const nowSeconds = Math.floor(Date.now() / 1000);

    return {
        id: 42,
        mode: 'ranked',
        state: devAnim === 'resign' ? 'finished' : 'active',
        turn: 'white',
        whiteName: 'cody_raves',
        blackName: 'Tom',
        players: {
            white: { name: 'cody_raves', rating: 1032, rankName: 'Gold' },
            black: { name: 'Tom', rating: 911, rankName: 'Silver' }
        },
        spectatorBets: {
            enabled: true,
            open: devAnim !== 'resign',
            closeAfterSeconds: 30,
            closesAt: nowSeconds + 30,
            serverNow: nowSeconds,
            secondsRemaining: 30,
            count: 3,
            total: 700,
            pools: {
                white: 500,
                black: 200
            }
        },
        clock: {
            enabled: true,
            activeColor: 'white',
            remaining: {
                white: 196000,
                black: 210000
            }
        },
        board: {
            a8: 'bR', b8: 'bN', c8: 'bB', d8: 'bQ', e8: 'bK', f8: 'bB', h8: 'bR',
            a7: 'bP', b7: 'bP', c7: 'bP', e7: 'bP', f7: 'bP', g7: 'bP', h7: 'bP',
            f6: 'bN', b4: 'bB', c4: 'wB', d5: 'wP', f3: 'wN',
            a2: 'wP', b2: 'wP', c2: 'wP', d2: 'wP', f2: 'wP', g2: 'wP', h2: 'wP',
            a1: 'wR', b1: 'wN', c1: 'wB', d1: 'wQ', e1: 'wK', g1: 'wN', h1: 'wR'
        },
        lastMove: {
            color: 'white',
            from: 'f1',
            to: 'c4',
            piece: 'wB',
            capturedPiece: devAnim === 'capture' ? 'bR' : null
        },
        winner: devAnim === 'resign' ? 'white' : null,
        result: devAnim === 'resign' ? 'white_win' : null,
        finishReason: devAnim === 'resign' ? 'resignation' : null
    };
}

if (new URLSearchParams(window.location.search).has('dev')) {
    setSnapshot({ snapshot: devSnapshot(), perspective: 'white' });
}
