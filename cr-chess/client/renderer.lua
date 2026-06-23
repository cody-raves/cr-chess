local renderedTables = {}
local tableBlips = {}
local currentMatch = nil
local tableCamera = nil
local ensureSeatForMatch
local ensureBotPedForMatch
local clearBotPed
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
local updateTableBlip
local removeTableBlip
local openTableMenu
local sendSnapshotToNui
local crChessDestroyAmbientDui
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
    cameraMode = 'normal',
    selected = nil,
    selectedPiece = nil,
    legalMoves = {},
    legalByTo = {}
}

local lastMoveHover = {
    visible = false,
    move = nil,
    outlinedEntity = nil
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
        'camera_black',
        'captured_white',
        'captured_black'
    }
}

local tunePreview = {
    ped = nil,
    target = nil,
    captured = {},
    capturedTarget = nil
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

local spectator = {
    active = false,
    matchId = nil,
    tableId = nil,
    camera = nil,
    yaw = 180.0,
    radius = nil,
    height = nil,
    focus = nil,
    camCoords = nil,
    lastUpdate = 0,
    followEntity = nil,
    followUntil = 0,
    focusSquare = nil,
    focusUntil = 0,
    snapshot = nil,
    cameraMode = 'orbit',
    moveFocus = true,
    dui = {
        dui = nil,
        txd = nil,
        txn = nil,
        txdName = 'cr_chess_spectator_dui',
        txnName = 'overlay',
        lastKey = nil,
        lastAmbientSyncAt = 0,
        lastAttractSeenAt = {},
        ambient = {}
    }
}

local observedMatches = {}

local files = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' }

local tuningFields = {
    seat_white = { 'x', 'y', 'z', 'rotX', 'rotY', 'rotZ' },
    seat_black = { 'x', 'y', 'z', 'rotX', 'rotY', 'rotZ' },
    camera_white = { 'x', 'y', 'z', 'lookX', 'lookY', 'lookZ', 'fov' },
    camera_black = { 'x', 'y', 'z', 'lookX', 'lookY', 'lookZ', 'fov' },
    captured_white = { 'x', 'y', 'z', 'rotX', 'rotY', 'rotZ' },
    captured_black = { 'x', 'y', 'z', 'rotX', 'rotY', 'rotZ' }
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

function soundDistanceVolume(rendered)
    local sounds = Config.Sounds or {}
    local baseVolume = tonumber(sounds.volume) or 0.55

    if sounds.enabled == false then
        return 0.0
    end

    if sounds.distanceEnabled == false then
        return baseVolume
    end

    if not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        return baseVolume
    end

    local maxDistance = tonumber(sounds.drawDistance)
        or tonumber(Config.SpectatorDui and Config.SpectatorDui.drawDistance)
        or 8.0

    if maxDistance <= 0.0 then
        return baseVolume
    end

    local fadeStart = tonumber(sounds.fadeStartDistance) or (maxDistance * 0.65)
    fadeStart = math.max(0.0, math.min(fadeStart, maxDistance - 0.01))

    local playerCoords = GetEntityCoords(PlayerPedId())
    local boardCoords = GetEntityCoords(rendered.board)
    local dx = playerCoords.x - boardCoords.x
    local dy = playerCoords.y - boardCoords.y
    local dz = playerCoords.z - boardCoords.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    if distance > maxDistance then
        return 0.0
    end

    if distance <= fadeStart then
        return baseVolume
    end

    local t = (distance - fadeStart) / (maxDistance - fadeStart)

    return baseVolume * (1.0 - math.max(0.0, math.min(1.0, t)))
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

local function playMoveSound(volume)
    if not Config.Sounds or not Config.Sounds.enabled then
        return
    end

    if volume ~= nil and volume <= 0.0 then
        return
    end

    local sounds = Config.Sounds.move or {}

    if #sounds == 0 then
        return
    end

    playNuiSoundFile(sounds[math.random(#sounds)], volume)
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

local function playFeedbackSound(kind, volume)
    if volume ~= nil and volume <= 0.0 then
        return
    end

    local sounds = feedbackSoundList(kind)

    if sounds and #sounds > 0 then
        playNuiSoundFile(sounds[math.random(#sounds)], volume)
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

function isAudioFile(value)
    value = tostring(value or ''):lower()
    return value:match('%.ogg$')
end

function normalizeSoundFile(value)
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

function crChessMoveColorFromSnapshot(snapshot, move)
    move = move or (snapshot and snapshot.lastMove or nil)

    if not snapshot or not move then
        return nil
    end

    if move.color then
        return move.color
    end

    if snapshot.moveHistory then
        local latest = snapshot.moveHistory[#snapshot.moveHistory]

        if latest
            and latest.from == move.from
            and latest.to == move.to
            and latest.capturedPiece == move.capturedPiece
        then
            return latest.color
        end
    end

    return nil
end

local function showMoveFeedback(snapshot, soundVolume)
    local move = snapshot and snapshot.lastMove or nil

    if not move or not move.capturedPiece then
        return
    end

    local localColor = localColorForSnapshot(snapshot)

    if not localColor then
        return
    end

    local moveColor = crChessMoveColorFromSnapshot(snapshot, move)

    local playerCaptured = moveColor == localColor
    local kind = playerCaptured and 'capture' or 'captured'
    local nativeKind = playerCaptured and 'captureByPlayer' or 'capturedByOpponent'
    local capturedName = pieceName(move.capturedPiece)
    local title = playerCaptured and 'Piece Taken' or 'Piece Lost'
    local message = playerCaptured
        and ('You captured %s on %s.'):format(capturedName, move.captureSquare or move.to)
        or ('You lost %s on %s.'):format(capturedName, move.captureSquare or move.to)

    playFeedbackSound(nativeKind, soundVolume)
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

local function finishReasonText(reason)
    if reason == 'timeout' then
        return 'on time'
    end

    return reason
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

    local reason = finishReasonText(snapshot.finishReason or (result == 'draw' and 'draw' or 'win'))
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

local function handleMoveLandingFeedback(snapshot, rendered)
    local soundVolume = soundDistanceVolume(rendered)

    playMoveSound(soundVolume)

    if playCaptureReactions then
        local move = snapshot and snapshot.lastMove or nil
        playCaptureReactions(snapshot, move, crChessMoveColorFromSnapshot(snapshot, move))
    end

    showMoveFeedback(snapshot, soundVolume)
end

local function toVector3(coords)
    return vector3(coords.x, coords.y, coords.z)
end

local function tableBlipsEnabled()
    local blips = Config.TableBlips or {}

    return blips.enabled ~= false
end

local function tableBlipData(tableData)
    if not tableBlipsEnabled() or not tableData or not tableData.coords then
        return nil
    end

    local defaults = Config.TableBlips or {}
    local blip = tableData.blip or {}

    if blip.enabled == false then
        return nil
    end

    return {
        label = tostring(blip.label or defaults.label or 'Chess Table'),
        sprite = tonumber(blip.sprite or defaults.sprite) or 280,
        color = tonumber(blip.color or defaults.color) or 25,
        scale = tonumber(blip.scale or defaults.scale) or 0.72,
        shortRange = blip.shortRange ~= false
    }
end

removeTableBlip = function(tableId)
    tableId = tonumber(tableId)

    if not tableId then
        return
    end

    local blip = tableBlips[tableId]

    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end

    tableBlips[tableId] = nil
end

updateTableBlip = function(tableData)
    if not tableData or not tableData.id then
        return
    end

    local data = tableBlipData(tableData)

    if not data then
        removeTableBlip(tableData.id)
        return
    end

    local coords = toVector3(tableData.coords)
    local blip = tableBlips[tableData.id]

    if not blip or not DoesBlipExist(blip) then
        blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        tableBlips[tableData.id] = blip
    else
        SetBlipCoords(blip, coords.x, coords.y, coords.z)
    end

    SetBlipSprite(blip, data.sprite)
    SetBlipDisplay(blip, 4)
    SetBlipColour(blip, data.color)
    SetBlipScale(blip, data.scale)
    SetBlipAsShortRange(blip, data.shortRange)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(data.label)
    EndTextCommandSetBlipName(blip)
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
        SetEntityAsMissionEntity(entity, true, true)
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

function crChessPurgeDuplicateTableObjects(rendered)
    if not rendered
        or rendered.destroyed
        or type(GetGamePool) ~= 'function'
        or not rendered.table
        or not DoesEntityExist(rendered.table)
        or not rendered.board
        or not DoesEntityExist(rendered.board)
    then
        return
    end

    local keep = {
        [rendered.table] = true,
        [rendered.board] = true
    }

    for _, chair in ipairs(rendered.chairs or {}) do
        keep[chair] = true
    end

    for _, piece in pairs(rendered.pieces or {}) do
        keep[piece] = true
    end

    for _, side in ipairs({ 'white', 'black' }) do
        for _, entry in ipairs(rendered.captured[side] or {}) do
            if entry.entity then
                keep[entry.entity] = true
            end
        end
    end

    for _, entity in ipairs(tunePreview.captured or {}) do
        if entity then
            keep[entity] = true
        end
    end

    local tableHash = joaat(Config.Props.table)
    local boardHash = joaat(Config.Props.board)
    local chairHash = joaat(Config.Props.chair)
    local pieceHashes = {}
    local chairPositions = {}

    for _, model in pairs(Config.Props.pieces or {}) do
        pieceHashes[joaat(model)] = true
    end

    for _, chair in ipairs(rendered.chairs or {}) do
        if chair and DoesEntityExist(chair) then
            chairPositions[#chairPositions + 1] = GetEntityCoords(chair)
        end
    end

    local tableCoords = GetEntityCoords(rendered.table)
    local boardCoords = GetEntityCoords(rendered.board)

    for _, entity in ipairs(GetGamePool('CObject')) do
        if entity
            and DoesEntityExist(entity)
            and not keep[entity]
        then
            local hash = GetEntityModel(entity)
            local coords = GetEntityCoords(entity)
            local dx = coords.x - tableCoords.x
            local dy = coords.y - tableCoords.y
            local dz = coords.z - tableCoords.z
            local tableDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
            local bx = coords.x - boardCoords.x
            local by = coords.y - boardCoords.y
            local bz = coords.z - boardCoords.z
            local boardDistance = math.sqrt(bx * bx + by * by + bz * bz)
            local duplicateChair = false

            if hash == chairHash then
                for _, chairCoords in ipairs(chairPositions) do
                    local cx = coords.x - chairCoords.x
                    local cy = coords.y - chairCoords.y
                    local cz = coords.z - chairCoords.z

                    if math.sqrt(cx * cx + cy * cy + cz * cz) < 0.18 then
                        duplicateChair = true
                        break
                    end
                end
            end

            if (hash == tableHash and tableDistance < 0.18)
                or (hash == boardHash and boardDistance < 0.18)
                or duplicateChair
                or (pieceHashes[hash] and boardDistance < 0.62)
            then
                deleteEntity(entity)
            end
        end
    end
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
        offset.rotX or 0.0,
        offset.rotY or 0.0,
        offset.rotZ or offset.heading or 0.0,
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
    rendered.pieceSpawns = rendered.pieceSpawns or {}

    if rendered.pieceSpawns[square] then
        rendered.pieceSpawns[square].cancelled = true
        rendered.pieceSpawns[square] = nil
    end

    local entity = rendered.pieces[square]

    if entity then
        deleteEntity(entity)
        rendered.pieces[square] = nil
        rendered.pieceCodes[square] = nil
    end
end

local function spawnPiece(rendered, pieceCode, square, boardSyncVersion)
    local model = Config.Props.pieces[pieceCode]

    if not model
        or not rendered.board
        or rendered.destroyed
        or (boardSyncVersion and rendered.boardSyncVersion ~= boardSyncVersion)
    then
        return nil
    end

    rendered.pieceSpawns = rendered.pieceSpawns or {}

    local pending = rendered.pieceSpawns[square]

    if pending
        and not pending.cancelled
        and pending.code == pieceCode
    then
        pending.boardSyncVersion = boardSyncVersion
        return nil
    end

    if pending then
        pending.cancelled = true
    end

    local token = {
        code = pieceCode,
        boardSyncVersion = boardSyncVersion,
        cancelled = false
    }

    rendered.pieceSpawns[square] = token

    local coords = GetEntityCoords(rendered.board)
    local piece = createObject(model, {
        x = coords.x,
        y = coords.y,
        z = coords.z + 0.5
    })

    if not piece then
        if rendered.pieceSpawns[square] == token then
            rendered.pieceSpawns[square] = nil
        end

        return nil
    end

    if rendered.destroyed
        or token.cancelled
        or rendered.pieceSpawns[square] ~= token
        or (token.boardSyncVersion and rendered.boardSyncVersion ~= token.boardSyncVersion)
        or not rendered.board
        or not DoesEntityExist(rendered.board)
    then
        deleteEntity(piece)
        return nil
    end

    local existing = rendered.pieces[square]

    if existing and DoesEntityExist(existing) then
        rendered.pieceSpawns[square] = nil
        deleteEntity(piece)
        return existing
    end

    SetEntityCollision(piece, false, false)
    SetEntityVisible(piece, true, false)
    attachPieceToSquare(piece, rendered.board, square)

    rendered.pieces[square] = piece
    rendered.pieceCodes[square] = pieceCode
    rendered.pieceSpawns[square] = nil

    return piece
end

local function moveRenderedPiece(rendered, from, to, pieceCode)
    local entity = rendered.pieces[from]

    if not entity then
        return false
    end

    rendered.pieceSpawns = rendered.pieceSpawns or {}

    if rendered.pieceSpawns[from] then
        rendered.pieceSpawns[from].cancelled = true
        rendered.pieceSpawns[from] = nil
    end

    if rendered.pieceSpawns[to] then
        rendered.pieceSpawns[to].cancelled = true
        rendered.pieceSpawns[to] = nil
    end

    rendered.pieces[from] = nil
    rendered.pieceCodes[from] = nil
    rendered.pieces[to] = entity
    rendered.pieceCodes[to] = pieceCode
    animateEntityToOffset(rendered, entity, squareOffset(to), 650, 0.16)

    return true
end

function crChessPieceColorSide(pieceCode)
    if not pieceCode then
        return nil
    end

    return pieceCode:sub(1, 1) == 'w' and 'white' or 'black'
end

function crChessCapturedConfig(side)
    local config = Config.CapturedPieces and Config.CapturedPieces[side] or nil

    if config then
        return config
    end

    local step = Config.PieceOffset and Config.PieceOffset.step or 0.06

    return {
        offset = { x = side == 'white' and -0.21 or 0.21, y = side == 'white' and -0.33 or 0.33, z = 0.01 },
        headingOffset = side == 'white' and 0.0 or 180.0,
        rotation = { x = 0.0, y = 0.0, z = 0.0 },
        rowSize = 8,
        columnStep = { x = side == 'white' and step or -step, y = 0.0, z = 0.0 },
        rowStep = { x = 0.0, y = side == 'white' and -step or step, z = 0.0 }
    }
end

function crChessRotateLocalVector(vector, rotation)
    rotation = rotation or {}

    local x = vector.x or 0.0
    local y = vector.y or 0.0
    local z = vector.z or 0.0
    local rx = math.rad(rotation.x or 0.0)
    local ry = math.rad(rotation.y or 0.0)
    local rz = math.rad(rotation.z or 0.0)

    local cosX = math.cos(rx)
    local sinX = math.sin(rx)
    local y1 = y * cosX - z * sinX
    local z1 = y * sinX + z * cosX

    y = y1
    z = z1

    local cosY = math.cos(ry)
    local sinY = math.sin(ry)
    local x1 = x * cosY + z * sinY
    local z2 = -x * sinY + z * cosY

    x = x1
    z = z2

    local cosZ = math.cos(rz)
    local sinZ = math.sin(rz)
    local x2 = x * cosZ - y * sinZ
    local y2 = x * sinZ + y * cosZ

    return {
        x = x2,
        y = y2,
        z = z
    }
end

function crChessCapturedOffset(side, index)
    local config = crChessCapturedConfig(side)
    local origin = config.offset or { x = 0.0, y = 0.0, z = Config.PieceOffset and Config.PieceOffset.z or 0.002 }
    local columnStep = config.columnStep or { x = Config.PieceOffset.step or 0.06, y = 0.0, z = 0.0 }
    local rowStep = config.rowStep or { x = 0.0, y = Config.PieceOffset.step or 0.06, z = 0.0 }
    local rotation = config.rotation or { x = 0.0, y = 0.0, z = 0.0 }
    local rowSize = math.max(1, tonumber(config.rowSize) or 8)
    local zeroIndex = math.max(0, (tonumber(index) or 1) - 1)
    local column = zeroIndex % rowSize
    local row = math.floor(zeroIndex / rowSize)
    local localOffset = crChessRotateLocalVector({
        x = (columnStep.x or 0.0) * column + (rowStep.x or 0.0) * row,
        y = (columnStep.y or 0.0) * column + (rowStep.y or 0.0) * row,
        z = (columnStep.z or 0.0) * column + (rowStep.z or 0.0) * row
    }, rotation)

    return {
        x = (origin.x or 0.0) + localOffset.x,
        y = (origin.y or 0.0) + localOffset.y,
        z = (origin.z or 0.0) + localOffset.z,
        rotX = rotation.x or 0.0,
        rotY = rotation.y or 0.0,
        rotZ = (config.headingOffset or 0.0) + (rotation.z or 0.0)
    }
end

function crChessNormalizeDegrees(value)
    value = tonumber(value) or 0.0
    value = value % 360.0

    if value > 180.0 then
        value = value - 360.0
    end

    return value
end

function crChessVectorAngleDegrees(vector)
    return math.deg(math.atan(vector.y or 0.0, vector.x or 0.0))
end

function crChessSetCapturedDirection(side, direction)
    local config = crChessCapturedConfig(side)
    local rotation = config.rotation or { x = 0.0, y = 0.0, z = 0.0 }
    local columnStep = config.columnStep or { x = Config.PieceOffset.step or 0.06, y = 0.0, z = 0.0 }
    local desired = nil
    local directionText = tostring(direction or ''):lower()

    if directionText == 'east' or directionText == 'e' then
        desired = 0.0
    elseif directionText == 'north' or directionText == 'n' then
        desired = 90.0
    elseif directionText == 'west' or directionText == 'w' then
        desired = 180.0
    elseif directionText == 'south' or directionText == 's' then
        desired = -90.0
    elseif directionText == 'flip' or directionText == 'opposite' then
        desired = (rotation.z or 0.0) + 180.0 + crChessVectorAngleDegrees(columnStep)
    elseif directionText == 'left' or directionText == 'ccw' then
        desired = (rotation.z or 0.0) + 90.0 + crChessVectorAngleDegrees(columnStep)
    elseif directionText == 'right' or directionText == 'cw' then
        desired = (rotation.z or 0.0) - 90.0 + crChessVectorAngleDegrees(columnStep)
    else
        desired = tonumber(direction)
    end

    if not desired then
        return false
    end

    config.rotation = rotation
    config.rotation.z = crChessNormalizeDegrees(desired - crChessVectorAngleDegrees(columnStep))

    return true
end

function crChessSpawnCapturedPiece(rendered, side, pieceCode, index)
    local model = Config.Props.pieces[pieceCode]

    if not model or not rendered or not rendered.board or rendered.destroyed then
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

    if rendered.destroyed or not rendered.board or not DoesEntityExist(rendered.board) then
        deleteEntity(piece)
        return nil
    end

    SetEntityCollision(piece, false, false)
    SetEntityVisible(piece, true, false)
    attachEntityToBoardOffset(piece, rendered.board, crChessCapturedOffset(side, index))

    return piece
end

local function clearCapturedSide(rendered, side)
    local entries = rendered.captured[side]

    for _, entry in ipairs(entries) do
        entry.cancelled = true
        deleteEntity(entry.entity)
    end

    rendered.captured[side] = {}
    rendered.capturedSyncVersions = rendered.capturedSyncVersions or {}
    rendered.capturedSyncVersions[side] = (rendered.capturedSyncVersions[side] or 0) + 1
end

function crChessSyncCapturedSide(rendered, side, codes)
    codes = codes or {}
    rendered.capturedSyncVersions = rendered.capturedSyncVersions or {}
    rendered.capturedSyncVersions[side] = (rendered.capturedSyncVersions[side] or 0) + 1

    local syncVersion = rendered.capturedSyncVersions[side]

    local oldEntries = rendered.captured[side] or {}
    local nextEntries = {}

    for index, pieceCode in ipairs(codes) do
        local entry = oldEntries[index]

        if not entry or entry.code ~= pieceCode or not entry.entity or not DoesEntityExist(entry.entity) then
            if entry then
                entry.cancelled = true
                deleteEntity(entry.entity)
            end

            entry = {
                code = pieceCode,
                entity = nil,
                index = index,
                spawning = true,
                cancelled = false
            }

            oldEntries[index] = entry
            rendered.captured[side] = oldEntries

            local entity = crChessSpawnCapturedPiece(rendered, side, pieceCode, index)

            if rendered.destroyed
                or entry.cancelled
                or rendered.capturedSyncVersions[side] ~= syncVersion
            then
                deleteEntity(entity)
                return
            end

            entry.entity = entity
            entry.spawning = false
        end

        if entry.entity and DoesEntityExist(entry.entity) then
            SetEntityCollision(entry.entity, false, false)
            SetEntityVisible(entry.entity, true, false)

            if entry.movingUntil and GetGameTimer() < entry.movingUntil then
                -- The capture animation is already carrying this prop to its slot.
            elseif entry.index ~= index then
                animateEntityToOffset(rendered, entry.entity, crChessCapturedOffset(side, index), 420, 0.08)
            else
                attachEntityToBoardOffset(entry.entity, rendered.board, crChessCapturedOffset(side, index))
            end
        end

        entry.index = index
        nextEntries[index] = entry
    end

    for index = #codes + 1, #oldEntries do
        local entry = oldEntries[index]

        if entry then
            entry.cancelled = true
            deleteEntity(entry.entity)
        end
    end

    if rendered.capturedSyncVersions[side] == syncVersion then
        rendered.captured[side] = nextEntries
    end
end

local function reconcileCaptured(rendered, capturedWhite, capturedBlack)
    rendered.capturedWhiteCodes = capturedWhite or {}
    rendered.capturedBlackCodes = capturedBlack or {}
    crChessSyncCapturedSide(rendered, 'white', capturedWhite or {})
    crChessSyncCapturedSide(rendered, 'black', capturedBlack or {})
end

function crChessRefreshCapturedPositions(rendered)
    if not rendered then
        return
    end

    for _, side in ipairs({ 'white', 'black' }) do
        for index, entry in ipairs(rendered.captured[side] or {}) do
            if entry.entity and DoesEntityExist(entry.entity) then
                attachEntityToBoardOffset(entry.entity, rendered.board, crChessCapturedOffset(side, index))
            end
        end
    end
end

function crChessCollectCapturedPiece(rendered, pieceCode, entity, snapshot)
    if not rendered or not pieceCode or not entity or not DoesEntityExist(entity) then
        return
    end

    local side = crChessPieceColorSide(pieceCode)
    local codes = side == 'white' and snapshot and snapshot.capturedWhite or snapshot and snapshot.capturedBlack
    local index = codes and #codes or ((rendered.captured[side] and #rendered.captured[side] or 0) + 1)

    if index <= 0 then
        index = (rendered.captured[side] and #rendered.captured[side] or 0) + 1
    end

    SetEntityCollision(entity, false, false)
    SetEntityVisible(entity, true, false)
    rendered.captured[side] = rendered.captured[side] or {}
    rendered.capturedSyncVersions = rendered.capturedSyncVersions or {}
    rendered.capturedSyncVersions[side] = (rendered.capturedSyncVersions[side] or 0) + 1

    local previous = rendered.captured[side][index]

    if previous and previous.entity ~= entity then
        previous.cancelled = true
        deleteEntity(previous.entity)
    end

    rendered.captured[side][index] = {
        code = pieceCode,
        entity = entity,
        index = index,
        movingUntil = GetGameTimer() + 540
    }
    animateEntityToOffset(rendered, entity, crChessCapturedOffset(side, index), 520, 0.10)
end

function crChessBoardPieceCount(board)
    local count = 0

    for _ in pairs(board or {}) do
        count = count + 1
    end

    return count
end

function crChessIsStartingBoard(board)
    if crChessBoardPieceCount(board) ~= 32 then
        return false
    end

    return board.a1 == 'wR' and board.b1 == 'wN' and board.c1 == 'wB' and board.d1 == 'wQ'
        and board.e1 == 'wK' and board.f1 == 'wB' and board.g1 == 'wN' and board.h1 == 'wR'
        and board.a8 == 'bR' and board.b8 == 'bN' and board.c8 == 'bB' and board.d8 == 'bQ'
        and board.e8 == 'bK' and board.f8 == 'bB' and board.g8 == 'bN' and board.h8 == 'bR'
        and board.a2 == 'wP' and board.b2 == 'wP' and board.c2 == 'wP' and board.d2 == 'wP'
        and board.e2 == 'wP' and board.f2 == 'wP' and board.g2 == 'wP' and board.h2 == 'wP'
        and board.a7 == 'bP' and board.b7 == 'bP' and board.c7 == 'bP' and board.d7 == 'bP'
        and board.e7 == 'bP' and board.f7 == 'bP' and board.g7 == 'bP' and board.h7 == 'bP'
end

function crChessHasCapturedPieces(rendered)
    return rendered
        and ((rendered.captured.white and #rendered.captured.white > 0)
            or (rendered.captured.black and #rendered.captured.black > 0))
end

function crChessQueueResetEntity(queues, pieceCode, entity)
    if not pieceCode or not entity or not DoesEntityExist(entity) then
        deleteEntity(entity)
        return
    end

    queues[pieceCode] = queues[pieceCode] or {}
    queues[pieceCode][#queues[pieceCode] + 1] = entity
end

function crChessPopResetEntity(queues, pieceCode)
    local queue = queues[pieceCode]

    if not queue or #queue == 0 then
        return nil
    end

    return table.remove(queue, 1)
end

function crChessShouldAnimateBoardReset(rendered, board, resetKey)
    if not rendered or not board or rendered.resetBoardKey == resetKey then
        return false
    end

    if not crChessIsStartingBoard(board) then
        return false
    end

    return crChessHasCapturedPieces(rendered) or not crChessIsStartingBoard(rendered.pieceCodes or {})
end

function crChessAnimateBoardReset(rendered, board, resetKey)
    if not rendered or not board then
        return false
    end

    rendered.resetBoardKey = resetKey
    rendered.boardSyncVersion = (rendered.boardSyncVersion or 0) + 1

    local resetSyncVersion = rendered.boardSyncVersion

    for square, pending in pairs(rendered.pieceSpawns or {}) do
        pending.cancelled = true
        rendered.pieceSpawns[square] = nil
    end

    rendered.capturedSyncVersions = rendered.capturedSyncVersions or {}
    rendered.capturedSyncVersions.white = (rendered.capturedSyncVersions.white or 0) + 1
    rendered.capturedSyncVersions.black = (rendered.capturedSyncVersions.black or 0) + 1

    local queues = {}

    for square, entity in pairs(rendered.pieces or {}) do
        crChessQueueResetEntity(queues, rendered.pieceCodes[square], entity)
    end

    for _, side in ipairs({ 'white', 'black' }) do
        for _, entry in ipairs(rendered.captured[side] or {}) do
            entry.cancelled = true
            crChessQueueResetEntity(queues, entry.code, entry.entity)
        end
    end

    rendered.pieces = {}
    rendered.pieceCodes = {}
    rendered.captured = {
        white = {},
        black = {}
    }
    rendered.capturedWhiteCodes = {}
    rendered.capturedBlackCodes = {}

    local order = {}

    for rank = 1, 8 do
        for _, file in ipairs(files) do
            local square = file .. tostring(rank)

            if board[square] then
                order[#order + 1] = square
            end
        end
    end

    for index, square in ipairs(order) do
        if rendered.boardSyncVersion ~= resetSyncVersion then
            break
        end

        local pieceCode = board[square]
        local entity = crChessPopResetEntity(queues, pieceCode)

        if entity and DoesEntityExist(entity) then
            SetEntityCollision(entity, false, false)
            SetEntityVisible(entity, true, false)
            rendered.pieces[square] = entity
            rendered.pieceCodes[square] = pieceCode

            CreateThread(function()
                Wait((index - 1) * 22)

                if entity and DoesEntityExist(entity) then
                    animateEntityToOffset(rendered, entity, squareOffset(square), 680, 0.12)
                end
            end)
        else
            spawnPiece(rendered, pieceCode, square)

            if rendered.boardSyncVersion ~= resetSyncVersion then
                break
            end
        end
    end

    for _, queue in pairs(queues) do
        for _, entity in ipairs(queue) do
            deleteEntity(entity)
        end
    end

    return true
end

local function reconcilePieces(rendered, board)
    board = board or {}
    rendered.boardSyncVersion = (rendered.boardSyncVersion or 0) + 1

    local boardSyncVersion = rendered.boardSyncVersion
    local staleSquares = {}

    for square, pending in pairs(rendered.pieceSpawns or {}) do
        if board[square] ~= pending.code then
            pending.cancelled = true
            rendered.pieceSpawns[square] = nil
        else
            pending.boardSyncVersion = boardSyncVersion
        end
    end

    for square, pieceCode in pairs(rendered.pieceCodes) do
        if board[square] ~= pieceCode then
            staleSquares[#staleSquares + 1] = square
        end
    end

    for _, square in ipairs(staleSquares) do
        deletePiece(rendered, square)
    end

    for square, pieceCode in pairs(board) do
        if rendered.boardSyncVersion ~= boardSyncVersion then
            return
        end

        if rendered.pieceCodes[square] ~= pieceCode then
            deletePiece(rendered, square)
            spawnPiece(rendered, pieceCode, square, boardSyncVersion)

            if rendered.boardSyncVersion ~= boardSyncVersion then
                return
            end
        end
    end
end

function crChessBoardMoveInProgress(rendered)
    return rendered and (rendered.moveAnimationUntil or 0) > GetGameTimer()
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

    rendered.pieceSpawns = rendered.pieceSpawns or {}

    for _, square in ipairs({ lastMove.from, capturedSquare, lastMove.to }) do
        if square and rendered.pieceSpawns[square] then
            rendered.pieceSpawns[square].cancelled = true
            rendered.pieceSpawns[square] = nil
        end
    end

    if capturedSquare then
        local capturedEntity = rendered.pieces[capturedSquare]
        rendered.pieces[capturedSquare] = nil
        rendered.pieceCodes[capturedSquare] = nil

        if capturedEntity and lastMove.capturedPiece then
            crChessCollectCapturedPiece(rendered, lastMove.capturedPiece, capturedEntity, snapshot)
        else
            deleteEntity(capturedEntity)
        end
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
        local moveDuration = 650
        local moveEndsAt = GetGameTimer() + delay + moveDuration + 120
        rendered.moveAnimationUntil = math.max(rendered.moveAnimationUntil or 0, moveEndsAt)
        rendered.moveAnimationKey = key

        if spectator.active and spectator.matchId == snapshot.id and spectator.moveFocus ~= false then
            spectator.followEntity = movingEntity
            spectator.followUntil = GetGameTimer() + delay + moveDuration + ((Config.Spectator and Config.Spectator.moveFollowExtraMs) or 450)
        end

        local function animateMove(done)
            local function run()
                animateEntityToOffset(rendered, movingEntity, squareOffset(lastMove.to), moveDuration, 0.16, done)
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
                handleMoveLandingFeedback(snapshot, rendered)
                rendered.moveAnimationUntil = math.max(rendered.moveAnimationUntil or 0, GetGameTimer() + 60)

                if rendered.pieces[lastMove.to] == movingEntity then
                    deleteEntity(movingEntity)
                    rendered.pieces[lastMove.to] = nil
                    rendered.pieceCodes[lastMove.to] = nil
                    spawnPiece(rendered, snapshot.board[lastMove.to], lastMove.to)
                end
            end)
        else
            animateMove(function()
                handleMoveLandingFeedback(snapshot, rendered)
                rendered.moveAnimationUntil = math.max(rendered.moveAnimationUntil or 0, GetGameTimer() + 60)
            end)
        end
    end
end

local function spawnChair(rendered, chairConfig)
    if rendered.destroyed or not rendered.table or not DoesEntityExist(rendered.table) then
        return
    end

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

    if rendered.destroyed or not rendered.table or not DoesEntityExist(rendered.table) then
        deleteEntity(chair)
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

    rendered.destroyed = true
    rendered.building = false
    rendered.pendingSnapshot = nil
    renderedTables[tableId] = nil

    if crChessDestroyAmbientDui then
        crChessDestroyAmbientDui(tableId)
    end

    removeTableBlip(tableId)
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

    clearBotPed(rendered)
    deleteEntity(rendered.board)
    deleteEntity(rendered.table)
end

local function renderTable(tableData)
    if renderedTables[tableData.id] then
        local rendered = renderedTables[tableData.id]

        if rendered.building then
            rendered.pendingSnapshot = tableData
            return
        end

        if not rendered.table
            or not DoesEntityExist(rendered.table)
            or not rendered.board
            or not DoesEntityExist(rendered.board)
        then
            cleanupTable(tableData.id)
        else
            if rendered.botMatchId and rendered.botMatchId ~= tableData.matchId then
                clearBotPed(rendered, nil, tableData.matchId == nil)
                rendered.botMatchId = nil
            end

            local resetKey = tableData.matchId and ('table:' .. tostring(tableData.matchId)) or nil
            local moving = crChessBoardMoveInProgress(rendered)
            local didReset = (not moving) and resetKey and crChessShouldAnimateBoardReset(rendered, tableData.board, resetKey)

            rendered.snapshot = tableData
            rendered.matchId = tableData.matchId
            updateTableBlip(tableData)

            if didReset then
                crChessAnimateBoardReset(rendered, tableData.board, resetKey)
            elseif not moving then
                reconcilePieces(rendered, tableData.board)
                reconcileCaptured(rendered, tableData.capturedWhite, tableData.capturedBlack)
            end

            reconcileSeatAvatars(rendered, tableData)
            registerTableTargets(tableData.id, rendered)

            if currentMatch and currentMatch.tableId == tableData.id then
                ensureSeatForMatch(currentMatch)
                ensureBotPedForMatch(currentMatch)
            end

            return
        end
    end

    local rendered = {
        table = nil,
        board = nil,
        chairs = {},
        pieces = {},
        pieceCodes = {},
        pieceSpawns = {},
        boardSyncVersion = 0,
        captured = {
            white = {},
            black = {}
        },
        capturedWhiteCodes = {},
        capturedBlackCodes = {},
        capturedSyncVersions = {
            white = 0,
            black = 0
        },
        botPed = nil,
        botPeds = {},
        botPedModels = {},
        botPedSpawns = {},
        releasedBotPeds = {},
        botMatchId = nil,
        seatAvatars = {},
        seatAvatarSpawns = {},
        matchId = tableData.matchId,
        moveAnimationUntil = 0,
        moveAnimationKey = nil,
        resetBoardKey = nil,
        lastMoveKey = nil,
        snapshot = tableData,
        pendingSnapshot = nil,
        building = true,
        destroyed = false,
        targetSystem = nil
    }

    renderedTables[tableData.id] = rendered

    local coords = toVector3(tableData.coords)
    local tableObject = createObject(Config.Props.table, {
        x = coords.x,
        y = coords.y,
        z = coords.z
    })

    if not tableObject then
        if renderedTables[tableData.id] == rendered then
            renderedTables[tableData.id] = nil
        end

        return
    end

    if rendered.destroyed or renderedTables[tableData.id] ~= rendered then
        deleteEntity(tableObject)
        return
    end

    rendered.table = tableObject
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
        cleanupTable(tableData.id)
        return
    end

    if rendered.destroyed or renderedTables[tableData.id] ~= rendered then
        deleteEntity(boardObject)
        return
    end

    rendered.board = boardObject
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

    for _, chairConfig in ipairs(Config.Chairs) do
        spawnChair(rendered, chairConfig)
    end

    local latest = tableData

    repeat
        latest = rendered.pendingSnapshot or latest
        rendered.pendingSnapshot = nil
        rendered.snapshot = latest
        rendered.matchId = latest.matchId
        reconcilePieces(rendered, latest.board)
        reconcileCaptured(rendered, latest.capturedWhite, latest.capturedBlack)
    until not rendered.pendingSnapshot

    if rendered.destroyed or renderedTables[tableData.id] ~= rendered then
        return
    end

    rendered.building = false
    crChessPurgeDuplicateTableObjects(rendered)
    registerTableTargets(tableData.id, rendered)
    updateTableBlip(latest)
    reconcileSeatAvatars(rendered, latest)

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

function crChessTopDownCameraConfigForColor(color)
    local cameras = Config.Camera or {}
    local topDown = cameras.topDown or {}
    local camera = topDown[color or 'white'] or topDown.white or topDown.black

    if camera and camera.offset and camera.lookAt then
        return camera
    end

    local yOffset = color == 'black' and 0.02 or -0.02

    return {
        offset = { x = 0.0, y = yOffset, z = 0.9 },
        lookAt = { x = 0.0, y = 0.0, z = 0.02 },
        fov = 42.0
    }
end

function crChessCameraConfigForCurrentMode(color)
    if interaction.cameraMode == 'top' or interaction.cameraMode == 'topdown' then
        return crChessTopDownCameraConfigForColor(color)
    end

    return cameraConfigForColor(color)
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

    local cameraConfig = crChessCameraConfigForCurrentMode(localPerspective())
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

    sendNui('cameraMode', {
        mode = interaction.cameraMode == 'topdown' and 'topdown' or 'normal'
    })
end

function stopSpectatorMode(hideUi)
    if spectator.camera then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(spectator.camera, false)
    end

    if destroySpectatorDui then
        destroySpectatorDui()
    end

    spectator.active = false
    spectator.matchId = nil
    spectator.tableId = nil
    spectator.camera = nil
    spectator.focus = nil
    spectator.camCoords = nil
    spectator.followEntity = nil
    spectator.followUntil = 0
    spectator.focusSquare = nil
    spectator.focusUntil = 0
    spectator.snapshot = nil

    if hideUi ~= false and not currentMatch then
        setNuiVisible(false)
    end

    sendNui('boardOverlay', { visible = false })
end

function boardCenterCoords(rendered, zOffset)
    local config = Config.PieceOffset
    local centerX = config.startX + config.step * 3.5
    local centerY = config.startY + config.step * 3.5

    return GetOffsetFromEntityInWorldCoords(rendered.board, centerX, centerY, (config.z or 0.002) + (zOffset or 0.0))
end

function spectatorDuiConfig()
    return Config.SpectatorDui or {}
end

function spectatorDuiEnabled()
    local config = spectatorDuiConfig()
    return config.enabled ~= false
end

function crChessSpectatorDuiAmbientEnabled()
    local config = spectatorDuiConfig()
    return spectatorDuiEnabled() and config.ambient ~= false
end

function spectatorDuiUrl()
    return ('https://cfx-nui-%s/html/spectator.html'):format(GetCurrentResourceName())
end

function ensureDuiState(duiState)
    if not spectatorDuiEnabled() then
        return false
    end

    if not duiState then
        return false
    end

    if duiState.dui then
        return true
    end

    local config = spectatorDuiConfig()
    local width = math.max(256, math.floor(tonumber(config.width) or 768))
    local height = math.max(192, math.floor(tonumber(config.height) or 512))

    duiState.dui = CreateDui(spectatorDuiUrl(), width, height)
    duiState.txd = CreateRuntimeTxd(duiState.txdName or 'cr_chess_spectator_dui')
    local duiHandle = GetDuiHandle(duiState.dui)
    duiState.txn = CreateRuntimeTextureFromDuiHandle(duiState.txd, duiState.txnName or 'overlay', duiHandle)
    duiState.lastKey = nil
    duiState.readyAt = GetGameTimer() + 350

    return true
end

function destroyDuiState(duiState)
    if duiState.dui then
        SendDuiMessage(duiState.dui, json.encode({ action = 'hide' }))
        DestroyDui(duiState.dui)
    end

    duiState.dui = nil
    duiState.txd = nil
    duiState.txn = nil
    duiState.lastKey = nil
    duiState.readyAt = nil
end

function ensureSpectatorDui()
    return ensureDuiState(spectator.dui)
end

destroySpectatorDui = function()
    destroyDuiState(spectator.dui)
end

function crChessDuiSnapshotKey(snapshot)
    if not snapshot then
        return nil
    end

    local move = snapshot.lastMove or {}
    local bets = snapshot.spectatorBets or {}
    local clock = snapshot.clock or {}
    local remaining = clock.remaining or {}

    return table.concat({
        tostring(snapshot.id or ''),
        tostring(snapshot.label or ''),
        tostring(snapshot.mode or ''),
        tostring(snapshot.state or ''),
        tostring(snapshot.turn or ''),
        tostring(snapshot.fen or ''),
        tostring(move.from or ''),
        tostring(move.to or ''),
        tostring(move.piece or ''),
        tostring(move.finalPiece or ''),
        tostring(move.capturedPiece or ''),
        tostring(snapshot.winner or ''),
        tostring(snapshot.result or ''),
        tostring(snapshot.finishReason or ''),
        tostring(bets.enabled or false),
        tostring(bets.open or false),
        tostring(bets.total or 0),
        tostring(bets.secondsRemaining or ''),
        tostring(clock.activeColor or ''),
        tostring(remaining.white or ''),
        tostring(remaining.black or '')
    }, '|')
end

function sendDuiSnapshotToState(duiState, snapshot, force)
    if not snapshot or not ensureDuiState(duiState) then
        return
    end

    local config = spectatorDuiConfig()
    local key = crChessDuiSnapshotKey(snapshot)
    local warmingUp = duiState.readyAt and GetGameTimer() < duiState.readyAt

    if not force and not warmingUp and key and duiState.lastKey == key then
        return
    end

    duiState.lastKey = warmingUp and nil or key

    SendDuiMessage(duiState.dui, json.encode({
        action = 'snapshot',
        snapshot = snapshot,
        perspective = config.perspective or 'white'
    }))
end

sendSpectatorDuiSnapshot = function(snapshot, force)
    sendDuiSnapshotToState(spectator.dui, snapshot, force)
end

function crChessDuiDistanceLayout(config, boardCoords)
    local offset = config.offset or {}
    local width = tonumber(config.screenWidth) or 0.245
    local height = tonumber(config.screenHeight) or 0.165
    local alpha = tonumber(config.alpha) or 242
    local z = tonumber(offset.z) or 0.52
    local scale = config.distanceScale or {}

    if scale.enabled == false or not boardCoords then
        return width, height, z, math.floor(alpha)
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local dx = playerCoords.x - boardCoords.x
    local dy = playerCoords.y - boardCoords.y
    local dz = playerCoords.z - boardCoords.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local nearDistance = tonumber(scale.nearDistance) or 2.0
    local farDistance = tonumber(scale.farDistance) or (tonumber(config.drawDistance) or 8.0)

    if farDistance <= nearDistance then
        farDistance = nearDistance + 0.01
    end

    local t = math.max(0.0, math.min(1.0, (distance - nearDistance) / (farDistance - nearDistance)))

    local function mix(nearValue, farValue, fallbackNear, fallbackFar)
        nearValue = tonumber(nearValue) or fallbackNear
        farValue = tonumber(farValue) or fallbackFar

        return nearValue + (farValue - nearValue) * t
    end

    width = mix(scale.nearScreenWidth, scale.farScreenWidth, width, width * 0.55)
    height = mix(scale.nearScreenHeight, scale.farScreenHeight, height, height * 0.55)
    z = mix(scale.nearOffsetZ, scale.farOffsetZ, z, z + 0.55)
    alpha = mix(scale.nearAlpha, scale.farAlpha, alpha, alpha * 0.86)

    return width, height, z, math.floor(math.max(0, math.min(255, alpha)))
end

function drawDuiState(rendered, snapshot, duiState)
    snapshot = snapshot or spectator.snapshot

    if not snapshot or not rendered or not rendered.board or not spectatorDuiEnabled() then
        return
    end

    sendDuiSnapshotToState(duiState, snapshot)

    if not ensureDuiState(duiState) then
        return
    end

    local config = spectatorDuiConfig()
    local offset = config.offset or {}
    local boardCoords = GetEntityCoords(rendered.board)
    local width, height, z, alpha = crChessDuiDistanceLayout(config, boardCoords)
    local coords = GetOffsetFromEntityInWorldCoords(
        rendered.board,
        tonumber(offset.x) or 0.0,
        tonumber(offset.y) or 0.0,
        z
    )
    local onScreen = World3dToScreen2d(coords.x, coords.y, coords.z)

    if not onScreen then
        return
    end

    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    DrawSprite(
        duiState.txdName or spectator.dui.txdName,
        duiState.txnName or spectator.dui.txnName,
        0.0,
        0.0,
        width,
        height,
        0.0,
        255,
        255,
        255,
        alpha
    )
    ClearDrawOrigin()
end

drawSpectatorDui = function(rendered, snapshot)
    drawDuiState(rendered, snapshot, spectator.dui)
end

function crChessAmbientDuiState(tableId)
    tableId = tonumber(tableId)

    if not tableId then
        return nil
    end

    spectator.dui.ambient = spectator.dui.ambient or {}

    if not spectator.dui.ambient[tableId] then
        spectator.dui.ambient[tableId] = {
            dui = nil,
            txd = nil,
            txn = nil,
            txdName = ('cr_chess_spectator_dui_%s'):format(tableId),
            txnName = 'overlay',
            lastKey = nil
        }
    end

    return spectator.dui.ambient[tableId]
end

crChessDestroyAmbientDui = function(tableId)
    tableId = tonumber(tableId)

    if not tableId or not spectator.dui.ambient or not spectator.dui.ambient[tableId] then
        return
    end

    destroyDuiState(spectator.dui.ambient[tableId])
    spectator.dui.ambient[tableId] = nil
end

function crChessDestroyStaleAmbientDuis(activeTableIds)
    if not spectator.dui.ambient then
        return
    end

    for tableId in pairs(spectator.dui.ambient) do
        if not activeTableIds or not activeTableIds[tableId] then
            crChessDestroyAmbientDui(tableId)
        end
    end
end

function crChessDrawAmbientSpectatorDui(tableId, rendered, snapshot)
    local duiState = crChessAmbientDuiState(tableId)

    if duiState then
        drawDuiState(rendered, snapshot, duiState)
    end
end

function crChessSeatPlayerName(seat)
    if type(seat) == 'table' then
        return seat.name
    end

    return nil
end

function crChessIdleTableDuiSnapshot(tableId, rendered)
    local config = spectatorDuiConfig()

    if config.showIdleTables == false then
        return nil
    end

    local tableData = rendered and rendered.snapshot or nil

    if not tableData then
        return nil
    end

    local seats = tableData.seats or {}
    local whiteName = crChessSeatPlayerName(seats.white) or 'White open'
    local blackName = crChessSeatPlayerName(seats.black) or 'Black open'

    return {
        id = tableId,
        label = ('Table %s'):format(tableId),
        mode = 'open',
        state = 'idle',
        tableId = tableId,
        whiteName = whiteName,
        blackName = blackName,
        players = {
            white = { name = whiteName, rankName = seats.white and 'Seated' or 'Open' },
            black = { name = blackName, rankName = seats.black and 'Seated' or 'Open' }
        },
        board = tableData.board or {},
        spectatorBets = { enabled = false },
        clock = { enabled = false },
        moveHistory = {},
        capturedWhite = tableData.capturedWhite or {},
        capturedBlack = tableData.capturedBlack or {}
    }
end

function crChessTableDuiSnapshot(tableId, rendered)
    local tableData = rendered and rendered.snapshot or nil
    local matchId = tableData and tonumber(tableData.matchId) or nil

    if matchId and observedMatches[matchId] then
        return observedMatches[matchId]
    end

    return crChessIdleTableDuiSnapshot(tableId, rendered)
end

function crChessAmbientDuiTargets()
    if not crChessSpectatorDuiAmbientEnabled() or spectator.active or currentMatch or seated.active then
        return {}
    end

    local config = spectatorDuiConfig()
    local range = tonumber(config.drawDistance) or 12.0
    local playerCoords = GetEntityCoords(PlayerPedId())
    local targets = {}

    for tableId, rendered in pairs(renderedTables) do
        if rendered.board and DoesEntityExist(rendered.board) then
            local snapshot = crChessTableDuiSnapshot(tableId, rendered)

            if snapshot then
                local coords = GetEntityCoords(rendered.board)
                local dx = playerCoords.x - coords.x
                local dy = playerCoords.y - coords.y
                local dz = playerCoords.z - coords.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                if distance <= range then
                    targets[#targets + 1] = {
                        tableId = tableId,
                        rendered = rendered,
                        snapshot = snapshot,
                        distance = distance
                    }
                end
            end
        end
    end

    table.sort(targets, function(a, b)
        return a.distance < b.distance
    end)

    local limit = math.max(1, math.floor(tonumber(config.maxAmbientDuis) or 4))

    while #targets > limit do
        targets[#targets] = nil
    end

    return targets
end

function crChessAmbientDuiTarget()
    local targets = crChessAmbientDuiTargets()
    local first = targets[1]

    if not first then
        return nil, nil, nil
    end

    return first.rendered, first.snapshot, first.tableId
end

function crChessMaybeSyncAmbientDui(snapshot)
    if not snapshot or snapshot.state == 'idle' then
        return
    end

    local interval = tonumber(spectatorDuiConfig().syncIntervalMs) or 5000
    local now = GetGameTimer()

    if now - (spectator.dui.lastAmbientSyncAt or 0) >= interval then
        spectator.dui.lastAmbientSyncAt = now
        TriggerServerEvent('cr-chess:server:requestSync')
    end
end

function crChessMaybeRequestAttractMode(tableId, snapshot)
    if not tableId or not snapshot then
        return
    end

    local config = Config.AttractMode or {}

    if config.enabled == false then
        return
    end

    if snapshot.state ~= 'idle' and snapshot.demo ~= true then
        return
    end

    local interval = tonumber(config.heartbeatIntervalMs) or 4000
    local now = GetGameTimer()
    local lastSeenByTable = spectator.dui.lastAttractSeenAt

    if type(lastSeenByTable) ~= 'table' then
        lastSeenByTable = {}
        spectator.dui.lastAttractSeenAt = lastSeenByTable
    end

    if now - (lastSeenByTable[tableId] or 0) < interval then
        return
    end

    lastSeenByTable[tableId] = now

    local coords = GetEntityCoords(PlayerPedId())

    TriggerServerEvent('cr-chess:server:attractTableSeen', tableId, {
        x = coords.x,
        y = coords.y,
        z = coords.z
    })
end

function spectatorFocusCoords(rendered)
    local config = Config.Spectator or {}
    local now = GetGameTimer()

    if spectator.followEntity and now <= (spectator.followUntil or 0) and DoesEntityExist(spectator.followEntity) then
        local coords = GetEntityCoords(spectator.followEntity)
        return vector3(coords.x, coords.y, coords.z + (config.focusHeight or 0.08))
    end

    if spectator.focusSquare and now <= (spectator.focusUntil or 0) then
        local offset = squareOffset(spectator.focusSquare)

        if offset then
            return GetOffsetFromEntityInWorldCoords(
                rendered.board,
                offset.x,
                offset.y,
                offset.z + (config.focusHeight or 0.08)
            )
        end
    end

    return boardCenterCoords(rendered, config.focusHeight or 0.08)
end

function updateSpectatorFocus(snapshot)
    if not snapshot or not snapshot.lastMove then
        return
    end

    if spectator.moveFocus == false then
        spectator.followEntity = nil
        spectator.followUntil = 0
        spectator.focusSquare = nil
        spectator.focusUntil = 0
        return
    end

    spectator.focusSquare = snapshot.lastMove.to
    spectator.focusUntil = GetGameTimer() + ((Config.Spectator and Config.Spectator.lastMoveFocusMs) or 1800)
end

function clampValue(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function lerpNumber(current, target, alpha)
    return current + (target - current) * alpha
end

function lerpCoords(current, target, alpha)
    if not current then
        return target
    end

    return vector3(
        lerpNumber(current.x, target.x, alpha),
        lerpNumber(current.y, target.y, alpha),
        lerpNumber(current.z, target.z, alpha)
    )
end

function lerpAlpha(speed, delta)
    return 1.0 - math.exp(-(speed or 8.0) * math.max(0.0, delta or 0.0))
end

function spectatorYawFromPlayer(rendered)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local localPoint = GetOffsetFromEntityGivenWorldCoords(rendered.board, playerCoords.x, playerCoords.y, playerCoords.z)

    if math.abs(localPoint.x) < 0.001 and math.abs(localPoint.y) < 0.001 then
        return 180.0
    end

    return math.deg(math.atan(localPoint.x, localPoint.y))
end

function startSpectatorMode(snapshot)
    if not snapshot or not snapshot.tableId then
        notify('No spectatable chess match found.')
        return
    end

    local rendered = renderedTables[snapshot.tableId]

    if not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        notify('That match table is not rendered yet. Try again in a moment.')
        TriggerServerEvent('cr-chess:server:requestSync')
        return
    end

    if reconcileSeatAvatars then
        reconcileSeatAvatars(rendered, crChessSeatSnapshotFromMatch(snapshot))
    end

    stopSpectatorMode(false)
    stopTableCamera()

    spectator.active = true
    spectator.matchId = snapshot.id
    spectator.tableId = snapshot.tableId
    spectator.snapshot = snapshot
    spectator.yaw = spectatorYawFromPlayer(rendered)
    spectator.radius = (Config.Spectator and Config.Spectator.radius) or 0.95
    spectator.height = (Config.Spectator and Config.Spectator.height) or 0.72
    spectator.lastUpdate = GetGameTimer()
    updateSpectatorFocus(snapshot)

    local config = Config.Spectator or {}
    local focus = spectatorFocusCoords(rendered)
    local yaw = math.rad(spectator.yaw)
    local camCoords = GetOffsetFromEntityInWorldCoords(
        rendered.board,
        math.sin(yaw) * spectator.radius,
        math.cos(yaw) * spectator.radius,
        spectator.height
    )

    spectator.focus = focus
    spectator.camCoords = camCoords

    spectator.camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(spectator.camera, camCoords.x, camCoords.y, camCoords.z)
    PointCamAtCoord(spectator.camera, focus.x, focus.y, focus.z)
    SetCamFov(spectator.camera, config.fov or 55.0)
    SetCamActive(spectator.camera, true)
    RenderScriptCams(true, true, 350, true, true)

    if spectatorDuiEnabled() and (spectatorDuiConfig().hideSidePanel ~= false) then
        setNuiVisible(false, false)
        sendSpectatorDuiSnapshot(snapshot)
    else
        setNuiVisible(true, false)
        sendSnapshotToNui(snapshot)
    end

    ensureBotPedForMatch(snapshot)
    notify(('Spectating match %d. Mouse moves camera, wheel zooms, Backspace exits.'):format(snapshot.id))
end

function crChessNormalizeSpectatorCameraMode(mode)
    mode = tostring(mode or ''):lower()

    if mode == 'top' or mode == 'topdown' or mode == 'top_down' then
        return 'topdown'
    end

    if mode == 'orbit' or mode == 'normal' or mode == 'angle' or mode == 'angled' or mode == 'default' then
        return 'orbit'
    end

    return nil
end

function crChessToggleSpectatorCameraMode(mode)
    if not spectator.active then
        return false
    end

    local nextMode = crChessNormalizeSpectatorCameraMode(mode)

    if not nextMode then
        nextMode = spectator.cameraMode == 'topdown' and 'orbit' or 'topdown'
    end

    spectator.cameraMode = nextMode
    spectator.followEntity = nil
    spectator.followUntil = 0
    spectator.focusSquare = nil
    spectator.focusUntil = 0
    spectator.focus = nil
    spectator.camCoords = nil

    if nextMode == 'topdown' then
        notify('Spectator camera: top-down view. Press G or use /chess_camera normal to switch back.')
    else
        notify('Spectator camera: free orbit view. Press G or use /chess_camera top for top-down.')
    end

    return true
end

function crChessToggleSpectatorMoveFocus()
    if not spectator.active then
        return false
    end

    spectator.moveFocus = spectator.moveFocus == false
    spectator.followEntity = nil
    spectator.followUntil = 0
    spectator.focusSquare = nil
    spectator.focusUntil = 0

    if spectator.moveFocus then
        updateSpectatorFocus(spectator.snapshot)
        notify('Spectator move focus enabled.')
    else
        notify('Spectator move focus disabled.')
    end

    return true
end

function updateSpectatorControls(delta)
    local config = Config.Spectator or {}
    local lookX = GetDisabledControlNormal(0, 1)
    local lookY = GetDisabledControlNormal(0, 2)
    local mouseSensitivity = config.mouseSensitivity or 135.0
    local verticalSensitivity = config.verticalSensitivity or 0.55

    if spectator.cameraMode == 'topdown' then
        local topDown = config.topDown or {}
        local offset = topDown.offset or {}

        spectator.topDownHeight = spectator.topDownHeight or tonumber(offset.z) or 1.25

        if IsDisabledControlJustPressed(0, 241) or IsControlJustPressed(0, 241) then
            spectator.topDownHeight = clampValue(
                spectator.topDownHeight - (config.zoomStep or 0.08),
                config.minHeight or 0.35,
                config.maxTopDownHeight or 2.25
            )
        elseif IsDisabledControlJustPressed(0, 242) or IsControlJustPressed(0, 242) then
            spectator.topDownHeight = clampValue(
                spectator.topDownHeight + (config.zoomStep or 0.08),
                config.minHeight or 0.35,
                config.maxTopDownHeight or 2.25
            )
        end

        return
    end

    spectator.yaw = (spectator.yaw - lookX * mouseSensitivity * math.max(delta, 0.0)) % 360.0
    spectator.height = clampValue(
        (spectator.height or config.height or 0.72) + lookY * verticalSensitivity * math.max(delta, 0.0),
        config.minHeight or 0.35,
        config.maxHeight or 1.15
    )

    if IsDisabledControlJustPressed(0, 241) or IsControlJustPressed(0, 241) then
        spectator.radius = clampValue(
            (spectator.radius or config.radius or 0.95) - (config.zoomStep or 0.08),
            config.minRadius or 0.55,
            config.maxRadius or 1.65
        )
    elseif IsDisabledControlJustPressed(0, 242) or IsControlJustPressed(0, 242) then
        spectator.radius = clampValue(
            (spectator.radius or config.radius or 0.95) + (config.zoomStep or 0.08),
            config.minRadius or 0.55,
            config.maxRadius or 1.65
        )
    end
end

function updateSpectatorCamera()
    if not spectator.active then
        return
    end

    local rendered = spectator.tableId and renderedTables[spectator.tableId] or nil

    if not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        stopSpectatorMode()
        notify('Spectator mode stopped: table disappeared.')
        return
    end

    if not spectator.camera then
        spectator.camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamActive(spectator.camera, true)
        RenderScriptCams(true, true, 350, true, true)
    end

    local now = GetGameTimer()
    local delta = math.max(0, now - (spectator.lastUpdate or now)) / 1000.0
    local config = Config.Spectator or {}

    spectator.lastUpdate = now
    updateSpectatorControls(delta)

    if spectator.cameraMode == 'topdown' then
        local topDown = config.topDown or {}
        local offset = topDown.offset or {}
        local lookAt = topDown.lookAt or {}
        local targetCamCoords = GetOffsetFromEntityInWorldCoords(
            rendered.board,
            tonumber(offset.x) or 0.0,
            tonumber(offset.y) or 0.0,
            spectator.topDownHeight or tonumber(offset.z) or 1.25
        )
        local targetFocus = GetOffsetFromEntityInWorldCoords(
            rendered.board,
            tonumber(lookAt.x) or 0.0,
            tonumber(lookAt.y) or 0.0,
            tonumber(lookAt.z) or 0.035
        )
        local focusAlpha = lerpAlpha(config.focusLerp or 7.5, delta)
        local cameraAlpha = lerpAlpha(config.cameraLerp or 12.0, delta)

        spectator.focus = lerpCoords(spectator.focus, targetFocus, focusAlpha)
        spectator.camCoords = lerpCoords(spectator.camCoords, targetCamCoords, cameraAlpha)

        SetCamCoord(spectator.camera, spectator.camCoords.x, spectator.camCoords.y, spectator.camCoords.z)
        PointCamAtCoord(spectator.camera, spectator.focus.x, spectator.focus.y, spectator.focus.z)
        SetCamFov(spectator.camera, topDown.fov or 42.0)
        return
    end

    local radians = math.rad(spectator.yaw or 180.0)
    local radius = spectator.radius or config.radius or 0.95
    local targetCamCoords = GetOffsetFromEntityInWorldCoords(
        rendered.board,
        math.sin(radians) * radius,
        math.cos(radians) * radius,
        spectator.height or config.height or 0.72
    )
    local targetFocus = spectatorFocusCoords(rendered)
    local focusAlpha = lerpAlpha(config.focusLerp or 7.5, delta)
    local cameraAlpha = lerpAlpha(config.cameraLerp or 12.0, delta)

    spectator.focus = lerpCoords(spectator.focus, targetFocus, focusAlpha)
    spectator.camCoords = lerpCoords(spectator.camCoords, targetCamCoords, cameraAlpha)

    SetCamCoord(spectator.camera, spectator.camCoords.x, spectator.camCoords.y, spectator.camCoords.z)
    PointCamAtCoord(spectator.camera, spectator.focus.x, spectator.focus.y, spectator.focus.z)
    SetCamFov(spectator.camera, config.fov or 55.0)
end

sendSnapshotToNui = function(snapshot)
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

function crChessTargetEntities(rendered)
    local entities = {}

    if rendered and rendered.table and DoesEntityExist(rendered.table) then
        entities[#entities + 1] = rendered.table
    end

    if rendered and rendered.board and DoesEntityExist(rendered.board) then
        entities[#entities + 1] = rendered.board
    end

    return entities
end

function crChessRenderedActiveMatch(rendered)
    local snapshot = rendered and rendered.snapshot or nil
    local matchId = snapshot and tonumber(snapshot.matchId) or nil

    if not matchId then
        return nil
    end

    local match = observedMatches[matchId]

    if match and match.state ~= 'active' then
        return nil
    end

    return match or {
        id = matchId,
        state = 'active'
    }
end

function crChessCanTargetSpectate(rendered)
    return crChessRenderedActiveMatch(rendered) ~= nil
end

function crChessSpectateTargetMatch(tableId, rendered)
    local match = crChessRenderedActiveMatch(rendered)

    if not match then
        notify('There is no active chess match on this board.')
        return
    end

    local coords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('cr-chess:server:spectateMatch', match.id, {
        x = coords.x,
        y = coords.y,
        z = coords.z
    })
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
            'cr_chess_menu',
            'cr_chess_spectate'
        }

        local spectateOption = {
            name = rendered.targetNames[4],
            label = 'Spectate Match',
            icon = 'fa-solid fa-eye',
            distance = distance,
            canInteract = function()
                return crChessCanTargetSpectate(rendered)
            end,
            onSelect = function()
                crChessSpectateTargetMatch(tableId, rendered)
            end
        }

        local options = {
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
            },
            spectateOption
        }

        rendered.targetEntities = crChessTargetEntities(rendered)

        exports.ox_target:addLocalEntity(rendered.table, options)

        if rendered.board and DoesEntityExist(rendered.board) then
            exports.ox_target:addLocalEntity(rendered.board, { spectateOption })
        end
    elseif system == 'qb' then
        rendered.targetEntities = crChessTargetEntities(rendered)

        local spectateOption = {
            label = 'Spectate Match',
            icon = 'fas fa-eye',
            canInteract = function()
                return crChessCanTargetSpectate(rendered)
            end,
            action = function()
                crChessSpectateTargetMatch(tableId, rendered)
            end
        }

        local targetConfig = {
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
                },
                spectateOption
            },
            distance = distance
        }

        exports['qb-target']:AddTargetEntity(rendered.table, targetConfig)

        if rendered.board and DoesEntityExist(rendered.board) then
            exports['qb-target']:AddTargetEntity(rendered.board, {
                options = { spectateOption },
                distance = distance
            })
        end
    end

    rendered.targetSystem = system
end

unregisterTableTargets = function(rendered)
    if not rendered or not rendered.targetSystem then
        return
    end

    local targetEntities = rendered.targetEntities or crChessTargetEntities(rendered)

    if rendered.targetSystem == 'ox' and GetResourceState('ox_target') == 'started' then
        local targetNames = rendered.targetNames or {
            'cr_chess_sit_white',
            'cr_chess_sit_black',
            'cr_chess_menu',
            'cr_chess_spectate'
        }

        for _, entity in ipairs(targetEntities) do
            if entity and DoesEntityExist(entity) then
                exports.ox_target:removeLocalEntity(entity, targetNames)
            end
        end
    elseif rendered.targetSystem == 'qb' and GetResourceState('qb-target') == 'started' then
        for _, entity in ipairs(targetEntities) do
            if entity and DoesEntityExist(entity) then
                exports['qb-target']:RemoveTargetEntity(entity)
            end
        end
    end

    rendered.targetSystem = nil
    rendered.targetNames = nil
    rendered.targetEntities = nil
end

local function useSeatAvatarForPlayer()
    return Config.Animations and Config.Animations.useSeatAvatarForPlayer == true
end

local function showLocalSeatAvatar()
    return Config.Animations and Config.Animations.showLocalSeatAvatar == true
end

local function deleteSeatAvatar()
    if seated.avatarSpawning then
        seated.avatarSpawning.cancelled = true
        seated.avatarSpawning = nil
    end

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

    local token = {
        tableId = seated.tableId,
        color = color,
        cancelled = false
    }

    seated.avatarSpawning = token

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
                if seated.avatarSpawning == token then
                    seated.avatarSpawning = nil
                end
                return nil
            end
        end

        local coords = GetEntityCoords(sourcePed)
        avatar = CreatePed(4, hash, coords.x, coords.y, coords.z, GetEntityHeading(sourcePed), false, true)
        SetModelAsNoLongerNeeded(hash)
    end

    if not avatar or not DoesEntityExist(avatar) then
        if seated.avatarSpawning == token then
            seated.avatarSpawning = nil
        end

        return nil
    end

    if token.cancelled
        or seated.avatarSpawning ~= token
        or seated.tableId ~= token.tableId
        or seated.color ~= token.color
    then
        deleteEntity(avatar)
        return nil
    end

    seated.avatarSpawning = nil
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

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() and GetPlayerPed(player) == ped then
            return false
        end
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

        if useSeatAvatarForPlayer()
            and not seated.avatarSpawning
            and (not seated.avatar or not DoesEntityExist(seated.avatar))
            and rendered
        then
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

local function clockConfigPayload()
    local clock = Config.Clock or {}
    local initialSeconds = tonumber(clock.initialSeconds)

    if not initialSeconds then
        initialSeconds = (tonumber(clock.initialMinutes) or 10) * 60
    end

    return {
        enabled = clock.enabled ~= false,
        initialMs = math.max(1000, math.floor(initialSeconds * 1000)),
        incrementMs = math.max(0, math.floor((tonumber(clock.incrementSeconds) or 0) * 1000))
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
        wagers = wagerConfigPayload(),
        clock = clockConfigPayload()
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
    if not rendered then
        return
    end

    rendered.seatAvatarSpawns = rendered.seatAvatarSpawns or {}

    if rendered.seatAvatarSpawns[color] then
        rendered.seatAvatarSpawns[color].cancelled = true
        rendered.seatAvatarSpawns[color] = nil
    end

    rendered.seatAvatars = rendered.seatAvatars or {}

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
    rendered.seatAvatarSpawns = rendered.seatAvatarSpawns or {}

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
        local pending = rendered.seatAvatarSpawns[color]

        if pending then
            pending.cancelled = true
            rendered.seatAvatarSpawns[color] = nil
        end

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

    local pending = rendered.seatAvatarSpawns[color]

    if pending and not pending.cancelled and pending.source == source then
        return
    end

    if pending then
        pending.cancelled = true
    end

    local token = {
        source = source,
        cancelled = false
    }

    rendered.seatAvatarSpawns[color] = token

    local avatar = createRemoteSeatAvatar(rendered, color, source)

    if not avatar then
        if rendered.seatAvatarSpawns[color] == token then
            rendered.seatAvatarSpawns[color] = nil
        end

        return
    end

    if rendered.destroyed
        or token.cancelled
        or rendered.seatAvatarSpawns[color] ~= token
    then
        deleteEntity(avatar)
        return
    end

    rendered.seatAvatarSpawns[color] = nil
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

    for _, entity in ipairs(tunePreview.captured or {}) do
        deleteEntity(entity)
    end

    tunePreview.captured = {}
    tunePreview.capturedTarget = nil
end

function crChessCapturedPreviewCodes(side)
    local prefix = side == 'white' and 'w' or 'b'

    return {
        prefix .. 'P',
        prefix .. 'P',
        prefix .. 'P',
        prefix .. 'P',
        prefix .. 'P',
        prefix .. 'P',
        prefix .. 'P',
        prefix .. 'P',
        prefix .. 'R',
        prefix .. 'N',
        prefix .. 'B',
        prefix .. 'Q',
        prefix .. 'K',
        prefix .. 'B',
        prefix .. 'N',
        prefix .. 'R'
    }
end

function crChessDeleteCapturedTunePreview()
    for _, entity in ipairs(tunePreview.captured or {}) do
        deleteEntity(entity)
    end

    tunePreview.captured = {}
    tunePreview.capturedTarget = nil
end

function crChessCreateCapturedTunePreview(rendered, side)
    crChessDeleteCapturedTunePreview()

    if tunePreview.ped then
        deleteEntity(tunePreview.ped)
        tunePreview.ped = nil
        tunePreview.target = nil
    end

    if not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        return
    end

    for index, pieceCode in ipairs(crChessCapturedPreviewCodes(side)) do
        local entity = crChessSpawnCapturedPiece(rendered, side, pieceCode, index)

        if entity and DoesEntityExist(entity) then
            SetEntityAlpha(entity, 150, false)
            SetEntityCollision(entity, false, false)
            FreezeEntityPosition(entity, true)
            tunePreview.captured[#tunePreview.captured + 1] = entity
        end
    end

    tunePreview.capturedTarget = 'captured_' .. side
end

function crChessUpdateCapturedTunePreview(rendered)
    if not tuning.enabled or (tuning.target ~= 'captured_white' and tuning.target ~= 'captured_black') then
        crChessDeleteCapturedTunePreview()
        return
    end

    if not rendered or not rendered.board or not DoesEntityExist(rendered.board) then
        return
    end

    local side = tuning.target == 'captured_white' and 'white' or 'black'

    if tunePreview.capturedTarget ~= tuning.target or #(tunePreview.captured or {}) == 0 then
        crChessCreateCapturedTunePreview(rendered, side)
    end

    for index, entity in ipairs(tunePreview.captured or {}) do
        if entity and DoesEntityExist(entity) then
            SetEntityAlpha(entity, 150, false)
            SetEntityCollision(entity, false, false)
            FreezeEntityPosition(entity, true)
            attachEntityToBoardOffset(entity, rendered.board, crChessCapturedOffset(side, index))
        end
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

local function botDifficultyForColor(snapshot, color)
    if not snapshot or not color then
        return nil
    end

    if snapshot.botDifficulties and snapshot.botDifficulties[color] then
        return snapshot.botDifficulties[color]
    end

    if snapshot.mode == 'bot' and color == snapshot.botColor then
        return snapshot.botDifficulty or 'easy'
    end

    return nil
end

function botPedModelPool()
    local config = Config.BotPed or {}

    if type(config.models) == 'table' and #config.models > 0 then
        return config.models
    end

    return { config.model or 'a_m_y_business_01' }
end

function botPedModelForColor(snapshot, color)
    local pool = botPedModelPool()
    local seed = (tonumber(snapshot and snapshot.id) or 0) * 37

    for index = 1, #color do
        seed = seed + string.byte(color, index) * index
    end

    local index = (math.abs(seed) % #pool) + 1

    return pool[index]
end

function crChessPurgeDuplicateBotPeds(rendered)
    if not rendered
        or rendered.destroyed
        or type(GetGamePool) ~= 'function'
        or not rendered.table
        or not DoesEntityExist(rendered.table)
    then
        return
    end

    local keep = {}
    local modelHashes = {}

    for _, model in ipairs(botPedModelPool()) do
        modelHashes[joaat(model)] = true
    end

    for _, ped in pairs(rendered.botPeds or {}) do
        if ped then
            keep[ped] = true
        end
    end

    for _, entry in pairs(rendered.seatAvatars or {}) do
        if entry.ped then
            keep[entry.ped] = true
        end
    end

    for _, ped in ipairs(rendered.releasedBotPeds or {}) do
        if ped then
            keep[ped] = true
        end
    end

    if seated.avatar then
        keep[seated.avatar] = true
    end

    if tunePreview.ped then
        keep[tunePreview.ped] = true
    end

    for _, player in ipairs(GetActivePlayers()) do
        keep[GetPlayerPed(player)] = true
    end

    local seatPositions = {}

    for _, color in ipairs({ 'white', 'black' }) do
        local transform = seatTransform(rendered, color)

        if transform and transform.pos then
            seatPositions[#seatPositions + 1] = transform.pos
        end
    end

    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped
            and DoesEntityExist(ped)
            and not keep[ped]
        then
            local coords = GetEntityCoords(ped)
            local botModel = modelHashes[GetEntityModel(ped)] == true

            for _, seatPos in ipairs(seatPositions) do
                local dx = coords.x - seatPos.x
                local dy = coords.y - seatPos.y
                local dz = coords.z - seatPos.z
                local maxDistance = botModel and 0.42 or 0.22

                if math.sqrt(dx * dx + dy * dy + dz * dz) < maxDistance then
                    deleteEntity(ped)
                    break
                end
            end
        end
    end
end

function crChessForgetReleasedBotPed(rendered, ped)
    if not rendered or not rendered.releasedBotPeds or not ped then
        return
    end

    for index = #rendered.releasedBotPeds, 1, -1 do
        if rendered.releasedBotPeds[index] == ped then
            table.remove(rendered.releasedBotPeds, index)
        end
    end
end

function crChessPurgeReleasedBotPeds(rendered)
    if not rendered or not rendered.releasedBotPeds then
        return
    end

    for _, ped in ipairs(rendered.releasedBotPeds) do
        deleteEntity(ped)
    end

    rendered.releasedBotPeds = {}
end

function releaseBotPedEntity(rendered, color, ped)
    if not ped or not DoesEntityExist(ped) then
        return
    end

    if rendered then
        rendered.releasedBotPeds = rendered.releasedBotPeds or {}
        rendered.releasedBotPeds[#rendered.releasedBotPeds + 1] = ped
    end

    SetEntityAsMissionEntity(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, false, false)
    ClearPedTasksImmediately(ped)

    local target = nil

    if rendered and rendered.table and DoesEntityExist(rendered.table) then
        local y = color == 'black' and 1.85 or -1.85
        target = GetOffsetFromEntityInWorldCoords(rendered.table, 0.0, y, 0.0)
    else
        local coords = GetEntityCoords(ped)
        target = vector3(coords.x, coords.y + 1.2, coords.z)
    end

    TaskGoStraightToCoord(ped, target.x, target.y, target.z, 0.85, 1800, GetEntityHeading(ped), 0.1)

    CreateThread(function()
        Wait(2300)
        deleteEntity(ped)
        crChessForgetReleasedBotPed(rendered, ped)
    end)
end

clearBotPed = function(rendered, color, leave)
    if not rendered then
        return
    end

    rendered.botPeds = rendered.botPeds or {}
    rendered.botPedModels = rendered.botPedModels or {}
    rendered.botPedSpawns = rendered.botPedSpawns or {}

    if color then
        if rendered.botPedSpawns[color] then
            rendered.botPedSpawns[color].cancelled = true
            rendered.botPedSpawns[color] = nil
        end

        local ped = rendered.botPeds[color]

        if leave then
            releaseBotPedEntity(rendered, color, ped)
        else
            deleteEntity(ped)
        end

        if rendered.botPed == ped then
            rendered.botPed = nil
        end

        rendered.botPeds[color] = nil
        rendered.botPedModels[color] = nil
        return
    end

    local deleted = {}

    for botColor, token in pairs(rendered.botPedSpawns) do
        token.cancelled = true
        rendered.botPedSpawns[botColor] = nil
    end

    if rendered.botPed then
        deleted[rendered.botPed] = true
        if leave then
            releaseBotPedEntity(rendered, nil, rendered.botPed)
        else
            deleteEntity(rendered.botPed)
        end
        rendered.botPed = nil
    end

    for botColor, ped in pairs(rendered.botPeds) do
        if not deleted[ped] then
            if leave then
                releaseBotPedEntity(rendered, botColor, ped)
            else
                deleteEntity(ped)
            end
        end

        rendered.botPeds[botColor] = nil
    end

    rendered.botPedModels = {}

    if not leave then
        crChessPurgeReleasedBotPeds(rendered)
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

    crChessPurgeDuplicateBotPeds(rendered)

    if snapshot.state == 'finished' then
        clearBotPed(rendered, nil, true)
        rendered.botMatchId = nil
        return
    end

    if rendered.botMatchId and rendered.botMatchId ~= snapshot.id then
        clearBotPed(rendered, nil, false)
        rendered.botMatchId = nil
    end

    crChessPurgeReleasedBotPeds(rendered)

    local hasBot = false

    rendered.botPeds = rendered.botPeds or {}
    rendered.botPedModels = rendered.botPedModels or {}
    rendered.botPedSpawns = rendered.botPedSpawns or {}

    for _, botColor in ipairs({ 'white', 'black' }) do
        if botDifficultyForColor(snapshot, botColor) then
            hasBot = true

            local model = botPedModelForColor(snapshot, botColor)
            local modelHash = joaat(model)
            local existing = rendered.botPeds[botColor]
            rendered.botMatchId = snapshot.id

            if existing and DoesEntityExist(existing) and GetEntityModel(existing) ~= modelHash then
                clearBotPed(rendered, botColor, false)
                existing = nil
            end

            if existing and DoesEntityExist(existing) then
                if isSeatAnimationLocked(existing) then
                    FreezeEntityPosition(existing, true)
                elseif not isSeatAnimationPlaying(existing) then
                    seatLocalPedOnTable(existing, rendered, botColor, true)
                else
                    applySeatTransform(existing, rendered, botColor, nil)
                    FreezeEntityPosition(existing, true)
                end
            else
                local pending = rendered.botPedSpawns[botColor]

                if not pending
                    or pending.cancelled
                    or pending.matchId ~= snapshot.id
                    or pending.model ~= model
                then
                    if pending then
                        pending.cancelled = true
                    end

                    local token = {
                        matchId = snapshot.id,
                        model = model,
                        cancelled = false
                    }

                    rendered.botPedSpawns[botColor] = token

                    local hash = loadModel(model)

                    if hash
                        and not rendered.destroyed
                        and not token.cancelled
                        and rendered.botPedSpawns[botColor] == token
                        and rendered.botMatchId == snapshot.id
                    then
                        local tableCoords = GetEntityCoords(rendered.table)
                        local ped = CreatePed(4, hash, tableCoords.x, tableCoords.y, tableCoords.z, GetEntityHeading(rendered.table), false, true)
                        SetModelAsNoLongerNeeded(hash)

                        if rendered.destroyed
                            or token.cancelled
                            or rendered.botPedSpawns[botColor] ~= token
                            or rendered.botMatchId ~= snapshot.id
                        then
                            deleteEntity(ped)
                        elseif ped and DoesEntityExist(ped) then
                            SetEntityInvincible(ped, true)
                            SetBlockingOfNonTemporaryEvents(ped, true)
                            SetEntityCollision(ped, false, false)
                            SetEntityAlpha(ped, Config.BotPed and Config.BotPed.alpha or 255, false)

                            if type(SetPedDefaultComponentVariation) == 'function' then
                                SetPedDefaultComponentVariation(ped)
                            end

                            rendered.botPeds[botColor] = ped
                            rendered.botPedModels[botColor] = model
                            rendered.botMatchId = snapshot.id
                            rendered.botPed = ped
                            seatLocalPedOnTable(ped, rendered, botColor, true)
                        end
                    end

                    if hash then
                        SetModelAsNoLongerNeeded(hash)
                    end

                    if rendered.botPedSpawns[botColor] == token then
                        rendered.botPedSpawns[botColor] = nil
                    end
                end
            end
        else
            clearBotPed(rendered, botColor)
        end
    end

    if not hasBot then
        clearBotPed(rendered, nil, true)
        rendered.botMatchId = nil
    end
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

function crChessSeatSnapshotFromMatch(snapshot)
    local seats = {}

    if not snapshot then
        return {
            seats = seats
        }
    end

    if tonumber(snapshot.white) and tonumber(snapshot.white) > 0 then
        seats.white = {
            source = tonumber(snapshot.white),
            name = snapshot.whiteName or 'White'
        }
    end

    if tonumber(snapshot.black) and tonumber(snapshot.black) > 0 then
        seats.black = {
            source = tonumber(snapshot.black),
            name = snapshot.blackName or 'Black'
        }
    end

    return {
        seats = seats
    }
end

local function isBotColor(snapshot, color)
    return botDifficultyForColor(snapshot, color) ~= nil
end

local function pedForReactionColor(rendered, snapshot, color)
    if not rendered or not snapshot or not color then
        return nil, false, false
    end

    if isBotColor(snapshot, color) then
        ensureBotPedForMatch(snapshot)
        return rendered.botPeds and rendered.botPeds[color] or rendered.botPed, true, true
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

    local player = GetPlayerFromServerId(source)

    if player ~= -1 then
        local ped = GetPlayerPed(player)

        if ped and DoesEntityExist(ped) then
            return ped, false, true
        end
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

    if not rendered then
        return
    end

    local capturedColor = oppositeColor(moveColor)

    if reconcileSeatAvatars then
        reconcileSeatAvatars(rendered, crChessSeatSnapshotFromMatch(snapshot))
    end

    playReactionForColor(rendered, snapshot, moveColor, 'captureByPlayer')
    playReactionForColor(rendered, snapshot, capturedColor, 'capturedByOpponent')
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
    if not snapshot or not lastMove then
        return false
    end

    local actor = tostring(lastMove.actor or '')

    return actor:find('^bot:') ~= nil or isBotColor(snapshot, lastMove.color)
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
        ped = rendered.botPeds and rendered.botPeds[color] or rendered.botPed
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

local function clearLastMoveHoverOutline()
    local entity = lastMoveHover.outlinedEntity

    if entity and DoesEntityExist(entity) and type(SetEntityDrawOutline) == 'function' then
        SetEntityDrawOutline(entity, false)
    end

    lastMoveHover.outlinedEntity = nil
end

local function moveHoverLabel(move)
    if not move then
        return nil
    end

    local piece = move.finalPiece or move.piece
    local name = piece and Config.PieceNames and Config.PieceNames[piece] or piece or 'Piece'

    return ('%s from %s'):format(name, move.from or '?')
end

local function drawLastMoveHover(rendered)
    local move = lastMoveHover.move

    if not lastMoveHover.visible or not rendered or not rendered.board or not move or not move.from or not move.to then
        clearLastMoveHoverOutline()
        return
    end

    drawSquare(rendered, move.from, { r = 255, g = 205, b = 75, a = 120 })
    drawSquare(rendered, move.to, { r = 90, g = 205, b = 255, a = 135 })

    local entity = rendered.pieces and rendered.pieces[move.to] or nil

    if entity and DoesEntityExist(entity) then
        if type(SetEntityDrawOutline) == 'function' then
            if lastMoveHover.outlinedEntity and lastMoveHover.outlinedEntity ~= entity then
                clearLastMoveHoverOutline()
            end

            SetEntityDrawOutline(entity, true)
            SetEntityDrawOutlineColor(255, 214, 82, 255)
            lastMoveHover.outlinedEntity = entity
        end

        local coords = GetEntityCoords(entity)
        drawText3d(vector3(coords.x, coords.y, coords.z + 0.24), moveHoverLabel(move))
        return
    end

    clearLastMoveHoverOutline()

    local offset = squareOffset(move.to)

    if offset then
        local coords = GetOffsetFromEntityInWorldCoords(rendered.board, offset.x, offset.y, offset.z + 0.12)
        drawText3d(vector3(coords.x, coords.y, coords.z), moveHoverLabel(move))
    end
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

function crChessNormalizeCameraMode(mode)
    mode = tostring(mode or ''):lower()

    if mode == 'top' or mode == 'topdown' or mode == 'top_down' then
        return 'topdown'
    end

    if mode == 'normal' or mode == 'angle' or mode == 'angled' or mode == 'default' then
        return 'normal'
    end

    return nil
end

RegisterNetEvent('cr-chess:client:toggleCameraMode', function(mode)
    if spectator.active then
        crChessToggleSpectatorCameraMode(mode)
        return
    end

    local rendered = getActiveRenderedTable()

    if not rendered or (not interaction.enabled and not seated.active and not currentMatch) then
        notify('Sit at a chess table or start chess interaction before changing the chess camera.')
        return
    end

    local nextMode = crChessNormalizeCameraMode(mode)

    if not nextMode then
        nextMode = interaction.cameraMode == 'topdown' and 'normal' or 'topdown'
    end

    interaction.cameraMode = nextMode

    startTableCamera(rendered)

    if nextMode == 'topdown' then
        notify('Chess camera: top-down view. Use /chess_camera normal, G/H, or the UI button to switch back.')
    else
        notify('Chess camera: normal angled view. Use /chess_camera top, G/H, or the UI button for top-down.')
    end
end)

RegisterNetEvent('cr-chess:client:toggleSpectatorMoveFocus', function()
    if not crChessToggleSpectatorMoveFocus() then
        notify('Start spectating a chess match before toggling move focus.')
    end
end)

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
    if spectator.active then
        stopSpectatorMode()
        cb({ ok = true, spectator = true })
        return
    end

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
    lastMoveHover.visible = false
    lastMoveHover.move = nil
    clearLastMoveHoverOutline()
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

RegisterNUICallback('lastMoveHover', function(data, cb)
    data = data or {}

    if data.visible and data.move then
        lastMoveHover.visible = true
        lastMoveHover.move = data.move
    else
        lastMoveHover.visible = false
        lastMoveHover.move = nil
        clearLastMoveHoverOutline()
    end

    cb({ ok = true })
end)

RegisterNUICallback('cameraToggle', function(_, cb)
    TriggerEvent('cr-chess:client:toggleCameraMode')
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

RegisterNUICallback('sideRollPick', function(data, cb)
    data = data or {}
    TriggerServerEvent('cr-chess:server:submitSideRollPick', tonumber(data.tableId), tonumber(data.number))
    cb({ ok = true })
end)

RegisterNUICallback('sideRollClose', function(data, cb)
    data = data or {}
    TriggerServerEvent('cr-chess:server:cancelSideRoll', tonumber(data.tableId) or tableMenu.tableId or seated.tableId)
    sendNui('sideRoll', { visible = false })
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
    elseif action == 'fairSide' then
        TriggerServerEvent('cr-chess:server:startSideRoll', tableId, data.vsBot == true)
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

local function capturedConfigForTarget()
    if tuning.target == 'captured_white' then
        return crChessCapturedConfig('white'), 'white'
    end

    if tuning.target == 'captured_black' then
        return crChessCapturedConfig('black'), 'black'
    end

    return nil, nil
end

local function tuningValue()
    local field = tuningField()
    local seat = seatConfigForTarget()
    local camera = cameraConfigForTarget()
    local captured = capturedConfigForTarget()

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

    if captured then
        captured.offset = captured.offset or { x = 0.0, y = 0.0, z = 0.01 }
        captured.rotation = captured.rotation or { x = 0.0, y = 0.0, z = 0.0 }

        if field == 'x' or field == 'y' or field == 'z' then
            return captured.offset[field]
        end

        if field == 'rotX' then return captured.rotation.x or 0.0 end
        if field == 'rotY' then return captured.rotation.y or 0.0 end
        if field == 'rotZ' then return captured.rotation.z or 0.0 end
    end

    return 0
end

local function setTuningValue(value)
    local field = tuningField()
    local seat = seatConfigForTarget()
    local camera = cameraConfigForTarget()
    local captured = capturedConfigForTarget()

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
    elseif captured then
        captured.offset = captured.offset or { x = 0.0, y = 0.0, z = 0.01 }
        captured.rotation = captured.rotation or { x = 0.0, y = 0.0, z = 0.0 }

        if field == 'x' or field == 'y' or field == 'z' then
            captured.offset[field] = value
        elseif field == 'rotX' then
            captured.rotation.x = value
        elseif field == 'rotY' then
            captured.rotation.y = value
        elseif field == 'rotZ' then
            captured.rotation.z = value
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

    if tuning.target == 'captured_white' or tuning.target == 'captured_black' then
        for _, rendered in pairs(renderedTables) do
            crChessRefreshCapturedPositions(rendered)
        end

        crChessUpdateCapturedTunePreview(getActiveRenderedTable())
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

    local captured, capturedColor = capturedConfigForTarget()

    if captured and capturedColor then
        captured.offset = captured.offset or { x = 0.0, y = 0.0, z = 0.01 }
        captured.rotation = captured.rotation or { x = 0.0, y = 0.0, z = 0.0 }
        captured.columnStep = captured.columnStep or { x = 0.060, y = 0.0, z = 0.0 }
        captured.rowStep = captured.rowStep or { x = 0.0, y = capturedColor == 'white' and -0.050 or 0.050, z = 0.0 }

        return ('Config.CapturedPieces.%s = { offset = { x = %.3f, y = %.3f, z = %.3f }, headingOffset = %.1f, rotation = { x = %.1f, y = %.1f, z = %.1f }, rowSize = %d, columnStep = { x = %.3f, y = %.3f, z = %.3f }, rowStep = { x = %.3f, y = %.3f, z = %.3f } }'):format(
            capturedColor,
            captured.offset.x or 0.0,
            captured.offset.y or 0.0,
            captured.offset.z or 0.0,
            captured.headingOffset or 0.0,
            captured.rotation.x or 0.0,
            captured.rotation.y or 0.0,
            captured.rotation.z or 0.0,
            captured.rowSize or 8,
            captured.columnStep.x or 0.0,
            captured.columnStep.y or 0.0,
            captured.columnStep.z or 0.0,
            captured.rowStep.x or 0.0,
            captured.rowStep.y or 0.0,
            captured.rowStep.z or 0.0
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
    elseif tuning.target == 'captured_white' or tuning.target == 'captured_black' then
        local side = tuning.target == 'captured_white' and 'white' or 'black'
        crChessUpdateCapturedTunePreview(rendered)

        local slot = crChessCapturedOffset(side, 1)
        local marker = GetOffsetFromEntityInWorldCoords(rendered.board, slot.x, slot.y, slot.z + 0.08)
        drawText3d(vector3(marker.x, marker.y, marker.z), tuning.target .. ' start')
        return
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
        notify('Tuning target must be seat_white, seat_black, camera_white, camera_black, captured_white, or captured_black.')
        return
    end

    tuning.target = target
    tuning.fieldIndex = 1
    tuning.enabled = true
    announceTuning()
end)

RegisterNetEvent('cr-chess:client:capturedDirection', function(side, direction)
    side = tostring(side or ''):lower()
    direction = tostring(direction or ''):lower()

    local directions = {
        north = true,
        n = true,
        south = true,
        s = true,
        east = true,
        e = true,
        west = true,
        w = true,
        left = true,
        right = true,
        cw = true,
        ccw = true,
        flip = true,
        opposite = true
    }

    if side ~= 'white' and side ~= 'black' and side ~= 'both' then
        if directions[side] or tonumber(side) then
            direction = side

            if tuning.target == 'captured_white' then
                side = 'white'
            elseif tuning.target == 'captured_black' then
                side = 'black'
            else
                side = 'both'
            end
        else
            notify('Use /chess_captured_flip [white|black|both] north|south|east|west|left|right|flip')
            return
        end
    end

    if direction == '' then
        direction = 'flip'
    end

    local sides = side == 'both' and { 'white', 'black' } or { side }
    local previousTarget = tuning.target
    local changed = false

    for _, capturedSide in ipairs(sides) do
        if crChessSetCapturedDirection(capturedSide, direction) then
            changed = true
            tuning.target = 'captured_' .. capturedSide
            print('[cr-chess tuning] ' .. formatTuningLine())
        end
    end

    tuning.target = previousTarget

    if not changed then
        notify('Direction must be north, south, east, west, left, right, flip, or a degree value.')
        return
    end

    for _, rendered in pairs(renderedTables) do
        crChessRefreshCapturedPositions(rendered)
    end

    notify(('Captured piece layout set: %s %s. Config lines printed in F8.'):format(side, direction))
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

RegisterNetEvent('cr-chess:client:sideRoll', function(data)
    data = data or {}
    setNuiVisible(data.visible ~= false, true)
    sendNui('sideRoll', data)

    if data.state == 'result' and data.whiteName and data.blackName then
        notify(('Side roll complete: %s plays white, %s plays black.'):format(data.whiteName, data.blackName))
    end
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

RegisterNetEvent('cr-chess:client:spectateMatch', function(snapshot)
    if not snapshot then
        return
    end

    observedMatches[snapshot.id] = snapshot
    startSpectatorMode(snapshot)
end)

RegisterNetEvent('cr-chess:client:stopSpectating', function()
    stopSpectatorMode()
    notify('Spectator mode stopped.')
end)

RegisterNetEvent('cr-chess:client:placeSpectatorBet', function(args)
    args = args or {}

    local side = args[1]
    local amount = args[2]
    local matchId = tonumber(args[3]) or spectator.matchId

    if not matchId then
        notify('Spectate a match first or pass a match id: /chess_bet white 100 1')
        return
    end

    TriggerServerEvent('cr-chess:server:placeSpectatorBet', matchId, side, amount)
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

    observedMatches[snapshot.id] = snapshot

    local rendered = renderedTables[snapshot.tableId]

    if rendered then
        if reconcileSeatAvatars then
            reconcileSeatAvatars(rendered, crChessSeatSnapshotFromMatch(snapshot))
        end

        local resetKey = 'match:' .. tostring(snapshot.id)

        if crChessShouldAnimateBoardReset(rendered, snapshot.board, resetKey) then
            crChessAnimateBoardReset(rendered, snapshot.board, resetKey)
        else
            applyLastMove(rendered, snapshot)
            reconcilePieces(rendered, snapshot.board)
            reconcileCaptured(rendered, snapshot.capturedWhite, snapshot.capturedBlack)
        end

        rendered.matchId = snapshot.id
        ensureBotPedForMatch(snapshot)
    end

    if spectator.active and spectator.matchId == snapshot.id then
        spectator.snapshot = snapshot
        updateSpectatorFocus(snapshot)

        if spectatorDuiEnabled() and (spectatorDuiConfig().hideSidePanel ~= false) then
            sendSpectatorDuiSnapshot(snapshot)
        else
            sendSnapshotToNui(snapshot)
        end

        if snapshot.state == 'finished' then
            notify('Spectated chess match finished. Backspace or /chess_spectate_stop exits spectator mode.')
        end
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

    if currentMatch then
        sendSnapshotToNui(currentMatch)
    elseif spectator.active and spectator.snapshot then
        if spectatorDuiEnabled() and (spectatorDuiConfig().hideSidePanel ~= false) then
            sendSpectatorDuiSnapshot(spectator.snapshot)
        else
            sendSnapshotToNui(spectator.snapshot)
        end
    end
end)

CreateThread(function()
    while true do
        local shouldDrawLight = Config.BoardLight and Config.BoardLight.enabled ~= false and next(renderedTables) ~= nil
        local hasLightNearby = shouldDrawLight and hasNearbyBoardLight()
        local hasHiddenRemoteSeats = next(hiddenRemoteSeatSources) ~= nil
        local ambientDuiTargets = crChessAmbientDuiTargets()
        local hasAmbientDui = #ambientDuiTargets > 0

        if interaction.enabled or tuning.enabled or uvDebug.enabled or seated.active or currentMatch or spectator.active or lastMoveHover.visible or hasLightNearby or hasHiddenRemoteSeats or hasAmbientDui then
            local rendered = getActiveRenderedTable()
            Wait(0)

            maintainSeatAvatarVisibility()

            if not tuning.enabled and not tablePlacement.active and (spectator.active or currentMatch or seated.active or interaction.enabled) then
                if IsControlJustPressed(0, 47)
                    or IsDisabledControlJustPressed(0, 47)
                    or IsControlJustPressed(0, 74)
                    or IsDisabledControlJustPressed(0, 74)
                then
                    TriggerEvent('cr-chess:client:toggleCameraMode')
                end
            end

            if spectator.active then
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
                DisableControlAction(0, 14, true)
                DisableControlAction(0, 15, true)
                DisableControlAction(0, 241, true)
                DisableControlAction(0, 242, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
                DisableControlAction(0, 38, true)
                updateSpectatorCamera()
                drawText2d(0.018, 0.82, 'Spectating chess match', 0.32)
                drawText2d(0.018, 0.85, 'Mouse: orbit/height | Wheel: zoom | G: top-down | E: move focus | Backspace: exit', 0.28)

                if IsControlJustPressed(0, 38) or IsDisabledControlJustPressed(0, 38) then
                    crChessToggleSpectatorMoveFocus()
                elseif IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 177) then
                    stopSpectatorMode()
                    notify('Spectator mode stopped.')
                end
            end

            if spectator.active then
                drawSpectatorDui(spectator.tableId and renderedTables[spectator.tableId] or rendered)
            elseif hasAmbientDui then
                local activeAmbientDuis = {}

                for _, target in ipairs(ambientDuiTargets) do
                    activeAmbientDuis[target.tableId] = true
                    crChessMaybeSyncAmbientDui(target.snapshot)
                    crChessMaybeRequestAttractMode(target.tableId, target.snapshot)
                    crChessDrawAmbientSpectatorDui(target.tableId, target.rendered, target.snapshot)
                end

                crChessDestroyStaleAmbientDuis(activeAmbientDuis)
            else
                crChessDestroyStaleAmbientDuis({})
            end

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

            if rendered and lastMoveHover.visible then
                drawLastMoveHover(rendered)
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

        for _, rendered in pairs(renderedTables) do
            if useRemoteSeatAvatars() then
                reconcileSeatAvatars(rendered, rendered.snapshot or {})
            end

            crChessPurgeDuplicateBotPeds(rendered)
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
    stopSpectatorMode(false)
    releaseSeat()
    deleteTunePreview()
    cleanupTablePlacementPreview()
    restoreAllRemoteSeatSources()

    for tableId in pairs(renderedTables) do
        cleanupTable(tableId)
    end
end)
