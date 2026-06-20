CRChess = CRChess or {}

local Bot = {}
CRChess.Bot = Bot

local Engine = CRChess.Engine

local function botConfig()
    local config = rawget(_G, 'Config')
    return config and config.BotAI or {}
end

local function shuffled(moves)
    local copy = {}

    for index, move in ipairs(moves) do
        copy[index] = move
    end

    for index = #copy, 2, -1 do
        local swap = math.random(index)
        copy[index], copy[swap] = copy[swap], copy[index]
    end

    return copy
end

local function moveScore(state, move, color)
    local score = 0

    if move.capture then
        local capturedPiece = state.board[move.capture] or state.board[move.to]
        score = score + Engine.materialValue(capturedPiece) + 50
    end

    if move.promotion then
        score = score + Engine.materialValue(Engine.colorPrefix(color) .. move.promotion:upper())
    end

    local clone = Engine.cloneState(state)
    Engine.applyMoveUnchecked(clone, move)

    if Engine.isInCheck(clone, clone.turn) then
        score = score + 75
    end

    return score + Engine.evaluateMaterial(clone, color)
end

local function quickMoveScore(state, move)
    local score = 0

    if move.capture then
        local capturedPiece = state.board[move.capture] or state.board[move.to]
        score = score + Engine.materialValue(capturedPiece) * 10 + 100
    end

    if move.promotion then
        score = score + Engine.materialValue(Engine.colorPrefix(state.turn) .. move.promotion:upper()) * 10
    end

    if move.castle then
        score = score + 25
    end

    return score
end

local function orderedMoves(state, moves, limit)
    local scored = {}

    for index, move in ipairs(shuffled(moves)) do
        scored[index] = {
            move = move,
            score = quickMoveScore(state, move)
        }
    end

    table.sort(scored, function(left, right)
        return left.score > right.score
    end)

    local ordered = {}
    local maxMoves = limit and math.min(#scored, limit) or #scored

    for index = 1, maxMoves do
        ordered[index] = scored[index].move
    end

    return ordered
end

local function chooseBestHeuristic(state, color)
    local moves = shuffled(Engine.generateLegalMoves(state, color))
    local bestMove = nil
    local bestScore = -math.huge

    for _, move in ipairs(moves) do
        local score = moveScore(state, move, color)

        if score > bestScore then
            bestMove = move
            bestScore = score
        end
    end

    return bestMove
end

local function minimax(state, depth, botColor, alpha, beta, branchLimit)
    local moves = Engine.generateLegalMoves(state, state.turn)

    if #moves == 0 then
        if Engine.isInCheck(state, state.turn) then
            return state.turn == botColor and -100000 or 100000
        end

        return 0
    end

    if depth <= 0 then
        local mobility = state.turn == botColor and #moves or -#moves
        return Engine.evaluateMaterial(state, botColor) + mobility
    end

    moves = orderedMoves(state, moves, branchLimit)
    local maximizing = state.turn == botColor

    if maximizing then
        local best = -math.huge

        for _, move in ipairs(moves) do
            local clone = Engine.cloneState(state)
            Engine.applyMoveUnchecked(clone, move)
            best = math.max(best, minimax(clone, depth - 1, botColor, alpha, beta, branchLimit))
            alpha = math.max(alpha, best)

            if beta <= alpha then
                break
            end
        end

        return best
    end

    local best = math.huge

    for _, move in ipairs(moves) do
        local clone = Engine.cloneState(state)
        Engine.applyMoveUnchecked(clone, move)
        best = math.min(best, minimax(clone, depth - 1, botColor, alpha, beta, branchLimit))
        beta = math.min(beta, best)

        if beta <= alpha then
            break
        end
    end

    return best
end

local function chooseMinimax(state, color)
    local config = botConfig()
    local depth = math.max(1, tonumber(config.hardDepth) or 2)
    local rootLimit = tonumber(config.hardRootMoveLimit) or 14
    local branchLimit = tonumber(config.hardBranchMoveLimit) or 10
    local moves = orderedMoves(state, Engine.generateLegalMoves(state, color), rootLimit)
    local bestMove = nil
    local bestScore = -math.huge

    for _, move in ipairs(moves) do
        local clone = Engine.cloneState(state)
        Engine.applyMoveUnchecked(clone, move)
        local score = minimax(clone, depth - 1, color, -math.huge, math.huge, branchLimit)

        if score > bestScore then
            bestMove = move
            bestScore = score
        end
    end

    return bestMove
end

function Bot.chooseMove(state, difficulty)
    local color = state.turn
    local moves = Engine.generateLegalMoves(state, color)

    if #moves == 0 then
        return nil
    end

    difficulty = (difficulty or 'easy'):lower()

    if difficulty == 'hard' then
        return chooseMinimax(state, color)
    end

    if difficulty == 'medium' then
        return chooseBestHeuristic(state, color)
    end

    return shuffled(moves)[1]
end
