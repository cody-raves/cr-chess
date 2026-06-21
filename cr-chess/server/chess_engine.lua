CRChess = CRChess or {}

local Engine = {}
CRChess.Engine = Engine

local files = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' }
local fileIndex = {}

for index, file in ipairs(files) do
    fileIndex[file] = index
end

local pieceFromFen = {
    P = 'wP',
    R = 'wR',
    N = 'wN',
    B = 'wB',
    Q = 'wQ',
    K = 'wK',
    p = 'bP',
    r = 'bR',
    n = 'bN',
    b = 'bB',
    q = 'bQ',
    k = 'bK'
}

local fenFromPiece = {
    wP = 'P',
    wR = 'R',
    wN = 'N',
    wB = 'B',
    wQ = 'Q',
    wK = 'K',
    bP = 'p',
    bR = 'r',
    bN = 'n',
    bB = 'b',
    bQ = 'q',
    bK = 'k'
}

local material = {
    P = 100,
    N = 320,
    B = 330,
    R = 500,
    Q = 900,
    K = 0
}

local knightOffsets = {
    { 1, 2 },
    { 2, 1 },
    { 2, -1 },
    { 1, -2 },
    { -1, -2 },
    { -2, -1 },
    { -2, 1 },
    { -1, 2 }
}

local kingOffsets = {
    { 1, 1 },
    { 1, 0 },
    { 1, -1 },
    { 0, 1 },
    { 0, -1 },
    { -1, 1 },
    { -1, 0 },
    { -1, -1 }
}

local bishopDirections = {
    { 1, 1 },
    { 1, -1 },
    { -1, 1 },
    { -1, -1 }
}

local rookDirections = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 }
}

local queenDirections = {
    { 1, 1 },
    { 1, -1 },
    { -1, 1 },
    { -1, -1 },
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 }
}

local function splitWords(value)
    local words = {}

    for word in tostring(value or ''):gmatch('%S+') do
        words[#words + 1] = word
    end

    return words
end

local function ensureCastling(state)
    state.castling = state.castling or {}
    state.castling.white = state.castling.white or { k = false, q = false }
    state.castling.black = state.castling.black or { k = false, q = false }
end

local function addMove(moves, from, to, extra)
    local move = {
        from = from,
        to = to
    }

    if extra then
        for key, value in pairs(extra) do
            move[key] = value
        end
    end

    moves[#moves + 1] = move
end

local function addPromotionMoves(moves, from, to, extra)
    for _, promotion in ipairs({ 'q', 'r', 'b', 'n' }) do
        local promoted = {}

        if extra then
            for key, value in pairs(extra) do
                promoted[key] = value
            end
        end

        promoted.promotion = promotion
        addMove(moves, from, to, promoted)
    end
end

function Engine.opposite(color)
    return color == 'white' and 'black' or 'white'
end

function Engine.pieceColor(piece)
    if not piece then
        return nil
    end

    return piece:sub(1, 1) == 'w' and 'white' or 'black'
end

function Engine.colorPrefix(color)
    return color == 'white' and 'w' or 'b'
end

function Engine.squareToCoords(square)
    if type(square) ~= 'string' or #square ~= 2 then
        return nil
    end

    local file = fileIndex[square:sub(1, 1)]
    local rank = tonumber(square:sub(2, 2))

    if not file or not rank or rank < 1 or rank > 8 then
        return nil
    end

    return file, rank
end

function Engine.coordsToSquare(file, rank)
    if file < 1 or file > 8 or rank < 1 or rank > 8 then
        return nil
    end

    return files[file] .. tostring(rank)
end

function Engine.isSquare(square)
    return Engine.squareToCoords(square) ~= nil
end

function Engine.cloneBoard(board)
    local clone = {}

    for square, piece in pairs(board or {}) do
        clone[square] = piece
    end

    return clone
end

function Engine.cloneState(state)
    local clone = {
        board = Engine.cloneBoard(state.board),
        turn = state.turn,
        enPassant = state.enPassant,
        halfmove = state.halfmove or 0,
        fullmove = state.fullmove or 1,
        castling = {
            white = {
                k = state.castling and state.castling.white and state.castling.white.k or false,
                q = state.castling and state.castling.white and state.castling.white.q or false
            },
            black = {
                k = state.castling and state.castling.black and state.castling.black.k or false,
                q = state.castling and state.castling.black and state.castling.black.q or false
            }
        }
    }

    return clone
end

function Engine.initialBoard()
    local board = {}
    local backRank = { 'R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R' }

    for file = 1, 8 do
        board[Engine.coordsToSquare(file, 1)] = 'w' .. backRank[file]
        board[Engine.coordsToSquare(file, 2)] = 'wP'
        board[Engine.coordsToSquare(file, 7)] = 'bP'
        board[Engine.coordsToSquare(file, 8)] = 'b' .. backRank[file]
    end

    return board
end

function Engine.newState()
    return {
        board = Engine.initialBoard(),
        turn = 'white',
        castling = {
            white = { k = true, q = true },
            black = { k = true, q = true }
        },
        enPassant = nil,
        halfmove = 0,
        fullmove = 1
    }
end

function Engine.loadFen(fen)
    local words = splitWords(fen)
    local boardText = words[1]

    if not boardText then
        return nil, 'missing board'
    end

    local board = {}
    local rank = 8
    local file = 1

    for char in boardText:gmatch('.') do
        if char == '/' then
            rank = rank - 1
            file = 1
        elseif char:match('%d') then
            file = file + tonumber(char)
        else
            local piece = pieceFromFen[char]

            if not piece then
                return nil, 'invalid FEN piece: ' .. char
            end

            local square = Engine.coordsToSquare(file, rank)

            if not square then
                return nil, 'invalid FEN square'
            end

            board[square] = piece
            file = file + 1
        end
    end

    local active = words[2] or 'w'
    local castlingText = words[3] or '-'
    local state = {
        board = board,
        turn = active == 'b' and 'black' or 'white',
        castling = {
            white = { k = false, q = false },
            black = { k = false, q = false }
        },
        enPassant = words[4] ~= '-' and words[4] or nil,
        halfmove = tonumber(words[5]) or 0,
        fullmove = tonumber(words[6]) or 1
    }

    if castlingText:find('K', 1, true) then state.castling.white.k = true end
    if castlingText:find('Q', 1, true) then state.castling.white.q = true end
    if castlingText:find('k', 1, true) then state.castling.black.k = true end
    if castlingText:find('q', 1, true) then state.castling.black.q = true end

    return state
end

function Engine.toFen(state)
    local ranks = {}

    for rank = 8, 1, -1 do
        local output = {}
        local empty = 0

        for file = 1, 8 do
            local square = Engine.coordsToSquare(file, rank)
            local piece = state.board[square]

            if piece then
                if empty > 0 then
                    output[#output + 1] = tostring(empty)
                    empty = 0
                end

                output[#output + 1] = fenFromPiece[piece]
            else
                empty = empty + 1
            end
        end

        if empty > 0 then
            output[#output + 1] = tostring(empty)
        end

        ranks[#ranks + 1] = table.concat(output)
    end

    ensureCastling(state)

    local castling = ''
    if state.castling.white.k then castling = castling .. 'K' end
    if state.castling.white.q then castling = castling .. 'Q' end
    if state.castling.black.k then castling = castling .. 'k' end
    if state.castling.black.q then castling = castling .. 'q' end
    if castling == '' then castling = '-' end

    return table.concat(ranks, '/')
        .. ' '
        .. (state.turn == 'white' and 'w' or 'b')
        .. ' '
        .. castling
        .. ' '
        .. (state.enPassant or '-')
        .. ' '
        .. tostring(state.halfmove or 0)
        .. ' '
        .. tostring(state.fullmove or 1)
end

function Engine.toAscii(state)
    local lines = {}

    for rank = 8, 1, -1 do
        local parts = { tostring(rank) }

        for file = 1, 8 do
            local square = Engine.coordsToSquare(file, rank)
            parts[#parts + 1] = fenFromPiece[state.board[square]] or '.'
        end

        lines[#lines + 1] = table.concat(parts, ' ')
    end

    lines[#lines + 1] = '  a b c d e f g h'
    return table.concat(lines, '\n')
end

function Engine.findKing(state, color)
    local king = Engine.colorPrefix(color) .. 'K'

    for square, piece in pairs(state.board) do
        if piece == king then
            return square
        end
    end

    return nil
end

function Engine.isSquareAttacked(state, square, byColor)
    local targetFile, targetRank = Engine.squareToCoords(square)

    if not targetFile then
        return false
    end

    local prefix = Engine.colorPrefix(byColor)
    local pawnRank = byColor == 'white' and targetRank - 1 or targetRank + 1

    for _, pawnFile in ipairs({ targetFile - 1, targetFile + 1 }) do
        local pawnSquare = Engine.coordsToSquare(pawnFile, pawnRank)

        if pawnSquare and state.board[pawnSquare] == prefix .. 'P' then
            return true
        end
    end

    for _, offset in ipairs(knightOffsets) do
        local attackSquare = Engine.coordsToSquare(targetFile + offset[1], targetRank + offset[2])

        if attackSquare and state.board[attackSquare] == prefix .. 'N' then
            return true
        end
    end

    for _, offset in ipairs(kingOffsets) do
        local attackSquare = Engine.coordsToSquare(targetFile + offset[1], targetRank + offset[2])

        if attackSquare and state.board[attackSquare] == prefix .. 'K' then
            return true
        end
    end

    local function scan(directions, attackers)
        for _, direction in ipairs(directions) do
            local file = targetFile + direction[1]
            local rank = targetRank + direction[2]

            while true do
                local scanSquare = Engine.coordsToSquare(file, rank)

                if not scanSquare then
                    break
                end

                local piece = state.board[scanSquare]

                if piece then
                    if piece:sub(1, 1) == prefix and attackers[piece:sub(2, 2)] then
                        return true
                    end

                    break
                end

                file = file + direction[1]
                rank = rank + direction[2]
            end
        end

        return false
    end

    if scan(bishopDirections, { B = true, Q = true }) then
        return true
    end

    if scan(rookDirections, { R = true, Q = true }) then
        return true
    end

    return false
end

function Engine.isInCheck(state, color)
    local kingSquare = Engine.findKing(state, color)

    if not kingSquare then
        return false
    end

    return Engine.isSquareAttacked(state, kingSquare, Engine.opposite(color))
end

local function addPawnMoves(state, moves, from, piece, file, rank)
    local color = Engine.pieceColor(piece)
    local direction = color == 'white' and 1 or -1
    local startRank = color == 'white' and 2 or 7
    local promotionRank = color == 'white' and 8 or 1
    local oneRank = rank + direction
    local oneSquare = Engine.coordsToSquare(file, oneRank)

    if oneSquare and not state.board[oneSquare] then
        if oneRank == promotionRank then
            addPromotionMoves(moves, from, oneSquare)
        else
            addMove(moves, from, oneSquare)
        end

        local twoSquare = Engine.coordsToSquare(file, rank + direction * 2)

        if rank == startRank and twoSquare and not state.board[twoSquare] then
            addMove(moves, from, twoSquare, {
                doublePawn = true
            })
        end
    end

    for _, fileDelta in ipairs({ -1, 1 }) do
        local target = Engine.coordsToSquare(file + fileDelta, oneRank)

        if target then
            local targetPiece = state.board[target]

            if targetPiece and Engine.pieceColor(targetPiece) == Engine.opposite(color) then
                if oneRank == promotionRank then
                    addPromotionMoves(moves, from, target, {
                        capture = target
                    })
                else
                    addMove(moves, from, target, {
                        capture = target
                    })
                end
            elseif state.enPassant and target == state.enPassant then
                local captureSquare = Engine.coordsToSquare(file + fileDelta, rank)

                if captureSquare and state.board[captureSquare] == Engine.colorPrefix(Engine.opposite(color)) .. 'P' then
                    addMove(moves, from, target, {
                        enPassant = true,
                        capture = captureSquare
                    })
                end
            end
        end
    end
end

local function addKnightMoves(state, moves, from, piece, file, rank)
    local color = Engine.pieceColor(piece)

    for _, offset in ipairs(knightOffsets) do
        local target = Engine.coordsToSquare(file + offset[1], rank + offset[2])

        if target then
            local targetPiece = state.board[target]

            if not targetPiece or Engine.pieceColor(targetPiece) ~= color then
                addMove(moves, from, target, {
                    capture = targetPiece and target or nil
                })
            end
        end
    end
end

local function addSlidingMoves(state, moves, from, piece, file, rank, directions)
    local color = Engine.pieceColor(piece)

    for _, direction in ipairs(directions) do
        local targetFile = file + direction[1]
        local targetRank = rank + direction[2]

        while true do
            local target = Engine.coordsToSquare(targetFile, targetRank)

            if not target then
                break
            end

            local targetPiece = state.board[target]

            if targetPiece then
                if Engine.pieceColor(targetPiece) ~= color then
                    addMove(moves, from, target, {
                        capture = target
                    })
                end

                break
            end

            addMove(moves, from, target)
            targetFile = targetFile + direction[1]
            targetRank = targetRank + direction[2]
        end
    end
end

local function addKingMoves(state, moves, from, piece, file, rank)
    local color = Engine.pieceColor(piece)

    for _, offset in ipairs(kingOffsets) do
        local target = Engine.coordsToSquare(file + offset[1], rank + offset[2])

        if target then
            local targetPiece = state.board[target]

            if not targetPiece or Engine.pieceColor(targetPiece) ~= color then
                addMove(moves, from, target, {
                    capture = targetPiece and target or nil
                })
            end
        end
    end

    ensureCastling(state)

    local opponent = Engine.opposite(color)
    local homeRank = color == 'white' and 1 or 8
    local kingHome = Engine.coordsToSquare(5, homeRank)

    if from ~= kingHome or Engine.isInCheck(state, color) then
        return
    end

    if state.castling[color].k then
        local rookSquare = Engine.coordsToSquare(8, homeRank)
        local fSquare = Engine.coordsToSquare(6, homeRank)
        local gSquare = Engine.coordsToSquare(7, homeRank)

        if state.board[rookSquare] == Engine.colorPrefix(color) .. 'R'
            and not state.board[fSquare]
            and not state.board[gSquare]
            and not Engine.isSquareAttacked(state, fSquare, opponent)
            and not Engine.isSquareAttacked(state, gSquare, opponent)
        then
            addMove(moves, from, gSquare, {
                castle = 'k',
                rookFrom = rookSquare,
                rookTo = fSquare
            })
        end
    end

    if state.castling[color].q then
        local rookSquare = Engine.coordsToSquare(1, homeRank)
        local bSquare = Engine.coordsToSquare(2, homeRank)
        local cSquare = Engine.coordsToSquare(3, homeRank)
        local dSquare = Engine.coordsToSquare(4, homeRank)

        if state.board[rookSquare] == Engine.colorPrefix(color) .. 'R'
            and not state.board[bSquare]
            and not state.board[cSquare]
            and not state.board[dSquare]
            and not Engine.isSquareAttacked(state, cSquare, opponent)
            and not Engine.isSquareAttacked(state, dSquare, opponent)
        then
            addMove(moves, from, cSquare, {
                castle = 'q',
                rookFrom = rookSquare,
                rookTo = dSquare
            })
        end
    end
end

function Engine.generatePseudoMoves(state, color)
    local moves = {}

    for from, piece in pairs(state.board) do
        if Engine.pieceColor(piece) == color then
            local file, rank = Engine.squareToCoords(from)
            local pieceType = piece:sub(2, 2)

            if pieceType == 'P' then
                addPawnMoves(state, moves, from, piece, file, rank)
            elseif pieceType == 'N' then
                addKnightMoves(state, moves, from, piece, file, rank)
            elseif pieceType == 'B' then
                addSlidingMoves(state, moves, from, piece, file, rank, bishopDirections)
            elseif pieceType == 'R' then
                addSlidingMoves(state, moves, from, piece, file, rank, rookDirections)
            elseif pieceType == 'Q' then
                addSlidingMoves(state, moves, from, piece, file, rank, queenDirections)
            elseif pieceType == 'K' then
                addKingMoves(state, moves, from, piece, file, rank)
            end
        end
    end

    return moves
end

function Engine.applyMoveUnchecked(state, move)
    ensureCastling(state)

    local board = state.board
    local piece = board[move.from]
    local color = Engine.pieceColor(piece)
    local opponent = Engine.opposite(color)
    local pieceType = piece and piece:sub(2, 2) or nil
    local targetPiece = board[move.to]
    local captureSquare = move.enPassant and move.capture or (targetPiece and move.to or nil)
    local capturedPiece = captureSquare and board[captureSquare] or nil

    board[move.from] = nil

    if captureSquare then
        board[captureSquare] = nil
    end

    if move.castle and move.rookFrom and move.rookTo then
        board[move.rookTo] = board[move.rookFrom]
        board[move.rookFrom] = nil
    end

    if pieceType == 'K' then
        state.castling[color].k = false
        state.castling[color].q = false
    elseif pieceType == 'R' then
        if move.from == (color == 'white' and 'h1' or 'h8') then
            state.castling[color].k = false
        elseif move.from == (color == 'white' and 'a1' or 'a8') then
            state.castling[color].q = false
        end
    end

    if capturedPiece and capturedPiece:sub(2, 2) == 'R' then
        if captureSquare == (opponent == 'white' and 'h1' or 'h8') then
            state.castling[opponent].k = false
        elseif captureSquare == (opponent == 'white' and 'a1' or 'a8') then
            state.castling[opponent].q = false
        end
    end

    local finalPiece = piece
    local _, toRank = Engine.squareToCoords(move.to)

    if pieceType == 'P' and (toRank == 8 or toRank == 1) then
        finalPiece = Engine.colorPrefix(color) .. (move.promotion or 'q'):upper()
    end

    board[move.to] = finalPiece

    if pieceType == 'P' then
        local fromFile, fromRank = Engine.squareToCoords(move.from)

        if math.abs(toRank - fromRank) == 2 then
            state.enPassant = Engine.coordsToSquare(fromFile, math.floor((fromRank + toRank) / 2))
        else
            state.enPassant = nil
        end
    else
        state.enPassant = nil
    end

    if pieceType == 'P' or capturedPiece then
        state.halfmove = 0
    else
        state.halfmove = (state.halfmove or 0) + 1
    end

    if color == 'black' then
        state.fullmove = (state.fullmove or 1) + 1
    end

    state.turn = opponent

    return {
        from = move.from,
        to = move.to,
        piece = piece,
        finalPiece = finalPiece,
        capturedPiece = capturedPiece,
        captureSquare = captureSquare,
        promotion = move.promotion,
        castle = move.castle,
        rookFrom = move.rookFrom,
        rookTo = move.rookTo,
        enPassant = move.enPassant or false,
        fen = Engine.toFen(state)
    }
end

function Engine.generateLegalMoves(state, color)
    local legal = {}
    local side = color or state.turn
    local pseudoMoves = Engine.generatePseudoMoves(state, side)

    for _, move in ipairs(pseudoMoves) do
        local clone = Engine.cloneState(state)
        Engine.applyMoveUnchecked(clone, move)

        if not Engine.isInCheck(clone, side) then
            legal[#legal + 1] = move
        end
    end

    return legal
end

function Engine.legalMovesFrom(state, square, color)
    local moves = {}
    square = square and square:lower() or nil

    if not square or not Engine.isSquare(square) then
        return moves
    end

    for _, move in ipairs(Engine.generateLegalMoves(state, color or state.turn)) do
        if move.from == square then
            moves[#moves + 1] = move
        end
    end

    return moves
end

function Engine.findLegalMove(state, from, to, promotion)
    if not Engine.isSquare(from) or not Engine.isSquare(to) then
        return nil, 'invalid square'
    end

    local piece = state.board[from]

    if not piece then
        return nil, 'no piece on ' .. from
    end

    if Engine.pieceColor(piece) ~= state.turn then
        return nil, 'it is ' .. state.turn .. "'s turn"
    end

    local requestedPromotion = promotion and promotion:lower() or nil

    if requestedPromotion and not ({ q = true, r = true, b = true, n = true })[requestedPromotion] then
        return nil, 'promotion must be q, r, b, or n'
    end

    for _, move in ipairs(Engine.generateLegalMoves(state, state.turn)) do
        if move.from == from and move.to == to then
            if move.promotion then
                if (requestedPromotion or 'q') == move.promotion then
                    return move
                end
            elseif not requestedPromotion then
                return move
            end
        end
    end

    return nil, 'illegal move'
end

function Engine.move(state, from, to, promotion)
    from = from and from:lower() or nil
    to = to and to:lower() or nil

    local legalMove, errorMessage = Engine.findLegalMove(state, from, to, promotion)

    if not legalMove then
        return false, errorMessage
    end

    return true, Engine.applyMoveUnchecked(state, legalMove)
end

function Engine.insufficientMaterial(state)
    local pieces = {
        white = {},
        black = {}
    }

    for square, piece in pairs(state.board or {}) do
        local color = Engine.pieceColor(piece)
        local pieceType = piece and piece:sub(2, 2)

        if color and pieceType ~= 'K' then
            pieces[color][#pieces[color] + 1] = {
                type = pieceType,
                square = square
            }
        end
    end

    local white = pieces.white
    local black = pieces.black
    local total = #white + #black

    if total == 0 then
        return true, 'bare_kings'
    end

    for _, side in ipairs({ white, black }) do
        for _, piece in ipairs(side) do
            if piece.type == 'P' or piece.type == 'R' or piece.type == 'Q' then
                return false
            end
        end
    end

    if total == 1 then
        local only = white[1] or black[1]

        if only.type == 'B' or only.type == 'N' then
            return true, 'single_minor'
        end
    end

    if #white == 1 and #black == 1 and white[1].type == 'B' and black[1].type == 'B' then
        local whiteFile, whiteRank = Engine.squareToCoords(white[1].square)
        local blackFile, blackRank = Engine.squareToCoords(black[1].square)

        if whiteFile and blackFile and ((whiteFile + whiteRank) % 2) == ((blackFile + blackRank) % 2) then
            return true, 'same_color_bishops'
        end
    end

    return false
end

function Engine.status(state)
    local color = state.turn
    local inCheck = Engine.isInCheck(state, color)
    local legalMoves = Engine.generateLegalMoves(state, color)
    local insufficientMaterial, insufficientReason = Engine.insufficientMaterial(state)

    if insufficientMaterial then
        return {
            check = inCheck,
            checkmate = false,
            stalemate = false,
            insufficientMaterial = true,
            insufficientReason = insufficientReason,
            winner = nil
        }
    end

    if #legalMoves == 0 and inCheck then
        return {
            check = true,
            checkmate = true,
            stalemate = false,
            insufficientMaterial = false,
            winner = Engine.opposite(color)
        }
    end

    if #legalMoves == 0 then
        return {
            check = false,
            checkmate = false,
            stalemate = true,
            insufficientMaterial = false,
            winner = nil
        }
    end

    return {
        check = inCheck,
        checkmate = false,
        stalemate = false,
        insufficientMaterial = false,
        winner = nil
    }
end

function Engine.materialValue(piece)
    if not piece then
        return 0
    end

    return material[piece:sub(2, 2)] or 0
end

function Engine.evaluateMaterial(state, perspective)
    local score = 0

    for _, piece in pairs(state.board) do
        local value = Engine.materialValue(piece)

        if Engine.pieceColor(piece) == perspective then
            score = score + value
        else
            score = score - value
        end
    end

    return score
end
