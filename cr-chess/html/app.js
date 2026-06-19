const app = document.getElementById('app');
const boardEl = document.getElementById('nui-board');
const movesList = document.getElementById('moves-list');
const turnCard = document.getElementById('turn-card');
const reviewCard = document.getElementById('review-card');
const selectedLabel = document.getElementById('selected-label');
const leaderboardEl = document.getElementById('leaderboard');
const profileEl = document.getElementById('profile');
const boardHitGrid = document.getElementById('board-hit-grid');
const tableMenuEl = document.getElementById('table-menu');
const feedbackStack = document.getElementById('feedback-stack');
const resultOverlay = document.getElementById('result-overlay');
const resignButton = document.getElementById('resign-match');

let resourceName = 'cr-chess';
let snapshot = null;
let legalMoves = [];
let selectedSquare = null;
let boardPerspective = 'white';

const pieceGlyphs = {
    wK: '♔',
    wQ: '♕',
    wR: '♖',
    wB: '♗',
    wN: '♘',
    wP: '♙',
    bK: '♚',
    bQ: '♛',
    bR: '♜',
    bB: '♝',
    bN: '♞',
    bP: '♟'
};

Object.assign(pieceGlyphs, {
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
});

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

function nui(name, data = {}) {
    return fetch(`https://${resourceName}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => {});
}

function setVisible(visible) {
    app.classList.toggle('hidden', !visible);

    if (!visible) {
        boardHitGrid.classList.add('hidden');
        tableMenuEl.classList.add('hidden');
        resultOverlay.classList.add('hidden');
        feedbackStack.innerHTML = '';
    }
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    }[char]));
}

function menuAction(payload) {
    return nui('tableMenuAction', payload);
}

function menuButton(label, payload, className = '') {
    const button = document.createElement('button');
    button.className = `menu-button ${className}`.trim();
    button.textContent = label;
    button.addEventListener('click', () => menuAction(payload));
    return button;
}

function appendMenuSection(title, children, muted) {
    const section = document.createElement('section');
    section.className = 'menu-section';

    if (title) {
        const heading = document.createElement('div');
        heading.className = 'menu-section-title';
        heading.textContent = title;
        section.append(heading);
    }

    if (muted) {
        const note = document.createElement('div');
        note.className = 'menu-muted';
        note.textContent = muted;
        section.append(note);
    }

    if (children) section.append(children);
    tableMenuEl.append(section);
}

function buttonGrid(buttons, columns = 2) {
    const grid = document.createElement('div');
    grid.className = `menu-actions ${columns === 3 ? 'three' : ''}`;
    grid.append(...buttons);
    return grid;
}

function renderSeats(seats = {}) {
    const wrapper = document.createElement('div');

    for (const color of ['white', 'black']) {
        const row = document.createElement('div');
        row.className = 'seat-row';
        row.innerHTML = `<strong>${color}</strong><span>${escapeHtml(seats[color]?.name || 'Open')}</span>`;
        wrapper.append(row);
    }

    return wrapper;
}

function renderInvitePlayers(data) {
    const wrapper = document.createElement('div');
    const players = data.invitePlayers || [];

    if (!players.length) {
        wrapper.className = 'menu-muted';
        wrapper.textContent = 'No nearby players found.';
        return wrapper;
    }

    for (const player of players) {
        const row = document.createElement('div');
        row.className = 'invite-row';

        const name = document.createElement('span');
        name.textContent = `${player.name} (${player.distance.toFixed(1)}m)`;

        const invite = menuButton('Invite', {
            action: 'invite',
            tableId: data.tableId,
            color: data.color,
            mode: data.inviteMode,
            targetSource: player.source,
            wagerAmount: data.wagerAmount || 0
        }, 'primary');

        row.append(name, invite);
        wrapper.append(row);
    }

    return wrapper;
}

function renderTableMenu(data) {
    if (!data?.visible) {
        tableMenuEl.classList.add('hidden');
        tableMenuEl.innerHTML = '';
        return;
    }

    tableMenuEl.classList.remove('hidden');
    tableMenuEl.innerHTML = '';

    const header = document.createElement('header');
    header.className = 'menu-header';
    header.innerHTML = `
        <div>
            <div class="menu-title">Chess Table ${escapeHtml(data.tableId || '')}</div>
            <div class="menu-subtitle">${data.color ? `Sitting as ${escapeHtml(data.color)}` : 'Choose a seat to start'}</div>
        </div>
    `;
    header.append(menuButton('x', { action: 'close' }, 'menu-close'));
    tableMenuEl.append(header);

    if (data.invite) {
        const invite = data.invite;
        const wager = Number(invite.wagerAmount || 0);
        const text = wager > 0
            ? `${invite.fromName} invited you to ${invite.mode} for $${wager}.`
            : `${invite.fromName} invited you to ${invite.mode}.`;

        appendMenuSection('Invite', buttonGrid([
            menuButton('Accept', { action: 'acceptInvite', matchId: invite.matchId }, 'primary'),
            menuButton('Decline', { action: 'declineInvite' })
        ]), text);
        return;
    }

    appendMenuSection('Seats', renderSeats(data.seats));

    if (!data.color) {
        appendMenuSection('Sit', buttonGrid([
            menuButton('White', { action: 'sit', tableId: data.tableId, color: 'white' }, 'primary'),
            menuButton('Black', { action: 'sit', tableId: data.tableId, color: 'black' }, 'primary')
        ]));
        return;
    }

    appendMenuSection('Bot', buttonGrid([
        menuButton('Easy', { action: 'bot', tableId: data.tableId, color: data.color, difficulty: 'easy' }),
        menuButton('Medium', { action: 'bot', tableId: data.tableId, color: data.color, difficulty: 'medium' }),
        menuButton('Hard', { action: 'bot', tableId: data.tableId, color: data.color, difficulty: 'hard' })
    ], 3));

    appendMenuSection('Casual 1v1', buttonGrid([
        menuButton('Wait', { action: 'wait', tableId: data.tableId, color: data.color, mode: 'casual' }, 'primary'),
        menuButton('Invite', { action: 'invitePicker', tableId: data.tableId, color: data.color, mode: 'casual' })
    ]));

    appendMenuSection('Ranked 1v1', buttonGrid([
        menuButton('Wait', { action: 'wait', tableId: data.tableId, color: data.color, mode: 'ranked' }, 'primary'),
        menuButton('Invite', { action: 'invitePicker', tableId: data.tableId, color: data.color, mode: 'ranked' })
    ]));

    if (data.wagers?.enabled && data.wagers.amounts?.length) {
        const wagerButtons = [];

        for (const amount of data.wagers.amounts) {
            wagerButtons.push(menuButton(`Wait $${amount}`, {
                action: 'wait',
                tableId: data.tableId,
                color: data.color,
                mode: 'ranked',
                wagerAmount: amount
            }, 'warn'));
            wagerButtons.push(menuButton(`Invite $${amount}`, {
                action: 'invitePicker',
                tableId: data.tableId,
                color: data.color,
                mode: 'ranked',
                wagerAmount: amount
            }, 'warn'));
        }

        appendMenuSection('Ranked Wagers', buttonGrid(wagerButtons), `Escrow account: ${data.wagers.account || 'cash'}`);
    }

    if (data.invitePlayers) {
        appendMenuSection('Nearby Players', renderInvitePlayers(data));
    }

    appendMenuSection(null, buttonGrid([
        menuButton('Board Controls', { action: 'interact', tableId: data.tableId }),
        menuButton('Stand', { action: 'stand' })
    ]));
}

function showFeedback(data) {
    const toast = document.createElement('div');
    toast.className = `feedback-toast ${data.kind || ''}`.trim();

    const title = document.createElement('div');
    title.className = 'feedback-title';
    title.textContent = data.title || 'Chess';

    const message = document.createElement('div');
    message.className = 'feedback-message';
    message.textContent = data.message || '';

    toast.append(title, message);
    feedbackStack.append(toast);

    while (feedbackStack.children.length > 3) {
        feedbackStack.firstElementChild.remove();
    }

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateY(8px)';
        toast.style.transition = 'opacity 160ms ease, transform 160ms ease';
        setTimeout(() => toast.remove(), 180);
    }, Number(data.duration || 2600));
}

function resultMetrics(review) {
    if (!review) return '';

    return `
        <div class="result-metrics">
            <div class="result-metric"><span>White Accuracy</span><strong>${review.whiteAccuracy || 0}%</strong></div>
            <div class="result-metric"><span>Black Accuracy</span><strong>${review.blackAccuracy || 0}%</strong></div>
            <div class="result-metric"><span>Mistakes</span><strong>${review.mistakes || 0}</strong></div>
            <div class="result-metric"><span>Blunders</span><strong>${review.blunders || 0}</strong></div>
        </div>
    `;
}

function renderMatchResult(data) {
    if (!data || data.visible === false) {
        resultOverlay.classList.add('hidden');
        resultOverlay.innerHTML = '';
        return;
    }

    resultOverlay.className = data.result || 'draw';
    resultOverlay.innerHTML = `
        <div class="result-band"></div>
        <div class="result-body">
            <div class="result-title">${escapeHtml(data.title || 'Game Over')}</div>
            <div class="result-subtitle">${escapeHtml(data.subtitle || '')}</div>
            ${resultMetrics(data.review)}
            <button id="result-close" class="menu-button primary result-close">Close</button>
        </div>
    `;
    resultOverlay.classList.remove('hidden');

    document.getElementById('result-close').addEventListener('click', () => {
        nui('close');
    });
}

function moveText(move) {
    if (!move) return '';
    const suffix = move.promotion ? `=${move.promotion.toUpperCase()}` : '';
    const capture = move.capturedPiece ? 'x' : '-';
    return `${move.from}${capture}${move.to}${suffix}`;
}

function renderMoves() {
    const history = snapshot?.moveHistory || [];
    movesList.innerHTML = '';

    for (let index = 0; index < history.length; index += 2) {
        const row = document.createElement('div');
        row.className = 'move-row';

        const number = document.createElement('div');
        number.className = 'move-number';
        number.textContent = `${Math.floor(index / 2) + 1}.`;

        const white = document.createElement('div');
        white.innerHTML = formatMove(history[index]);

        const black = document.createElement('div');
        black.innerHTML = formatMove(history[index + 1]);

        row.append(number, white, black);
        movesList.append(row);
    }
}

function formatMove(move) {
    if (!move) return '';
    const quality = move.accuracy ? `<div class="move-quality">${move.accuracy}% ${move.quality || ''}</div>` : '';
    return `<div>${moveText(move)}</div>${quality}`;
}

function renderReview() {
    const review = snapshot?.review;

    if (!review || snapshot?.state !== 'finished') {
        reviewCard.classList.add('hidden');
        reviewCard.innerHTML = '';
        return;
    }

    reviewCard.classList.remove('hidden');
    reviewCard.innerHTML = `
        <strong>Game Review</strong>
        <div class="metric-grid">
            <div class="metric"><span>White Accuracy</span><strong>${review.whiteAccuracy}%</strong></div>
            <div class="metric"><span>Black Accuracy</span><strong>${review.blackAccuracy}%</strong></div>
            <div class="metric"><span>Mistakes</span><strong>${review.mistakes}</strong></div>
            <div class="metric"><span>Blunders</span><strong>${review.blunders}</strong></div>
        </div>
    `;
}

function renderBoard() {
    boardEl.innerHTML = '';
    const board = snapshot?.board || {};
    const legalBySquare = {};
    const ranks = boardPerspective === 'black'
        ? [1, 2, 3, 4, 5, 6, 7, 8]
        : [8, 7, 6, 5, 4, 3, 2, 1];
    const files = boardPerspective === 'black'
        ? ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a']
        : ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

    boardEl.style.gridTemplateColumns = 'repeat(8, minmax(0, 1fr))';
    boardEl.style.gridTemplateRows = 'repeat(8, minmax(0, 1fr))';

    for (const move of legalMoves) {
        legalBySquare[move.to] = move;
    }

    for (const rank of ranks) {
        for (let fileIndex = 0; fileIndex < files.length; fileIndex++) {
            const file = files[fileIndex];
            const fileNumber = file.charCodeAt(0) - 97;
            const square = `${file}${rank}`;
            const piece = board[square];
            const cell = document.createElement('button');
            cell.className = `square ${((fileNumber + rank) % 2 === 0) ? 'dark' : 'light'}`;
            cell.dataset.square = square;
            cell.textContent = pieceGlyphs[piece] || '';

            if (selectedSquare === square) cell.classList.add('selected');
            if (legalBySquare[square]) cell.classList.add(legalBySquare[square].capture ? 'capture' : 'legal');

            cell.addEventListener('mousedown', (event) => {
                if (event.button !== 0 && event.button !== 2) return;
                event.preventDefault();
                nui('boardSquare', { square });
            });

            boardEl.append(cell);
        }
    }
}

function renderStatus() {
    const title = document.getElementById('match-title');
    const subtitle = document.getElementById('match-subtitle');
    const active = snapshot?.state === 'active';

    if (!snapshot) {
        title.textContent = 'Chess';
        subtitle.textContent = 'No active match';
        turnCard.textContent = 'Waiting for match data';
        resignButton.classList.add('hidden');
        return;
    }

    title.textContent = `Match ${snapshot.id}`;
    subtitle.textContent = `${snapshot.whiteName || 'White'} vs ${snapshot.blackName || 'Black'}`;
    turnCard.textContent = snapshot.state === 'finished'
        ? `Finished: ${snapshot.result || 'draw'}`
        : `${snapshot.turn}'s turn`;
    resignButton.classList.toggle('hidden', !active);
}

function setLegalMoves(data) {
    selectedSquare = data?.from || null;
    legalMoves = data?.moves || [];
    const piece = snapshot?.board?.[selectedSquare] || data?.piece;
    selectedLabel.textContent = piece ? `${pieceNames[piece] || piece} on ${selectedSquare}` : 'Select a piece';
    renderBoard();
}

function renderLeaderboard(players) {
    leaderboardEl.innerHTML = '';

    for (const player of players || []) {
        const row = document.createElement('button');
        row.className = 'leader-row';
        row.innerHTML = `<span>#${player.rank}</span><span>${player.name}</span><strong>${player.rating}</strong>`;
        row.addEventListener('click', () => nui('requestProfile', { identifier: player.identifier }));
        leaderboardEl.append(row);
    }
}

function renderProfile(profile) {
    if (!profile) {
        profileEl.innerHTML = '';
        return;
    }

    const matches = (profile.matches || []).map((match) => `
        <div class="recent-match">
            <strong>${match.mode}</strong> ${match.result}<br>
            ${match.whiteName || 'White'} vs ${match.blackName || 'Black'} &middot; ${match.moveCount} moves
        </div>
    `).join('');

    profileEl.innerHTML = `
        <strong>${profile.name}</strong>
        <div class="metric-grid">
            <div class="metric"><span>Rating</span><strong>${profile.rating}</strong></div>
            <div class="metric"><span>Rank</span><strong>${profile.rankName}</strong></div>
            <div class="metric"><span>Games</span><strong>${profile.gamesPlayed}</strong></div>
            <div class="metric"><span>Accuracy</span><strong>${profile.accuracy}%</strong></div>
        </div>
        <h4>Recent Matches</h4>
        ${matches || '<p>No completed matches yet.</p>'}
    `;
}

function playSound(data) {
    if (!data?.file) return;

    const audio = new Audio(data.file);
    audio.volume = Math.max(0, Math.min(1, Number(data.volume ?? 0.55)));
    audio.play().catch(() => {});
}

function renderBoardOverlay(data) {
    if (!data?.visible || !Array.isArray(data.corners)) {
        boardHitGrid.classList.add('hidden');
        return;
    }

    const xs = data.corners.map((corner) => corner.x * window.innerWidth);
    const ys = data.corners.map((corner) => corner.y * window.innerHeight);
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);

    boardHitGrid.style.left = `${minX}px`;
    boardHitGrid.style.top = `${minY}px`;
    boardHitGrid.style.width = `${Math.max(1, maxX - minX)}px`;
    boardHitGrid.style.height = `${Math.max(1, maxY - minY)}px`;
    boardHitGrid.classList.remove('hidden');
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.resourceName) resourceName = data.resourceName;
    if (data.action === 'show') setVisible(true);
    if (data.action === 'hide') setVisible(false);
    if (data.action === 'snapshot') {
        snapshot = data.snapshot;
        boardPerspective = data.perspective || snapshot?.perspective || 'white';
        renderStatus();
        renderMoves();
        renderReview();
        renderBoard();
    }
    if (data.action === 'legalMoves') setLegalMoves(data.data);
    if (data.action === 'leaderboard') renderLeaderboard(data.players);
    if (data.action === 'profile') renderProfile(data.profile);
    if (data.action === 'playSound') playSound(data);
    if (data.action === 'boardOverlay') renderBoardOverlay(data);
    if (data.action === 'tableMenu') renderTableMenu(data);
    if (data.action === 'feedback') showFeedback(data);
    if (data.action === 'matchResult') renderMatchResult(data);
});

document.addEventListener('contextmenu', (event) => event.preventDefault());

document.addEventListener('mousedown', (event) => {
    if (event.button !== 0 && event.button !== 2) return;
    if (event.target.closest('#side-panel, #table-menu, #result-overlay')) return;

    event.preventDefault();
    nui('worldClick', {
        x: event.clientX / window.innerWidth,
        y: event.clientY / window.innerHeight
    });
});

document.getElementById('close').addEventListener('click', () => nui('close'));
resignButton.addEventListener('click', () => nui('resign'));
document.getElementById('refresh-leaderboard').addEventListener('click', () => nui('requestLeaderboard'));

for (const tab of document.querySelectorAll('.tab')) {
    tab.addEventListener('click', () => {
        for (const item of document.querySelectorAll('.tab')) item.classList.remove('active');
        for (const pane of document.querySelectorAll('.tab-pane')) pane.classList.remove('active');
        tab.classList.add('active');
        document.getElementById(`${tab.dataset.tab}-tab`).classList.add('active');
        if (tab.dataset.tab === 'stats') nui('requestLeaderboard');
    });
}

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') nui('close');
    if (event.key.toLowerCase() === 'q') nui('tuneCycleTarget');
    if (event.key.toLowerCase() === 'e') nui('tuneCycleField');
});

document.addEventListener('wheel', (event) => {
    nui('tuneWheel', { direction: event.deltaY < 0 ? 1 : -1 });
});

renderBoard();
