const app = document.getElementById('app');
const sidePanel = document.getElementById('side-panel');
const boardEl = document.getElementById('nui-board');
const movesList = document.getElementById('moves-list');
const turnCard = document.getElementById('turn-card');
const lastMoveCard = document.getElementById('last-move-card');
const reviewCard = document.getElementById('review-card');
const selectedLabel = document.getElementById('selected-label');
let leaderboardEl = document.getElementById('leaderboard');
let profileEl = document.getElementById('profile');
const boardHitGrid = document.getElementById('board-hit-grid');
const tableMenuEl = document.getElementById('table-menu');
const feedbackStack = document.getElementById('feedback-stack');
const resultOverlay = document.getElementById('result-overlay');
const sideRollOverlay = document.getElementById('side-roll-overlay');
const resignButton = document.getElementById('resign-match');
const boardToggleButton = document.getElementById('toggle-board');
const cameraToggleButton = document.getElementById('toggle-camera');
const clockStrip = document.getElementById('clock-strip');
const clockEls = {
    white: document.getElementById('clock-white'),
    black: document.getElementById('clock-black')
};
const devParams = new URLSearchParams(window.location.search);
const devPreview = devParams.has('dev');

let resourceName = 'cr-chess';
let snapshot = null;
let legalMoves = [];
let selectedSquare = null;
let hoveredMove = null;
let clearLastMoveHoverListeners = null;
let boardPerspective = 'white';
let snapshotReceivedAt = performance.now();
let tableMenuView = 'play';
let leaderboardPlayers = [];
let currentProfile = null;
let sideRollTimers = [];
let selectedPlayMode = null;
let selectedPlayerMode = null;
let selectedBotDifficulty = 'easy';
let selectedWagerAmount = null;
let matchBoardOpen = false;
let cameraMode = 'normal';

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

function pieceSide(piece) {
    return piece?.charAt(0) === 'w' ? 'white' : 'black';
}

function pieceBadgeHtml(piece, extraClass = '') {
    if (!piece) return '';

    const side = pieceSide(piece);
    const label = pieceIcons[piece] || pieceLetters[piece] || piece;
    const title = pieceNames[piece] || piece;

    return `<span class="piece-badge ${side} ${extraClass}" title="${escapeHtml(title)}">${escapeHtml(label)}</span>`;
}

function nui(name, data = {}) {
    if (devPreview) {
        if (name === 'boardSquare') {
            setLegalMoves(devLegalMoves(data.square));
        }

        if (name === 'tableMenuAction') {
            devHandleTableMenuAction(data);
        }

        if (name === 'requestLeaderboard') {
            renderLeaderboard(devLeaderboard());
        }

        if (name === 'requestProfile') {
            renderProfile(devProfile(data.identifier));
        }

        if (name === 'sideRollPick') {
            renderSideRoll(devSideRollResult(Number(data.number) || 50));
        }

        if (name === 'sideRollClose') {
            renderSideRoll({ visible: false });
        }

        console.info('[cr-chess dev nui]', name, data);
        return Promise.resolve({ ok: true });
    }

    return fetch(`https://${resourceName}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => {});
}

function devLegalMoves(square) {
    const moves = {
        e1: [{ to: 'e2' }, { to: 'f1' }],
        d1: [{ to: 'h5' }, { to: 'd3' }],
        c4: [{ to: 'f7', capture: true }, { to: 'b5' }],
        f3: [{ to: 'g5' }, { to: 'd4' }],
        d5: [{ to: 'e6', capture: true }],
        f6: [{ to: 'd5', capture: true }, { to: 'g4' }],
        b4: [{ to: 'c3', capture: true }, { to: 'e1', capture: true }]
    };

    return {
        from: square,
        moves: moves[square] || []
    };
}

function setVisible(visible) {
    app.classList.toggle('hidden', !visible);

    if (!visible) {
        setHoveredMove(null);
        boardHitGrid.classList.add('hidden');
        tableMenuEl.classList.add('hidden');
        resultOverlay.classList.add('hidden');
        sideRollOverlay.classList.add('hidden');
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

function localMenuButton(label, onClick, className = '') {
    const button = document.createElement('button');
    button.className = `menu-button ${className}`.trim();
    button.textContent = label;
    button.addEventListener('click', onClick);
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
    grid.className = `menu-actions ${columns === 3 ? 'three' : columns === 1 ? 'one' : ''}`;
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

function seatTaken(seat) {
    return !!(seat?.name && seat.name !== 'Open');
}

function tableHasBothSeats(seats = {}) {
    return seatTaken(seats.white) && seatTaken(seats.black);
}

function clockConfigLabel(clock) {
    if (!clock?.enabled) return 'Clock disabled';

    const base = formatClock(clock.initialMs || 0);
    const increment = Math.floor((clock.incrementMs || 0) / 1000);

    return increment > 0 ? `${base} + ${increment}s clock` : `${base} clock`;
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

function menuTab(label, view, data) {
    const button = document.createElement('button');
    button.className = `menu-tab ${tableMenuView === view ? 'active' : ''}`;
    button.textContent = label;
    button.addEventListener('click', () => {
        tableMenuView = view;
        renderTableMenu(data);
        if (view === 'stats') nui('requestLeaderboard');
    });
    return button;
}

function renderMenuTabs(data) {
    const tabs = document.createElement('nav');
    tabs.className = 'menu-tabs';
    tabs.append(
        menuTab('Play', 'play', data),
        menuTab('Stats', 'stats', data)
    );
    tableMenuEl.append(tabs);
}

function colorLabel(color) {
    if (!color) return 'No side selected';

    return `${color.charAt(0).toUpperCase()}${color.slice(1)} side`;
}

function compactButtonRow(buttons) {
    const row = document.createElement('div');
    row.className = 'compact-button-row';
    row.append(...buttons);
    return row;
}

function optionStrip(options, selected, onSelect) {
    const strip = document.createElement('div');
    strip.className = 'option-strip';

    for (const option of options) {
        strip.append(localMenuButton(option.label, () => onSelect(option.value), option.value === selected ? 'active' : ''));
    }

    return strip;
}

function ensureSelectedWager(data) {
    const amounts = data.wagers?.amounts || [];

    if (!amounts.length) {
        selectedWagerAmount = null;
        return null;
    }

    if (!amounts.includes(selectedWagerAmount)) {
        selectedWagerAmount = amounts[0];
    }

    return selectedWagerAmount;
}

function renderUnseatedPlayMenu(data) {
    appendMenuSection('Pick A Side', compactButtonRow([
        menuButton('White', { action: 'sit', tableId: data.tableId, color: 'white' }, 'primary'),
        menuButton('Black', { action: 'sit', tableId: data.tableId, color: 'black' }, 'primary')
    ]), 'Sit first, then choose how you want to play.');
}

function playStatusText(data) {
    const side = colorLabel(data.color);
    const clock = clockConfigLabel(data.clock);
    return `${side} · ${clock}`;
}

function renderRootPlayChoice(data) {
    const grid = document.createElement('div');
    grid.className = 'choice-grid';
    grid.append(
        localMenuButton('Player', () => {
            selectedPlayMode = 'player';
            selectedPlayerMode = null;
            renderTableMenu(data);
        }, 'choice-card primary'),
        localMenuButton('Bot', () => {
            selectedPlayMode = 'bot';
            selectedPlayerMode = null;
            renderTableMenu(data);
        }, 'choice-card')
    );
    return grid;
}

function backToRoot(data) {
    selectedPlayMode = null;
    selectedPlayerMode = null;
    renderTableMenu(data);
}

function renderBotFlow(data) {
    const wrapper = document.createElement('div');
    wrapper.className = 'mode-detail compact-flow';

    wrapper.append(optionStrip([
        { label: 'Easy', value: 'easy' },
        { label: 'Medium', value: 'medium' },
        { label: 'Hard', value: 'hard' }
    ], selectedBotDifficulty, (value) => {
        selectedBotDifficulty = value;
        renderTableMenu(data);
    }));
    wrapper.append(menuButton(`Start ${selectedBotDifficulty} bot`, {
        action: 'bot',
        tableId: data.tableId,
        color: data.color,
        difficulty: selectedBotDifficulty
    }, 'primary wide-compact'));
    wrapper.append(localMenuButton('Back', () => backToRoot(data)));
    return wrapper;
}

function renderPlayerTypeFlow(data) {
    const grid = document.createElement('div');
    grid.className = 'choice-grid';
    grid.append(
        localMenuButton('Non-Wager', () => {
            selectedPlayerMode = 'casual';
            renderTableMenu(data);
        }, 'choice-card primary'),
        localMenuButton('Wager', () => {
            selectedPlayerMode = 'wager';
            renderTableMenu(data);
        }, 'choice-card warn')
    );
    return grid;
}

function renderPlayerActions(data, mode) {
    const wrapper = document.createElement('div');
    wrapper.className = 'mode-detail compact-flow';
    const isWager = mode === 'wager';
    const amount = isWager ? ensureSelectedWager(data) : 0;

    if (isWager) {
        if (!data.wagers?.enabled || !amount) {
            wrapper.innerHTML = '<div class="menu-muted">Wagers are disabled for this table.</div>';
            wrapper.append(localMenuButton('Back', () => {
                selectedPlayerMode = null;
                renderTableMenu(data);
            }));
            return wrapper;
        }

        wrapper.append(optionStrip(data.wagers.amounts.map((wager) => ({
            label: `$${wager}`,
            value: wager
        })), amount, (value) => {
            selectedWagerAmount = value;
            renderTableMenu(data);
        }));
    }

    wrapper.append(compactButtonRow([
        menuButton('Wait', {
            action: 'wait',
            tableId: data.tableId,
            color: data.color,
            mode: isWager ? 'ranked' : 'casual',
            wagerAmount: amount
        }, isWager ? 'warn' : 'primary'),
        menuButton('Invite', {
            action: 'invitePicker',
            tableId: data.tableId,
            color: data.color,
            mode: isWager ? 'ranked' : 'casual',
            wagerAmount: amount
        }, isWager ? 'warn' : '')
    ]));
    wrapper.append(localMenuButton('Back', () => {
        selectedPlayerMode = null;
        renderTableMenu(data);
    }));

    if (tableHasBothSeats(data.seats) && data.matchId) {
        wrapper.append(menuButton('Roll for White', {
            action: 'fairSide',
            tableId: data.tableId,
            vsBot: false
        }));
    }

    return wrapper;
}

function renderPlayMenu(data) {
    if (data.invitePlayers) {
        appendMenuSection('Nearby Players', renderInvitePlayers(data), 'Choose someone close to the table.');
        appendMenuSection(null, compactButtonRow([
            localMenuButton('Back', () => {
                const next = { ...data };
                delete next.invitePlayers;
                renderTableMenu(next);
            }),
            menuButton('Stand', { action: 'stand' })
        ]));
        return;
    }

    if (!data.color) {
        renderUnseatedPlayMenu(data);
        return;
    }

    if (!selectedPlayMode) {
        appendMenuSection(null, renderRootPlayChoice(data), playStatusText(data));
    } else if (selectedPlayMode === 'bot') {
        appendMenuSection('Bot', renderBotFlow(data), playStatusText(data));
    } else if (!selectedPlayerMode) {
        appendMenuSection('Player', renderPlayerTypeFlow(data), 'Choose whether money is on the line.');
        appendMenuSection(null, localMenuButton('Back', () => backToRoot(data)));
    } else {
        const title = selectedPlayerMode === 'wager' ? 'Wager Match' : 'Player Match';
        const note = selectedPlayerMode === 'wager'
            ? 'Both players must accept the same wager before side choice.'
            : 'Invite someone nearby or wait for another player to sit down.';
        appendMenuSection(title, renderPlayerActions(data, selectedPlayerMode), note);
    }

    appendMenuSection(null, compactButtonRow([
        menuButton('Board Controls', { action: 'interact', tableId: data.tableId }),
        menuButton('Stand', { action: 'stand' })
    ]));
}

function statsActionButton(label, handler, className = '') {
    const button = document.createElement('button');
    button.className = `menu-button ${className}`.trim();
    button.textContent = label;
    button.addEventListener('click', handler);
    return button;
}

function renderStatsMenu() {
    const leaderboardWrap = document.createElement('div');
    leaderboardWrap.className = 'stats-block';

    leaderboardEl = document.createElement('div');
    leaderboardEl.id = 'leaderboard-main';
    leaderboardEl.className = 'leaderboard';
    leaderboardWrap.append(leaderboardEl);

    appendMenuSection('Top 10 Players', leaderboardWrap, 'Click a player to inspect rating, accuracy, and recent games.');

    const profileWrap = document.createElement('div');
    profileEl = document.createElement('div');
    profileEl.id = 'profile-main';
    profileEl.className = 'profile';
    profileWrap.append(profileEl);

    appendMenuSection('Player Stats', profileWrap);
    appendMenuSection(null, buttonGrid([
        statsActionButton('Refresh Stats', () => nui('requestLeaderboard'), 'primary')
    ], 1));

    renderLeaderboard(leaderboardPlayers);
    renderProfile(currentProfile);

    if (!leaderboardPlayers.length) {
        nui('requestLeaderboard');
    }
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
            <div class="menu-title">Play Chess</div>
            <div class="menu-subtitle">${data.tableId ? `Table ${escapeHtml(data.tableId)} · ` : ''}${data.color ? `${escapeHtml(data.color)} side selected` : 'Choose how you want to play'}</div>
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

    renderMenuTabs(data);

    if (tableMenuView === 'stats') {
        renderStatsMenu();
    } else {
        renderPlayMenu(data);
    }
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

function clearSideRollTimers() {
    for (const timer of sideRollTimers) {
        clearInterval(timer);
        clearTimeout(timer);
    }

    sideRollTimers = [];
}

function sideRollPlayerRows(players = [], reveal) {
    return players.map((player) => {
        const color = player.color ? `<span class="roll-color">${escapeHtml(player.color)}</span>` : '';
        const hasPick = player.picked || player.pick;
        const pick = reveal && player.pick ? player.pick : (hasPick ? 'Locked' : 'Waiting');
        const distance = reveal && typeof player.distance === 'number'
            ? `<span>${player.distance} away</span>`
            : '';

        return `
            <div class="roll-player ${player.color || ''}">
                <div>
                    <strong>${escapeHtml(player.name || 'Player')}</strong>
                    ${color}
                </div>
                <div class="roll-pick ${reveal ? 'slot-number' : ''}" data-final="${escapeHtml(pick)}">${escapeHtml(pick)}</div>
                ${distance}
            </div>
        `;
    }).join('');
}

function animateSideRollNumbers() {
    const numbers = Array.from(sideRollOverlay.querySelectorAll('.slot-number'));

    sideRollOverlay.classList.add('spinning');
    sideRollOverlay.classList.remove('revealed');

    const interval = setInterval(() => {
        for (const el of numbers) {
            el.textContent = String(Math.floor(Math.random() * 100) + 1).padStart(2, '0');
        }
    }, 70);

    const timeout = setTimeout(() => {
        clearInterval(interval);

        for (const el of numbers) {
            el.textContent = el.dataset.final || '';
        }

        sideRollOverlay.classList.remove('spinning');
        sideRollOverlay.classList.add('revealed');
    }, 1450);

    sideRollTimers.push(interval, timeout);
}

function renderSideRoll(data = {}) {
    clearSideRollTimers();

    if (data.visible === false) {
        sideRollOverlay.classList.add('hidden');
        sideRollOverlay.innerHTML = '';
        return;
    }

    const state = data.state || 'pick';
    const players = data.players || [];
    const closeButton = '<button id="side-roll-close" class="menu-button side-roll-close">x</button>';

    if (state === 'result') {
        sideRollOverlay.className = 'side-roll result';
        sideRollOverlay.innerHTML = `
            ${closeButton}
            <div class="roll-title">White Side Roll</div>
            <div class="roll-subtitle">${escapeHtml(data.winnerName || 'Winner')} gets white</div>
            <div class="roll-target">
                <span>Target Number</span>
                <strong class="slot-number" data-final="${escapeHtml(data.target || '')}">${escapeHtml(data.target || '')}</strong>
            </div>
            <div class="roll-players">${sideRollPlayerRows(players, true)}</div>
            <div class="roll-summary">${escapeHtml(data.whiteName || 'White')} plays white. ${escapeHtml(data.blackName || 'Black')} plays black.</div>
        `;
        sideRollOverlay.classList.remove('hidden');
        animateSideRollNumbers();
    } else {
        const locked = state === 'waiting';

        sideRollOverlay.className = 'side-roll pick';
        sideRollOverlay.innerHTML = `
            ${closeButton}
            <div class="roll-title">Roll for White</div>
            <div class="roll-subtitle">Pick a number from 1 to 100. Closest to the rolled target gets white.</div>
            <div class="roll-players">${sideRollPlayerRows(players, false)}</div>
            <form id="side-roll-form" class="side-roll-form">
                <input id="side-roll-number" type="number" min="1" max="100" value="50" ${locked ? 'disabled' : ''}>
                <button class="menu-button primary" type="submit" ${locked ? 'disabled' : ''}>Lock Number</button>
            </form>
            <div class="menu-muted">${locked ? 'Number locked. Waiting for the other player.' : 'Your number stays hidden until the reveal.'}</div>
        `;
        sideRollOverlay.classList.remove('hidden');

        const form = document.getElementById('side-roll-form');

        if (form && !locked) {
            form.addEventListener('submit', (event) => {
                event.preventDefault();
                const number = Number(document.getElementById('side-roll-number')?.value || 0);
                renderSideRoll({
                    ...data,
                    state: 'waiting',
                    players: players.map((player, index) => index === 0 ? { ...player, picked: true } : player)
                });
                nui('sideRollPick', { tableId: data.tableId, number });
            });
        }
    }

    document.getElementById('side-roll-close')?.addEventListener('click', () => {
        renderSideRoll({ visible: false });
        nui('sideRollClose', { tableId: data.tableId });
    });
}

function moveText(move) {
    if (!move) return '';
    const suffix = move.promotion ? `=${move.promotion.toUpperCase()}` : '';
    const capture = move.capturedPiece ? 'x' : '-';
    return `${move.from}${capture}${move.to}${suffix}`;
}

function sameMove(a, b) {
    return !!a && !!b
        && a.from === b.from
        && a.to === b.to
        && (a.piece || '') === (b.piece || '')
        && (a.promotion || '') === (b.promotion || '');
}

function setHoveredMove(move) {
    hoveredMove = move || null;
    lastMoveCard.classList.toggle('is-hovered', !!hoveredMove);
    nui('lastMoveHover', {
        visible: !!hoveredMove,
        move: hoveredMove ? {
            from: hoveredMove.from,
            to: hoveredMove.to,
            piece: hoveredMove.piece,
            finalPiece: hoveredMove.finalPiece,
            promotion: hoveredMove.promotion,
            capturedPiece: hoveredMove.capturedPiece
        } : null
    });
    renderBoard();
}

function clearLastMoveHoverHandlers() {
    if (clearLastMoveHoverListeners) {
        clearLastMoveHoverListeners();
        clearLastMoveHoverListeners = null;
    }

    lastMoveCard.removeAttribute('tabindex');
}

function renderLastMove(history) {
    const move = history[history.length - 1] || snapshot?.lastMove;

    if (snapshot?.state === 'finished') {
        lastMoveCard.classList.add('hidden');
        lastMoveCard.innerHTML = '';
        clearLastMoveHoverHandlers();
        setHoveredMove(null);
        return;
    }

    lastMoveCard.classList.remove('hidden');
    lastMoveCard.classList.toggle('is-hovered', sameMove(hoveredMove, move));

    if (!move) {
        lastMoveCard.innerHTML = '<span class="card-label">Last move</span><strong>No moves yet</strong>';
        clearLastMoveHoverHandlers();
        setHoveredMove(null);
        return;
    }

    if (hoveredMove && !sameMove(hoveredMove, move)) {
        setHoveredMove(null);
    }

    const actor = move.color ? `${move.color.charAt(0).toUpperCase()}${move.color.slice(1)}` : 'Last';
    const pieceCode = move.finalPiece || move.piece;
    const piece = pieceNames[pieceCode] || pieceCode || 'Piece';
    clearLastMoveHoverHandlers();
    lastMoveCard.innerHTML = `
        <span class="card-label">Last move</span>
        <span class="last-move-line">
            ${pieceBadgeHtml(pieceCode, 'last-move-piece')}
            <strong>${escapeHtml(actor)} ${escapeHtml(moveText(move))}</strong>
        </span>
        <span class="move-hover-detail">${escapeHtml(piece)} from ${escapeHtml(move.from)} to ${escapeHtml(move.to)}</span>
    `;
    const showHover = () => setHoveredMove(move);
    const clearHover = () => setHoveredMove(null);
    lastMoveCard.addEventListener('pointerenter', showHover);
    lastMoveCard.addEventListener('pointerleave', clearHover);
    lastMoveCard.addEventListener('focus', showHover);
    lastMoveCard.addEventListener('blur', clearHover);
    clearLastMoveHoverListeners = () => {
        lastMoveCard.removeEventListener('pointerenter', showHover);
        lastMoveCard.removeEventListener('pointerleave', clearHover);
        lastMoveCard.removeEventListener('focus', showHover);
        lastMoveCard.removeEventListener('blur', clearHover);
    };
    lastMoveCard.tabIndex = 0;
}

function renderMoves() {
    const history = snapshot?.moveHistory || [];
    movesList.innerHTML = '';
    renderLastMove(history);

    if (snapshot?.state !== 'finished') {
        movesList.classList.add('hidden');
        return;
    }

    movesList.classList.remove('hidden');

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
    const showQuality = snapshot?.state === 'finished';
    const quality = showQuality && move.accuracy ? `<div class="move-quality">${move.accuracy}% ${move.quality || ''}</div>` : '';
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
            cell.innerHTML = pieceBadgeHtml(piece, 'board-piece');

            if (selectedSquare === square) cell.classList.add('selected');
            if (legalBySquare[square]) cell.classList.add(legalBySquare[square].capture ? 'capture' : 'legal');
            if (hoveredMove?.from === square) cell.classList.add('last-from');
            if (hoveredMove?.to === square) cell.classList.add('last-to');

            cell.addEventListener('mousedown', (event) => {
                if (event.button !== 0 && event.button !== 2) return;
                event.preventDefault();
                nui('boardSquare', { square });
            });

            boardEl.append(cell);
        }
    }
}

function formatClock(ms) {
    const totalSeconds = Math.max(0, Math.ceil(Number(ms || 0) / 1000));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    if (hours > 0) {
        return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
    }

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

function renderClock() {
    const clock = snapshot?.clock;

    if (!clock?.enabled) {
        clockStrip.classList.add('hidden');
        return;
    }

    clockStrip.classList.remove('hidden');

    for (const color of ['white', 'black']) {
        const el = clockEls[color];
        const remaining = clockRemaining(color);
        const lowTime = remaining !== null && remaining <= Number(clock.lowTimeMs || 30000);
        const active = snapshot?.state === 'active' && clock.activeColor === color;

        el.classList.toggle('active', active);
        el.classList.toggle('low', lowTime);
        el.querySelector('span').textContent = color === 'white'
            ? (snapshot.whiteName || 'White')
            : (snapshot.blackName || 'Black');
        el.querySelector('strong').textContent = formatClock(remaining);
    }
}

function renderStatus() {
    const title = document.getElementById('match-title');
    const subtitle = document.getElementById('match-subtitle');
    const active = snapshot?.state === 'active';
    const finished = snapshot?.state === 'finished';
    const playerSide = ['white', 'black'].includes(boardPerspective) ? boardPerspective : null;
    const yourTurn = !!(active && playerSide && snapshot?.turn === playerSide);
    const opponentTurn = !!(active && playerSide && snapshot?.turn !== playerSide);

    sidePanel.classList.toggle('active-match', !!active);
    sidePanel.classList.toggle('finished-match', !!finished);
    sidePanel.classList.toggle('board-open', !!(active && matchBoardOpen));
    turnCard.classList.remove('your-turn', 'opponent-turn', 'finished');
    turnCard.classList.toggle('your-turn', yourTurn);
    turnCard.classList.toggle('opponent-turn', opponentTurn);
    turnCard.classList.toggle('finished', finished);

    if (!snapshot) {
        title.textContent = 'Chess';
        subtitle.textContent = 'No active match';
        turnCard.textContent = 'Waiting for match data';
        resignButton.classList.add('hidden');
        boardToggleButton.classList.add('hidden');
        cameraToggleButton.classList.add('hidden');
        matchBoardOpen = false;
        renderClock();
        return;
    }

    title.textContent = `Match ${snapshot.id}`;
    subtitle.textContent = `${snapshot.whiteName || 'White'} vs ${snapshot.blackName || 'Black'}`;
    if (finished) {
        turnCard.innerHTML = `<span class="card-label">Result</span><strong>${escapeHtml(snapshot.result || 'draw')}</strong>`;
    } else if (yourTurn) {
        turnCard.innerHTML = '<span class="card-label">Turn</span><strong>Your turn</strong>';
    } else if (opponentTurn) {
        turnCard.innerHTML = '<span class="card-label">Turn</span><strong>Opponent\'s turn</strong>';
    } else {
        turnCard.innerHTML = `<span class="card-label">Turn</span><strong>${escapeHtml(snapshot.turn || 'white')}'s turn</strong>`;
    }
    resignButton.classList.toggle('hidden', !active);
    boardToggleButton.classList.toggle('hidden', !active);
    cameraToggleButton.classList.toggle('hidden', !active);
    boardToggleButton.textContent = matchBoardOpen ? 'Hide Board' : 'View Board';
    cameraToggleButton.textContent = cameraMode === 'topdown' ? 'Angle View' : 'Top View';
    renderClock();
}

function setLegalMoves(data) {
    selectedSquare = data?.from || null;
    legalMoves = data?.moves || [];
    const piece = snapshot?.board?.[selectedSquare] || data?.piece;
    selectedLabel.textContent = piece ? `${pieceNames[piece] || piece} on ${selectedSquare}` : 'Select a piece';
    renderBoard();
}

function renderLeaderboard(players) {
    leaderboardPlayers = (players || []).slice(0, 10);
    if (!leaderboardEl) return;

    leaderboardEl.innerHTML = '';

    if (!leaderboardPlayers.length) {
        leaderboardEl.innerHTML = '<div class="menu-muted">No ranked players yet.</div>';
        return;
    }

    for (const player of leaderboardPlayers) {
        const row = document.createElement('button');
        row.className = 'leader-row';
        if (currentProfile?.identifier && currentProfile.identifier === player.identifier) {
            row.classList.add('selected');
        }
        row.innerHTML = `<span>#${player.rank}</span><span>${player.name}</span><strong>${player.rating}</strong>`;
        row.addEventListener('click', () => nui('requestProfile', { identifier: player.identifier }));
        leaderboardEl.append(row);
    }

    if (!currentProfile && leaderboardPlayers[0]?.identifier) {
        nui('requestProfile', { identifier: leaderboardPlayers[0].identifier });
    }
}

function renderProfile(profile) {
    currentProfile = profile || null;
    if (!profileEl) return;

    if (!profile) {
        profileEl.innerHTML = '<div class="menu-muted">Select a player from the leaderboard.</div>';
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

    renderLeaderboard(leaderboardPlayers);
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
        snapshotReceivedAt = performance.now();
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
    if (data.action === 'cameraMode') {
        cameraMode = data.mode === 'topdown' ? 'topdown' : 'normal';
        renderStatus();
    }
    if (data.action === 'tableMenu') renderTableMenu(data);
    if (data.action === 'feedback') showFeedback(data);
    if (data.action === 'matchResult') renderMatchResult(data);
    if (data.action === 'sideRoll') renderSideRoll(data);
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
boardToggleButton.addEventListener('click', () => {
    matchBoardOpen = !matchBoardOpen;
    renderStatus();
});
cameraToggleButton.addEventListener('click', () => nui('cameraToggle'));
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
    if (!event.repeat && (event.key.toLowerCase() === 'h' || event.key.toLowerCase() === 'g')) nui('cameraToggle');
});

document.addEventListener('wheel', (event) => {
    nui('tuneWheel', { direction: event.deltaY < 0 ? 1 : -1 });
});

function devBoard() {
    return {
        a1: 'wR',
        b1: 'wN',
        c1: 'wB',
        d1: 'wQ',
        e1: 'wK',
        f1: 'wB',
        h1: 'wR',
        a2: 'wP',
        b2: 'wP',
        c2: 'wP',
        f2: 'wP',
        g2: 'wP',
        h2: 'wP',
        d4: 'wP',
        d5: 'wP',
        c4: 'wB',
        f3: 'wN',
        a8: 'bR',
        b8: 'bN',
        c8: 'bB',
        d8: 'bQ',
        e8: 'bK',
        f8: 'bB',
        h8: 'bR',
        a7: 'bP',
        b7: 'bP',
        c7: 'bP',
        e7: 'bP',
        f7: 'bP',
        g7: 'bP',
        h7: 'bP',
        f6: 'bN',
        b4: 'bB'
    };
}

function devSnapshot() {
    const finished = devParams.get('state') === 'finished';
    const now = Date.now();

    return {
        id: 42,
        mode: 'ranked',
        state: finished ? 'finished' : 'active',
        tableId: 1,
        white: 1,
        black: 0,
        whiteName: 'cody_raves',
        blackName: 'Hard bot',
        botColor: 'black',
        botDifficulty: 'hard',
        turn: 'white',
        board: devBoard(),
        fen: 'dev-preview',
        capturedWhite: ['wP', 'wN'],
        capturedBlack: ['bP', 'bP', 'bB'],
        winner: finished ? 'white' : null,
        result: finished ? 'white_win' : null,
        finishReason: finished ? 'checkmate' : null,
        clock: {
            enabled: true,
            initialMs: 600000,
            incrementMs: 0,
            activeColor: finished ? null : 'white',
            serverNow: now,
            lowTimeMs: 30000,
            remaining: {
                white: 196000,
                black: 210000
            }
        },
        moveHistory: [
            { color: 'white', from: 'e2', to: 'e4', piece: 'wP', accuracy: 96, quality: 'Best' },
            { color: 'black', from: 'd7', to: 'd5', piece: 'bP', accuracy: 84, quality: 'Good' },
            { color: 'white', from: 'e4', to: 'd5', piece: 'wP', capturedPiece: 'bP', accuracy: 88, quality: 'Good' },
            { color: 'black', from: 'g8', to: 'f6', piece: 'bN', accuracy: 91, quality: 'Best' },
            { color: 'white', from: 'g1', to: 'f3', piece: 'wN', accuracy: 89, quality: 'Good' },
            { color: 'black', from: 'f8', to: 'b4', piece: 'bB', accuracy: 72, quality: 'Mistake' },
            { color: 'white', from: 'f1', to: 'c4', piece: 'wB', accuracy: 94, quality: 'Best' }
        ],
        lastMove: {
            color: 'white',
            from: 'f1',
            to: 'c4',
            piece: 'wB',
            fen: 'dev-preview'
        },
        review: finished ? {
            whiteAccuracy: 91,
            blackAccuracy: 78,
            mistakes: 1,
            blunders: 0
        } : null,
        status: {
            check: false,
            checkmate: false,
            stalemate: false
        }
    };
}

function devClockConfig() {
    return {
        enabled: true,
        initialMs: 600000,
        incrementMs: 0
    };
}

function devLeaderboard() {
    return [
        { rank: 1, identifier: 'dev:cody', name: 'cody_raves', rating: 1032 },
        { rank: 2, identifier: 'dev:ava', name: 'Ava', rating: 984 },
        { rank: 3, identifier: 'dev:tom', name: 'Tom', rating: 911 },
        { rank: 4, identifier: 'dev:mason', name: 'Mason', rating: 884 },
        { rank: 5, identifier: 'dev:ivy', name: 'Ivy', rating: 841 },
        { rank: 6, identifier: 'dev:noah', name: 'Noah', rating: 822 },
        { rank: 7, identifier: 'dev:mia', name: 'Mia', rating: 807 },
        { rank: 8, identifier: 'dev:jay', name: 'Jay', rating: 792 },
        { rank: 9, identifier: 'dev:leo', name: 'Leo', rating: 775 },
        { rank: 10, identifier: 'dev:zoe', name: 'Zoe', rating: 760 }
    ];
}

function devProfile(identifier = 'dev:cody') {
    const player = devLeaderboard().find((item) => item.identifier === identifier) || devLeaderboard()[0];

    return {
        identifier: player.identifier,
        name: player.name,
        rating: player.rating,
        rankName: 'Rapid',
        gamesPlayed: player.rank === 1 ? 37 : Math.max(3, 18 - player.rank),
        accuracy: Math.max(62, 88 - player.rank),
        matches: [
            { mode: 'ranked wager', result: player.rank === 1 ? 'white_win' : 'black_win', whiteName: player.name, blackName: 'Hard bot', moveCount: 31 },
            { mode: 'casual', result: 'draw', whiteName: 'Tom', blackName: player.name, moveCount: 58 }
        ]
    };
}

function devSideRollPick(vsBot) {
    return {
        state: 'pick',
        tableId: 1,
        players: [
            { name: 'cody_raves' },
            { name: vsBot ? 'Bot' : 'Tom', isBot: !!vsBot }
        ]
    };
}

function devSideRollResult(playerPick) {
    const opponentPick = 73;
    const target = 64;
    const playerDistance = Math.abs(playerPick - target);
    const opponentDistance = Math.abs(opponentPick - target);
    const playerWins = playerDistance <= opponentDistance;

    return {
        state: 'result',
        tableId: 1,
        target,
        winnerName: playerWins ? 'cody_raves' : 'Tom',
        whiteName: playerWins ? 'cody_raves' : 'Tom',
        blackName: playerWins ? 'Tom' : 'cody_raves',
        players: [
            {
                name: 'cody_raves',
                pick: playerPick,
                distance: playerDistance,
                color: playerWins ? 'white' : 'black'
            },
            {
                name: 'Tom',
                pick: opponentPick,
                distance: opponentDistance,
                color: playerWins ? 'black' : 'white'
            }
        ]
    };
}

function devBaseMenuData(state = 'seated') {
    const seated = state !== 'seat';

    return {
        visible: true,
        tableId: 1,
        color: seated ? 'white' : null,
        seats: seated
            ? {
                white: { name: 'cody_raves' },
                black: { name: 'Open' }
            }
            : {
                white: { name: 'Open' },
                black: { name: 'Open' }
            },
        matchId: seated ? null : undefined,
        wagers: {
            enabled: true,
            account: 'cash',
            amounts: [100, 500, 1000]
        },
        clock: devClockConfig()
    };
}

function devMenuData(state = 'seated') {
    const data = devBaseMenuData(state);

    if (state === 'invite') {
        data.invitePlayers = [
            { source: 7, name: 'Tom', distance: 1.4 },
            { source: 12, name: 'Ava', distance: 2.2 },
            { source: 19, name: 'Mason', distance: 3.8 }
        ];
        data.inviteMode = 'ranked';
        data.wagerAmount = 0;
    }

    if (state === 'wager') {
        data.invitePlayers = [
            { source: 7, name: 'Tom', distance: 1.4 },
            { source: 12, name: 'Ava', distance: 2.2 }
        ];
        data.inviteMode = 'ranked';
        data.wagerAmount = 500;
    }

    if (state === 'incoming') {
        data.color = 'black';
        data.invite = {
            fromName: 'Tom',
            matchId: 77,
            mode: 'ranked',
            wagerAmount: 500
        };
    }

    if (state === 'both') {
        data.color = 'white';
        data.seats = {
            white: { name: 'cody_raves' },
            black: { name: 'Tom' }
        };
    }

    return data;
}

function showDevMenuState(state) {
    renderTableMenu(devMenuData(state));
}

function devHandleTableMenuAction(data = {}) {
    if (data.action === 'sit') {
        showDevMenuState('seated');
    } else if (data.action === 'invitePicker') {
        showDevMenuState(Number(data.wagerAmount || 0) > 0 ? 'wager' : 'invite');
    } else if (data.action === 'fairSide') {
        renderSideRoll(devSideRollPick(data.vsBot === true));
    } else if (data.action === 'close') {
        renderTableMenu({ visible: false });
    } else if (data.action === 'stand') {
        showDevMenuState('seat');
    }
}

function renderDevToolbar() {
    let toolbar = document.getElementById('dev-toolbar');

    if (!toolbar) {
        toolbar = document.createElement('div');
        toolbar.id = 'dev-toolbar';
        app.append(toolbar);
    }

    toolbar.innerHTML = '';

    const states = [
        ['seat', 'Choose Seat'],
        ['seated', 'Seated Menu'],
        ['both', 'Two Players'],
        ['invite', 'Invite Picker'],
        ['wager', 'Wager Invite'],
        ['incoming', 'Incoming Invite']
    ];

    for (const [state, label] of states) {
        const button = document.createElement('button');
        button.textContent = label;
        button.addEventListener('click', () => showDevMenuState(state));
        toolbar.append(button);
    }
}

function startDevPreview() {
    snapshot = devSnapshot();
    snapshotReceivedAt = performance.now();
    boardPerspective = devParams.get('side') === 'black' ? 'black' : 'white';

    setVisible(true);
    renderDevToolbar();
    showDevMenuState(devParams.get('menu') || 'seated');
    renderStatus();
    renderMoves();
    renderReview();
    renderBoard();
    renderLeaderboard(devLeaderboard());
    renderProfile(devProfile('dev:cody'));

    if (snapshot.state === 'finished') {
        renderMatchResult({
            result: 'win',
            title: 'Victory',
            subtitle: 'You won by checkmate.',
            review: snapshot.review
        });
    }
}

setInterval(renderClock, 250);

if (devPreview) {
    startDevPreview();
} else {
    renderBoard();
}
