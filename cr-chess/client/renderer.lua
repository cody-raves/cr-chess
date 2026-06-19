local renderedTables = {}
local currentMatch = nil
local tableCamera = nil
local ensureSeatForMatch
local ensureBotPedForMatch
local seatLocalPedOnTable
local applySeatTransform
local reconcileSeatAvatars
local clearSeatAvatars
local playActorMoveAnimation
local playCaptureReactions
local playResultReaction
local playTestReaction
local drawText3d
local drawText2d
local registerTableTargets
local unregisterTableTargets
local openTableMenu
local lastBoardOverlayAt = 0
local seated = {
    active = false,
    color = nil,
    tableId = nil,
    avatar = nil,
    hiddenPlayer = false
}

local tableMenu = {
    visible = false,
    tableId = nil,
    color = nil,
    invite = nil
}

local feedback = {
    lastResultKey = nil,
    resultOpen = false
}

local seatAnimLocks = {}
local hiddenRemoteSeatSources = {}

local interaction = {
    enabled = false,
    selected = nil,
    selectedPiece = nil,
    legalMoves = {},
    legalByTo = {}
}

local uvDebug = {
    enabled = false
}

local tuning = {
    enabled = false,
    target = 'seat_white',
    fieldIndex = 1,
    targets = {
        'seat_white',
        'seat_black',
        'camera_white',
        'camera_black'
    }
}

local tunePreview = {
    ped = nil,
    target = nil
}

local tablePlacement = {
    active = false,
    heading = 0.0,
    coords = nil,
    table = nil,
    board = nil,
    chairs = {},
    requestId = nil
}

local files = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' }

local tuningFields = {
    seat_white = { 'x', 'y', 'z', 'rotX', 'rotY', 'rotZ' },
    seat_black = { 'x', 'y', 'z', 'rotX', 'rotY', 'rotZ' },
    camera_white = { 'x', 'y', 'z', 'lookX', 'lookY', 'lookZ', 'fov' },
    camera_black = { 'x', 'y', 'z', 'lookX', 'lookY', 'lookZ', 'fov' }
}

local function notify(message)
    TriggerEvent('chat:addMessage', {
        color = { 160, 230, 160 },
        multiline = true,
        args = { 'Chess', message }
    })
end

local function sendNui(action, payload)
    payload = payload or {}
    payload.action = action
    payload.resourceName = GetCurrentResourceName()
    SendNUIMessage(payload)
end

local function playNuiSoundFile(file, volume)
    if not file or file == '' then
        return
    end

    sendNui('playSound', {
        file = file,
        volume = volume or (Config.Sounds and Config.Sounds.volume) or 0.55
    })
end

local function setNuiVisible(visible, focus)
    if focus == nil then
        focus = visible
    end

    sendNui(visible and 'show' or 'hide')
    SetNuiFocus(visible and focus or false, visible and focus or false)

    if type(SetNuiFocusKeepInput) == 'function' then
        SetNuiFocusKeepInput(false)
    end

    CreateThread(function()
        Wait(75)
        sendNui(visible and 'show' or 'hide')
    end)
end

local function playMoveSound()
    if not Config.Sounds or not Config.Sounds.enabled then
        return
    end

    local sounds = Config.Sounds.move or {}

    if #sounds == 0 then
        return
    end

    playNuiSoundFile(sounds[math.random(#sounds)])
end

local function localColorForSnapshot(snapshot)
    if not snapshot then
        return nil
    end

    local myServerId = GetPlayerServerId(PlayerId())

    if snapshot.white == myServerId then
        return 'white'
    end

    if snapshot.black == myServerId then
        return 'black'
    end

    return nil
end

local function nativeSoundList(kind)
    if not Config.Sounds or not Config.Sounds.native or Config.Sounds.native.enabled == false then
        return nil
    end

    return Config.Sounds.native[kind]
end

local function playNativeFeedback(kind)
    local sounds = nativeSoundList(kind)

    if not sounds or #sounds == 0 then
        return
    end

    local sound = sounds[math.random(#sounds)]

    if sound and sound.name and sound.set then
        PlaySoundFrontend(-1, sound.name, sound.set, true)
    end
end

local function feedbackSoundList(kind)
    if not Config.Sounds or not Config.Sounds.enabled or not Config.Sounds.feedback then
        return nil
    end

    return Config.Sounds.feedback[kind]
end

local function playFeedbackSound(kind)
    local sounds = feedbackSoundList(kind)

    if sounds and #sounds > 0 then
        playNuiSoundFile(sounds[math.random(#sounds)])
        return
    end

    playNativeFeedback(kind)
end

local soundAliases = {
    take = 'captureByPlayer',
    capture = 'captureByPlayer',
    capturebyplayer = 'captureByPlayer',
    takepiece = 'captureByPlayer',
    take_piece = 'captureByPlayer',
    captured = 'capturedByOpponent',
    capturedbyopponent = 'capturedByOpponent',
    taken = 'capturedByOpponent',
    losepiece = 'capturedByOpponent',
    lostpiece = 'capturedByOpponent',
    lose_piece = 'capturedByOpponent',
    lost_piece = 'capturedByOpponent',
    win = 'win',
    winmatch = 'win',
    win_match = 'win',
    lose = 'lose',
    loss = 'lose',
    losematch = 'lose',
    lose_match = 'lose',
    draw = 'draw'
}

local function isAudioFile(value)
    value = tostring(value or ''):lower()
    return value:match('%.ogg$')
end

local function normalizeSoundFile(value)
    value = tostring(value or ''):gsub('\\', '/')

    if value == '' or not isAudioFile(value) then
        return nil
    end

    if value:find('/', 1, true) then
        return value
    end

    return 'sfx/' .. value
end

local function nativeSoundConfigLine(kind, sound)
    return ("{ name = '%s', set = '%s' } -- %s"):format(sound.name, sound.set, kind)
end

local function feedbackSoundConfigLine(kind, file)
    return ("Config.Sounds.feedback.%s = { '%s' }"):format(kind, file)
end

local function testConfiguredSound(alias, index)
    local kind = soundAliases[tostring(alias or ''):lower()]

    if not kind then
        return false
    end

    local sounds = feedbackSoundList(kind)

    if not sounds or #sounds == 0 then
        sounds = nativeSoundList(kind)

        if not sounds or #sounds == 0 then
            notify(('No configured sounds for %s.'):format(kind))
            return true
        end

        index = tonumber(index) or 1

        if index < 1 or index > #sounds then
            notify(('Sound index must be 1-%d for %s.'):format(#sounds, kind))
            return true
        end

        local sound = sounds[index]
        PlaySoundFrontend(-1, sound.name, sound.set, true)
        print('[cr-chess sound] ' .. nativeSoundConfigLine(kind, sound))
        notify(('Played native %s #%d: %s / %s'):format(kind, index, sound.name, sound.set))
        return true
    end

    index = tonumber(index) or 1

    if index < 1 or index > #sounds then
        notify(('Sound index must be 1-%d for %s.'):format(#sounds, kind))
        return true
    end

    local file = sounds[index]
    playNuiSoundFile(file)
    print('[cr-chess sound] ' .. feedbackSoundConfigLine(kind, file))
    notify(('Played file %s #%d: %s'):format(kind, index, file))

    return true
end

RegisterNetEvent('cr-chess:client:testSound', function(args)
    args = args or {}

    if testConfiguredSound(args[1], args[2]) then
        return
    end

    local soundFile = normalizeSoundFile(args[1])

    if soundFile then
        playNuiSoundFile(soundFile)
        print(("[cr-chess sound] '%s'"):format(soundFile))
        notify(('Played file sound: %s'):format(soundFile))
        return
    end

    local soundName = args[1]
    local soundSet = args[2]

    if not soundName or not soundSet then
        notify('Use /chess_sound take|taken|win|lose|draw [index], /chess_sound sfx/take_piece.ogg, or /chess_sound <soundName> <soundSet>.')
        return
    end

    PlaySoundFrontend(-1, soundName, soundSet, true)

    local line = ("{ name = '%s', set = '%s' }"):format(soundName, soundSet)
    print('[cr-chess sound] ' .. line)
    notify(('Played native sound: %s / %s'):format(soundName, soundSet))
end)

RegisterNetEvent('cr-chess:client:testAnimation', function(args)
    if playTestReaction then
        playTestReaction(args)
        return
    end

    notify('Animation tester is not ready yet.')
end)

local function pieceName(pieceCode)
    return (Config.PieceNames and Config.PieceNames[pieceCode]) or tostring(pieceCode or 'piece')
end

local function showMoveFeedback(snapshot)
    local move = snapshot and snapshot.lastMove or nil

    if not move or not move.capturedPiece then
        return
    end

    local localColor = localColorForSnapshot(snapshot)

    if not localColor then
        return
    end

    local moveColor = move.color

    if not moveColor and snapshot.moveHistory then
        local latest = snapshot.moveHistory[#snapshot.moveHistory]

        if latest
            and latest.from == move.from
            and latest.to == move.to
            and latest.capturedPiece == move.capturedPiece
        then
            moveColor = latest.color
        end
    end

    local playerCaptured = moveColor == localColor
    local kind = playerCaptured and 'capture' or 'captured'
    local nativeKind = playerCaptured and 'captureByPlayer' or 'capturedByOpponent'
    local capturedName = pieceName(move.capturedPiece)
    local title = playerCaptured and 'Piece Taken' or 'Piece Lost'
    local message = playerCaptured
        and ('You captured %s on %s.'):format(capturedName, move.captureSquare or move.to)
        or ('You lost %s on %s.'):format(capturedName, move.captureSquare or move.to)

    if playCaptureReactions then
        playCaptureReactions(snapshot, move, moveColor)
    end

    playFeedbackSound(nativeKind)
    sendNui('feedback', {
        kind = kind,
        title = title,
        message = message
    })
end

local function finishTitle(result)
    if result == 'win' then
        return 'Victory'
    end

    if result == 'lose' then
        return 'Defeat'
    end

    return 'Draw'
end

local function resultForSnapshot(snapshot)
    local localColor = localColorForSnapshot(snapshot)

    if not localColor or not snapshot or snapshot.state ~= 'finished' then
        return nil
    end

    if snapshot.result == 'draw' or not snapshot.winner then
        return 'draw'
    end

    return snapshot.winner == localColor and 'win' or 'lose'
end

local function showMatchResultFeedback(snapshot)
    local result = resultForSnapshot(snapshot)

    if not result then
        return
    end

    local key = ('%s:%s:%s'):format(snapshot.id, snapshot.result or 'draw', snapshot.finishReason or 'finished')

    if feedback.lastResultKey == key then
        return
    end

    feedback.lastResultKey = key

    if playResultReaction then
        playResultReaction(snapshot, result)
    end

    playFeedbackSound(result)
    feedback.resultOpen = true
    setNuiVisible(true, true)

    local reason = snapshot.finishReason or (result == 'draw' and 'draw' or 'win')
    local subtitle = result == 'draw'
        and ('Game drawn by %s.'):format(reason)
        or (result == 'win'
            and ('You won by %s.'):format(reason)
            or ('You lost by %s.'):format(reason))

    sendNui('matchResult', {
        result = result,
        title = finishTitle(result),
        subtitle = subtitle,
        review = snapshot.review
    })
end

local function handleMoveLandingFeedback(snapshot)
    playMoveSound()
    showMoveFeedback(snapshot)
end

local function toVector3(coords)
    return vector3(coords.x, coords.y, coords.z)
end

local function loadModel(model)
    local hash = joaat(model)

    RequestModel(hash)

    local expiresAt = GetGameTimer() + 5000

    while not HasModelLoaded(hash) do
        Wait(0)

        if GetGameTimer() > expiresAt then
            print(('[cr-chess] Failed to load model %s'):format(model))
            return nil
        end
    end

    return hash
end

local function loadAnimDict(animDict)
    RequestAnimDict(animDict)

    local expiresAt = GetGameTimer() + 5000

    while not HasAnimDictLoaded(animDict) do
        Wait(0)

        if GetGameTimer() > expiresAt then
            print(('[cr-chess] Failed to load anim dict %s'):format(animDict))
            return false
        end
    end

    return true
end

local function deleteEntity(entity)
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

local function createObject(model, coords)
    local hash = loadModel(model)

    if not hash then
        return nil
    end

    local object = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)

    return object
end

local function squareOffset(square)
    square = tostring(square or ''):lower()

    local file = square:sub(1, 1)
    local rank = tonumber(square:sub(2, 2))
    local fileIndexes = {
        a = 0,
        b = 1,
        c = 2,
        d = 3,
        e = 4,
        f = 5,
        g = 6,
        h = 7
    }

    local fileIndex = fileIndexes[file]

    if not fileIndex or not rank or rank < 1 or rank > 8 then
        return nil
    end

    local config = Config.PieceOffset

    return {
        x = config.startX + fileIndex * config.step,
        y = config.startY + (rank - 1) * config.step,
        z = config.z
    }
end

local function squareFromLocal(localPoint)
    local config = Config.PieceOffset
    local minX = config.startX - config.step * 0.5
    local minY = config.startY - config.step * 0.5
    local maxX = config.startX + config.step * 7.5
    local maxY = config.startY + config.step * 7.5

    if localPoint.x < minX or localPoint.x > maxX or localPoint.y < minY or localPoint.y > maxY then
        return nil
    end

    local fileIndex = math.floor((localPoint.x - minX) / config.step) + 1
    local rank = math.floor((localPoint.y - minY) / config.step) + 1

    if fileIndex < 1 or fileIndex > 8 or rank < 1 or rank > 8 then
        return nil
    end

    return files[fileIndex] .. tostring(rank)
end

local function attachEntityToBoardOffset(entity, boardEntity, offset)
    if not offset or not entity or not boardEntity then
        return
    end

    AttachEntityToEntity(
        entity,
        boardEntity,
        0,
        offset.x,
        offset.y,
        offset.z,
        0.0,
        0.0,
        offset.heading or 0.0,
        false,
        false,
        false,
        false,
        2,
        true
    )
end

local function attachPieceToSquare(pieceEntity, boardEntity, square)
    attachEntityToBoardOffset(pieceEntity, boardEntity, squareOffset(square))
end

local function animateEntityToOffset(rendered, entity, offset, duration, lift, done)
    if not entity or not DoesEntityExist(entity) or not offset then
        if done then
            done()
        end

        return
    end

    CreateThread(function()
        DetachEntity(entity, true, true)

        local startCoords = GetEntityCoords(entity)
        local target = GetOffsetFromEntityInWorldCoords(rendered.board, offset.x, offset.y, offset.z)
        local startedAt = GetGameTimer()
        local total = duration or 650

        while DoesEntityExist(entity) do
            local elapsed = GetGameTimer() - startedAt
            local t = math.min(elapsed / total, 1.0)
            local eased = t * t * (3.0 - 2.0 * t)
            local arc = math.sin(eased * math.pi) * (lift or 0.16)
            local x = startCoords.x + (target.x - startCoords.x) * eased
            local y = startCoords.y + (target.y - startCoords.y) * eased
            local z = startCoords.z + (target.z - startCoords.z) * eased + arc

            SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)

            if t >= 1.0 then
                break
            end

            Wait(0)
        end

        if DoesEntityExist(entity) then
            attachEntityToBoardOffset(entity, rendered.board, offset)
        end

        if done then
            done()
        end
    end)
end

local function deletePiece(rendered, square)
    local entity = rendered.pieces[square]

    if entity then
        deleteEntity(entity)
        rendered.pieces[square] = nil
        rendered.pieceCodes[square] = nil
    end
end

local function spawnPiece(rendered, pieceCode, square)
    local model = Config.Props.pieces[pieceCode]

    if not model or not rendered.board then
        return nil
    end

    local coords = GetEntityCoords(rendered.board)
    local piece = createObject(model, {
        x = coords.x,
        y = coords.y,
        z = coords.z + 0.5
    })

    if not piece then
        return nil
    end

    SetEntityCollision(piece, false, false)
    SetEntityVisible(piece, true, false)
    attachPieceToSquare(piece, rendered.board, square)

    rendered.pieces[square] = piece
    rendered.pieceCodes[square] = pieceCode

    return piece
end

local function moveRenderedPiece(rendered, from, to, pieceCode)
    local entity = rendered.pieces[from]

    if not entity then
        return false
    end

    rendered.pieces[from] = nil
    rendered.pieceCodes[from] = nil
    rendered.pieces[to] = entity
    rendered.pieceCodes[to] = pieceCode
    animateEntityToOffset(rendered, entity, squareOffset(to), 650, 0.16)

    return true
end

local function clearCapturedSide(rendered, side)
    local entries = rendered.captured[side]

    for _, entry in ipairs(entries) do
        deleteEntity(entry.entity)
    end

    rendered.captured[side] = {}
end

local function reconcileCaptured(rendered)
    rendered.capturedWhiteCodes = {}
    rendered.capturedBlackCodes = {}
    clearCapturedSide(rendered, 'white')
    clearCapturedSide(rendered, 'black')
end

local function removeCapturedPiece(entity)
    if not entity then
        return
    end

    deleteEntity(entity)
end

local function reconcilePieces(rendered, board)
    board = board or {}
    local staleSquares = {}

    for square, pieceCode in pairs(rendered.pieceCodes) do
        if board[square] ~= pieceCode then
            staleSquares[#staleSquares + 1] = square
        end
    end

    for _, square in ipairs(staleSquares) do
        deletePiece(rendered, square)
    end

    for square, pieceCode in pairs(board) do
        if rendered.pieceCodes[square] ~= pieceCode then
            deletePiece(rendered, square)
            spawnPiece(rendered, pieceCode, square)
        end
    end
end

local function moveKey(snapshot)
    local lastMove = snapshot.lastMove

    if not lastMove then
        return nil
    end

    return table.concat({
        tostring(snapshot.id),
        tostring(#(snapshot.moveHistory or {})),
        tostring(lastMove.from),
        tostring(lastMove.to),
        tostring(lastMove.fen)
    }, ':')
end

local function applyLastMove(rendered, snapshot)
    local lastMove = snapshot.lastMove

    if not lastMove then
        return
    end

    local key = moveKey(snapshot)

    if rendered.lastMoveKey == key then
        return
    end

    rendered.lastMoveKey = key

    local capturedSquare = lastMove.captureSquare

    if not capturedSquare and lastMove.capturedPiece then
        capturedSquare = lastMove.to
    end

    if capturedSquare then
        local capturedEntity = rendered.pieces[capturedSquare]
        rendered.pieces[capturedSquare] = nil
        rendered.pieceCodes[capturedSquare] = nil
        removeCapturedPiece(capturedEntity)
    end

    if lastMove.castle and lastMove.rookFrom and lastMove.rookTo then
        moveRenderedPiece(rendered, lastMove.rookFrom, lastMove.rookTo, snapshot.board[lastMove.rookTo])
    end

    local movingEntity = rendered.pieces[lastMove.from]

    if movingEntity and snapshot.board and snapshot.board[lastMove.to] then
        rendered.pieces[lastMove.from] = nil
        rendered.pieceCodes[lastMove.from] = nil
        rendered.pieces[lastMove.to] = movingEntity
        rendered.pieceCodes[lastMove.to] = snapshot.board[lastMove.to]

        local didAnimateActor = playActorMoveAnimation and playActorMoveAnimation(rendered, snapshot, lastMove)
        local delay = didAnimateActor and ((Config.Animations and Config.Animations.pieceMoveDelay) or 0) or 0

        local function animateMove(done)
            local function run()
                animateEntityToOffset(rendered, movingEntity, squareOffset(lastMove.to), 650, 0.16, done)
            end

            if delay > 0 then
                CreateThread(function()
                    Wait(delay)
                    run()
                end)
            else
                run()
            end
        end

        if lastMove.promotion then
            animateMove(function()
                handleMoveLandingFeedback(snapshot)

                if rendered.pieces[lastMove.to] == movingEntity then
                    deleteEntity(movingEntity)
                    rendered.pieces[lastMove.to] = nil
                    rendered.pieceCodes[lastMove.to] = nil
                    spawnPiece(rendered, snapshot.board[lastMove.to], lastMove.to)
                end
            end)
        else
            animateMove(function()
                handleMoveLandingFeedback(snapshot)
            end)
        end
    end
end

local function spawnChair(rendered, chairConfig)
    local offset = chairConfig.offset
    local chairPos = GetOffsetFromEntityInWorldCoords(rendered.table, offset.x, offset.y, offset.z)
    local foundGround, groundZ = GetGroundZFor_3dCoord(chairPos.x, chairPos.y, chairPos.z + 5.0, false)

    if foundGround then
        chairPos = vector3(chairPos.x, chairPos.y, groundZ)
    end

    local chair = createObject(Config.Props.chair, {
        x = chairPos.x,
        y = chairPos.y,
        z = chairPos.z
    })

    if not chair then
        return
    end

    SetEntityHeading(chair, GetEntityHeading(rendered.table) + chairConfig.headingOffset)
    PlaceObjectOnGroundProperly(chair)
    SetEntityCollision(chair, true, true)
    FreezeEntityPosition(chair, true)

    rendered.chairs[#rendered.chairs + 1] = chair
end

local function cleanupTable(tableId)
    local rendered = renderedTables[tableId]

    if not rendered then
        return
    end

    unregisterTableTargets(rendered)

    if clearSeatAvatars then
        clearSeatAvatars(rendered)
    end

    local squares = {}

    for square in pairs(rendered.pieces) do
        squares[#squares + 1] = square
    end

    for _, square in ipairs(squares) do
        deletePiece(rendered, square)
    end

    for _, side in ipairs({ 'white', 'black' }) do
        for _, entry in ipairs(rendered.captured[side]) do
            deleteEntity(entry.entity)
        end
    end

    for _, chair in ipairs(rendered.chairs) do
        deleteEntity(chair)
    end

    deleteEntity(rendered.botPed)
    deleteEntity(rendered.board)
    deleteEntity(rendered.table)
    renderedTables[tableId] = nil
end

local function renderTable(tableData)
    if renderedTables[tableData.id] then
        local rendered = renderedTables[tableData.id]

        if not rendered.table
            or not DoesEntityExist(rendered.table)
            or not rendered.board
            or not DoesEntityExist(rendered.board)
        then
            cleanupTable(tableData.id)
        else
            rendered.snapshot = tableData
            reconcilePieces(rendered, tableData.board)
            reconcileCaptured(rendered, tableData.capturedWhite, tableData.capturedBlack)
            reconcileSeatAvatars(rendered, tableData)
            registerTableTargets(tableData.id, rendered)

            if currentMatch and currentMatch.tableId == tableData.id then
                ensureSeatForMatch(currentMatch)
                ensureBotPedForMatch(currentMatch)
            end

            return
        end
    end

    local coords = toVector3(tableData.coords)
    local tableObject = createObject(Config.Props.table, {
        x = coords.x,
        y = coords.y,
        z = coords.z
    })

    if not tableObject then
        return
    end

    SetEntityHeading(tableObject, tableData.heading or 0.0)
    PlaceObjectOnGroundProperly(tableObject)
    FreezeEntityPosition(tableObject, true)

    local boardOffset = Config.TableBoardOffset
    local boardObject = createObject(Config.Props.board, {
        x = coords.x,
        y = coords.y,
        z = coords.z + boardOffset.z
    })

    if not boardObject then
        deleteEntity(tableObject)
        return
    end

    SetEntityCollision(boardObject, false, false)
    SetEntityVisible(boardObject, true, false)
    AttachEntityToEntity(
        boardObject,
        tableObject,
        0,
        boardOffset.x,
        boardOffset.y,
        boardOffset.z,
        0.0,
        0.0,
        0.0,
        false,
        false,
        false,
        false,
        2,
        true
    )

    renderedTables[tableData.id] = {
        table = tableObject,
        board = boardObject,
        chairs = {},
        pieces = {},
        pieceCodes = {},
        captured = {
            white = {},
            black = {}
        },
        capturedWhiteCodes = {},
        capturedBlackCodes = {},
        botPed = nil,
        seatAvatars = {},
        lastMoveKey = nil,
        snapshot = tableData,
        targetSystem = nil
    }

    registerTableTargets(tableData.id, renderedTables[tableData.id])

    for _, chairConfig in ipairs(Config.Chairs) do
        spawnChair(renderedTables[tableData.id], chairConfig)
    end

    reconcilePieces(renderedTables[tableData.id], tableData.board)
    reconcileCaptured(renderedTables[tableData.id], tableData.capturedWhite, tableData.capturedBlack)
    reconcileSeatAvatars(renderedTables[tableData.id], tableData)

    if currentMatch and currentMatch.tableId == tableData.id then
        ensureSeatForMatch(currentMatch)
        ensureBotPedForMatch(currentMatch)
    end
end

local function rotationToDirection(rotation)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local num = math.abs(math.cos(x))

    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function vectorLength(value)
    return math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
end

local function normalize(value)
    local length = vectorLength(value)

    if length <= 0.0001 then
        return value
    end

    return vector3(value.x / length, value.y / length, value.z / length)
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a, b)
    return vector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

local function addVector(a, b)
    return vector3(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function subtractVector(a, b)
    return vector3(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function scaleVector(value, scale)
    return vector3(value.x * scale, value.y * scale, value.z * scale)
end

local function cleanupTablePlacementPreview()
    for _, chair in ipairs(tablePlacement.chairs) do
        deleteEntity(chair)
    end

    tablePlacement.chairs = {}
    deleteEntity(tablePlacement.board)
    deleteEntity(tablePlacement.table)
    tablePlacement.table = nil
    tablePlacement.board = nil
    tablePlacement.coords = nil
    tablePlacement.requestId = nil
end

local function setPlacementPreviewEntity(entity, freeze)
    if not entity or not DoesEntityExist(entity) then
        return
    end

    SetEntityCollision(entity, false, false)
    SetEntityAlpha(entity, (Config.TablePlacement and Config.TablePlacement.previewAlpha) or 165, false)

    if freeze ~= false then
        FreezeEntityPosition(entity, true)
    end
end

local function createTablePlacementPreview()
    if tablePlacement.table and DoesEntityExist(tablePlacement.table) then
        return true
    end

    cleanupTablePlacementPreview()

    local coords = GetEntityCoords(PlayerPedId())
    local tableObject = createObject(Config.Props.table, {
        x = coords.x,
        y = coords.y,
        z = coords.z
    })

    if not tableObject then
        return false
    end

    tablePlacement.table = tableObject
    setPlacementPreviewEntity(tablePlacement.table)

    local boardOffset = Config.TableBoardOffset
    local boardObject = createObject(Config.Props.board, {
        x = coords.x,
        y = coords.y,
        z = coords.z + boardOffset.z
    })

    if not boardObject then
        cleanupTablePlacementPreview()
        return false
    end

    tablePlacement.board = boardObject
    setPlacementPreviewEntity(tablePlacement.board, false)
    AttachEntityToEntity(
        tablePlacement.board,
        tablePlacement.table,
        0,
        boardOffset.x,
        boardOffset.y,
        boardOffset.z,
        0.0,
        0.0,
        0.0,
        false,
        false,
        false,
        false,
        2,
        true
    )

    for _, chairConfig in ipairs(Config.Chairs or {}) do
        local chair = createObject(Config.Props.chair, {
            x = coords.x,
            y = coords.y,
            z = coords.z
        })

        if chair then
            setPlacementPreviewEntity(chair, false)
            AttachEntityToEntity(
                chair,
                tablePlacement.table,
                0,
                chairConfig.offset.x,
                chairConfig.offset.y,
                chairConfig.offset.z,
                0.0,
                0.0,
                chairConfig.headingOffset or 0.0,
                false,
                false,
                false,
                false,
                2,
                true
            )
            tablePlacement.chairs[#tablePlacement.chairs + 1] = chair
        end
    end

    return true
end

local function groundCoordsForPlacement(coords)
    if not coords then
        return nil
    end

    local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)

    if foundGround then
        return vector3(coords.x, coords.y, groundZ)
    end

    return vector3(coords.x, coords.y, coords.z)
end

local function placementCoordsFromCamera()
    local placement = Config.TablePlacement or {}
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local direction = normalize(rotationToDirection(camRot))
    local distance = placement.rayDistance or 8.0
    local destination = addVector(camCoords, scaleVector(direction, distance))
    local ray = StartShapeTestRay(
        camCoords.x,
        camCoords.y,
        camCoords.z,
        destination.x,
        destination.y,
        destination.z,
        -1,
        PlayerPedId(),
        7
    )
    local _, hit, hitCoords = GetShapeTestResult(ray)

    if hit == true or hit == 1 then
        return groundCoordsForPlacement(hitCoords)
    end

    local fallback = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, placement.fallbackDistance or 2.0, 0.0)

    return groundCoordsForPlacement(fallback)
end

local function updateTablePlacementPreview(coords, heading)
    if not coords or not createTablePlacementPreview() then
        return false
    end

    SetEntityCoordsNoOffset(tablePlacement.table, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(tablePlacement.table, heading)
    PlaceObjectOnGroundProperly(tablePlacement.table)
    FreezeEntityPosition(tablePlacement.table, true)

    tablePlacement.coords = coords
    return true
end

local function placementControlJustPressed(control)
    return IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control)
end

local function confirmTablePlacement()
    if not tablePlacement.coords then
        notify('No valid chess table placement found.')
        return
    end

    local coords = {
        x = tablePlacement.coords.x,
        y = tablePlacement.coords.y,
        z = tablePlacement.coords.z
    }
    local heading = tablePlacement.heading
    local requestId = tablePlacement.requestId or ('%d:%d'):format(GetPlayerServerId(PlayerId()), GetGameTimer())

    tablePlacement.active = false
    cleanupTablePlacementPreview()
    TriggerServerEvent('cr-chess:server:createTable', coords, heading, requestId)
end

local function cancelTablePlacement()
    tablePlacement.active = false
    cleanupTablePlacementPreview()
    notify('Chess table placement cancelled.')
end

local function startTablePlacement()
    if tablePlacement.active then
        notify('Chess table placement is already active.')
        return
    end

    tablePlacement.active = true
    tablePlacement.heading = GetEntityHeading(PlayerPedId())
    tablePlacement.requestId = ('%d:%d'):format(GetPlayerServerId(PlayerId()), GetGameTimer())
    notify('Place chess table: mouse wheel rotates, E/left click confirms, right click/backspace cancels.')

    CreateThread(function()
        while tablePlacement.active do
            Wait(0)

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)

            local placement = Config.TablePlacement or {}
            local rotateAmount = IsControlPressed(0, 21) and (placement.rotateFastStep or 15.0) or (placement.rotateStep or 5.0)

            if placementControlJustPressed(241) then
                tablePlacement.heading = (tablePlacement.heading + rotateAmount) % 360.0
            elseif placementControlJustPressed(242) then
                tablePlacement.heading = (tablePlacement.heading - rotateAmount) % 360.0
            end

            local coords = placementCoordsFromCamera()

            if coords then
                updateTablePlacementPreview(coords, tablePlacement.heading)
                DrawMarker(25, coords.x, coords.y, coords.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.85, 0.85, 0.02, 90, 210, 120, 120, false, false, 2, false, nil, nil, false)
            end

            drawText2d(0.018, 0.71, 'Chess table placement', 0.34)
            drawText2d(0.018, 0.742, 'Mouse wheel: rotate | Shift: faster', 0.29)
            drawText2d(0.018, 0.769, 'E / left click: place | Right click / Backspace: cancel', 0.29)

            if placementControlJustPressed(38) or placementControlJustPressed(24) then
                confirmTablePlacement()
            elseif placementControlJustPressed(25) or placementControlJustPressed(177) then
                cancelTablePlacement()
            end
        end

        cleanupTablePlacementPreview()
    end)
end

local function getActiveRenderedTable()
    if currentMatch and currentMatch.tableId then
        return renderedTables[currentMatch.tableId], currentMatch.tableId
    end

    local pedCoords = GetEntityCoords(PlayerPedId())
    local closest = nil
    local closestId = nil
    local closestDistance = 4.0

    for tableId, rendered in pairs(renderedTables) do
        local tableCoords = GetEntityCoords(rendered.table)
        local dx = pedCoords.x - tableCoords.x
        local dy = pedCoords.y - tableCoords.y
        local dz = pedCoords.z - tableCoords.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        if dist < closestDistance then
            closest = rendered
            closestId = tableId
            closestDistance = dist
        end
    end

    return closest, closestId
end

local function localPerspective()
    return localColorForSnapshot(currentMatch) or seated.color or 'white'
end

local function cameraConfigForColor(color)
    local cameras = Config.Camera or {}
    local camera = cameras[color or 'white'] or cameras.white or cameras.black

    if camera then
        return camera
    end

    return {
        offset = cameras.offset or { x = 0.0, y = -0.62, z = 0.52 },
        lookAt = cameras.lookAt or { x = 0.0, y = 0.04, z = 0.045 },
        fov = cameras.fov or 45.0
    }
end

local function stopTableCamera()
    if tableCamera then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(tableCamera, false)
        tableCamera = nil
    end
end

local function startTableCamera(rendered)
    if not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        return
    end

    stopTableCamera()

    local cameraConfig = cameraConfigForColor(localPerspective())
    local camCoords = GetOffsetFromEntityInWorldCoords(
        rendered.board,
        cameraConfig.offset.x,
        cameraConfig.offset.y,
        cameraConfig.offset.z
    )
    local lookAt = GetOffsetFromEntityInWorldCoords(
        rendered.board,
        cameraConfig.lookAt.x,
        cameraConfig.lookAt.y,
        cameraConfig.lookAt.z
    )

    tableCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(tableCamera, camCoords.x, camCoords.y, camCoords.z)
    PointCamAtCoord(tableCamera, lookAt.x, lookAt.y, lookAt.z)
    SetCamFov(tableCamera, cameraConfig.fov or 50.0)
    SetCamActive(tableCamera, true)
    RenderScriptCams(true, true, 350, true, true)
end

local function sendSnapshotToNui(snapshot)
    sendNui('snapshot', {
        snapshot = snapshot,
        perspective = localColorForSnapshot(snapshot) or seated.color or 'white'
    })
end

local function configuredTargetSystem()
    if Config.Target and Config.Target.enabled == false then
        return nil
    end

    local preferred = Config.Target and Config.Target.system or 'auto'

    if preferred == 'ox' or preferred == 'auto' then
        if GetResourceState('ox_target') == 'started' then
            return 'ox'
        end
    end

    if preferred == 'qb' or preferred == 'auto' then
        if GetResourceState('qb-target') == 'started' then
            return 'qb'
        end
    end

    return nil
end

registerTableTargets = function(tableId, rendered)
    if not rendered or not rendered.table or rendered.targetSystem then
        return
    end

    local system = configuredTargetSystem()

    if not system then
        return
    end

    local distance = (Config.Target and Config.Target.distance) or 2.2

    if system == 'ox' then
        rendered.targetNames = {
            'cr_chess_sit_white',
            'cr_chess_sit_black',
            'cr_chess_menu'
        }

        exports.ox_target:addLocalEntity(rendered.table, {
            {
                name = rendered.targetNames[1],
                label = 'Sit as White',
                icon = 'fa-solid fa-chess-pawn',
                distance = distance,
                onSelect = function()
                    TriggerServerEvent('cr-chess:server:sitAtTable', tableId, 'white')
                end
            },
            {
                name = rendered.targetNames[2],
                label = 'Sit as Black',
                icon = 'fa-solid fa-chess-pawn',
                distance = distance,
                onSelect = function()
                    TriggerServerEvent('cr-chess:server:sitAtTable', tableId, 'black')
                end
            },
            {
                name = rendered.targetNames[3],
                label = 'Chess Menu',
                icon = 'fa-solid fa-chess-board',
                distance = distance,
                onSelect = function()
                    openTableMenu(tableId, seated.tableId == tableId and seated.color or nil)
                end
            }
        })
    elseif system == 'qb' then
        exports['qb-target']:AddTargetEntity(rendered.table, {
            options = {
                {
                    label = 'Sit as White',
                    icon = 'fas fa-chess-pawn',
                    action = function()
                        TriggerServerEvent('cr-chess:server:sitAtTable', tableId, 'white')
                    end
                },
                {
                    label = 'Sit as Black',
                    icon = 'fas fa-chess-pawn',
                    action = function()
                        TriggerServerEvent('cr-chess:server:sitAtTable', tableId, 'black')
                    end
                },
                {
                    label = 'Chess Menu',
                    icon = 'fas fa-chess-board',
                    action = function()
                        openTableMenu(tableId, seated.tableId == tableId and seated.color or nil)
                    end
                }
            },
            distance = distance
        })
    end

    rendered.targetSystem = system
end

unregisterTableTargets = function(rendered)
    if not rendered or not rendered.targetSystem or not rendered.table then
        return
    end

    if rendered.targetSystem == 'ox' and GetResourceState('ox_target') == 'started' then
        exports.ox_target:removeLocalEntity(rendered.table, rendered.targetNames or {
            'cr_chess_sit_white',
            'cr_chess_sit_black',
            'cr_chess_menu'
        })
    elseif rendered.targetSystem == 'qb' and GetResourceState('qb-target') == 'started' then
        exports['qb-target']:RemoveTargetEntity(rendered.table)
    end

    rendered.targetSystem = nil
    rendered.targetNames = nil
end

local function useSeatAvatarForPlayer()
    return Config.Animations and Config.Animations.useSeatAvatarForPlayer == true
end

local function showLocalSeatAvatar()
    return Config.Animations and Config.Animations.showLocalSeatAvatar == true
end

local function deleteSeatAvatar()
    if seated.avatar then
        deleteEntity(seated.avatar)
        seated.avatar = nil
    end
end

local function restoreLocalPlayerAfterSeat()
    if not seated.hiddenPlayer then
        return
    end

    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 255, false)

    if type(ResetEntityAlpha) == 'function' then
        ResetEntityAlpha(ped)
    end

    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetPedCanRagdoll(ped, true)
    seated.hiddenPlayer = false
end

local function hideLocalPlayerForSeat(rendered, color)
    local ped = PlayerPedId()

    ClearPedTasksImmediately(ped)
    applySeatTransform(ped, rendered, color, true)
    SetPedCanRagdoll(ped, false)
    SetEntityCollision(ped, false, false)
    SetEntityAlpha(ped, 0, false)
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    seated.hiddenPlayer = true
end

local function localSeatPed()
    if seated.avatar and DoesEntityExist(seated.avatar) then
        return seated.avatar
    end

    return PlayerPedId()
end

local function createSeatAvatar(rendered, color)
    deleteSeatAvatar()

    local sourcePed = PlayerPedId()
    local avatar = nil

    if type(ClonePed) == 'function' then
        avatar = ClonePed(sourcePed, false, false, true)
    end

    if not avatar or not DoesEntityExist(avatar) then
        local hash = GetEntityModel(sourcePed)
        RequestModel(hash)

        local expiresAt = GetGameTimer() + 5000

        while not HasModelLoaded(hash) do
            Wait(0)

            if GetGameTimer() > expiresAt then
                print('[cr-chess seat] failed to load player model for seat avatar')
                return nil
            end
        end

        local coords = GetEntityCoords(sourcePed)
        avatar = CreatePed(4, hash, coords.x, coords.y, coords.z, GetEntityHeading(sourcePed), false, true)
        SetModelAsNoLongerNeeded(hash)
    end

    if not avatar or not DoesEntityExist(avatar) then
        return nil
    end

    SetEntityAsMissionEntity(avatar, true, true)
    SetEntityInvincible(avatar, true)
    SetPedCanRagdoll(avatar, false)
    SetBlockingOfNonTemporaryEvents(avatar, true)
    SetEntityCollision(avatar, false, false)
    SetEntityVisible(avatar, showLocalSeatAvatar(), false)
    SetEntityAlpha(avatar, showLocalSeatAvatar() and 255 or 0, false)
    applySeatTransform(avatar, rendered, color, true)

    seated.avatar = avatar
    return avatar
end

local function releaseSeat()
    if not seated.active and not seated.avatar and not seated.hiddenPlayer then
        return
    end

    deleteSeatAvatar()
    restoreLocalPlayerAfterSeat()

    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    SetPedCanRagdoll(ped, true)
    seated.active = false
    seated.color = nil
    seated.tableId = nil
end

local function shouldFreezeSeatedPed(ped)
    if seated.avatar and ped == seated.avatar then
        return true
    end

    if ped and ped == PlayerPedId() then
        return not Config.Animations or Config.Animations.freezePlayerSeat ~= false
    end

    return true
end

local function lockSeatAnimation(ped, duration)
    if not ped or not DoesEntityExist(ped) then
        return
    end

    seatAnimLocks[ped] = GetGameTimer() + math.max(0, duration or 0)
end

local function clearSeatAnimationLock(ped)
    if ped then
        seatAnimLocks[ped] = nil
    end
end

local function isSeatAnimationLocked(ped)
    local untilTime = ped and seatAnimLocks[ped] or nil

    if not untilTime then
        return false
    end

    if GetGameTimer() > untilTime then
        seatAnimLocks[ped] = nil
        return false
    end

    return true
end

applySeatTransform = function(ped, rendered, color, freeze)
    if not ped or not rendered or not rendered.table or not DoesEntityExist(rendered.table) then
        return false
    end

    local seat = Config.PlayerSeats[color]

    if not seat then
        return false
    end

    seat.rotation = seat.rotation or { x = 0.0, y = 0.0, z = seat.headingOffset or 0.0 }

    local pos = GetOffsetFromEntityInWorldCoords(rendered.table, seat.offset.x, seat.offset.y, seat.offset.z)
    local tableHeading = GetEntityHeading(rendered.table)
    local rotX = seat.rotation.x or 0.0
    local rotY = seat.rotation.y or 0.0
    local rotZ = tableHeading + (seat.rotation.z or seat.headingOffset or 0.0)

    SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(ped, rotZ)
    SetEntityRotation(ped, rotX, rotY, rotZ, 2, true)

    if freeze ~= nil then
        FreezeEntityPosition(ped, freeze == true)
    end

    return true
end

local function seatTransform(rendered, color)
    if not rendered or not rendered.table or not DoesEntityExist(rendered.table) then
        return nil
    end

    local seat = Config.PlayerSeats[color]

    if not seat then
        return nil
    end

    seat.rotation = seat.rotation or { x = 0.0, y = 0.0, z = seat.headingOffset or 0.0 }

    local pos = GetOffsetFromEntityInWorldCoords(rendered.table, seat.offset.x, seat.offset.y, seat.offset.z)
    local tableHeading = GetEntityHeading(rendered.table)

    return {
        pos = pos,
        rotX = seat.rotation.x or 0.0,
        rotY = seat.rotation.y or 0.0,
        rotZ = tableHeading + (seat.rotation.z or seat.headingOffset or 0.0)
    }
end

local function restoreSeatAfterAnimation(ped, rendered, color, freeze)
    if not ped or not rendered or not color then
        return
    end

    local delays = (Config.Animations and Config.Animations.seatRestoreDelays) or { 175, 500, 1000 }

    CreateThread(function()
        for _, delay in ipairs(delays) do
            Wait(delay)

            if ped and DoesEntityExist(ped) and rendered and rendered.table and DoesEntityExist(rendered.table) then
                if not isSeatAnimationLocked(ped) then
                    applySeatTransform(ped, rendered, color, nil)
                end
            end
        end
    end)
end

local function seatAnimationConfig()
    local animations = Config.Animations or {}
    local seat = animations.seat or {}

    if not seat.dict and not animations.dict then
        return nil
    end

    if not seat.name and not animations.waiting then
        return nil
    end

    return {
        dict = seat.dict or animations.dict,
        name = seat.name or animations.waiting,
        flag = seat.flag or animations.flag or 1,
        blendIn = seat.blendIn or 8.0,
        blendOut = seat.blendOut or -8.0
    }
end

local function moveAnimationConfig()
    local animations = Config.Animations or {}
    local move = animations.move or {}

    if not move.dict and not animations.dict then
        return nil
    end

    if not move.name and not animations.playing then
        return nil
    end

    return {
        dict = move.dict or animations.dict,
        name = move.name or animations.playing,
        flag = move.flag or 0,
        duration = move.duration or animations.playingDuration or 1500
    }
end

local function playSeatAnimation(ped, rendered, color, freeze, advanced)
    local seatAnim = seatAnimationConfig()

    if seatAnim and loadAnimDict(seatAnim.dict) then
        clearSeatAnimationLock(ped)
        FreezeEntityPosition(ped, false)

        local transform = seatTransform(rendered, color)

        if transform and advanced ~= false then
            TaskPlayAnimAdvanced(
                ped,
                seatAnim.dict,
                seatAnim.name,
                transform.pos.x,
                transform.pos.y,
                transform.pos.z,
                transform.rotX,
                transform.rotY,
                transform.rotZ,
                seatAnim.blendIn,
                seatAnim.blendOut,
                -1,
                seatAnim.flag,
                0.0,
                false,
                false
            )
        else
            TaskPlayAnim(
                ped,
                seatAnim.dict,
                seatAnim.name,
                seatAnim.blendIn,
                seatAnim.blendOut,
                -1,
                seatAnim.flag,
                0.0,
                false,
                false,
                false
            )
        end

        restoreSeatAfterAnimation(ped, rendered, color, freeze)

        if freeze == true then
            CreateThread(function()
                Wait(450)

                if ped and DoesEntityExist(ped) then
                    FreezeEntityPosition(ped, true)
                end
            end)
        end

        return true
    end

    return false
end

local function isSeatAnimationPlaying(ped)
    local seatAnim = seatAnimationConfig()

    return ped
        and DoesEntityExist(ped)
        and seatAnim
        and IsEntityPlayingAnim(ped, seatAnim.dict, seatAnim.name, 3)
end

local function keepSeatAnimation(ped, rendered, color, freeze)
    CreateThread(function()
        for attempt, delay in ipairs({ 350, 900, 1600 }) do
            Wait(delay)

            if ped and DoesEntityExist(ped) then
                local isPlaying = isSeatAnimationPlaying(ped)

                if isSeatAnimationLocked(ped) then
                    if freeze == true then
                        FreezeEntityPosition(ped, true)
                    end
                elseif not isPlaying then
                    FreezeEntityPosition(ped, false)
                    print(('[cr-chess seat] sit animation not playing for %s; retry %d'):format(color or 'unknown', attempt))
                    playSeatAnimation(ped, rendered, color, freeze, attempt == 1)
                elseif rendered and color then
                    applySeatTransform(ped, rendered, color, nil)

                    if freeze == true and attempt >= 2 then
                        FreezeEntityPosition(ped, true)
                    end
                end
            end
        end
    end)
end

local function seatPlayer(rendered, color, tableId)
    if not rendered or not rendered.table or not DoesEntityExist(rendered.table) then
        return
    end

    local seat = Config.PlayerSeats[color]

    if not seat then
        return
    end

    local ped = PlayerPedId()

    ClearPedTasksImmediately(ped)
    SetPedCanRagdoll(ped, false)
    applySeatTransform(ped, rendered, color, false)

    seated.active = true
    seated.color = color
    seated.tableId = tableId

    if useSeatAvatarForPlayer() then
        local avatar = createSeatAvatar(rendered, color)

        if avatar then
            hideLocalPlayerForSeat(rendered, color)
            playSeatAnimation(avatar, rendered, color, true, false)
            keepSeatAnimation(avatar, rendered, color, true)
            print(('[cr-chess seat] using local seat avatar for %s'):format(color))
            return
        end

        print('[cr-chess seat] seat avatar failed; falling back to player ped animation')
    else
        deleteSeatAvatar()
        restoreLocalPlayerAfterSeat()
    end

    local freezePlayer = shouldFreezeSeatedPed(ped)
    playSeatAnimation(ped, rendered, color, freezePlayer, false)
    keepSeatAnimation(ped, rendered, color, freezePlayer)
end

ensureSeatForMatch = function(snapshot)
    if not snapshot or not snapshot.tableId then
        releaseSeat()
        return
    end

    if snapshot.state == 'finished' then
        return
    end

    local myServerId = GetPlayerServerId(PlayerId())
    local color = nil

    if snapshot.white == myServerId then
        color = 'white'
    elseif snapshot.black == myServerId then
        color = 'black'
    end

    if not color then
        releaseSeat()
        return
    end

    if seated.active and seated.color == color and seated.tableId == snapshot.tableId then
        local rendered = renderedTables[snapshot.tableId]
        local ped = localSeatPed()

        if useSeatAvatarForPlayer() and (not seated.avatar or not DoesEntityExist(seated.avatar)) and rendered then
            seatPlayer(rendered, color, snapshot.tableId)
            return
        end

        local freezePlayer = shouldFreezeSeatedPed(ped)
        local isPlaying = isSeatAnimationPlaying(ped)

        if isSeatAnimationLocked(ped) then
            if freezePlayer then
                FreezeEntityPosition(ped, true)
            end
        elseif not isPlaying then
            playSeatAnimation(ped, rendered, color, freezePlayer)
        elseif rendered then
            applySeatTransform(ped, rendered, color, nil)

            if freezePlayer then
                FreezeEntityPosition(ped, true)
            end
        end

        return
    end

    seatPlayer(renderedTables[snapshot.tableId], color, snapshot.tableId)
end

local function wagerConfigPayload()
    local wagers = Config.Wagers or {}
    local amounts = {}

    for _, amount in ipairs(wagers.amounts or {}) do
        amounts[#amounts + 1] = amount
    end

    return {
        enabled = wagers.enabled == true,
        account = wagers.account or 'cash',
        amounts = amounts
    }
end

local function nearbyPlayers()
    local players = {}
    local range = (Config.Invites and Config.Invites.range) or 4.0
    local myPlayer = PlayerId()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= myPlayer then
            local ped = GetPlayerPed(player)

            if ped and DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                local dx = coords.x - myCoords.x
                local dy = coords.y - myCoords.y
                local dz = coords.z - myCoords.z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

                if dist <= range then
                    players[#players + 1] = {
                        source = GetPlayerServerId(player),
                        name = GetPlayerName(player) or ('Player %d'):format(GetPlayerServerId(player)),
                        distance = dist
                    }
                end
            end
        end
    end

    table.sort(players, function(a, b)
        return a.distance < b.distance
    end)

    return players
end

local function enableInteractionForTable(rendered)
    if not rendered then
        return
    end

    interaction.enabled = true
    startTableCamera(rendered)
    setNuiVisible(true)

    if not uvDebug.enabled then
        sendNui('boardOverlay', { visible = false })
    end

    sendSnapshotToNui(currentMatch)
    TriggerServerEvent('cr-chess:server:requestLeaderboard')
end

openTableMenu = function(tableId, color, extra)
    extra = extra or {}
    tableId = tonumber(tableId)

    if not tableId then
        local _, activeTableId = getActiveRenderedTable()
        tableId = activeTableId
    end

    local rendered = tableId and renderedTables[tableId] or nil
    local snapshot = rendered and rendered.snapshot or {}

    tableMenu.visible = true
    tableMenu.tableId = tableId
    tableMenu.color = color or (seated.tableId == tableId and seated.color or nil)
    tableMenu.invite = extra.invite

    setNuiVisible(true)
    sendNui('tableMenu', {
        visible = true,
        tableId = tableId,
        color = tableMenu.color,
        seats = snapshot.seats or {},
        matchId = snapshot.matchId,
        invite = extra.invite,
        invitePlayers = extra.invitePlayers,
        inviteMode = extra.inviteMode,
        wagerAmount = extra.wagerAmount,
        wagers = wagerConfigPayload()
    })
end

seatLocalPedOnTable = function(ped, rendered, color, freeze)
    local seat = Config.PlayerSeats[color]

    if not ped or not rendered or not rendered.table or not seat then
        return
    end

    applySeatTransform(ped, rendered, color, false)
    playSeatAnimation(ped, rendered, color, freeze == true)

    if freeze == true then
        CreateThread(function()
            Wait(450)

            if ped and DoesEntityExist(ped) then
                FreezeEntityPosition(ped, true)
            end
        end)
    end

    keepSeatAnimation(ped, rendered, color, freeze == true)
end

local function useRemoteSeatAvatars()
    return Config.Animations and Config.Animations.useSeatAvatarsForRemotePlayers == true
end

local function restoreRemoteSeatSource(source)
    source = tonumber(source)

    if not source or not hiddenRemoteSeatSources[source] then
        return
    end

    local player = GetPlayerFromServerId(source)

    if player ~= -1 then
        local ped = GetPlayerPed(player)

        if ped and DoesEntityExist(ped) then
            SetEntityVisible(ped, true, false)
            SetEntityAlpha(ped, 255, false)

            if type(ResetEntityAlpha) == 'function' then
                ResetEntityAlpha(ped)
            end

            SetEntityCollision(ped, true, true)
            FreezeEntityPosition(ped, false)
        end
    end

    hiddenRemoteSeatSources[source] = nil
end

local function hideRemoteSeatSource(source)
    source = tonumber(source)

    if not source or source == GetPlayerServerId(PlayerId()) then
        return
    end

    local player = GetPlayerFromServerId(source)

    if player == -1 then
        return
    end

    local ped = GetPlayerPed(player)

    if not ped or not DoesEntityExist(ped) then
        return
    end

    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityAlpha(ped, 0, false)

    if type(SetEntityLocallyInvisible) == 'function' then
        SetEntityLocallyInvisible(ped)
    end

    hiddenRemoteSeatSources[source] = true
end

local function deleteSeatAvatarEntry(rendered, color)
    if not rendered or not rendered.seatAvatars then
        return
    end

    local entry = rendered.seatAvatars[color]

    if not entry then
        return
    end

    restoreRemoteSeatSource(entry.source)
    deleteEntity(entry.ped)
    rendered.seatAvatars[color] = nil
end

clearSeatAvatars = function(rendered)
    if not rendered or not rendered.seatAvatars then
        return
    end

    for _, color in ipairs({ 'white', 'black' }) do
        deleteSeatAvatarEntry(rendered, color)
    end
end

local function createRemoteSeatAvatar(rendered, color, source)
    local player = GetPlayerFromServerId(source)

    if player == -1 then
        return nil
    end

    local sourcePed = GetPlayerPed(player)

    if not sourcePed or not DoesEntityExist(sourcePed) then
        return nil
    end

    local avatar = nil

    if type(ClonePed) == 'function' then
        avatar = ClonePed(sourcePed, false, false, true)
    end

    if not avatar or not DoesEntityExist(avatar) then
        local hash = GetEntityModel(sourcePed)
        RequestModel(hash)

        local expiresAt = GetGameTimer() + 5000

        while not HasModelLoaded(hash) do
            Wait(0)

            if GetGameTimer() > expiresAt then
                print(('[cr-chess seat] failed to load remote seat avatar model for %s'):format(source))
                return nil
            end
        end

        local coords = GetEntityCoords(sourcePed)
        avatar = CreatePed(4, hash, coords.x, coords.y, coords.z, GetEntityHeading(sourcePed), false, true)
        SetModelAsNoLongerNeeded(hash)
    end

    if not avatar or not DoesEntityExist(avatar) then
        return nil
    end

    SetEntityAsMissionEntity(avatar, true, true)
    SetEntityInvincible(avatar, true)
    SetPedCanRagdoll(avatar, false)
    SetBlockingOfNonTemporaryEvents(avatar, true)
    SetEntityCollision(avatar, false, false)
    SetEntityVisible(avatar, true, false)
    SetEntityAlpha(avatar, 255, false)
    seatLocalPedOnTable(avatar, rendered, color, true)

    return avatar
end

local function reconcileSeatAvatar(rendered, tableData, color)
    rendered.seatAvatars = rendered.seatAvatars or {}

    local seat = tableData and tableData.seats and tableData.seats[color] or nil
    local source = seat and tonumber(seat.source) or nil
    local localSource = GetPlayerServerId(PlayerId())
    local entry = rendered.seatAvatars[color]

    if not useRemoteSeatAvatars() or not source or source == localSource then
        deleteSeatAvatarEntry(rendered, color)
        return
    end

    if entry and entry.source ~= source then
        deleteSeatAvatarEntry(rendered, color)
        entry = nil
    end

    if entry and entry.ped and DoesEntityExist(entry.ped) then
        hideRemoteSeatSource(source)

        if not isSeatAnimationLocked(entry.ped) then
            if not isSeatAnimationPlaying(entry.ped) then
                seatLocalPedOnTable(entry.ped, rendered, color, true)
            else
                applySeatTransform(entry.ped, rendered, color, nil)
                FreezeEntityPosition(entry.ped, true)
            end
        end

        return
    end

    local avatar = createRemoteSeatAvatar(rendered, color, source)

    if not avatar then
        return
    end

    hideRemoteSeatSource(source)
    rendered.seatAvatars[color] = {
        source = source,
        ped = avatar
    }

    print(('[cr-chess seat] using remote seat avatar for %s source %s'):format(color, source))
end

reconcileSeatAvatars = function(rendered, tableData)
    if not rendered then
        return
    end

    reconcileSeatAvatar(rendered, tableData or rendered.snapshot or {}, 'white')
    reconcileSeatAvatar(rendered, tableData or rendered.snapshot or {}, 'black')
end

local function maintainSeatAvatarVisibility()
    for source in pairs(hiddenRemoteSeatSources) do
        hideRemoteSeatSource(source)
    end
end

local function restoreAllRemoteSeatSources()
    local sources = {}

    for source in pairs(hiddenRemoteSeatSources) do
        sources[#sources + 1] = source
    end

    for _, source in ipairs(sources) do
        restoreRemoteSeatSource(source)
    end
end

local function seatAvatarForSource(rendered, color, source)
    if not rendered or not rendered.seatAvatars or not source then
        return nil
    end

    local entry = rendered.seatAvatars[color]

    if entry and entry.source == tonumber(source) and entry.ped and DoesEntityExist(entry.ped) then
        return entry.ped
    end

    return nil
end

local function deleteTunePreview()
    if tunePreview.ped then
        deleteEntity(tunePreview.ped)
        tunePreview.ped = nil
        tunePreview.target = nil
    end
end

local function createTunePreview(target)
    deleteTunePreview()

    local sourcePed = PlayerPedId()
    local ped = nil

    if type(ClonePed) == 'function' then
        ped = ClonePed(sourcePed, false, false, true)
    end

    if not ped or not DoesEntityExist(ped) then
        local hash = GetEntityModel(sourcePed)
        RequestModel(hash)

        local expiresAt = GetGameTimer() + 5000

        while not HasModelLoaded(hash) do
            Wait(0)

            if GetGameTimer() > expiresAt then
                return
            end
        end

        local coords = GetEntityCoords(sourcePed)
        ped = CreatePed(4, hash, coords.x, coords.y, coords.z, GetEntityHeading(sourcePed), false, true)
        SetModelAsNoLongerNeeded(hash)
    end

    if not ped or not DoesEntityExist(ped) then
        return
    end

    SetEntityAlpha(ped, 175, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    local seatAnim = seatAnimationConfig()

    if seatAnim and loadAnimDict(seatAnim.dict) then
        TaskPlayAnim(
            ped,
            seatAnim.dict,
            seatAnim.name,
            seatAnim.blendIn,
            seatAnim.blendOut,
            -1,
            seatAnim.flag,
            0.0,
            false,
            false,
            false
        )
    end

    tunePreview.ped = ped
    tunePreview.target = target
end

local function updateTunePreview(rendered)
    if not tuning.enabled or (tuning.target ~= 'seat_white' and tuning.target ~= 'seat_black') then
        deleteTunePreview()
        return
    end

    if not rendered or not rendered.table or not DoesEntityExist(rendered.table) then
        return
    end

    if not tunePreview.ped or not DoesEntityExist(tunePreview.ped) or tunePreview.target ~= tuning.target then
        createTunePreview(tuning.target)
    end

    if not tunePreview.ped or not DoesEntityExist(tunePreview.ped) then
        return
    end

    local color = tuning.target == 'seat_white' and 'white' or 'black'
    local seat = Config.PlayerSeats[color]
    local pos = GetOffsetFromEntityInWorldCoords(rendered.table, seat.offset.x, seat.offset.y, seat.offset.z)

    applySeatTransform(tunePreview.ped, rendered, color, true)
    drawText3d(vector3(pos.x, pos.y, pos.z + 1.05), color .. ' seat preview')
end

local function clearBotPed(rendered)
    if rendered and rendered.botPed then
        deleteEntity(rendered.botPed)
        rendered.botPed = nil
    end
end

ensureBotPedForMatch = function(snapshot)
    if not snapshot or not snapshot.tableId then
        return
    end

    local rendered = renderedTables[snapshot.tableId]

    if not rendered then
        return
    end

    if snapshot.mode ~= 'bot' or snapshot.state == 'finished' then
        clearBotPed(rendered)
        return
    end

    local botColor = snapshot.botColor or 'black'

    if rendered.botPed and DoesEntityExist(rendered.botPed) then
        if isSeatAnimationLocked(rendered.botPed) then
            FreezeEntityPosition(rendered.botPed, true)
        elseif not isSeatAnimationPlaying(rendered.botPed) then
            seatLocalPedOnTable(rendered.botPed, rendered, botColor, true)
        else
            applySeatTransform(rendered.botPed, rendered, botColor, nil)
            FreezeEntityPosition(rendered.botPed, true)
        end

        return
    end

    local model = Config.BotPed and Config.BotPed.model or 'mp_m_freemode_01'
    local hash = loadModel(model)

    if not hash then
        return
    end

    local tableCoords = GetEntityCoords(rendered.table)
    local ped = CreatePed(4, hash, tableCoords.x, tableCoords.y, tableCoords.z, GetEntityHeading(rendered.table), false, true)
    SetModelAsNoLongerNeeded(hash)

    if not ped or not DoesEntityExist(ped) then
        return
    end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityAlpha(ped, Config.BotPed and Config.BotPed.alpha or 255, false)

    rendered.botPed = ped
    seatLocalPedOnTable(ped, rendered, botColor, true)
end

local function oppositeColor(color)
    return color == 'white' and 'black' or 'white'
end

local function sourceForColor(snapshot, color)
    if not snapshot then
        return nil
    end

    if color == 'white' then
        return tonumber(snapshot.white)
    end

    if color == 'black' then
        return tonumber(snapshot.black)
    end

    return nil
end

local function isBotColor(snapshot, color)
    return snapshot and snapshot.mode == 'bot' and color == snapshot.botColor
end

local function pedForReactionColor(rendered, snapshot, color)
    if not rendered or not snapshot or not color then
        return nil, false, false
    end

    if isBotColor(snapshot, color) then
        ensureBotPedForMatch(snapshot)
        return rendered.botPed, true, true
    end

    local source = sourceForColor(snapshot, color)

    if not source or source <= 0 then
        return nil, false, false
    end

    local isLocal = source == GetPlayerServerId(PlayerId())

    if isLocal then
        return localSeatPed(), seated.avatar ~= nil, true
    end

    local avatar = seatAvatarForSource(rendered, color, source)

    if avatar then
        return avatar, true, true
    end

    return nil, false, false
end

local function reactionConfig(kind)
    local reactions = Config.Animations and Config.Animations.reactions

    return reactions and reactions[kind] or nil
end

local function reactionConfigLine(kind, reaction)
    return ("Config.Animations.reactions.%s = { dict = '%s', name = '%s', duration = %d, flag = %d }"):format(
        kind,
        reaction.dict,
        reaction.name,
        reaction.duration or 1200,
        reaction.flag or 48
    )
end

local function reactionSeatConfig()
    local config = Config.Animations and Config.Animations.reactionSeat

    if not config or config.enabled == false then
        return nil
    end

    return config
end

local function playReactionSeatBase(ped, rendered, color, freeze)
    local config = reactionSeatConfig()

    if not config or not config.dict or not config.name or not loadAnimDict(config.dict) then
        return false
    end

    local transform = seatTransform(rendered, color)

    if not transform then
        return false
    end

    applySeatTransform(ped, rendered, color, false)

    local seatAnim = seatAnimationConfig()

    if type(StopAnimTask) == 'function' and seatAnim then
        StopAnimTask(ped, seatAnim.dict, seatAnim.name, 1.0)
    end

    TaskPlayAnimAdvanced(
        ped,
        config.dict,
        config.name,
        transform.pos.x,
        transform.pos.y,
        transform.pos.z,
        transform.rotX,
        transform.rotY,
        transform.rotZ,
        4.0,
        -4.0,
        -1,
        config.flag or 1,
        0.0,
        false,
        false,
        false
    )

    if freeze then
        FreezeEntityPosition(ped, true)
    end

    return true
end

local function anchorReactionSeat(ped, rendered, color, duration, freeze)
    CreateThread(function()
        local endsAt = GetGameTimer() + math.max(0, duration or 0)

        while GetGameTimer() < endsAt do
            if not ped
                or not DoesEntityExist(ped)
                or not rendered
                or not rendered.table
                or not DoesEntityExist(rendered.table)
            then
                return
            end

            if ped == PlayerPedId() and not seated.active then
                return
            end

            applySeatTransform(ped, rendered, color, nil)

            if freeze then
                FreezeEntityPosition(ped, true)
            end

            Wait(0)
        end

        if ped and DoesEntityExist(ped) and rendered and rendered.table and DoesEntityExist(rendered.table) then
            applySeatTransform(ped, rendered, color, nil)

            if freeze then
                FreezeEntityPosition(ped, true)
            end
        end
    end)
end

local function stopReactionSeatBase(ped)
    local config = reactionSeatConfig()

    if not config or not ped or not DoesEntityExist(ped) then
        return
    end

    if type(StopAnimTask) == 'function' then
        StopAnimTask(ped, config.dict, config.name, 1.0)
    end
end

local function stopSeatedReaction(ped, reaction)
    if not ped or not DoesEntityExist(ped) or not reaction then
        return
    end

    if type(StopAnimTask) == 'function' then
        StopAnimTask(ped, reaction.dict, reaction.name, 1.0)
    end

    if type(ClearPedSecondaryTask) == 'function' then
        ClearPedSecondaryTask(ped)
    end
end

local function playSeatedReaction(ped, rendered, color, kind)
    local reaction = reactionConfig(kind)

    if not reaction or not ped or not DoesEntityExist(ped) or not rendered or not rendered.table or not color then
        return false
    end

    if not reaction.dict or not reaction.name or not loadAnimDict(reaction.dict) then
        return false
    end

    local duration = reaction.duration or 1200
    local freezePed = shouldFreezeSeatedPed(ped)
    local nativeSeat = reactionSeatConfig()
    local usedReactionSeat = playReactionSeatBase(ped, rendered, color, freezePed)
    local settleDelay = usedReactionSeat and nativeSeat and nativeSeat.settleDelay or 0
    local restoreDelay = usedReactionSeat and nativeSeat and nativeSeat.restoreDelay or 0
    local totalReactionTime = duration + settleDelay + restoreDelay + 500
    local localReactionPed = ped == PlayerPedId() or ped == seated.avatar

    if not usedReactionSeat and not isSeatAnimationPlaying(ped) then
        playSeatAnimation(ped, rendered, color, freezePed, false)
    end

    lockSeatAnimation(ped, totalReactionTime)
    anchorReactionSeat(ped, rendered, color, totalReactionTime, freezePed)

    if freezePed then
        FreezeEntityPosition(ped, true)
    end

    if settleDelay > 0 then
        Wait(settleDelay)
    end

    TaskPlayAnim(
        ped,
        reaction.dict,
        reaction.name,
        8.0,
        -8.0,
        duration,
        reaction.flag or 48,
        0.0,
        false,
        false,
        false
    )

    if freezePed then
        FreezeEntityPosition(ped, true)
    end

    CreateThread(function()
        Wait(math.max(250, duration))

        if ped and DoesEntityExist(ped) and rendered and rendered.table and DoesEntityExist(rendered.table) then
            stopSeatedReaction(ped, reaction)

            if localReactionPed and not seated.active then
                clearSeatAnimationLock(ped)
                return
            end

            if usedReactionSeat then
                stopReactionSeatBase(ped)
                Wait(math.max(0, restoreDelay))
                clearSeatAnimationLock(ped)
                playSeatAnimation(ped, rendered, color, freezePed, false)
                keepSeatAnimation(ped, rendered, color, freezePed)
            elseif not isSeatAnimationPlaying(ped) then
                clearSeatAnimationLock(ped)
                playSeatAnimation(ped, rendered, color, freezePed, false)
                keepSeatAnimation(ped, rendered, color, freezePed)
            elseif freezePed then
                clearSeatAnimationLock(ped)
                FreezeEntityPosition(ped, true)
            end
        else
            clearSeatAnimationLock(ped)
        end
    end)

    return true
end

local function playReactionForColor(rendered, snapshot, color, kind)
    local ped = pedForReactionColor(rendered, snapshot, color)

    if not ped then
        return false
    end

    return playSeatedReaction(ped, rendered, color, kind)
end

playCaptureReactions = function(snapshot, move, moveColor)
    if not snapshot or not move or not move.capturedPiece or not moveColor then
        return
    end

    local rendered = snapshot.tableId and renderedTables[snapshot.tableId] or nil
    local localColor = localColorForSnapshot(snapshot)

    if not rendered or not localColor then
        return
    end

    local capturedColor = oppositeColor(moveColor)
    local localKind = localColor == moveColor and 'captureByPlayer' or 'capturedByOpponent'

    playReactionForColor(rendered, snapshot, localColor, localKind)

    if isBotColor(snapshot, moveColor) then
        playReactionForColor(rendered, snapshot, moveColor, 'captureByPlayer')
    elseif isBotColor(snapshot, capturedColor) then
        playReactionForColor(rendered, snapshot, capturedColor, 'capturedByOpponent')
    end
end

playResultReaction = function(snapshot, result)
    local rendered = snapshot and snapshot.tableId and renderedTables[snapshot.tableId] or nil
    local localColor = localColorForSnapshot(snapshot)

    if not rendered or not localColor then
        return
    end

    playReactionForColor(rendered, snapshot, localColor, result)

    if snapshot.mode == 'bot' and snapshot.botColor then
        local botResult = result == 'draw' and 'draw' or (result == 'win' and 'lose' or 'win')
        playReactionForColor(rendered, snapshot, snapshot.botColor, botResult)
    end
end

playTestReaction = function(args)
    args = args or {}

    local alias = tostring(args[1] or ''):lower()
    local kind = soundAliases[alias] or alias

    if kind == 'capture' then
        kind = 'captureByPlayer'
    elseif kind == 'captured' then
        kind = 'capturedByOpponent'
    end

    local reaction = reactionConfig(kind)

    if not reaction then
        notify('Use /chess_anim take|taken|win|lose|draw.')
        return
    end

    local rendered = nil
    local color = nil

    if currentMatch then
        rendered = currentMatch.tableId and renderedTables[currentMatch.tableId] or nil
        color = localColorForSnapshot(currentMatch)
    end

    if (not rendered or not color) and seated.active then
        rendered = renderedTables[seated.tableId]
        color = seated.color
    end

    if not rendered or not color then
        notify('Sit at a chess table before testing seated animations.')
        return
    end

    if playSeatedReaction(localSeatPed(), rendered, color, kind) then
        print('[cr-chess anim] ' .. reactionConfigLine(kind, reaction))
        notify(('Played seated animation: %s'):format(kind))
    else
        notify(('Could not play seated animation: %s'):format(kind))
    end
end

local function actorSourceForMove(snapshot, lastMove)
    local actorSource = tonumber(lastMove and lastMove.actorSource)

    if actorSource and actorSource > 0 then
        return actorSource
    end

    if not snapshot or not lastMove then
        return nil
    end

    if lastMove.color == 'white' then
        return tonumber(snapshot.white)
    end

    if lastMove.color == 'black' then
        return tonumber(snapshot.black)
    end

    return nil
end

local function moveWasMadeByBot(snapshot, lastMove)
    if not snapshot or snapshot.mode ~= 'bot' or not lastMove then
        return false
    end

    local actor = tostring(lastMove.actor or '')

    return actor:find('^bot:') ~= nil or lastMove.color == snapshot.botColor
end

playActorMoveAnimation = function(rendered, snapshot, lastMove)
    if not rendered or not snapshot or not lastMove or not Config.Animations then
        return false
    end

    if Config.Animations.playMoveAnimation == false then
        return false
    end

    local ped = nil
    local color = lastMove.color
    local reseatAfter = false
    local freezeAfter = false

    if moveWasMadeByBot(snapshot, lastMove) then
        ensureBotPedForMatch(snapshot)
        ped = rendered.botPed
        color = snapshot.botColor or color
        reseatAfter = true
        freezeAfter = true
    else
        local source = actorSourceForMove(snapshot, lastMove)

        if source and source > 0 then
            local player = GetPlayerFromServerId(source)

            if player ~= -1 then
                reseatAfter = source == GetPlayerServerId(PlayerId())

                if reseatAfter then
                    ped = localSeatPed()
                else
                    ped = GetPlayerPed(player)
                end

                freezeAfter = shouldFreezeSeatedPed(ped)
            end
        end
    end

    local moveAnim = moveAnimationConfig()

    if not ped or not DoesEntityExist(ped) or not moveAnim then
        return false
    end

    if not loadAnimDict(moveAnim.dict) then
        return false
    end

    local duration = moveAnim.duration

    lockSeatAnimation(ped, duration + 250)
    TaskPlayAnim(
        ped,
        moveAnim.dict,
        moveAnim.name,
        8.0,
        -8.0,
        duration,
        moveAnim.flag,
        0.0,
        false,
        false,
        false
    )

    if reseatAfter then
        CreateThread(function()
            Wait(math.max(250, duration - 50))

            if ped and DoesEntityExist(ped) and rendered and rendered.table and DoesEntityExist(rendered.table) then
                seatLocalPedOnTable(ped, rendered, color, freezeAfter)
            end
        end)
    end

    return true
end

local function boardScreenCorners(rendered)
    if not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        return nil
    end

    local config = Config.PieceOffset
    local half = config.step * 0.5
    local minX = config.startX - half
    local minY = config.startY - half
    local maxX = config.startX + config.step * 7 + half
    local maxY = config.startY + config.step * 7 + half
    local z = config.z + 0.012
    local locals = {
        { x = minX, y = minY, z = z },
        { x = maxX, y = minY, z = z },
        { x = maxX, y = maxY, z = z },
        { x = minX, y = maxY, z = z }
    }
    local corners = {}

    for index, offset in ipairs(locals) do
        local world = GetOffsetFromEntityInWorldCoords(rendered.board, offset.x, offset.y, offset.z)
        local visible, screenX, screenY = World3dToScreen2d(world.x, world.y, world.z)

        if not visible then
            return nil
        end

        corners[index] = {
            x = screenX,
            y = screenY
        }
    end

    return corners
end

local function cameraRayFromScreen(screenX, screenY)
    local camCoords = nil
    local camRot = nil
    local fov = nil

    if tableCamera then
        camCoords = GetCamCoord(tableCamera)
        camRot = GetCamRot(tableCamera, 2)
        fov = GetCamFov(tableCamera)
    elseif type(GetFinalRenderedCamCoord) == 'function' then
        camCoords = GetFinalRenderedCamCoord()
        camRot = GetFinalRenderedCamRot(2)
        fov = GetFinalRenderedCamFov()
    else
        camCoords = GetGameplayCamCoord()
        camRot = GetGameplayCamRot(2)
        fov = GetGameplayCamFov()
    end

    if not camCoords or not camRot then
        return nil, nil
    end

    local width, height = GetActiveScreenResolution()
    local aspect = 16.0 / 9.0

    if width and height and height > 0 then
        aspect = width / height
    end

    local forward = normalize(rotationToDirection(camRot))
    local right = normalize(cross(forward, vector3(0.0, 0.0, 1.0)))

    if vectorLength(right) <= 0.0001 then
        right = vector3(1.0, 0.0, 0.0)
    end

    local up = normalize(cross(right, forward))
    local tanVertical = math.tan(math.rad(fov or 60.0) * 0.5)
    local tanHorizontal = tanVertical * aspect
    local ndcX = ((screenX or 0.5) * 2.0 - 1.0)
    local ndcY = (1.0 - (screenY or 0.5) * 2.0)
    local direction = normalize(addVector(
        forward,
        addVector(
            scaleVector(right, ndcX * tanHorizontal),
            scaleVector(up, ndcY * tanVertical)
        )
    ))

    return camCoords, direction
end

local function squareFromCameraRay(rendered, screenX, screenY)
    if not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        return nil
    end

    local rayOrigin, rayDirection = cameraRayFromScreen(screenX, screenY)

    if not rayOrigin or not rayDirection then
        return nil
    end

    local p0 = GetOffsetFromEntityInWorldCoords(rendered.board, 0.0, 0.0, Config.PieceOffset.z or 0.002)
    local px = GetOffsetFromEntityInWorldCoords(rendered.board, 0.1, 0.0, Config.PieceOffset.z or 0.002)
    local py = GetOffsetFromEntityInWorldCoords(rendered.board, 0.0, 0.1, Config.PieceOffset.z or 0.002)
    local normal = normalize(cross(subtractVector(px, p0), subtractVector(py, p0)))
    local denom = dot(rayDirection, normal)

    if math.abs(denom) < 0.00001 then
        return nil
    end

    local t = dot(subtractVector(p0, rayOrigin), normal) / denom

    if t < 0.0 then
        return nil
    end

    local hit = addVector(rayOrigin, scaleVector(rayDirection, t))
    local localPoint = GetOffsetFromEntityGivenWorldCoords(rendered.board, hit.x, hit.y, hit.z)

    return squareFromLocal(localPoint)
end

local function squareFromScreenAffine(rendered, screenX, screenY)
    local corners = boardScreenCorners(rendered)

    if not corners then
        return nil
    end

    local a = corners[1]
    local b = corners[2]
    local d = corners[4]
    local vx = b.x - a.x
    local vy = b.y - a.y
    local wx = d.x - a.x
    local wy = d.y - a.y
    local px = (screenX or 0.5) - a.x
    local py = (screenY or 0.5) - a.y
    local det = vx * wy - vy * wx

    if math.abs(det) < 0.00001 then
        return nil
    end

    local u = (px * wy - py * wx) / det
    local v = (vx * py - vy * px) / det

    if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0 then
        return nil
    end

    local fileIndex = math.min(8, math.max(1, math.floor(u * 8) + 1))
    local rank = math.min(8, math.max(1, math.floor(v * 8) + 1))

    return files[fileIndex] .. tostring(rank)
end

local function squareFromScreen(rendered, screenX, screenY)
    return squareFromCameraRay(rendered, screenX, screenY) or squareFromScreenAffine(rendered, screenX, screenY)
end

local function updateBoardOverlay(rendered)
    local now = GetGameTimer()

    if now - lastBoardOverlayAt < 100 then
        return
    end

    lastBoardOverlayAt = now

    local corners = boardScreenCorners(rendered)

    if not corners then
        sendNui('boardOverlay', { visible = false })
        return
    end

    sendNui('boardOverlay', {
        visible = true,
        corners = corners
    })
end

local function drawSquare(rendered, square, color)
    local offset = squareOffset(square)

    if not offset then
        return
    end

    local half = (Config.PieceOffset.step or 0.06) * 0.44
    local z = offset.z + 0.006
    local p1 = GetOffsetFromEntityInWorldCoords(rendered.board, offset.x - half, offset.y - half, z)
    local p2 = GetOffsetFromEntityInWorldCoords(rendered.board, offset.x + half, offset.y - half, z)
    local p3 = GetOffsetFromEntityInWorldCoords(rendered.board, offset.x + half, offset.y + half, z)
    local p4 = GetOffsetFromEntityInWorldCoords(rendered.board, offset.x - half, offset.y + half, z)

    DrawPoly(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, p3.x, p3.y, p3.z, color.r, color.g, color.b, color.a)
    DrawPoly(p1.x, p1.y, p1.z, p3.x, p3.y, p3.z, p4.x, p4.y, p4.z, color.r, color.g, color.b, color.a)
    DrawPoly(p3.x, p3.y, p3.z, p2.x, p2.y, p2.z, p1.x, p1.y, p1.z, color.r, color.g, color.b, color.a)
    DrawPoly(p4.x, p4.y, p4.z, p3.x, p3.y, p3.z, p1.x, p1.y, p1.z, color.r, color.g, color.b, color.a)
end

local function drawUvDebugGrid(rendered)
    if not uvDebug.enabled or not rendered then
        return
    end

    for rank = 1, 8 do
        for fileIndex = 1, 8 do
            local square = files[fileIndex] .. tostring(rank)
            local light = (fileIndex + rank) % 2 == 0
            local color = light
                and { r = 80, g = 180, b = 255, a = 70 }
                or { r = 255, g = 220, b = 70, a = 60 }
            drawSquare(rendered, square, color)
        end
    end

    drawText2d(0.018, 0.27, 'UV debug: click board, F8 logs resolved square', 0.30)
end

drawText3d = function(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)

    if not onScreen then
        return
    end

    SetTextScale(0.28, 0.28)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

drawText2d = function(x, y, text, scale)
    SetTextScale(scale or 0.32, scale or 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawSelectedPiece(rendered)
    if not interaction.selected then
        return
    end

    local entity = rendered.pieces[interaction.selected]

    if not entity or not DoesEntityExist(entity) then
        return
    end

    if type(SetEntityDrawOutline) == 'function' then
        SetEntityDrawOutline(entity, true)
        SetEntityDrawOutlineColor(90, 180, 255, 255)
    end

    local coords = GetEntityCoords(entity)
    drawText3d(vector3(coords.x, coords.y, coords.z + 0.23), interaction.selectedPiece or interaction.selected)
end

local function drawHighlights(rendered)
    if interaction.selected then
        drawSquare(rendered, interaction.selected, { r = 80, g = 160, b = 255, a = 130 })
    end

    for _, move in ipairs(interaction.legalMoves) do
        if move.capture then
            drawSquare(rendered, move.to, { r = 255, g = 95, b = 70, a = 140 })
        else
            drawSquare(rendered, move.to, { r = 60, g = 255, b = 120, a = 125 })
        end
    end

    drawSelectedPiece(rendered)
end

local function drawBoardLight(rendered)
    local light = Config.BoardLight

    if not light or light.enabled == false or not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        return
    end

    local color = light.color or { r = 255, g = 238, b = 205 }
    local point = light.point or {}

    if point.enabled ~= false and type(DrawLightWithRange) == 'function' then
        local pointOffset = point.offset or light.offset or { x = 0.0, y = 0.0, z = 0.42 }
        local pointPos = GetOffsetFromEntityInWorldCoords(rendered.board, pointOffset.x, pointOffset.y, pointOffset.z)

        DrawLightWithRange(
            pointPos.x,
            pointPos.y,
            pointPos.z,
            color.r or 255,
            color.g or 238,
            color.b or 205,
            point.range or light.range or 1.15,
            point.intensity or light.intensity or 3.2
        )
    end

    local spot = light.spot or light

    if spot.enabled ~= false then
        local offset = spot.offset or light.offset or { x = 0.0, y = 0.0, z = 0.95 }
        local direction = spot.direction or light.direction or { x = 0.0, y = 0.0, z = -1.0 }
        local pos = GetOffsetFromEntityInWorldCoords(rendered.board, offset.x, offset.y, offset.z)

        DrawSpotLight(
            pos.x,
            pos.y,
            pos.z,
            direction.x or 0.0,
            direction.y or 0.0,
            direction.z or -1.0,
            color.r or 255,
            color.g or 238,
            color.b or 205,
            spot.distance or light.distance or 3.2,
            spot.brightness or light.brightness or 2.0,
            spot.hardness or light.hardness or 0.0,
            spot.radius or light.radius or 90.0,
            spot.falloff or light.falloff or 1.0
        )
    end
end

local function isBoardLightInRange(rendered)
    local light = Config.BoardLight

    if not light or light.enabled == false or not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        return false
    end

    local maxDistance = light.drawDistance or 22.0
    local playerCoords = GetEntityCoords(PlayerPedId())
    local boardCoords = GetEntityCoords(rendered.board)
    local dx = playerCoords.x - boardCoords.x
    local dy = playerCoords.y - boardCoords.y
    local dz = playerCoords.z - boardCoords.z

    return (dx * dx + dy * dy + dz * dz) <= (maxDistance * maxDistance)
end

local function hasNearbyBoardLight()
    if not Config.BoardLight or Config.BoardLight.enabled == false then
        return false
    end

    for _, rendered in pairs(renderedTables) do
        if isBoardLightInRange(rendered) then
            return true
        end
    end

    return false
end

local function drawNearbyBoardLights()
    if not Config.BoardLight or Config.BoardLight.enabled == false then
        return
    end

    for _, rendered in pairs(renderedTables) do
        if isBoardLightInRange(rendered) then
            drawBoardLight(rendered)
        end
    end
end

local function clearSelection()
    local rendered = getActiveRenderedTable()

    if rendered and interaction.selected then
        local entity = rendered.pieces[interaction.selected]

        if entity and DoesEntityExist(entity) and type(SetEntityDrawOutline) == 'function' then
            SetEntityDrawOutline(entity, false)
        end
    end

    interaction.selected = nil
    interaction.selectedPiece = nil
    interaction.legalMoves = {}
    interaction.legalByTo = {}
    sendNui('legalMoves', {
        data = {
            from = nil,
            moves = {}
        }
    })
end

local function releaseFinishedMatchControls()
    feedback.resultOpen = false
    interaction.enabled = false
    tableMenu.visible = false
    tableMenu.invite = nil
    clearSelection()
    stopTableCamera()
    releaseSeat()
    sendNui('boardOverlay', { visible = false })
    sendNui('tableMenu', { visible = false })
    SetNuiFocus(false, false)

    if type(SetNuiFocusKeepInput) == 'function' then
        SetNuiFocusKeepInput(false)
    end
end

local function isActiveLocalMatch()
    return currentMatch
        and currentMatch.state == 'active'
        and localColorForSnapshot(currentMatch) ~= nil
end

local function keepActiveMatchUiOpen()
    local rendered = currentMatch and currentMatch.tableId and renderedTables[currentMatch.tableId] or nil

    tableMenu.visible = false
    tableMenu.invite = nil
    sendNui('tableMenu', { visible = false })
    sendNui('matchResult', { visible = false })

    if rendered then
        enableInteractionForTable(rendered)
    else
        interaction.enabled = true
        setNuiVisible(true, true)
    end

    sendSnapshotToNui(currentMatch)
    notify('You are in an active chess match. Use Resign Match or /chess_resign to leave.')
end

local function prepareFinishedMatchResult()
    interaction.enabled = false
    tableMenu.visible = false
    tableMenu.invite = nil
    clearSelection()
    sendNui('boardOverlay', { visible = false })
    sendNui('tableMenu', { visible = false })
end

local function handleSquareClick(square)
    if not square then
        clearSelection()
        return
    end

    if interaction.selected and interaction.legalByTo[square] then
        local move = interaction.legalByTo[square]
        TriggerServerEvent('cr-chess:server:move', interaction.selected, square, move.promotion)
        clearSelection()
        return
    end

    TriggerServerEvent('cr-chess:server:selectSquare', square)
end

local function handleWorldClick(screenX, screenY)
    local rendered = getActiveRenderedTable()
    local square = squareFromScreen(rendered, screenX, screenY)

    if uvDebug.enabled then
        print(('[cr-chess uv] click x=%.4f y=%.4f square=%s'):format(
            screenX or -1.0,
            screenY or -1.0,
            square or 'none'
        ))
        notify(('UV click: %s'):format(square or 'none'))
    end

    if interaction.enabled then
        handleSquareClick(square)
    end
end

RegisterNetEvent('cr-chess:client:toggleInteract', function()
    interaction.enabled = not interaction.enabled

    if not interaction.enabled then
        clearSelection()
        setNuiVisible(false)
        stopTableCamera()
        notify('Chess interaction disabled.')
        return
    end

    local rendered = getActiveRenderedTable()

    if not rendered then
        interaction.enabled = false
        setNuiVisible(true)
        sendSnapshotToNui(currentMatch)
        notify('No chess table is close enough to interact with.')
        return
    end

    startTableCamera(rendered)
    setNuiVisible(true)
    if not uvDebug.enabled then
        sendNui('boardOverlay', { visible = false })
    end
    sendSnapshotToNui(currentMatch)
    TriggerServerEvent('cr-chess:server:requestLeaderboard')
    notify('Chess interaction enabled. Use your mouse to right-click the board or use the NUI board.')
end)

RegisterNetEvent('cr-chess:client:openTableMenu', function()
    local rendered, tableId = getActiveRenderedTable()

    if not rendered or not tableId then
        notify('No chess table is close enough for the menu.')
        return
    end

    openTableMenu(tableId, seated.tableId == tableId and seated.color or nil)
end)

RegisterNetEvent('cr-chess:client:toggleUvDebug', function()
    uvDebug.enabled = not uvDebug.enabled

    if uvDebug.enabled then
        setNuiVisible(true)
        notify('Chess UV debug enabled. The board grid should be visible; clicks print to F8.')
    else
        sendNui('boardOverlay', { visible = false })
        notify('Chess UV debug disabled.')
    end
end)

RegisterNetEvent('cr-chess:client:toggleBoardLight', function()
    Config.BoardLight = Config.BoardLight or {}
    Config.BoardLight.enabled = not Config.BoardLight.enabled
    notify(('Chess board light %s.'):format(Config.BoardLight.enabled and 'enabled' or 'disabled'))
end)

RegisterNetEvent('cr-chess:client:startTablePlacement', function()
    startTablePlacement()
end)

RegisterNetEvent('cr-chess:client:legalMoves', function(response)
    response = response or {}
    clearSelection()

    if response.message then
        notify(response.message)
    end

    if not response.from or not response.moves or #response.moves == 0 then
        return
    end

    interaction.selected = response.from
    interaction.selectedPiece = response.piece and (Config.PieceNames[response.piece] or response.piece) or response.from
    interaction.legalMoves = response.moves
    interaction.legalByTo = {}

    for _, move in ipairs(response.moves) do
        if not interaction.legalByTo[move.to] or move.promotion == 'q' then
            interaction.legalByTo[move.to] = move
        end
    end

    sendNui('legalMoves', { data = response })
end)

local adjustTuning
local cycleTuningTarget
local cycleTuningField

RegisterNUICallback('close', function(_, cb)
    if isActiveLocalMatch() then
        keepActiveMatchUiOpen()
        cb({ ok = true, active = true })
        return
    end

    local shouldReleaseSeat = feedback.resultOpen or (currentMatch and currentMatch.state == 'finished')

    interaction.enabled = false
    tableMenu.visible = false
    tableMenu.invite = nil
    clearSelection()
    sendNui('tableMenu', { visible = false })
    sendNui('matchResult', { visible = false })

    if shouldReleaseSeat then
        releaseFinishedMatchControls()
        currentMatch = nil
    end

    setNuiVisible(false)
    stopTableCamera()
    cb({ ok = true })
end)

RegisterNUICallback('resign', function(_, cb)
    if isActiveLocalMatch() then
        TriggerServerEvent('cr-chess:server:resign')
        cb({ ok = true })
        return
    end

    notify('You are not in an active chess match.')
    cb({ ok = false })
end)

RegisterNUICallback('worldClick', function(data, cb)
    if interaction.enabled or uvDebug.enabled then
        handleWorldClick(tonumber(data.x) or 0.5, tonumber(data.y) or 0.5)
    end

    cb({ ok = true })
end)

RegisterNUICallback('boardSquare', function(data, cb)
    if interaction.enabled and data and data.square then
        handleSquareClick(data.square)
    end

    cb({ ok = true })
end)

RegisterNUICallback('requestLeaderboard', function(_, cb)
    TriggerServerEvent('cr-chess:server:requestLeaderboard')
    cb({ ok = true })
end)

RegisterNUICallback('requestProfile', function(data, cb)
    if data and data.identifier then
        TriggerServerEvent('cr-chess:server:requestProfile', data.identifier)
    end

    cb({ ok = true })
end)

RegisterNUICallback('tableMenuAction', function(data, cb)
    data = data or {}

    local action = tostring(data.action or '')
    local tableId = tonumber(data.tableId) or tableMenu.tableId or seated.tableId
    local color = tostring(data.color or tableMenu.color or seated.color or ''):lower()
    local mode = tostring(data.mode or ''):lower()
    local wagerAmount = tonumber(data.wagerAmount) or 0

    if action == 'close' then
        tableMenu.visible = false
        tableMenu.invite = nil
        sendNui('tableMenu', { visible = false })
    elseif action == 'sit' then
        TriggerServerEvent('cr-chess:server:sitAtTable', tableId, color)
    elseif action == 'stand' then
        tableMenu.visible = false
        tableMenu.invite = nil
        sendNui('tableMenu', { visible = false })
        TriggerServerEvent('cr-chess:server:standFromTable')
    elseif action == 'resign' then
        sendNui('tableMenu', { visible = false })
        TriggerServerEvent('cr-chess:server:resign')
    elseif action == 'bot' then
        sendNui('tableMenu', { visible = false })
        TriggerServerEvent('cr-chess:server:startSeatedBot', tableId, color, data.difficulty or 'easy')
    elseif action == 'wait' then
        TriggerServerEvent('cr-chess:server:startSeatedWait', tableId, color, mode, wagerAmount)
    elseif action == 'invitePicker' then
        openTableMenu(tableId, color, {
            invitePlayers = nearbyPlayers(),
            inviteMode = mode,
            wagerAmount = wagerAmount
        })
    elseif action == 'invite' then
        local targetSource = tonumber(data.targetSource)
        TriggerServerEvent('cr-chess:server:inviteSeatedMatch', tableId, color, mode, targetSource, wagerAmount)
    elseif action == 'acceptInvite' then
        sendNui('tableMenu', { visible = false })
        TriggerServerEvent('cr-chess:server:acceptInvite', data.matchId)
    elseif action == 'declineInvite' then
        tableMenu.invite = nil
        sendNui('tableMenu', { visible = false })
    elseif action == 'interact' then
        local rendered = tableId and renderedTables[tableId] or getActiveRenderedTable()
        enableInteractionForTable(rendered)
        sendNui('tableMenu', { visible = false })
    end

    cb({ ok = true })
end)

RegisterNUICallback('tuneWheel', function(data, cb)
    if tuning.enabled then
        adjustTuning((tonumber(data.direction) or 1) >= 0 and 1 or -1)
    end

    cb({ ok = true })
end)

RegisterNUICallback('tuneCycleTarget', function(_, cb)
    if tuning.enabled then
        cycleTuningTarget()
    end

    cb({ ok = true })
end)

RegisterNUICallback('tuneCycleField', function(_, cb)
    if tuning.enabled then
        cycleTuningField()
    end

    cb({ ok = true })
end)

RegisterNetEvent('cr-chess:client:leaderboardData', function(players)
    sendNui('leaderboard', { players = players or {} })
end)

RegisterNetEvent('cr-chess:client:profileData', function(profile)
    sendNui('profile', { profile = profile })
end)

local function tuningField()
    local fields = tuningFields[tuning.target]

    if not fields then
        return nil
    end

    if tuning.fieldIndex > #fields then
        tuning.fieldIndex = 1
    end

    return fields[tuning.fieldIndex]
end

local function seatConfigForTarget()
    if tuning.target == 'seat_white' then
        return Config.PlayerSeats.white
    end

    if tuning.target == 'seat_black' then
        return Config.PlayerSeats.black
    end

    return nil
end

local function cameraConfigForTarget()
    if tuning.target == 'camera_white' then
        return cameraConfigForColor('white'), 'white'
    end

    if tuning.target == 'camera_black' then
        return cameraConfigForColor('black'), 'black'
    end

    return nil, nil
end

local function tuningValue()
    local field = tuningField()
    local seat = seatConfigForTarget()
    local camera = cameraConfigForTarget()

    if seat then
        seat.rotation = seat.rotation or { x = 0.0, y = 0.0, z = seat.headingOffset or 0.0 }

        if field == 'x' or field == 'y' or field == 'z' then
            return seat.offset[field]
        end

        if field == 'rotX' then return seat.rotation.x end
        if field == 'rotY' then return seat.rotation.y end
        if field == 'rotZ' then return seat.rotation.z end
    end

    if camera then
        if field == 'x' or field == 'y' or field == 'z' then
            return camera.offset[field]
        end

        if field == 'lookX' then
            return camera.lookAt.x
        end

        if field == 'lookY' then
            return camera.lookAt.y
        end

        if field == 'lookZ' then
            return camera.lookAt.z
        end

        if field == 'fov' then return camera.fov end
    end

    return 0
end

local function setTuningValue(value)
    local field = tuningField()
    local seat = seatConfigForTarget()
    local camera = cameraConfigForTarget()

    if seat then
        seat.rotation = seat.rotation or { x = 0.0, y = 0.0, z = seat.headingOffset or 0.0 }

        if field == 'x' or field == 'y' or field == 'z' then
            seat.offset[field] = value
        elseif field == 'rotX' then
            seat.rotation.x = value
        elseif field == 'rotY' then
            seat.rotation.y = value
        elseif field == 'rotZ' then
            seat.rotation.z = value
            seat.headingOffset = value
        end
    elseif camera then
        if field == 'x' or field == 'y' or field == 'z' then
            camera.offset[field] = value
        elseif field == 'lookX' then
            camera.lookAt.x = value
        elseif field == 'lookY' then
            camera.lookAt.y = value
        elseif field == 'lookZ' then
            camera.lookAt.z = value
        elseif field == 'fov' then
            camera.fov = math.max(20.0, math.min(90.0, value))
        end
    end
end

local function applyTuning()
    if currentMatch and currentMatch.tableId then
        local rendered = renderedTables[currentMatch.tableId]

        ensureSeatForMatch(currentMatch)
        updateTunePreview(rendered)

        if interaction.enabled and rendered then
            startTableCamera(rendered)
        end
    end
end

local function formatTuningLine()
    if tuning.target == 'seat_white' or tuning.target == 'seat_black' then
        local color = tuning.target == 'seat_white' and 'white' or 'black'
        local seat = Config.PlayerSeats[color]
        seat.rotation = seat.rotation or { x = 0.0, y = 0.0, z = seat.headingOffset or 0.0 }

        return ('Config.PlayerSeats.%s = { offset = { x = %.3f, y = %.3f, z = %.3f }, headingOffset = %.1f, rotation = { x = %.1f, y = %.1f, z = %.1f } }'):format(
            color,
            seat.offset.x,
            seat.offset.y,
            seat.offset.z,
            seat.rotation.z or seat.headingOffset or 0.0,
            seat.rotation.x or 0.0,
            seat.rotation.y or 0.0,
            seat.rotation.z or seat.headingOffset or 0.0
        )
    end

    local camera, color = cameraConfigForTarget()

    if camera and color then
        return ('Config.Camera.%s = { offset = { x = %.3f, y = %.3f, z = %.3f }, lookAt = { x = %.3f, y = %.3f, z = %.3f }, fov = %.1f }'):format(
            color,
            camera.offset.x,
            camera.offset.y,
            camera.offset.z,
            camera.lookAt.x,
            camera.lookAt.y,
            camera.lookAt.z,
            camera.fov
        )
    end

    local fallback = cameraConfigForColor('white')

    return ('Config.Camera.white = { offset = { x = %.3f, y = %.3f, z = %.3f }, lookAt = { x = %.3f, y = %.3f, z = %.3f }, fov = %.1f }'):format(
        fallback.offset.x,
        fallback.offset.y,
        fallback.offset.z,
        fallback.lookAt.x,
        fallback.lookAt.y,
        fallback.lookAt.z,
        fallback.fov
    )
end

local function printSeatConfig(color)
    local seat = Config.PlayerSeats[color]

    if not seat then
        return
    end

    seat.rotation = seat.rotation or { x = 0.0, y = 0.0, z = seat.headingOffset or 0.0 }

    local line = ('Config.PlayerSeats.%s = { offset = { x = %.3f, y = %.3f, z = %.3f }, headingOffset = %.1f, rotation = { x = %.1f, y = %.1f, z = %.1f } }'):format(
        color,
        seat.offset.x,
        seat.offset.y,
        seat.offset.z,
        seat.rotation.z or seat.headingOffset or 0.0,
        seat.rotation.x or 0.0,
        seat.rotation.y or 0.0,
        seat.rotation.z or seat.headingOffset or 0.0
    )

    print('[cr-chess tuning] ' .. line)
    notify(line)
end

local function announceTuning()
    local line = formatTuningLine()

    print('[cr-chess tuning] ' .. line)
    notify(('Tuning %s / %s = %.3f\n%s'):format(
        tuning.target,
        tuningField() or '?',
        tuningValue() or 0,
        line
    ))
end

cycleTuningTarget = function()
    for index, target in ipairs(tuning.targets) do
        if target == tuning.target then
            tuning.target = tuning.targets[index % #tuning.targets + 1]
            tuning.fieldIndex = 1
            announceTuning()
            return
        end
    end

    tuning.target = tuning.targets[1]
    tuning.fieldIndex = 1
    announceTuning()
end

cycleTuningField = function()
    local fields = tuningFields[tuning.target]

    if not fields then
        return
    end

    tuning.fieldIndex = tuning.fieldIndex % #fields + 1
    announceTuning()
end

adjustTuning = function(direction)
    local field = tuningField()

    if not field then
        return
    end

    local large = IsControlPressed(0, 21)
    local amount = (field == 'rotX' or field == 'rotY' or field == 'rotZ' or field == 'fov')
        and (large and Config.Tuning.rotateLarge or Config.Tuning.rotateSmall)
        or (large and Config.Tuning.nudgeLarge or Config.Tuning.nudgeSmall)

    setTuningValue((tuningValue() or 0) + direction * amount)
    applyTuning()
    announceTuning()
end

local function drawTuningHelp()
    if not tuning.enabled then
        return
    end

    local field = tuningField() or '?'
    local value = tuningValue() or 0
    local x = 0.018
    local y = 0.34

    DrawRect(0.18, 0.43, 0.32, 0.19, 0, 0, 0, 155)
    drawText2d(x, y, 'Chess tuning', 0.36)
    drawText2d(x, y + 0.032, ('Target: %s'):format(tuning.target), 0.30)
    drawText2d(x, y + 0.058, ('Field: %s = %.3f'):format(field, value), 0.30)
    drawText2d(x, y + 0.088, 'Mouse wheel: adjust | Shift: faster', 0.28)
    drawText2d(x, y + 0.114, 'E: field | Q: target | Backspace: exit', 0.28)
    drawText2d(x, y + 0.140, 'Copy-paste config line is printed in F8.', 0.28)
end

local function drawTuningMarker(rendered)
    if not tuning.enabled or not rendered then
        return
    end

    local offset = nil

    if tuning.target == 'seat_white' then
        updateTunePreview(rendered)
        return
    elseif tuning.target == 'seat_black' then
        updateTunePreview(rendered)
        return
    elseif tuning.target == 'camera_white' or tuning.target == 'camera_black' then
        deleteTunePreview()
        local camera = cameraConfigForTarget()

        if camera then
            offset = camera.offset

            local look = GetOffsetFromEntityInWorldCoords(rendered.board, camera.lookAt.x, camera.lookAt.y, camera.lookAt.z + 0.03)
            DrawMarker(28, look.x, look.y, look.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.04, 0.04, 0.04, 80, 200, 255, 150, false, false, 2, false, nil, nil, false)
            drawText3d(vector3(look.x, look.y, look.z + 0.08), tuning.target .. ' lookAt')
        end
    end

    if offset then
        local marker = GetOffsetFromEntityInWorldCoords(rendered.board, offset.x, offset.y, offset.z + 0.03)
        DrawMarker(28, marker.x, marker.y, marker.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.05, 0.05, 255, 220, 70, 150, false, false, 2, false, nil, nil, false)
        drawText3d(vector3(marker.x, marker.y, marker.z + 0.08), tuning.target .. ' / ' .. (tuningField() or '?'))
    end
end

RegisterNetEvent('cr-chess:client:toggleTune', function()
    tuning.enabled = not tuning.enabled

    if tuning.enabled then
        announceTuning()
    else
        deleteTunePreview()
        notify('Chess tuning disabled.')
    end
end)

RegisterNetEvent('cr-chess:client:setTuneTarget', function(target)
    target = tostring(target or ''):lower()

    if target == 'camera' then
        target = localPerspective() == 'black' and 'camera_black' or 'camera_white'
    end

    if not tuningFields[target] then
        notify('Tuning target must be seat_white, seat_black, camera_white, or camera_black.')
        return
    end

    tuning.target = target
    tuning.fieldIndex = 1
    tuning.enabled = true
    announceTuning()
end)

RegisterNetEvent('cr-chess:client:gizmoSeat', function(color)
    color = tostring(color or ''):lower()

    if color ~= 'white' and color ~= 'black' then
        notify('Use /chess_gizmo_seat white or /chess_gizmo_seat black.')
        return
    end

    if GetResourceState('object_gizmo') ~= 'started' then
        notify('object_gizmo is not started. Install/start it first, or use /chess_tune.')
        return
    end

    local rendered = getActiveRenderedTable()

    if not rendered then
        notify('No chess table is close enough for gizmo tuning.')
        return
    end

    tuning.enabled = true
    tuning.target = color == 'white' and 'seat_white' or 'seat_black'
    tuning.fieldIndex = 1
    updateTunePreview(rendered)

    if not tunePreview.ped or not DoesEntityExist(tunePreview.ped) then
        notify('Could not create seat preview ped for gizmo.')
        return
    end

    notify('object_gizmo started. Move/rotate the preview ped, then press Enter to finish.')
    local result = exports.object_gizmo:useGizmo(tunePreview.ped)

    if not result then
        notify('object_gizmo did not return placement data.')
        return
    end

    local position = result.position or GetEntityCoords(tunePreview.ped)
    local rotation = result.rotation or GetEntityRotation(tunePreview.ped, 2)
    local localPos = GetOffsetFromEntityGivenWorldCoords(rendered.table, position.x, position.y, position.z)
    local tableHeading = GetEntityHeading(rendered.table)
    local relativeRotZ = (rotation.z or GetEntityHeading(tunePreview.ped)) - tableHeading
    local seat = Config.PlayerSeats[color]

    seat.offset = {
        x = localPos.x,
        y = localPos.y,
        z = localPos.z
    }
    seat.rotation = {
        x = rotation.x or 0.0,
        y = rotation.y or 0.0,
        z = relativeRotZ
    }
    seat.headingOffset = relativeRotZ

    applyTuning()
    printSeatConfig(color)
end)

RegisterNetEvent('cr-chess:client:seatedAtTable', function(tableId, color, tableSnapshot)
    if tableSnapshot then
        renderTable(tableSnapshot)
    end

    local rendered = renderedTables[tableId]

    if rendered then
        seatPlayer(rendered, color, tableId)
        startTableCamera(rendered)
    end

    openTableMenu(tableId, color)
end)

RegisterNetEvent('cr-chess:client:matchInvite', function(invite)
    invite = invite or {}
    notify(('%s invited you to a %s chess match.'):format(invite.fromName or 'Someone', invite.mode or 'casual'))
    openTableMenu(invite.tableId, invite.color, {
        invite = invite
    })
end)

RegisterNetEvent('cr-chess:client:forceSeat', function()
    if currentMatch then
        ensureSeatForMatch(currentMatch)
        return
    end

    if seated.active and seated.tableId and seated.color then
        seatPlayer(renderedTables[seated.tableId], seated.color, seated.tableId)
        return
    end

    notify('You are not seated at a chess table.')
end)

RegisterNetEvent('cr-chess:client:forceStand', function()
    interaction.enabled = false
    tableMenu.visible = false
    tableMenu.invite = nil
    clearSelection()
    stopTableCamera()
    releaseSeat()
    setNuiVisible(false)
    sendNui('tableMenu', { visible = false })
    sendNui('boardOverlay', { visible = false })
end)

RegisterNetEvent('cr-chess:client:syncTables', function(tables)
    local seen = {}

    for _, tableData in ipairs(tables or {}) do
        seen[tableData.id] = true
        renderTable(tableData)
    end

    for tableId in pairs(renderedTables) do
        if not seen[tableId] then
            cleanupTable(tableId)
        end
    end
end)

RegisterNetEvent('cr-chess:client:updateTable', function(tableData)
    if tableData then
        renderTable(tableData)
    end
end)

RegisterNetEvent('cr-chess:client:removeTable', function(tableId)
    cleanupTable(tableId)
end)

RegisterNetEvent('cr-chess:client:updateMatch', function(snapshot)
    if not snapshot or not snapshot.tableId then
        return
    end

    local rendered = renderedTables[snapshot.tableId]

    if rendered then
        applyLastMove(rendered, snapshot)
        reconcilePieces(rendered, snapshot.board)
        reconcileCaptured(rendered, snapshot.capturedWhite, snapshot.capturedBlack)
    end

    local myServerId = GetPlayerServerId(PlayerId())

    if snapshot.white == myServerId or snapshot.black == myServerId then
        currentMatch = snapshot
        ensureSeatForMatch(snapshot)
        ensureBotPedForMatch(snapshot)
        clearSelection()

        if snapshot.state == 'active' then
            feedback.resultOpen = false
            tableMenu.visible = false
            sendNui('tableMenu', { visible = false })

            if rendered and not interaction.enabled then
                enableInteractionForTable(rendered)
            end
        elseif snapshot.state == 'finished' then
            prepareFinishedMatchResult()
            showMatchResultFeedback(snapshot)
        end
    elseif currentMatch and currentMatch.id == snapshot.id and snapshot.state == 'finished' then
        currentMatch = snapshot
        ensureSeatForMatch(snapshot)
        ensureBotPedForMatch(snapshot)
        clearSelection()
        prepareFinishedMatchResult()
        showMatchResultFeedback(snapshot)
    end

    sendSnapshotToNui(currentMatch)
end)

CreateThread(function()
    while true do
        local shouldDrawLight = Config.BoardLight and Config.BoardLight.enabled ~= false and next(renderedTables) ~= nil
        local hasLightNearby = shouldDrawLight and hasNearbyBoardLight()
        local hasHiddenRemoteSeats = next(hiddenRemoteSeatSources) ~= nil

        if interaction.enabled or tuning.enabled or uvDebug.enabled or seated.active or hasLightNearby or hasHiddenRemoteSeats then
            local rendered = getActiveRenderedTable()
            Wait(0)

            maintainSeatAvatarVisibility()

            if interaction.enabled then
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
            end

            if seated.active then
                if seated.avatar and DoesEntityExist(seated.avatar) and not showLocalSeatAvatar() then
                    SetEntityVisible(seated.avatar, false, false)
                    SetEntityAlpha(seated.avatar, 0, false)

                    if type(SetEntityLocallyInvisible) == 'function' then
                        SetEntityLocallyInvisible(seated.avatar)
                    end
                end

                if seated.hiddenPlayer then
                    local ped = PlayerPedId()
                    SetEntityVisible(ped, false, false)
                    SetEntityCollision(ped, false, false)
                    FreezeEntityPosition(ped, true)

                    if type(SetEntityLocallyInvisible) == 'function' then
                        SetEntityLocallyInvisible(ped)
                    end
                end

                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
                DisableControlAction(0, 36, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
            end

            if shouldDrawLight then
                drawNearbyBoardLights()
            end

            if rendered and interaction.enabled then
                drawHighlights(rendered)
            end

            if rendered and uvDebug.enabled then
                drawUvDebugGrid(rendered)
                updateBoardOverlay(rendered)
            end

            if rendered and tuning.enabled then
                drawTuningMarker(rendered)
            end

            if tuning.enabled then
                drawTuningHelp()

                if IsControlJustPressed(0, 44) then
                    cycleTuningTarget()
                elseif IsControlJustPressed(0, 38) then
                    cycleTuningField()
                elseif IsControlJustPressed(0, 241) then
                    adjustTuning(1)
                elseif IsControlJustPressed(0, 242) then
                    adjustTuning(-1)
                elseif IsControlJustPressed(0, 177) then
                    tuning.enabled = false
                    deleteTunePreview()
                    notify('Chess tuning disabled.')
                end
            end
        else
            Wait(200)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)

        if useRemoteSeatAvatars() then
            for _, rendered in pairs(renderedTables) do
                reconcileSeatAvatars(rendered, rendered.snapshot or {})
            end
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'ox_target' or resourceName == 'qb-target' then
        for tableId, rendered in pairs(renderedTables) do
            registerTableTargets(tableId, rendered)
        end

        return
    end

    if resourceName ~= GetCurrentResourceName() then
        return
    end

    setNuiVisible(false)
    Wait(500)
    TriggerServerEvent('cr-chess:server:requestSync')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    setNuiVisible(false)
    stopTableCamera()
    releaseSeat()
    deleteTunePreview()
    cleanupTablePlacementPreview()
    restoreAllRemoteSeatSources()

    for tableId in pairs(renderedTables) do
        cleanupTable(tableId)
    end
end)
