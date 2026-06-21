CRChess = {}

dofile('server/chess_engine.lua')
dofile('server/bot.lua')
dofile('server/stats.lua')

local Engine = CRChess.Engine
local Bot = CRChess.Bot
local Stats = CRChess.Stats

math.randomseed(1234)

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = {
        name = name,
        fn = fn
    }
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or 'assertEqual failed') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
    end
end

local function assertTruthy(value, message)
    if not value then
        error(message or 'expected truthy value', 2)
    end
end

local function assertMove(state, from, to, promotion)
    local ok, err = Engine.move(state, from, to, promotion)
    assertTruthy(ok, ('expected %s-%s to be legal, got %s'):format(from, to, tostring(err)))
    return err
end

local function assertIllegal(state, from, to, promotion)
    local ok = Engine.move(state, from, to, promotion)

    if ok then
        error(('expected %s-%s to be illegal'):format(from, to), 2)
    end
end

test('standard opening moves', function()
    local state = Engine.newState()

    assertMove(state, 'e2', 'e4')
    assertMove(state, 'e7', 'e5')

    assertEqual(state.board.e4, 'wP')
    assertEqual(state.board.e5, 'bP')
    assertEqual(state.turn, 'white')
end)

test('illegal movement rejection', function()
    local state = Engine.newState()

    assertIllegal(state, 'e2', 'e5')
end)

test('turn enforcement', function()
    local state = Engine.newState()

    assertMove(state, 'e2', 'e4')
    assertIllegal(state, 'g1', 'f3')
end)

test('legal moves from selected piece', function()
    local state = Engine.newState()
    local moves = Engine.legalMovesFrom(state, 'g1', 'white')
    local destinations = {}

    for _, move in ipairs(moves) do
        destinations[move.to] = true
    end

    assertTruthy(destinations.f3, 'knight should be able to move to f3')
    assertTruthy(destinations.h3, 'knight should be able to move to h3')
    assertEqual(destinations.g2, nil)
end)

test('self-check rejection', function()
    local state = assert(Engine.loadFen('k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1'))

    assertIllegal(state, 'e2', 'd2')
end)

test('captures', function()
    local state = Engine.newState()

    assertMove(state, 'e2', 'e4')
    assertMove(state, 'd7', 'd5')
    assertMove(state, 'e4', 'd5')

    assertEqual(state.board.d5, 'wP')
    assertEqual(state.board.e4, nil)
end)

test('fools mate checkmate', function()
    local state = Engine.newState()

    assertMove(state, 'f2', 'f3')
    assertMove(state, 'e7', 'e5')
    assertMove(state, 'g2', 'g4')
    assertMove(state, 'd8', 'h4')

    local status = Engine.status(state)
    assertTruthy(status.checkmate, 'expected checkmate')
    assertEqual(status.winner, 'black')
end)

test('stalemate fixture', function()
    local state = assert(Engine.loadFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'))
    local status = Engine.status(state)

    assertTruthy(status.stalemate, 'expected stalemate')
end)

test('insufficient material bare kings', function()
    local state = assert(Engine.loadFen('8/8/8/8/8/8/4k3/4K3 w - - 0 1'))
    local status = Engine.status(state)

    assertTruthy(status.insufficientMaterial, 'expected insufficient material')
    assertEqual(status.winner, nil)
end)

test('insufficient material single minor', function()
    local bishopState = assert(Engine.loadFen('8/8/8/8/8/8/4k3/3BK3 w - - 0 1'))
    local knightState = assert(Engine.loadFen('8/8/8/8/8/8/4k3/3NK3 w - - 0 1'))

    assertTruthy(Engine.status(bishopState).insufficientMaterial, 'expected king bishop vs king draw')
    assertTruthy(Engine.status(knightState).insufficientMaterial, 'expected king knight vs king draw')
end)

test('sufficient material queen remains playable', function()
    local state = assert(Engine.loadFen('8/8/8/8/8/8/4k3/3QK3 w - - 0 1'))

    assertEqual(Engine.status(state).insufficientMaterial, false)
end)

test('castling', function()
    local state = assert(Engine.loadFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'))

    assertMove(state, 'e1', 'g1')

    assertEqual(state.board.g1, 'wK')
    assertEqual(state.board.f1, 'wR')
    assertEqual(state.board.e1, nil)
    assertEqual(state.board.h1, nil)
end)

test('en passant', function()
    local state = Engine.newState()

    assertMove(state, 'e2', 'e4')
    assertMove(state, 'a7', 'a6')
    assertMove(state, 'e4', 'e5')
    assertMove(state, 'd7', 'd5')
    assertMove(state, 'e5', 'd6')

    assertEqual(state.board.d6, 'wP')
    assertEqual(state.board.d5, nil)
end)

test('promotion', function()
    local state = assert(Engine.loadFen('k7/4P3/8/8/8/8/8/4K3 w - - 0 1'))

    assertMove(state, 'e7', 'e8', 'q')
    assertEqual(state.board.e8, 'wQ')
end)

test('FEN output', function()
    local state = Engine.newState()

    assertEqual(Engine.toFen(state), 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1')
end)

test('bot move legality', function()
    local state = Engine.newState()
    local move = Bot.chooseMove(state, 'hard')

    assertTruthy(move, 'expected bot move')
    assertMove(state, move.from, move.to, move.promotion)
end)

test('ranked rating and leaderboard ordering', function()
    Stats.players = {}
    Stats.matches = {}

    Stats.recordMatch({
        mode = 'ranked',
        whiteIdentifier = 'license:white',
        blackIdentifier = 'license:black',
        whiteName = 'White',
        blackName = 'Black',
        winnerIdentifier = 'license:white',
        result = 'white_win'
    })

    local white = Stats.players['license:white']
    local black = Stats.players['license:black']
    local leaderboard = Stats.leaderboard(2)

    assertTruthy(white.rating > black.rating, 'winner should gain rating')
    assertEqual(leaderboard[1].identifier, 'license:white')
end)

local passed = 0

for _, item in ipairs(tests) do
    io.write(('Running %-36s'):format(item.name .. '...'))
    item.fn()
    passed = passed + 1
    io.write(' ok\n')
end

print(('%d tests passed.'):format(passed))
