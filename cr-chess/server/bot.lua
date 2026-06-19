CRChess = CRChess or {}

local Bot = {}
CRChess.Bot = Bot

local Engine = CRChess.Engine

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

local function minimax(state, depth, botColor, alpha, beta)
    local status = Engine.status(state)

    if status.checkmate then
        return status.winner == botColor and 100000 or -100000
    end

    if status.stalemate then
        return 0
    end

    if depth == 0 then
        local mobility = #Engine.generateLegalMoves(state, botColor)
        return Engine.evaluateMaterial(state, botColor) + mobility
    end

    local moves = Engine.generateLegalMoves(state, state.turn)
    local maximizing = state.turn == botColor

    if maximizing then
        local best = -math.huge

        for _, move in ipairs(moves) do
            local clone = Engine.cloneState(state)
            Engine.applyMoveUnchecked(clone, move)
            best = math.max(best, minimax(clone, depth - 1, botColor, alpha, beta))
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
        best = math.min(best, minimax(clone, depth - 1, botColor, alpha, beta))
        beta = math.min(beta, best)

        if beta <= alpha then
            break
        end
    end

    return best
end

local function chooseMinimax(state, color)
    local moves = shuffled(Engine.generateLegalMoves(state, color))
    local bestMove = nil
    local bestScore = -math.huge

    for _, move in ipairs(moves) do
        local clone = Engine.cloneState(state)
        Engine.applyMoveUnchecked(clone, move)
        local score = minimax(clone, 2, color, -math.huge, math.huge)

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
