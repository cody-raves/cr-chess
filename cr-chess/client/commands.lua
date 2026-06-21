local function chat(message)
    TriggerEvent('chat:addMessage', {
        color = { 220, 220, 220 },
        multiline = true,
        args = { 'Chess', message }
    })
end

local function playerCoords()
    local coords = GetEntityCoords(PlayerPedId())

    return {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }
end

RegisterNetEvent('cr-chess:client:notify', function(message)
    chat(message)
end)

RegisterCommand('chess_help', function()
    chat(table.concat({
        '/chess_table_spawn (preview placement)',
        '/chess_table_delete <tableId>',
        '/chess_table_cleanup [range]',
        '/chess_table_blip <tableId> on|off|toggle [label]',
        '/chess_create casual',
        '/chess_create ranked',
        '/chess_create bot easy|medium|hard',
        '/chess_test_bots [whiteDifficulty] [blackDifficulty]',
        '/chess_spectate [matchId]',
        '/chess_spectate_stop',
        '/chess_spectate_focus',
        '/chess_bet white|black <amount> [matchId]',
        '/chess_interact',
        '/chess_camera [normal|top] (or G/H while playing/spectating)',
        '/chess_menu',
        '/chess_sound take|taken|win|lose|draw [index]',
        '/chess_sound sfx/take_piece.ogg',
        '/chess_sound <soundName> <soundSet>',
        '/chess_anim take|taken|win|lose|draw',
        '/chess_tune',
        '/chess_tune_target seat_white|seat_black|camera_white|camera_black|captured_white|captured_black',
        '/chess_captured_flip [white|black|both] north|south|east|west|left|right|flip',
        '/chess_light',
        '/chess_uv_debug',
        '/chess_gizmo_seat white|black',
        '/chess_sit',
        '/chess_stand',
        '/chess_join <matchId> white|black',
        '/chess_move <from> <to> [q|r|b|n]',
        '/chess_board',
        '/chess_resign',
        '/chess_stats',
        '/chess_leaderboard'
    }, '\n'))
end, false)

RegisterCommand('chess_table_spawn', function()
    TriggerEvent('cr-chess:client:startTablePlacement')
end, false)

RegisterCommand('chess_table_delete', function(_, args)
    TriggerServerEvent('cr-chess:server:deleteTable', args[1])
end, false)

RegisterCommand('chess_table_cleanup', function(_, args)
    TriggerServerEvent('cr-chess:server:cleanupTablesNear', playerCoords(), tonumber(args[1]))
end, false)

RegisterCommand('chess_table_blip', function(_, args)
    local tableId = args[1]
    local state = args[2]
    local label = nil

    if #args >= 3 then
        label = table.concat(args, ' ', 3)
    end

    TriggerServerEvent('cr-chess:server:setTableBlip', tableId, state, label)
end, false)

RegisterCommand('chess_create', function(_, args)
    TriggerServerEvent('cr-chess:server:createMatch', args, playerCoords())
end, false)

RegisterCommand('chess_test_bots', function(_, args)
    TriggerServerEvent('cr-chess:server:testBotMatch', playerCoords(), args[1] or 'easy', args[2] or args[1] or 'easy')
end, false)

RegisterCommand('chess_spectate', function(_, args)
    TriggerServerEvent('cr-chess:server:spectateMatch', args[1], playerCoords())
end, false)

RegisterCommand('chess_spectate_stop', function()
    TriggerEvent('cr-chess:client:stopSpectating')
end, false)

RegisterCommand('chess_spectate_focus', function()
    TriggerEvent('cr-chess:client:toggleSpectatorMoveFocus')
end, false)

RegisterCommand('chess_bet', function(_, args)
    TriggerEvent('cr-chess:client:placeSpectatorBet', args)
end, false)

RegisterCommand('chess_join', function(_, args)
    TriggerServerEvent('cr-chess:server:joinMatch', args[1], args[2])
end, false)

RegisterCommand('chess_interact', function()
    TriggerEvent('cr-chess:client:toggleInteract')
end, false)

RegisterCommand('chess_camera', function(_, args)
    TriggerEvent('cr-chess:client:toggleCameraMode', args[1])
end, false)

RegisterKeyMapping('chess_camera', 'Toggle chess camera view', 'keyboard', 'H')

RegisterCommand('chess_menu', function()
    TriggerEvent('cr-chess:client:openTableMenu')
end, false)

RegisterCommand('chess_sound', function(_, args)
    TriggerEvent('cr-chess:client:testSound', args)
end, false)

RegisterCommand('chess_anim', function(_, args)
    TriggerEvent('cr-chess:client:testAnimation', args)
end, false)

RegisterCommand('chess_tune', function()
    TriggerEvent('cr-chess:client:toggleTune')
end, false)

RegisterCommand('chess_tune_target', function(_, args)
    TriggerEvent('cr-chess:client:setTuneTarget', args[1])
end, false)

RegisterCommand('chess_captured_flip', function(_, args)
    TriggerEvent('cr-chess:client:capturedDirection', args[1], args[2])
end, false)

RegisterCommand('chess_light', function()
    TriggerEvent('cr-chess:client:toggleBoardLight')
end, false)

RegisterCommand('chess_uv_debug', function()
    TriggerEvent('cr-chess:client:toggleUvDebug')
end, false)

RegisterCommand('chess_gizmo_seat', function(_, args)
    TriggerEvent('cr-chess:client:gizmoSeat', args[1])
end, false)

RegisterCommand('chess_sit', function()
    TriggerEvent('cr-chess:client:forceSeat')
end, false)

RegisterCommand('chess_stand', function()
    TriggerServerEvent('cr-chess:server:standFromTable')
end, false)

RegisterCommand('chess_move', function(_, args)
    TriggerServerEvent('cr-chess:server:move', args[1], args[2], args[3])
end, false)

RegisterCommand('chess_board', function()
    TriggerServerEvent('cr-chess:server:board')
end, false)

RegisterCommand('chess_resign', function()
    TriggerServerEvent('cr-chess:server:resign')
end, false)

RegisterCommand('chess_stats', function()
    TriggerServerEvent('cr-chess:server:stats')
end, false)

RegisterCommand('chess_leaderboard', function()
    TriggerServerEvent('cr-chess:server:leaderboard')
end, false)
