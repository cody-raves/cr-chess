CRChess = CRChess or {}

local Engine = CRChess.Engine
local Bot = CRChess.Bot
local Stats = CRChess.Stats

local tables = {}
local matches = {}
local activeByPlayer = {}
local seatedByPlayer = {}
local pendingInvites = {}
local lastTableSpawnByPlayer = {}
local nextTableId = 1
local nextMatchId = 1

local function now()
    return os.time()
end

local function nowMs()
    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end

    return math.floor(os.clock() * 1000)
end

local function notify(target, message)
    if target == 0 then
        print(('[cr-chess] %s'):format(message))
        return
    end

    TriggerClientEvent('cr-chess:client:notify', target, message)
end

local function validCoords(coords)
    return type(coords) == 'table'
        and type(coords.x) == 'number'
        and type(coords.y) == 'number'
        and type(coords.z) == 'number'
end

local function copyBoard(board)
    return Engine.cloneBoard(board or {})
end

local function seatSnapshot(source)
    if not source then
        return nil
    end

    return {
        source = source,
        name = GetPlayerName(source) or ('Player %s'):format(source)
    }
end

local function tableSnapshot(tableData)
    local match = tableData.matchId and matches[tableData.matchId] or nil

    return {
        id = tableData.id,
        coords = {
            x = tableData.coords.x,
            y = tableData.coords.y,
            z = tableData.coords.z
        },
        heading = tableData.heading,
        createdBy = tableData.createdBy,
        matchId = tableData.matchId,
        board = copyBoard(tableData.board),
        seats = {
            white = tableData.seats and seatSnapshot(tableData.seats.white) or nil,
            black = tableData.seats and seatSnapshot(tableData.seats.black) or nil
        },
        capturedWhite = match and match.capturedWhite or tableData.capturedWhite or {},
        capturedBlack = match and match.capturedBlack or tableData.capturedBlack or {}
    }
end

local function allTableSnapshots()
    local snapshots = {}

    for _, tableData in pairs(tables) do
        snapshots[#snapshots + 1] = tableSnapshot(tableData)
    end

    table.sort(snapshots, function(a, b)
        return a.id < b.id
    end)

    return snapshots
end

local function broadcastTables(target)
    TriggerClientEvent('cr-chess:client:syncTables', target or -1, allTableSnapshots())
end

local function broadcastTable(tableId)
    local tableData = tables[tableId]

    if tableData then
        TriggerClientEvent('cr-chess:client:updateTable', -1, tableSnapshot(tableData))
    else
        TriggerClientEvent('cr-chess:client:removeTable', -1, tableId)
    end
end

local function getIdentifier(source)
    if source == 0 then
        return 'console'
    end

    if type(GetPlayerIdentifierByType) == 'function' then
        local license = GetPlayerIdentifierByType(source, 'license')

        if license then
            return license
        end
    end

    if type(GetPlayerIdentifiers) == 'function' then
        local identifiers = GetPlayerIdentifiers(source)

        for _, identifier in ipairs(identifiers) do
            if identifier:sub(1, 8) == 'license:' then
                return identifier
            end
        end

        if identifiers[1] then
            return identifiers[1]
        end
    end

    return 'source:' .. tostring(source)
end

local function getName(source)
    if source == 0 then
        return 'Console'
    end

    return GetPlayerName(source) or ('Player %s'):format(source)
end

local function distance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function nearestTable(coords)
    if not validCoords(coords) then
        return nil
    end

    local maxRange = Config.TableBindRange or 3.0
    local nearest = nil
    local nearestDistance = maxRange

    for _, tableData in pairs(tables) do
        if not tableData.matchId then
            local tableDistance = distance(coords, tableData.coords)

            if tableDistance <= nearestDistance then
                nearest = tableData
                nearestDistance = tableDistance
            end
        end
    end

    return nearest
end

local function tableHasLiveMatch(tableData)
    local match = tableData and tableData.matchId and matches[tableData.matchId] or nil

    return match and match.stateName ~= 'finished'
end

local function tableHasSeats(tableData)
    return tableData
        and tableData.seats
        and (tableData.seats.white ~= nil or tableData.seats.black ~= nil)
end

local function canRemoveIdleTable(tableData)
    return tableData and not tableHasLiveMatch(tableData) and not tableHasSeats(tableData)
end

local function findNearbyTable(coords, range)
    if not validCoords(coords) then
        return nil, nil
    end

    local maxRange = tonumber(range) or Config.TableSpawnReuseRange or 1.25
    local nearest = nil
    local nearestDistance = maxRange

    for _, tableData in pairs(tables) do
        local tableDistance = distance(coords, tableData.coords)

        if tableDistance <= nearestDistance then
            nearest = tableData
            nearestDistance = tableDistance
        end
    end

    return nearest, nearestDistance
end

local function removeIdleTablesNear(coords, range, keepId)
    if not validCoords(coords) then
        return {}
    end

    local maxRange = tonumber(range) or Config.TableCleanupRange or 3.0
    local removed = {}

    for tableId, tableData in pairs(tables) do
        if tableId ~= keepId and canRemoveIdleTable(tableData) and distance(coords, tableData.coords) <= maxRange then
            tables[tableId] = nil
            removed[#removed + 1] = tableId
        end
    end

    table.sort(removed)

    for _, tableId in ipairs(removed) do
        broadcastTable(tableId)
    end

    return removed
end

local function getTable(tableId)
    tableId = tonumber(tableId)

    if not tableId then
        return nil
    end

    return tables[tableId]
end

local function clearSourceSeat(source, shouldBroadcast)
    local seated = seatedByPlayer[source]

    if not seated then
        return
    end

    local tableData = tables[seated.tableId]

    if tableData and tableData.seats and tableData.seats[seated.color] == source then
        tableData.seats[seated.color] = nil

        if shouldBroadcast ~= false then
            broadcastTable(seated.tableId)
        end
    end

    seatedByPlayer[source] = nil
end

local function occupySeat(source, tableData, color)
    if not tableData then
        return false, 'Table not found.'
    end

    if color ~= 'white' and color ~= 'black' then
        return false, 'Choose white or black.'
    end

    tableData.seats = tableData.seats or {}

    local current = tableData.seats[color]

    if current and current ~= source and GetPlayerName(current) then
        return false, ('%s is already seated as %s.'):format(GetPlayerName(current) or 'Someone', color)
    end

    clearSourceSeat(source, false)

    tableData.seats[color] = source
    seatedByPlayer[source] = {
        tableId = tableData.id,
        color = color
    }

    broadcastTable(tableData.id)

    return true
end

local function opponentColor(color)
    return color == 'white' and 'black' or 'white'
end

local function colorForSource(match, source)
    if match.white == source then
        return 'white'
    end

    if match.black == source then
        return 'black'
    end

    return nil
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function scorePosition(state, color)
    local status = Engine.status(state)

    if status.checkmate then
        return status.winner == color and 100000 or -100000
    end

    if status.stalemate then
        return 0
    end

    local score = Engine.evaluateMaterial(state, color)
    local opponent = Engine.opposite(color)

    if Engine.isInCheck(state, opponent) then
        score = score + 40
    end

    score = score + #Engine.generateLegalMoves(state, color)
    return score
end

local function evaluateMoveChoice(stateBefore, selectedMove, color)
    local bestScore = -math.huge
    local chosenScore = -math.huge

    for _, legalMove in ipairs(Engine.generateLegalMoves(stateBefore, color)) do
        local clone = Engine.cloneState(stateBefore)
        Engine.applyMoveUnchecked(clone, legalMove)
        local score = scorePosition(clone, color)

        if score > bestScore then
            bestScore = score
        end

        if legalMove.from == selectedMove.from
            and legalMove.to == selectedMove.to
            and (legalMove.promotion or '') == (selectedMove.promotion or '')
        then
            chosenScore = score
        end
    end

    if bestScore == -math.huge or chosenScore == -math.huge then
        return {
            accuracy = 100,
            quality = 'Book'
        }
    end

    local loss = math.max(0, bestScore - chosenScore)
    local accuracy = clamp(math.floor(100 - (loss / 8) + 0.5), 0, 100)
    local quality = 'Good'

    if accuracy >= 92 then
        quality = 'Best'
    elseif accuracy >= 78 then
        quality = 'Good'
    elseif accuracy >= 55 then
        quality = 'Mistake'
    else
        quality = 'Blunder'
    end

    return {
        accuracy = accuracy,
        quality = quality,
        loss = loss
    }
end

local function buildReview(match)
    local totals = {
        white = { accuracy = 0, count = 0 },
        black = { accuracy = 0, count = 0 }
    }
    local mistakes = 0
    local blunders = 0

    for _, move in ipairs(match.moveHistory or {}) do
        if move.accuracy then
            local bucket = totals[move.color]

            if bucket then
                bucket.accuracy = bucket.accuracy + move.accuracy
                bucket.count = bucket.count + 1
            end
        end

        if move.quality == 'Mistake' then
            mistakes = mistakes + 1
        elseif move.quality == 'Blunder' then
            blunders = blunders + 1
        end
    end

    local function average(bucket)
        if bucket.count == 0 then
            return 0
        end

        return math.floor(bucket.accuracy / bucket.count + 0.5)
    end

    return {
        whiteAccuracy = average(totals.white),
        blackAccuracy = average(totals.black),
        mistakes = mistakes,
        blunders = blunders
    }
end

local function matchSnapshot(match)
    local status = Engine.status(match.state)

    return {
        id = match.id,
        mode = match.mode,
        state = match.stateName,
        tableId = match.tableId,
        white = match.white,
        black = match.black,
        whiteName = match.whiteName,
        blackName = match.blackName,
        botColor = match.botColor,
        botDifficulty = match.botDifficulty,
        wagerAmount = match.wagerAmount,
        wagerAccount = match.wagerAccount,
        wagerPot = match.wagerPot,
        turn = match.state.turn,
        board = copyBoard(match.state.board),
        fen = Engine.toFen(match.state),
        moveHistory = match.moveHistory,
        lastMove = match.lastMove,
        capturedWhite = match.capturedWhite,
        capturedBlack = match.capturedBlack,
        winner = match.winner,
        result = match.result,
        finishReason = match.finishReason,
        review = match.review,
        status = status
    }
end

local function syncMatch(match)
    if match.tableId and tables[match.tableId] then
        tables[match.tableId].board = copyBoard(match.state.board)
        tables[match.tableId].capturedWhite = match.capturedWhite
        tables[match.tableId].capturedBlack = match.capturedBlack
    end

    TriggerClientEvent('cr-chess:client:updateMatch', -1, matchSnapshot(match))

    if match.tableId and tables[match.tableId] then
        broadcastTable(match.tableId)
    end
end

local function sendMatchPlayers(match, message)
    if match.white and match.white ~= 0 then
        notify(match.white, message)
    end

    if match.black and match.black ~= 0 and match.black ~= match.white then
        notify(match.black, message)
    end
end

local function configuredWagerAccount()
    return (Config.Wagers and Config.Wagers.account) or 'cash'
end

local function detectMoneyFramework()
    local configured = Config.Wagers and Config.Wagers.framework or 'auto'

    if configured and configured ~= 'auto' then
        return configured
    end

    if GetResourceState('qbx_core') == 'started' then
        return 'qbox'
    end

    if GetResourceState('qb-core') == 'started' then
        return 'qb'
    end

    if GetResourceState('es_extended') == 'started' then
        return 'esx'
    end

    return nil
end

local function isAllowedWagerAmount(amount)
    amount = tonumber(amount) or 0
    amount = math.floor(amount)

    if amount <= 0 then
        return true, 0
    end

    if not Config.Wagers or not Config.Wagers.enabled then
        return false, 0, 'Wagers are disabled in Config.Wagers.'
    end

    for _, allowed in ipairs(Config.Wagers.amounts or {}) do
        if amount == tonumber(allowed) then
            return true, amount
        end
    end

    return false, 0, 'Choose one of the configured wager amounts.'
end

local function removePlayerMoney(source, amount, account, reason)
    local framework = detectMoneyFramework()

    if not framework then
        return false, 'No supported money framework is started.'
    end

    if framework == 'qbox' or framework == 'qbx' then
        local ok, result = pcall(function()
            return exports.qbx_core:RemoveMoney(source, account, amount, reason)
        end)

        return ok and result == true, ok and nil or tostring(result)
    end

    if framework == 'qb' then
        local ok, result = pcall(function()
            local QBCore = exports['qb-core']:GetCoreObject()
            local player = QBCore.Functions.GetPlayer(source)

            if not player then
                return false
            end

            return player.Functions.RemoveMoney(account, amount, reason) ~= false
        end)

        return ok and result == true, ok and nil or tostring(result)
    end

    if framework == 'esx' then
        local ok, result = pcall(function()
            local ESX = exports['es_extended']:getSharedObject()
            local player = ESX.GetPlayerFromId(source)

            if not player then
                return false
            end

            if account == 'cash' or account == 'money' then
                if player.getMoney() < amount then
                    return false
                end

                player.removeMoney(amount)
                return true
            end

            local accountData = player.getAccount(account)

            if not accountData or accountData.money < amount then
                return false
            end

            player.removeAccountMoney(account, amount)
            return true
        end)

        return ok and result == true, ok and nil or tostring(result)
    end

    return false, ('Unsupported wager framework %s.'):format(tostring(framework))
end

local function addPlayerMoney(source, amount, account, reason)
    local framework = detectMoneyFramework()

    if not framework then
        return false, 'No supported money framework is started.'
    end

    if framework == 'qbox' or framework == 'qbx' then
        local ok, result = pcall(function()
            return exports.qbx_core:AddMoney(source, account, amount, reason)
        end)

        return ok and result == true, ok and nil or tostring(result)
    end

    if framework == 'qb' then
        local ok, result = pcall(function()
            local QBCore = exports['qb-core']:GetCoreObject()
            local player = QBCore.Functions.GetPlayer(source)

            if not player then
                return false
            end

            return player.Functions.AddMoney(account, amount, reason) ~= false
        end)

        return ok and result == true, ok and nil or tostring(result)
    end

    if framework == 'esx' then
        local ok, result = pcall(function()
            local ESX = exports['es_extended']:getSharedObject()
            local player = ESX.GetPlayerFromId(source)

            if not player then
                return false
            end

            if account == 'cash' or account == 'money' then
                player.addMoney(amount)
            else
                player.addAccountMoney(account, amount)
            end

            return true
        end)

        return ok and result == true, ok and nil or tostring(result)
    end

    return false, ('Unsupported wager framework %s.'):format(tostring(framework))
end

local function collectWager(match)
    local amount = tonumber(match.wagerAmount) or 0

    if amount <= 0 or match.wagerEscrowed then
        return true
    end

    if not match.white or match.white == 0 or not match.black or match.black == 0 then
        return false, 'Wagers require two players.'
    end

    local account = match.wagerAccount or configuredWagerAccount()
    local reason = ('cr-chess match %d wager'):format(match.id)
    local whiteOk, whiteError = removePlayerMoney(match.white, amount, account, reason)

    if not whiteOk then
        notify(match.white, ('Could not escrow your wager: %s'):format(whiteError or 'not enough money'))
        notify(match.black, ('%s could not escrow the wager.'):format(match.whiteName or 'White'))
        return false, 'White could not escrow the wager.'
    end

    local blackOk, blackError = removePlayerMoney(match.black, amount, account, reason)

    if not blackOk then
        addPlayerMoney(match.white, amount, account, ('cr-chess match %d wager refund'):format(match.id))
        notify(match.black, ('Could not escrow your wager: %s'):format(blackError or 'not enough money'))
        notify(match.white, ('%s could not escrow the wager. Your stake was refunded.'):format(match.blackName or 'Black'))
        return false, 'Black could not escrow the wager.'
    end

    match.wagerEscrowed = true
    match.wagerPot = amount * 2
    sendMatchPlayers(match, ('Wager escrowed: $%d each, pot $%d.'):format(amount, match.wagerPot))

    return true
end

local function payoutWager(match)
    local amount = tonumber(match.wagerAmount) or 0

    if amount <= 0 or not match.wagerEscrowed or match.wagerPaidOut then
        return
    end

    local account = match.wagerAccount or configuredWagerAccount()
    local pot = tonumber(match.wagerPot) or amount * 2
    local reason = ('cr-chess match %d payout'):format(match.id)

    match.wagerPaidOut = true

    if not match.winner then
        if match.white and match.white ~= 0 then
            addPlayerMoney(match.white, amount, account, reason .. ' refund')
        end

        if match.black and match.black ~= 0 then
            addPlayerMoney(match.black, amount, account, reason .. ' refund')
        end

        sendMatchPlayers(match, ('Draw wager refunded: $%d each.'):format(amount))
        return
    end

    local winnerSource = match.winner == 'white' and match.white or match.black
    local houseCutPercent = tonumber(Config.Wagers and Config.Wagers.houseCutPercent) or 0
    local payout = math.floor(pot * (100 - houseCutPercent) / 100)

    if winnerSource and winnerSource ~= 0 then
        local ok, errorMessage = addPlayerMoney(winnerSource, payout, account, reason)

        if ok then
            sendMatchPlayers(match, ('%s wins the $%d wager pot.'):format(match.winner, payout))
        else
            print(('[cr-chess] Failed to pay wager for match %d: %s'):format(match.id, tostring(errorMessage)))
        end
    end
end

local function releaseMatchPlayers(match)
    if match.white and match.white ~= 0 then
        activeByPlayer[match.white] = nil
        clearSourceSeat(match.white, false)
    end

    if match.black and match.black ~= 0 then
        activeByPlayer[match.black] = nil
        clearSourceSeat(match.black, false)
    end
end

local function finishMatch(match, reason, winnerColor)
    if match.stateName == 'finished' then
        return
    end

    match.stateName = 'finished'
    match.endedAt = now()
    match.finishReason = reason
    match.winner = winnerColor
    match.winnerIdentifier = winnerColor == 'white' and match.whiteIdentifier
        or (winnerColor == 'black' and match.blackIdentifier or nil)
    match.result = winnerColor and (winnerColor .. '_win') or 'draw'
    match.review = buildReview(match)
    payoutWager(match)

    if match.tableId and tables[match.tableId] then
        tables[match.tableId].matchId = nil
        tables[match.tableId].board = copyBoard(match.state.board)
        tables[match.tableId].seats = {}
    end

    releaseMatchPlayers(match)
    Stats.recordMatch(match)
    syncMatch(match)

    if winnerColor then
        sendMatchPlayers(match, ('Match %d finished by %s. %s wins.'):format(match.id, reason, winnerColor))
    else
        sendMatchPlayers(match, ('Match %d finished by %s. Draw.'):format(match.id, reason))
    end
end

local function finishIfNeeded(match)
    local status = Engine.status(match.state)

    if status.checkmate then
        finishMatch(match, 'checkmate', status.winner)
        return true
    end

    if status.stalemate then
        finishMatch(match, 'stalemate', nil)
        return true
    end

    return false
end

local function recordCaptured(match, moveInfo)
    if not moveInfo.capturedPiece then
        return
    end

    if moveInfo.capturedPiece:sub(1, 1) == 'w' then
        match.capturedWhite[#match.capturedWhite + 1] = moveInfo.capturedPiece
    else
        match.capturedBlack[#match.capturedBlack + 1] = moveInfo.capturedPiece
    end
end

local runBotTurn

local function scheduleBotTurn(match)
    local botColor = match.botColor or 'black'

    if match.mode ~= 'bot' or match.stateName ~= 'active' or match.state.turn ~= botColor then
        return
    end

    SetTimeout(650, function()
        runBotTurn(match.id)
    end)
end

local function applyMove(match, color, from, to, promotion, actor, actorSource)
    if match.stateName ~= 'active' then
        return false, 'match is not active'
    end

    if match.state.turn ~= color then
        return false, ('it is %s\'s turn'):format(match.state.turn)
    end

    from = from and from:lower() or nil
    to = to and to:lower() or nil

    local stateBefore = Engine.cloneState(match.state)
    local legalMove, errorMessage = Engine.findLegalMove(match.state, from, to, promotion)

    if not legalMove then
        return false, errorMessage
    end

    local moveReview = evaluateMoveChoice(stateBefore, legalMove, color)
    local moveInfo = Engine.applyMoveUnchecked(match.state, legalMove)
    moveInfo.color = color
    moveInfo.actor = actor
    moveInfo.actorSource = actorSource
    moveInfo.accuracy = moveReview.accuracy
    moveInfo.quality = moveReview.quality
    moveInfo.loss = moveReview.loss

    recordCaptured(match, moveInfo)
    match.lastMove = moveInfo
    match.moveHistory[#match.moveHistory + 1] = {
        color = color,
        from = moveInfo.from,
        to = moveInfo.to,
        piece = moveInfo.piece,
        finalPiece = moveInfo.finalPiece,
        capturedPiece = moveInfo.capturedPiece,
        captureSquare = moveInfo.captureSquare,
        promotion = moveInfo.promotion,
        castle = moveInfo.castle,
        actor = actor,
        actorSource = actorSource,
        accuracy = moveInfo.accuracy,
        quality = moveInfo.quality,
        loss = moveInfo.loss,
        fen = moveInfo.fen
    }

    if finishIfNeeded(match) then
        return true
    end

    syncMatch(match)
    scheduleBotTurn(match)

    return true
end

runBotTurn = function(matchId)
    local match = matches[matchId]
    local botColor = match and (match.botColor or 'black') or 'black'

    if not match or match.stateName ~= 'active' or match.mode ~= 'bot' or match.state.turn ~= botColor then
        return
    end

    local move = Bot.chooseMove(match.state, match.botDifficulty)

    if not move then
        finishIfNeeded(match)
        return
    end

    local ok, errorMessage = applyMove(match, botColor, move.from, move.to, move.promotion, 'bot:' .. match.botDifficulty, nil)

    if not ok then
        sendMatchPlayers(match, 'Bot failed to move: ' .. tostring(errorMessage))
    end
end

local function createEmptyMatch(mode, tableData, options)
    options = options or {}
    local state = Engine.newState()
    local match = {
        id = nextMatchId,
        mode = mode,
        stateName = 'waiting',
        tableId = tableData and tableData.id or nil,
        white = nil,
        black = nil,
        whiteIdentifier = nil,
        blackIdentifier = nil,
        whiteName = nil,
        blackName = nil,
        state = state,
        moveHistory = {},
        capturedWhite = {},
        capturedBlack = {},
        startedAt = nil,
        endedAt = nil,
        winner = nil,
        winnerIdentifier = nil,
        result = nil,
        lastMove = nil,
        startingFen = Engine.toFen(state),
        botColor = options.botColor,
        botDifficulty = options.botDifficulty,
        wagerAmount = options.wagerAmount,
        wagerAccount = options.wagerAmount and configuredWagerAccount() or nil,
        wagerPot = options.wagerAmount and options.wagerAmount * 2 or nil
    }

    nextMatchId = nextMatchId + 1
    matches[match.id] = match

    if tableData then
        tableData.matchId = match.id
        tableData.board = copyBoard(match.state.board)
        tableData.capturedWhite = {}
        tableData.capturedBlack = {}
    end

    return match
end

local function assignPlayer(match, source, color)
    local identifier = getIdentifier(source)
    local name = getName(source)

    if color == 'white' then
        match.white = source
        match.whiteIdentifier = identifier
        match.whiteName = name
    else
        match.black = source
        match.blackIdentifier = identifier
        match.blackName = name
    end

    activeByPlayer[source] = match.id
    Stats.ensure(identifier, name)
end

local function clearMatchColor(match, color)
    local player = color == 'white' and match.white or match.black

    if player and player ~= 0 then
        activeByPlayer[player] = nil
    end

    if color == 'white' then
        match.white = nil
        match.whiteIdentifier = nil
        match.whiteName = nil
    else
        match.black = nil
        match.blackIdentifier = nil
        match.blackName = nil
    end
end

local function startMatchIfReady(match)
    if not match.white or not match.black or match.stateName ~= 'waiting' then
        return false
    end

    local ok, errorMessage = collectWager(match)

    if not ok then
        return false, errorMessage
    end

    match.stateName = 'active'
    match.startedAt = now()
    sendMatchPlayers(match, ('Match %d started. White to move.'):format(match.id))

    return true
end

local function validMatchMode(mode)
    mode = tostring(mode or ''):lower()

    if mode == 'casual' or mode == 'ranked' then
        return mode
    end

    return nil
end

local function validBotDifficulty(difficulty)
    difficulty = tostring(difficulty or 'easy'):lower()

    if difficulty == 'easy' or difficulty == 'medium' or difficulty == 'hard' then
        return difficulty
    end

    return nil
end

local function waitingMatchCompatible(match, mode, wagerAmount)
    return match
        and match.stateName == 'waiting'
        and match.mode == mode
        and (tonumber(match.wagerAmount) or 0) == (tonumber(wagerAmount) or 0)
end

local function createOrJoinTableMatch(source, tableId, color, mode, wagerAmount)
    mode = validMatchMode(mode)
    color = tostring(color or ''):lower()

    if not mode then
        notify(source, 'Choose casual or ranked.')
        return nil
    end

    if color ~= 'white' and color ~= 'black' then
        notify(source, 'Choose white or black.')
        return nil
    end

    local wagerOk, normalizedWager, wagerError = isAllowedWagerAmount(wagerAmount)

    if not wagerOk then
        notify(source, wagerError)
        return nil
    end

    local tableData = getTable(tableId)

    if not tableData then
        notify(source, 'Table not found.')
        return nil
    end

    if activeByPlayer[source] then
        local activeMatch = matches[activeByPlayer[source]]

        if activeMatch and activeMatch.stateName == 'waiting' and activeMatch.tableId == tableData.id then
            notify(source, ('You are already waiting in match %d.'):format(activeMatch.id))
            return activeMatch
        end

        notify(source, 'You are already in a chess match.')
        return nil
    end

    local seatOk, seatError = occupySeat(source, tableData, color)

    if not seatOk then
        notify(source, seatError)
        return nil
    end

    local match = tableData.matchId and matches[tableData.matchId] or nil

    if match and not waitingMatchCompatible(match, mode, normalizedWager) then
        notify(source, 'That table already has a different active or waiting match.')
        return nil
    end

    if not match then
        match = createEmptyMatch(mode, tableData, {
            wagerAmount = normalizedWager > 0 and normalizedWager or nil
        })
    end

    if match[color] and match[color] ~= source then
        notify(source, ('%s is already taken for match %d.'):format(color, match.id))
        return nil
    end

    if match.white == source or match.black == source then
        notify(source, ('You already joined match %d.'):format(match.id))
        return match
    end

    assignPlayer(match, source, color)

    local started, startError = startMatchIfReady(match)

    if startError then
        clearMatchColor(match, color)
        notify(source, startError)
    elseif not started then
        notify(source, ('Created %s match %d as %s. Waiting for opponent.'):format(mode, match.id, color))
    end

    syncMatch(match)

    return match
end

local function startBotMatch(source, tableData, playerColor, difficulty)
    difficulty = validBotDifficulty(difficulty)
    playerColor = playerColor == 'black' and 'black' or 'white'

    if not difficulty then
        return notify(source, 'Bot difficulty must be easy, medium, or hard.')
    end

    if activeByPlayer[source] then
        return notify(source, 'You are already in an active chess match.')
    end

    local botColor = opponentColor(playerColor)
    local match = createEmptyMatch('bot', tableData, {
        botColor = botColor,
        botDifficulty = difficulty
    })
    local botName = ('%s bot'):format(difficulty:gsub('^%l', string.upper))

    match.stateName = 'active'
    match.botColor = botColor
    match.botDifficulty = difficulty
    match.startedAt = now()

    if playerColor == 'white' then
        match.white = source
        match.whiteIdentifier = getIdentifier(source)
        match.whiteName = getName(source)
        match.black = 0
        match.blackIdentifier = 'bot:' .. difficulty
        match.blackName = botName
    else
        match.white = 0
        match.whiteIdentifier = 'bot:' .. difficulty
        match.whiteName = botName
        match.black = source
        match.blackIdentifier = getIdentifier(source)
        match.blackName = getName(source)
    end

    activeByPlayer[source] = match.id
    Stats.ensure(getIdentifier(source), getName(source))

    if tableData then
        occupySeat(source, tableData, playerColor)
    end

    syncMatch(match)
    scheduleBotTurn(match)
    notify(source, ('Created bot match %d (%s). You are %s.'):format(match.id, match.botDifficulty, playerColor))
end

local function createMatch(source, args, coords)
    local mode = (args[1] or 'casual'):lower()
    local tableData = nearestTable(coords)

    if mode == 'bot' then
        return startBotMatch(source, tableData, 'white', args[2] or 'easy')
    end

    mode = validMatchMode(mode)

    if not mode then
        return notify(source, 'Use /chess_create casual, /chess_create ranked, or /chess_create bot easy|medium|hard.')
    end

    local match = createEmptyMatch(mode, tableData)
    syncMatch(match)
    notify(source, ('Created %s match %d. Join with /chess_join %d white or /chess_join %d black.'):format(mode, match.id, match.id, match.id))
end

local function joinMatch(source, matchId, color)
    matchId = tonumber(matchId)
    color = color and color:lower() or nil

    local match = matchId and matches[matchId] or nil

    if not match then
        return notify(source, 'Match not found.')
    end

    if match.mode == 'bot' then
        return notify(source, 'Bot matches cannot be joined.')
    end

    if match.stateName ~= 'waiting' then
        return notify(source, 'That match is not waiting for players.')
    end

    if color ~= 'white' and color ~= 'black' then
        return notify(source, 'Choose white or black.')
    end

    if activeByPlayer[source] then
        return notify(source, 'You are already in a chess match.')
    end

    if match.white == source or match.black == source then
        return notify(source, 'You already joined this match.')
    end

    if color == 'white' and match.white then
        return notify(source, 'White is already taken.')
    end

    if color == 'black' and match.black then
        return notify(source, 'Black is already taken.')
    end

    assignPlayer(match, source, color)

    local started, startError = startMatchIfReady(match)

    if startError then
        clearMatchColor(match, color)
        return notify(source, startError)
    end

    if not started then
        notify(source, ('Joined match %d as %s. Waiting for opponent.'):format(match.id, color))
    end

    syncMatch(match)
end

local function movePiece(source, from, to, promotion)
    local matchId = activeByPlayer[source]
    local match = matchId and matches[matchId] or nil

    if not match then
        return notify(source, 'You are not in a chess match.')
    end

    local color = colorForSource(match, source)

    if not color then
        return notify(source, 'You are not a player in this match.')
    end

    local ok, errorMessage = applyMove(match, color, from, to, promotion, getName(source), source)

    if not ok then
        return notify(source, errorMessage)
    end
end

local function selectSquare(source, square)
    square = square and square:lower() or nil

    local matchId = activeByPlayer[source]
    local match = matchId and matches[matchId] or nil

    local response = {
        matchId = matchId,
        from = square,
        moves = {},
        message = nil
    }

    if not match then
        response.message = 'You are not in a chess match.'
        TriggerClientEvent('cr-chess:client:legalMoves', source, response)
        return
    end

    response.tableId = match.tableId

    if match.stateName ~= 'active' then
        response.message = 'That match is not active yet.'
        TriggerClientEvent('cr-chess:client:legalMoves', source, response)
        return
    end

    local color = colorForSource(match, source)

    if not color then
        response.message = 'You are not a player in this match.'
        TriggerClientEvent('cr-chess:client:legalMoves', source, response)
        return
    end

    if match.state.turn ~= color then
        response.message = ('It is %s\'s turn.'):format(match.state.turn)
        TriggerClientEvent('cr-chess:client:legalMoves', source, response)
        return
    end

    if not Engine.isSquare(square) then
        response.message = 'Select a valid board square.'
        TriggerClientEvent('cr-chess:client:legalMoves', source, response)
        return
    end

    local piece = match.state.board[square]

    if not piece then
        response.message = 'There is no piece on that square.'
        TriggerClientEvent('cr-chess:client:legalMoves', source, response)
        return
    end

    if Engine.pieceColor(piece) ~= color then
        response.message = 'That is not your piece.'
        TriggerClientEvent('cr-chess:client:legalMoves', source, response)
        return
    end

    response.piece = piece

    for _, move in ipairs(Engine.legalMovesFrom(match.state, square, color)) do
        response.moves[#response.moves + 1] = {
            to = move.to,
            capture = move.capture ~= nil,
            captureSquare = move.capture,
            promotion = move.promotion,
            castle = move.castle
        }
    end

    if #response.moves == 0 then
        response.message = 'That piece has no legal moves.'
    end

    TriggerClientEvent('cr-chess:client:legalMoves', source, response)
end

local function showBoard(source)
    local matchId = activeByPlayer[source]
    local match = matchId and matches[matchId] or nil

    if not match then
        return notify(source, 'You are not in a chess match.')
    end

    notify(source, ('Match %d | turn: %s | FEN: %s\n%s'):format(
        match.id,
        match.state.turn,
        Engine.toFen(match.state),
        Engine.toAscii(match.state)
    ))
end

local function resign(source)
    local matchId = activeByPlayer[source]
    local match = matchId and matches[matchId] or nil

    if not match then
        return notify(source, 'You are not in a chess match.')
    end

    if match.stateName ~= 'active' then
        activeByPlayer[source] = nil
        clearSourceSeat(source, false)

        if match.white == source then
            match.white = nil
            match.whiteIdentifier = nil
            match.whiteName = nil
        elseif match.black == source then
            match.black = nil
            match.blackIdentifier = nil
            match.blackName = nil
        end

        if not match.white and not match.black and match.tableId and tables[match.tableId] then
            tables[match.tableId].matchId = nil
            tables[match.tableId].board = Engine.initialBoard()
        end

        syncMatch(match)
        return notify(source, 'You left the waiting match.')
    end

    local color = colorForSource(match, source)

    if not color then
        return notify(source, 'You are not a player in this match.')
    end

    finishMatch(match, 'resignation', Engine.opposite(color))
end

local function showStats(source)
    local identifier = getIdentifier(source)
    local player = Stats.ensure(identifier, getName(source))

    notify(source, ('%s | Rating: %d (%s) | Casual %d/%d/%d | Ranked %d/%d/%d | Bot %d/%d/%d | Games: %d'):format(
        player.name,
        player.rating,
        Stats.rankName(player.rating),
        player.casualWins,
        player.casualLosses,
        player.casualDraws,
        player.rankedWins,
        player.rankedLosses,
        player.rankedDraws,
        player.botWins,
        player.botLosses,
        player.botDraws,
        player.gamesPlayed
    ))
end

local function showLeaderboard(source)
    local rows = Stats.leaderboard(10)

    if #rows == 0 then
        return notify(source, 'No chess ratings yet.')
    end

    local lines = { 'Chess leaderboard:' }

    for index, player in ipairs(rows) do
        lines[#lines + 1] = ('%d. %s - %d (%s)'):format(index, player.name, player.rating, Stats.rankName(player.rating))
    end

    notify(source, table.concat(lines, '\n'))
end

local function sendLeaderboard(source)
    TriggerClientEvent('cr-chess:client:leaderboardData', source, Stats.leaderboardRows(25))
end

local function sendProfile(source, identifier)
    TriggerClientEvent('cr-chess:client:profileData', source, Stats.profile(identifier))
end

local function sitAtTable(source, tableId, color)
    color = tostring(color or ''):lower()
    local tableData = getTable(tableId)

    if not tableData then
        return notify(source, 'Table not found.')
    end

    local activeMatch = activeByPlayer[source] and matches[activeByPlayer[source]] or nil

    if activeMatch and (activeMatch.stateName == 'active' or activeMatch.tableId ~= tableData.id) then
        return notify(source, 'You are already in a chess match.')
    end

    local ok, errorMessage = occupySeat(source, tableData, color)

    if not ok then
        return notify(source, errorMessage)
    end

    TriggerClientEvent('cr-chess:client:seatedAtTable', source, tableData.id, color, tableSnapshot(tableData))
    notify(source, ('Seated as %s at chess table %d.'):format(color, tableData.id))
end

local function standFromTable(source)
    local activeMatch = activeByPlayer[source] and matches[activeByPlayer[source]] or nil

    if activeMatch then
        if activeMatch.stateName == 'active' then
            return notify(source, 'Use /chess_resign before standing from an active match.')
        end

        resign(source)
    end

    clearSourceSeat(source, true)
    TriggerClientEvent('cr-chess:client:forceStand', source)
    notify(source, 'You stood up from the chess table.')
end

local function startSeatedBot(source, tableId, color, difficulty)
    local tableData = getTable(tableId)

    if not tableData then
        return notify(source, 'Table not found.')
    end

    if activeByPlayer[source] then
        return notify(source, 'You are already in a chess match.')
    end

    if tableData.matchId then
        local match = matches[tableData.matchId]

        if match and match.stateName ~= 'finished' then
            return notify(source, 'That table already has a match.')
        end
    end

    local ok, errorMessage = occupySeat(source, tableData, color)

    if not ok then
        return notify(source, errorMessage)
    end

    startBotMatch(source, tableData, color, difficulty)
end

local function startSeatedWait(source, tableId, color, mode, wagerAmount)
    createOrJoinTableMatch(source, tableId, color, mode, wagerAmount)
end

local function inviteSeatedMatch(source, tableId, color, mode, targetSource, wagerAmount)
    targetSource = tonumber(targetSource)

    if not targetSource or targetSource == source or not GetPlayerName(targetSource) then
        return notify(source, 'Choose a nearby player to invite.')
    end

    local match = createOrJoinTableMatch(source, tableId, color, mode, wagerAmount)

    if not match then
        return
    end

    if match.stateName ~= 'waiting' then
        return notify(source, 'That match is already active.')
    end

    local sourceColor = colorForSource(match, source) or color
    local inviteColor = opponentColor(sourceColor)

    pendingInvites[targetSource] = {
        fromSource = source,
        fromName = getName(source),
        matchId = match.id,
        tableId = tonumber(tableId),
        color = inviteColor,
        mode = match.mode,
        wagerAmount = match.wagerAmount or 0,
        wagerAccount = match.wagerAccount or configuredWagerAccount()
    }

    TriggerClientEvent('cr-chess:client:matchInvite', targetSource, pendingInvites[targetSource])
    notify(source, ('Invited %s to match %d as %s.'):format(getName(targetSource), match.id, inviteColor))
end

local function acceptInvite(source, matchId)
    local invite = pendingInvites[source]

    if not invite then
        return notify(source, 'You do not have a pending chess invite.')
    end

    if matchId and tonumber(matchId) and tonumber(matchId) ~= invite.matchId then
        return notify(source, 'That invite is no longer current.')
    end

    pendingInvites[source] = nil
    createOrJoinTableMatch(source, invite.tableId, invite.color, invite.mode, invite.wagerAmount)
end

RegisterNetEvent('cr-chess:server:requestSync', function()
    broadcastTables(source)
end)

RegisterNetEvent('cr-chess:server:createTable', function(coords, heading, requestId)
    local source = source

    if not validCoords(coords) then
        return notify(source, 'Invalid table coordinates.')
    end

    requestId = tostring(requestId or '')

    local spawnAt = nowMs()
    local lastSpawn = lastTableSpawnByPlayer[source]
    local cooldown = tonumber(Config.TableSpawnCooldownMs) or 1500

    if lastSpawn then
        if requestId ~= '' and lastSpawn.requestId == requestId then
            return notify(source, 'That chess table placement was already submitted.')
        end

        if spawnAt - (lastSpawn.at or 0) < cooldown then
            return notify(source, 'Please wait a moment before spawning another chess table.')
        end
    end

    lastTableSpawnByPlayer[source] = {
        at = spawnAt,
        requestId = requestId
    }

    local reuseRange = tonumber(Config.TableSpawnReuseRange) or 1.25
    local nearby = findNearbyTable(coords, reuseRange)

    if nearby then
        local removed = removeIdleTablesNear(coords, reuseRange, nearby.id)
        local suffix = #removed > 0 and (' Removed %d duplicate idle table%s.'):format(#removed, #removed == 1 and '' or 's') or ''

        if #removed > 0 then
            broadcastTables()
        end

        if canRemoveIdleTable(nearby) then
            return notify(source, ('A chess table is already here: %d.%s'):format(nearby.id, suffix))
        end

        return notify(source, ('Chess table %d is already here and is in use.%s'):format(nearby.id, suffix))
    end

    local tableId = nextTableId
    nextTableId = nextTableId + 1

    tables[tableId] = {
        id = tableId,
        coords = {
            x = coords.x,
            y = coords.y,
            z = coords.z
        },
        heading = tonumber(heading) or 0.0,
        createdBy = source,
        matchId = nil,
        seats = {},
        board = Engine.initialBoard(),
        capturedWhite = {},
        capturedBlack = {}
    }

    broadcastTables()
    notify(source, ('Spawned chess table %d.'):format(tableId))
end)

RegisterNetEvent('cr-chess:server:cleanupTablesNear', function(coords, range)
    local source = source

    if not validCoords(coords) then
        return notify(source, 'Invalid cleanup coordinates.')
    end

    local maxRange = tonumber(range) or Config.TableCleanupRange or 3.0
    maxRange = math.max(0.5, math.min(maxRange, 10.0))

    local removed = removeIdleTablesNear(coords, maxRange)

    if #removed == 0 then
        return notify(source, ('No idle chess tables found within %.1fm.'):format(maxRange))
    end

    broadcastTables()
    notify(source, ('Removed %d idle chess table%s within %.1fm.'):format(#removed, #removed == 1 and '' or 's', maxRange))
end)

RegisterNetEvent('cr-chess:server:deleteTable', function(tableId)
    local source = source
    tableId = tonumber(tableId)

    if not tableId or not tables[tableId] then
        return notify(source, 'Table not found.')
    end

    local tableData = tables[tableId]

    if tableData.matchId then
        local match = matches[tableData.matchId]

        if match and match.stateName ~= 'finished' then
            return notify(source, 'That table has an active or waiting match.')
        end
    end

    tables[tableId] = nil
    broadcastTables()
    notify(source, ('Deleted chess table %d.'):format(tableId))
end)

RegisterNetEvent('cr-chess:server:createMatch', function(args, coords)
    createMatch(source, args or {}, coords)
end)

RegisterNetEvent('cr-chess:server:joinMatch', function(matchId, color)
    joinMatch(source, matchId, color)
end)

RegisterNetEvent('cr-chess:server:sitAtTable', function(tableId, color)
    sitAtTable(source, tableId, color)
end)

RegisterNetEvent('cr-chess:server:standFromTable', function()
    standFromTable(source)
end)

RegisterNetEvent('cr-chess:server:startSeatedBot', function(tableId, color, difficulty)
    startSeatedBot(source, tableId, color, difficulty)
end)

RegisterNetEvent('cr-chess:server:startSeatedWait', function(tableId, color, mode, wagerAmount)
    startSeatedWait(source, tableId, color, mode, wagerAmount)
end)

RegisterNetEvent('cr-chess:server:inviteSeatedMatch', function(tableId, color, mode, targetSource, wagerAmount)
    inviteSeatedMatch(source, tableId, color, mode, targetSource, wagerAmount)
end)

RegisterNetEvent('cr-chess:server:acceptInvite', function(matchId)
    acceptInvite(source, matchId)
end)

RegisterNetEvent('cr-chess:server:move', function(from, to, promotion)
    movePiece(source, from, to, promotion)
end)

RegisterNetEvent('cr-chess:server:selectSquare', function(square)
    selectSquare(source, square)
end)

RegisterNetEvent('cr-chess:server:board', function()
    showBoard(source)
end)

RegisterNetEvent('cr-chess:server:resign', function()
    resign(source)
end)

RegisterNetEvent('cr-chess:server:stats', function()
    showStats(source)
end)

RegisterNetEvent('cr-chess:server:leaderboard', function()
    showLeaderboard(source)
end)

RegisterNetEvent('cr-chess:server:requestLeaderboard', function()
    sendLeaderboard(source)
end)

RegisterNetEvent('cr-chess:server:requestProfile', function(identifier)
    sendProfile(source, identifier)
end)

AddEventHandler('playerDropped', function()
    local source = source
    local matchId = activeByPlayer[source]
    local match = matchId and matches[matchId] or nil

    pendingInvites[source] = nil
    lastTableSpawnByPlayer[source] = nil

    for target, invite in pairs(pendingInvites) do
        if invite.fromSource == source then
            pendingInvites[target] = nil
        end
    end

    if not match then
        clearSourceSeat(source, true)
        return
    end

    if match.stateName == 'active' then
        local color = colorForSource(match, source)
        finishMatch(match, 'disconnect', color and Engine.opposite(color) or nil)
        return
    end

    if match.white == source then
        match.white = nil
        match.whiteIdentifier = nil
        match.whiteName = nil
    elseif match.black == source then
        match.black = nil
        match.blackIdentifier = nil
        match.blackName = nil
    end

    activeByPlayer[source] = nil
    clearSourceSeat(source, true)
    syncMatch(match)
end)

math.randomseed(os.time())
