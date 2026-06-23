CRChess = CRChess or {}

local Engine = CRChess.Engine
local Bot = CRChess.Bot
local Stats = CRChess.Stats

local tables = {}
local matches = {}
local activeByPlayer = {}
local seatedByPlayer = {}
local pendingInvites = {}
local pendingSideRolls = {}
local lastTableSpawnByPlayer = {}
local nextTableId = 1
local nextMatchId = 1
local finishMatch
local getName
local clearTableDemoMatch

math.randomseed(os.time())

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
        name = getName(source)
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
        createdByIdentifier = tableData.createdByIdentifier,
        createdByName = tableData.createdByName,
        persistent = tableData.persistent == true,
        blip = tableData.blip and {
            enabled = tableData.blip.enabled ~= false,
            label = tableData.blip.label,
            sprite = tableData.blip.sprite,
            color = tableData.blip.color,
            scale = tableData.blip.scale,
            shortRange = tableData.blip.shortRange ~= false
        } or nil,
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

local function trimName(value)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:gsub('^%s+', ''):gsub('%s+$', '')

    if value == '' then
        return nil
    end

    return value
end

local function joinCharacterName(first, last)
    first = trimName(first)
    last = trimName(last)

    if first and last then
        return first .. ' ' .. last
    end

    return first or last
end

local function charInfoName(charinfo)
    if type(charinfo) ~= 'table' then
        return nil
    end

    return joinCharacterName(
        charinfo.firstname or charinfo.firstName or charinfo.first_name,
        charinfo.lastname or charinfo.lastName or charinfo.last_name
    ) or trimName(charinfo.name)
end

local function playerDataName(data)
    if type(data) ~= 'table' then
        return nil
    end

    return charInfoName(data.charinfo or data.charInfo)
        or joinCharacterName(
            data.firstname or data.firstName or data.first_name,
            data.lastname or data.lastName or data.last_name
        )
        or trimName(data.name)
end

local function resourceStarted(resource)
    return type(GetResourceState) == 'function' and GetResourceState(resource) == 'started'
end

local function qboxCharacterName(source)
    if not resourceStarted('qbx_core') then
        return nil
    end

    local ok, player = pcall(function()
        return exports['qbx_core']:GetPlayer(source)
    end)

    if not ok or not player then
        return nil
    end

    return playerDataName(player.PlayerData) or playerDataName(player)
end

local function qbCharacterName(source)
    if not resourceStarted('qb-core') then
        return nil
    end

    local ok, core = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)

    if not ok or not core or not core.Functions or not core.Functions.GetPlayer then
        return nil
    end

    local playerOk, player = pcall(function()
        return core.Functions.GetPlayer(source)
    end)

    if not playerOk or not player then
        return nil
    end

    return playerDataName(player.PlayerData) or playerDataName(player)
end

local function esxCharacterName(source)
    if not resourceStarted('es_extended') then
        return nil
    end

    local ok, esx = pcall(function()
        return exports['es_extended']:getSharedObject()
    end)

    if not ok or not esx then
        esx = rawget(_G, 'ESX')
    end

    if not esx or not esx.GetPlayerFromId then
        return nil
    end

    local playerOk, player = pcall(function()
        return esx.GetPlayerFromId(source)
    end)

    if not playerOk or not player then
        return nil
    end

    if type(player.get) == 'function' then
        local firstOk, first = pcall(function()
            return player.get('firstName') or player.get('firstname')
        end)
        local lastOk, last = pcall(function()
            return player.get('lastName') or player.get('lastname')
        end)
        local name = joinCharacterName(firstOk and first or nil, lastOk and last or nil)

        if name then
            return name
        end
    end

    if type(player.getName) == 'function' then
        local nameOk, name = pcall(function()
            return player.getName()
        end)

        if nameOk then
            name = trimName(name)

            if name then
                return name
            end
        end
    end

    return playerDataName(player.variables) or playerDataName(player)
end

local function identityFramework()
    local identity = Config.Identity or {}
    local framework = tostring(identity.framework or identity.system or 'auto'):lower()

    if framework == 'qbcore' or framework == 'qb-core' then
        framework = 'qb'
    end

    if framework == 'qbox' or framework == 'qb' or framework == 'esx' or framework == 'none' then
        return framework
    end

    return 'auto'
end

local function identityFrameworkOrder()
    local configured = identityFramework()

    if configured == 'none' then
        return {}
    end

    if configured ~= 'auto' then
        return { configured }
    end

    local order = {}
    local seen = {}

    local function add(framework)
        framework = tostring(framework or ''):lower()

        if framework == 'qbcore' or framework == 'qb-core' then
            framework = 'qb'
        end

        if (framework == 'qbox' or framework == 'qb' or framework == 'esx') and not seen[framework] then
            seen[framework] = true
            order[#order + 1] = framework
        end
    end

    if Config.Wagers and Config.Wagers.framework and Config.Wagers.framework ~= 'auto' then
        add(Config.Wagers.framework)
    end

    add('qbox')
    add('qb')
    add('esx')

    return order
end

local function frameworkCharacterName(source, framework)
    if framework == 'qbox' then
        return qboxCharacterName(source)
    end

    if framework == 'qb' then
        return qbCharacterName(source)
    end

    if framework == 'esx' then
        return esxCharacterName(source)
    end

    return nil
end

getName = function(source)
    if source == 0 then
        return 'Console'
    end

    for _, framework in ipairs(identityFrameworkOrder()) do
        local name = frameworkCharacterName(source, framework)

        if name then
            return name
        end
    end

    return GetPlayerName(source) or ('Player %s'):format(source)
end

local persistenceWarned = false
local persistentTablesLoadStarted = false
local databaseSchemaInstallStarted = false
local databaseSchemaInstalled = false
local databaseSchemaCallbacks = {}

local function tableAdminConfig()
    return Config.TableAdmin or {}
end

local function canManageTables(source)
    local admin = tableAdminConfig()

    if admin.requireAce ~= true then
        return true
    end

    if source == 0 then
        return true
    end

    return type(IsPlayerAceAllowed) == 'function'
        and IsPlayerAceAllowed(source, admin.ace or 'cr-chess.admin')
end

local function requireTableAdmin(source)
    if canManageTables(source) then
        return true
    end

    notify(source, 'You do not have permission to manage chess tables.')
    return false
end

local function tablePersistenceConfig()
    return Config.TablePersistence or {}
end

local function tablePersistenceEnabled()
    local persistence = tablePersistenceConfig()

    return persistence.enabled == true
end

local function tablePersistenceAutoInstallEnabled()
    local persistence = tablePersistenceConfig()

    return persistence.autoInstall ~= false
end

local function tableBlipConfig()
    return Config.TableBlips or {}
end

local function sqlIdentifier(value, fallback)
    value = tostring(value or fallback or '')

    if value:match('^[%w_]+$') then
        return value
    end

    return fallback
end

local function chessTablesSqlName()
    local persistence = tablePersistenceConfig()

    return ('`%s`'):format(sqlIdentifier(persistence.table, 'chess_tables'))
end

local function warnPersistence(message)
    if persistenceWarned then
        return
    end

    persistenceWarned = true
    print(('[cr-chess] Table persistence disabled: %s'):format(message))
end

local function persistenceQuery(sql, params, callback)
    if not tablePersistenceEnabled() then
        return false
    end

    local persistence = tablePersistenceConfig()
    local driver = tostring(persistence.driver or 'oxmysql'):lower()

    if driver ~= 'oxmysql' then
        warnPersistence(('unsupported driver "%s"'):format(driver))
        return false
    end

    if not resourceStarted('oxmysql') then
        warnPersistence('oxmysql is not started')
        return false
    end

    local ok, err = pcall(function()
        exports.oxmysql:query(sql, params or {}, function(result)
            if callback then
                callback(result or {})
            end
        end)
    end)

    if not ok then
        warnPersistence(err or 'oxmysql query failed')
        return false
    end

    return true
end

local function databaseSchemaStatements()
    return {
        [[
            CREATE TABLE IF NOT EXISTS `chess_players` (
                identifier VARCHAR(64) NOT NULL PRIMARY KEY,
                name VARCHAR(64) NOT NULL,
                rating INT NOT NULL DEFAULT 800,
                casual_wins INT NOT NULL DEFAULT 0,
                casual_losses INT NOT NULL DEFAULT 0,
                casual_draws INT NOT NULL DEFAULT 0,
                ranked_wins INT NOT NULL DEFAULT 0,
                ranked_losses INT NOT NULL DEFAULT 0,
                ranked_draws INT NOT NULL DEFAULT 0,
                bot_wins INT NOT NULL DEFAULT 0,
                bot_losses INT NOT NULL DEFAULT 0,
                bot_draws INT NOT NULL DEFAULT 0,
                games_played INT NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `chess_matches` (
                id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                mode VARCHAR(16) NOT NULL,
                result VARCHAR(32) NOT NULL,
                white_identifier VARCHAR(64),
                black_identifier VARCHAR(64),
                winner_identifier VARCHAR(64),
                starting_fen TEXT,
                final_fen TEXT,
                move_history LONGTEXT,
                started_at TIMESTAMP NULL,
                ended_at TIMESTAMP NULL
            )
        ]],
        ([[
            CREATE TABLE IF NOT EXISTS %s (
                id INT NOT NULL PRIMARY KEY,
                x DOUBLE NOT NULL,
                y DOUBLE NOT NULL,
                z DOUBLE NOT NULL,
                heading DOUBLE NOT NULL DEFAULT 0,
                created_by_identifier VARCHAR(64),
                created_by_name VARCHAR(64),
                blip_enabled TINYINT(1) NOT NULL DEFAULT 1,
                blip_label VARCHAR(64) NOT NULL DEFAULT 'Chess Table',
                blip_sprite INT NOT NULL DEFAULT 280,
                blip_color INT NOT NULL DEFAULT 25,
                blip_scale DOUBLE NOT NULL DEFAULT 0.72,
                blip_short_range TINYINT(1) NOT NULL DEFAULT 1,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        ]]):format(chessTablesSqlName())
    }
end

local function flushDatabaseSchemaCallbacks(success)
    local callbacks = databaseSchemaCallbacks
    databaseSchemaCallbacks = {}

    for _, callback in ipairs(callbacks) do
        callback(success == true)
    end
end

local function ensureDatabaseSchema(callback)
    if not tablePersistenceEnabled() or not tablePersistenceAutoInstallEnabled() then
        if callback then
            callback(true)
        end

        return true
    end

    if databaseSchemaInstalled then
        if callback then
            callback(true)
        end

        return true
    end

    if callback then
        databaseSchemaCallbacks[#databaseSchemaCallbacks + 1] = callback
    end

    if databaseSchemaInstallStarted then
        return true
    end

    databaseSchemaInstallStarted = true

    local statements = databaseSchemaStatements()
    local index = 1

    local function finish(success)
        if success then
            databaseSchemaInstalled = true
            print('[cr-chess] SQL schema is ready.')
        else
            databaseSchemaInstallStarted = false
            print('[cr-chess] SQL schema auto-install could not run.')
        end

        flushDatabaseSchemaCallbacks(success)
    end

    local function runNext()
        if index > #statements then
            finish(true)
            return
        end

        local sql = statements[index]
        index = index + 1

        if not persistenceQuery(sql, {}, runNext) then
            finish(false)
        end
    end

    runNext()
    return true
end

local function boolValue(value, default)
    if value == nil then
        return default
    end

    if value == true or value == 1 or value == '1' or value == 'true' then
        return true
    end

    if value == false or value == 0 or value == '0' or value == 'false' then
        return false
    end

    return default
end

local function numberValue(value, fallback)
    value = tonumber(value)

    if value == nil then
        return fallback
    end

    return value
end

local function tableBlipLabel(tableId)
    local blips = tableBlipConfig()
    local format = blips.labelFormat

    if type(format) == 'string' and format ~= '' then
        local ok, label = pcall(string.format, format, tableId)

        if ok and label and label ~= '' then
            return label
        end
    end

    return blips.label or 'Chess Table'
end

local function defaultTableBlip(tableId)
    local blips = tableBlipConfig()

    return {
        enabled = blips.enabled ~= false,
        label = tableBlipLabel(tableId),
        sprite = numberValue(blips.sprite, 280),
        color = numberValue(blips.color, 25),
        scale = numberValue(blips.scale, 0.72),
        shortRange = blips.shortRange ~= false
    }
end

local function normalizeTableBlip(tableId, blip)
    local normalized = defaultTableBlip(tableId)

    if type(blip) ~= 'table' then
        return normalized
    end

    normalized.enabled = boolValue(blip.enabled, normalized.enabled)
    normalized.label = tostring(blip.label or normalized.label)
    normalized.sprite = numberValue(blip.sprite, normalized.sprite)
    normalized.color = numberValue(blip.color, normalized.color)
    normalized.scale = numberValue(blip.scale, normalized.scale)
    normalized.shortRange = boolValue(blip.shortRange, normalized.shortRange)

    return normalized
end

local function newTableData(tableId, coords, heading, source, options)
    options = options or {}
    tableId = tonumber(tableId)

    return {
        id = tableId,
        coords = {
            x = coords.x,
            y = coords.y,
            z = coords.z
        },
        heading = tonumber(heading) or 0.0,
        createdBy = options.createdBy or source,
        createdByIdentifier = options.createdByIdentifier or (source and getIdentifier(source) or nil),
        createdByName = options.createdByName or (source and getName(source) or nil),
        persistent = options.persistent == true,
        blip = normalizeTableBlip(tableId, options.blip),
        matchId = nil,
        seats = {},
        board = Engine.initialBoard(),
        capturedWhite = {},
        capturedBlack = {}
    }
end

local function savePersistentTable(tableData, source)
    if not tableData then
        return false
    end

    local blip = normalizeTableBlip(tableData.id, tableData.blip)
    tableData.blip = blip

    local sql = ([[
        INSERT INTO %s
            (id, x, y, z, heading, created_by_identifier, created_by_name, blip_enabled, blip_label, blip_sprite, blip_color, blip_scale, blip_short_range)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            x = VALUES(x),
            y = VALUES(y),
            z = VALUES(z),
            heading = VALUES(heading),
            created_by_identifier = VALUES(created_by_identifier),
            created_by_name = VALUES(created_by_name),
            blip_enabled = VALUES(blip_enabled),
            blip_label = VALUES(blip_label),
            blip_sprite = VALUES(blip_sprite),
            blip_color = VALUES(blip_color),
            blip_scale = VALUES(blip_scale),
            blip_short_range = VALUES(blip_short_range)
    ]]):format(chessTablesSqlName())

    return persistenceQuery(sql, {
        tableData.id,
        tableData.coords.x,
        tableData.coords.y,
        tableData.coords.z,
        tableData.heading,
        tableData.createdByIdentifier,
        tableData.createdByName,
        blip.enabled and 1 or 0,
        blip.label,
        blip.sprite,
        blip.color,
        blip.scale,
        blip.shortRange and 1 or 0
    }, function()
        tableData.persistent = true
        broadcastTable(tableData.id)

        if source then
            notify(source, ('Saved chess table %d to SQL.'):format(tableData.id))
        end
    end)
end

local function savePersistentTableBlip(tableData, source)
    if not tableData then
        return false
    end

    if not tableData.persistent then
        return savePersistentTable(tableData, source)
    end

    local blip = normalizeTableBlip(tableData.id, tableData.blip)
    tableData.blip = blip

    local sql = ([[
        UPDATE %s
        SET blip_enabled = ?, blip_label = ?, blip_sprite = ?, blip_color = ?, blip_scale = ?, blip_short_range = ?
        WHERE id = ?
    ]]):format(chessTablesSqlName())

    return persistenceQuery(sql, {
        blip.enabled and 1 or 0,
        blip.label,
        blip.sprite,
        blip.color,
        blip.scale,
        blip.shortRange and 1 or 0,
        tableData.id
    }, function()
        if source then
            notify(source, ('Updated chess table %d blip.'):format(tableData.id))
        end
    end)
end

local function deletePersistentTable(tableId)
    local sql = ('DELETE FROM %s WHERE id = ?'):format(chessTablesSqlName())

    return persistenceQuery(sql, { tableId })
end

local function loadPersistentTables()
    if persistentTablesLoadStarted then
        return
    end

    persistentTablesLoadStarted = true

    ensureDatabaseSchema(function(schemaReady)
        if not schemaReady then
            persistentTablesLoadStarted = false
            return
        end

        local sql = ([[
            SELECT id, x, y, z, heading, created_by_identifier, created_by_name,
                   blip_enabled, blip_label, blip_sprite, blip_color, blip_scale, blip_short_range
            FROM %s
            ORDER BY id ASC
        ]]):format(chessTablesSqlName())

        if not persistenceQuery(sql, {}, function(rows)
            local loaded = 0
            local maxId = nextTableId - 1
            local loadedCoords = {}
            local duplicateIds = {}
            local reuseRange = tonumber(Config.TableSpawnReuseRange) or 1.25

            for _, row in ipairs(rows or {}) do
                local tableId = tonumber(row.id)

                if tableId then
                    local coords = {
                        x = numberValue(row.x, 0.0),
                        y = numberValue(row.y, 0.0),
                        z = numberValue(row.z, 0.0)
                    }

                    local duplicateOf = nil

                    for _, loadedEntry in ipairs(loadedCoords) do
                        local dx = coords.x - loadedEntry.coords.x
                        local dy = coords.y - loadedEntry.coords.y
                        local dz = coords.z - loadedEntry.coords.z

                        if math.sqrt(dx * dx + dy * dy + dz * dz) <= reuseRange then
                            duplicateOf = loadedEntry.id
                            break
                        end
                    end

                    if duplicateOf then
                        duplicateIds[#duplicateIds + 1] = tableId
                        print(('[cr-chess] Removing duplicate persistent table %d near table %d.'):format(tableId, duplicateOf))
                    else
                        tables[tableId] = newTableData(tableId, coords, row.heading, nil, {
                            createdBy = nil,
                            createdByIdentifier = row.created_by_identifier,
                            createdByName = row.created_by_name,
                            persistent = true,
                            blip = {
                                enabled = boolValue(row.blip_enabled, true),
                                label = row.blip_label,
                                sprite = row.blip_sprite,
                                color = row.blip_color,
                                scale = row.blip_scale,
                                shortRange = boolValue(row.blip_short_range, true)
                            }
                        })

                        loadedCoords[#loadedCoords + 1] = {
                            id = tableId,
                            coords = coords
                        }
                        loaded = loaded + 1
                        maxId = math.max(maxId, tableId)
                    end
                end
            end

            for _, duplicateId in ipairs(duplicateIds) do
                deletePersistentTable(duplicateId)
            end

            nextTableId = math.max(nextTableId, maxId + 1)
            print(('[cr-chess] Loaded %d persistent chess table%s.'):format(loaded, loaded == 1 and '' or 's'))
            broadcastTables()
        end) then
            persistentTablesLoadStarted = false
        end
    end)
end

local function distance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function isDemoMatch(match)
    return match and match.demo == true
end

local function nearestTable(coords)
    if not validCoords(coords) then
        return nil
    end

    local maxRange = Config.TableBindRange or 3.0
    local nearest = nil
    local nearestDistance = maxRange

    for _, tableData in pairs(tables) do
        local match = tableData.matchId and matches[tableData.matchId] or nil

        if not tableData.matchId or isDemoMatch(match) or (match and match.stateName == 'finished') then
            local tableDistance = distance(coords, tableData.coords)

            if tableDistance <= nearestDistance then
                nearest = tableData
                nearestDistance = tableDistance
            end
        end
    end

    return nearest
end

local function nearestMatchTable(coords)
    if not validCoords(coords) then
        return nil
    end

    local maxRange = Config.TableBindRange or 3.0
    local nearest = nil
    local nearestDistance = maxRange

    for _, tableData in pairs(tables) do
        if tableData.matchId and matches[tableData.matchId] then
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

    return match and not isDemoMatch(match) and match.stateName ~= 'finished'
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
            clearTableDemoMatch(tableData, false)
            tables[tableId] = nil
            deletePersistentTable(tableId)
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
        return false, ('%s is already seated as %s.'):format(getName(current), color)
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

local function clockInitialMs()
    local clock = Config.Clock or {}
    local initialSeconds = tonumber(clock.initialSeconds)

    if not initialSeconds then
        initialSeconds = (tonumber(clock.initialMinutes) or 10) * 60
    end

    return math.max(1000, math.floor(initialSeconds * 1000))
end

local function clockIncrementMs()
    local clock = Config.Clock or {}

    return math.max(0, math.floor((tonumber(clock.incrementSeconds) or 0) * 1000))
end

local function createMatchClock()
    if Config.Clock and Config.Clock.enabled == false then
        return {
            enabled = false
        }
    end

    local initialMs = clockInitialMs()

    return {
        enabled = true,
        initialMs = initialMs,
        incrementMs = clockIncrementMs(),
        remaining = {
            white = initialMs,
            black = initialMs
        },
        turn = 'white',
        turnStartedAt = nil,
        timeoutToken = 0
    }
end

local function clockEnabled(match)
    return match and match.clock and match.clock.enabled == true
end

local function clockRemaining(match, color, at)
    if not clockEnabled(match) then
        return nil
    end

    local clock = match.clock
    local remaining = (clock.remaining and clock.remaining[color]) or clock.initialMs or clockInitialMs()

    if match.stateName == 'active' and clock.turn == color and clock.turnStartedAt then
        remaining = remaining - math.max(0, (at or nowMs()) - clock.turnStartedAt)
    end

    return math.max(0, math.floor(remaining))
end

local function clockSnapshot(match)
    if not clockEnabled(match) then
        return nil
    end

    local at = nowMs()
    local clock = match.clock

    return {
        enabled = true,
        initialMs = clock.initialMs,
        incrementMs = clock.incrementMs or 0,
        activeColor = match.stateName == 'active' and match.state.turn or nil,
        serverNow = at,
        lowTimeMs = (Config.Clock and Config.Clock.lowTimeMs) or 30000,
        remaining = {
            white = clockRemaining(match, 'white', at),
            black = clockRemaining(match, 'black', at)
        }
    }
end

function crChessSpectatorBetsConfig()
    return Config.SpectatorBets or {}
end

function crChessSpectatorBetsEnabled()
    return crChessSpectatorBetsConfig().enabled == true
end

function crChessIsBotIdentifier(identifier)
    return type(identifier) == 'string' and identifier:sub(1, 4) == 'bot:'
end

function crChessIsHumanVsHumanMatch(match)
    return match
        and match.white
        and match.black
        and match.white ~= 0
        and match.black ~= 0
        and not crChessIsBotIdentifier(match.whiteIdentifier)
        and not crChessIsBotIdentifier(match.blackIdentifier)
end

function crChessSpectatorBetWindowSeconds()
    local config = crChessSpectatorBetsConfig()
    local seconds = tonumber(config.closeAfterSeconds or config.openSeconds or config.windowSeconds)

    if not seconds then
        return 30
    end

    return math.max(0, math.floor(seconds))
end

function crChessSpectatorBetClosesAt(match)
    if not match or not match.startedAt then
        return nil
    end

    return match.startedAt + crChessSpectatorBetWindowSeconds()
end

function crChessSpectatorBetsRemainingSeconds(match)
    local closesAt = crChessSpectatorBetClosesAt(match)

    if not closesAt then
        return 0
    end

    return math.max(0, closesAt - now())
end

function crChessSpectatorBetsOpen(match)
    if not crChessSpectatorBetsEnabled()
        or not crChessIsHumanVsHumanMatch(match)
        or match.stateName ~= 'active'
    then
        return false
    end

    return crChessSpectatorBetsRemainingSeconds(match) > 0
end

function crChessSpectatorBetsSnapshot(match)
    local pools = match and match.spectatorBetPools or {}
    local bets = match and match.spectatorBets or {}
    local count = 0

    for _ in pairs(bets) do
        count = count + 1
    end

    local white = tonumber(pools.white) or 0
    local black = tonumber(pools.black) or 0
    local closeAfterSeconds = crChessSpectatorBetWindowSeconds()
    local closesAt = crChessSpectatorBetClosesAt(match)

    return {
        enabled = crChessSpectatorBetsEnabled() and crChessIsHumanVsHumanMatch(match),
        open = crChessSpectatorBetsOpen(match),
        closeAfterSeconds = closeAfterSeconds,
        closesAt = closesAt,
        serverNow = now(),
        secondsRemaining = crChessSpectatorBetsRemainingSeconds(match),
        count = count,
        total = white + black,
        pools = {
            white = white,
            black = black
        }
    }
end

local function accrueClock(match, at)
    if not clockEnabled(match) or match.stateName ~= 'active' then
        return false, nil
    end

    local clock = match.clock
    local color = clock.turn or match.state.turn

    if not color or not clock.turnStartedAt then
        return false, nil
    end

    local remaining = clockRemaining(match, color, at)

    clock.remaining[color] = remaining
    clock.turnStartedAt = at or nowMs()

    return remaining <= 0, color
end

local function invalidateClockTimeout(match)
    if clockEnabled(match) then
        match.clock.timeoutToken = (match.clock.timeoutToken or 0) + 1
    end
end

local function scheduleClockTimeout(match)
    if not clockEnabled(match) or match.stateName ~= 'active' or type(SetTimeout) ~= 'function' then
        return
    end

    local clock = match.clock
    local at = nowMs()
    local color = match.state.turn

    clock.turn = color
    clock.turnStartedAt = clock.turnStartedAt or at
    clock.timeoutToken = (clock.timeoutToken or 0) + 1

    local token = clock.timeoutToken
    local remaining = clockRemaining(match, color, at) or 0
    local slack = tonumber(Config.Clock and Config.Clock.timeoutSlackMs) or 250

    SetTimeout(math.max(50, remaining + slack), function()
        local current = matches[match.id]

        if not current or not clockEnabled(current) or current.stateName ~= 'active' then
            return
        end

        if current.clock.timeoutToken ~= token then
            return
        end

        local timedOut, timedColor = accrueClock(current, nowMs())

        if timedOut then
            finishMatch(current, 'timeout', Engine.opposite(timedColor))
            return
        end

        scheduleClockTimeout(current)
    end)
end

local function startClock(match)
    if not clockEnabled(match) then
        return
    end

    match.clock.turn = match.state.turn
    match.clock.turnStartedAt = nowMs()
    scheduleClockTimeout(match)
end

local function switchClockAfterMove(match, movingColor)
    if not clockEnabled(match) then
        return true
    end

    if (match.clock.incrementMs or 0) > 0 then
        match.clock.remaining[movingColor] = (match.clock.remaining[movingColor] or 0) + match.clock.incrementMs
    end

    match.clock.turn = match.state.turn
    match.clock.turnStartedAt = nowMs()
    scheduleClockTimeout(match)

    return true
end

local function stopClock(match)
    if not clockEnabled(match) then
        return
    end

    accrueClock(match, nowMs())
    match.clock.turnStartedAt = nil
    invalidateClockTimeout(match)
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

    if status.insufficientMaterial then
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
    local whiteProfile = Stats.playerSummary(match.whiteIdentifier, match.whiteName)
    local blackProfile = Stats.playerSummary(match.blackIdentifier, match.blackName)

    return {
        id = match.id,
        mode = match.mode,
        state = match.stateName,
        demo = match.demo == true,
        tableId = match.tableId,
        white = match.white,
        black = match.black,
        whiteName = match.whiteName,
        blackName = match.blackName,
        whiteRating = whiteProfile and whiteProfile.rating or nil,
        blackRating = blackProfile and blackProfile.rating or nil,
        whiteRank = whiteProfile and whiteProfile.rankName or nil,
        blackRank = blackProfile and blackProfile.rankName or nil,
        players = {
            white = whiteProfile,
            black = blackProfile
        },
        botColor = match.botColor,
        botDifficulty = match.botDifficulty,
        botDifficulties = match.botDifficulties,
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
        spectatorBets = crChessSpectatorBetsSnapshot(match),
        clock = clockSnapshot(match),
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

function crChessAllowedSpectatorBetAmount(amount)
    amount = tonumber(amount) or 0
    amount = math.floor(amount)

    if amount <= 0 then
        return false, 0, 'Choose a positive bet amount.'
    end

    if not crChessSpectatorBetsEnabled() then
        return false, 0, 'Spectator betting is disabled.'
    end

    local amounts = crChessSpectatorBetsConfig().amounts or (Config.Wagers and Config.Wagers.amounts) or {}

    for _, allowed in ipairs(amounts) do
        if amount == tonumber(allowed) then
            return true, amount
        end
    end

    return false, 0, 'Choose one of the configured spectator bet amounts.'
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

function crChessRefundSpectatorBet(match, bet, reason)
    if not bet or bet.amount <= 0 then
        return
    end

    addPlayerMoney(bet.source, bet.amount, bet.account or configuredWagerAccount(), reason or ('cr-chess match %d spectator bet refund'):format(match.id))
    notify(bet.source, ('Your chess spectator bet was refunded: $%d.'):format(bet.amount))
end

function crChessPayoutSpectatorBets(match)
    if not match or match.spectatorBetsPaidOut then
        return
    end

    match.spectatorBetsPaidOut = true

    local bets = match.spectatorBets or {}
    local pools = match.spectatorBetPools or { white = 0, black = 0 }
    local totalPool = (tonumber(pools.white) or 0) + (tonumber(pools.black) or 0)

    if totalPool <= 0 then
        return
    end

    local reason = ('cr-chess match %d spectator bet'):format(match.id)

    if not match.winner then
        for _, bet in pairs(bets) do
            crChessRefundSpectatorBet(match, bet, reason .. ' draw refund')
        end

        return
    end

    local winningPool = tonumber(pools[match.winner]) or 0

    if winningPool <= 0 then
        for _, bet in pairs(bets) do
            crChessRefundSpectatorBet(match, bet, reason .. ' no winning pool refund')
        end

        return
    end

    local houseCutPercent = tonumber(crChessSpectatorBetsConfig().houseCutPercent) or 0
    local distributable = math.floor(totalPool * (100 - houseCutPercent) / 100)

    for _, bet in pairs(bets) do
        if bet.side == match.winner then
            local payout = math.max(0, math.floor(distributable * (bet.amount / winningPool)))

            if payout > 0 then
                local ok, errorMessage = addPlayerMoney(bet.source, payout, bet.account or configuredWagerAccount(), reason .. ' payout')

                if ok then
                    notify(bet.source, ('Your chess spectator bet won: $%d paid out.'):format(payout))
                else
                    print(('[cr-chess] Failed to pay spectator bet for match %d: %s'):format(match.id, tostring(errorMessage)))
                end
            end
        else
            notify(bet.source, ('Your chess spectator bet lost: %s won.'):format(match.winner))
        end
    end
end

function crChessRefundSpectatorBetsForSource(source)
    for _, match in pairs(matches) do
        local bets = match.spectatorBets or {}
        local bet = bets[source]

        if bet and match.stateName ~= 'finished' and not match.spectatorBetsPaidOut then
            crChessRefundSpectatorBet(match, bet, ('cr-chess match %d spectator bet disconnect refund'):format(match.id))
            bets[source] = nil
            match.spectatorBetPools = match.spectatorBetPools or { white = 0, black = 0 }
            match.spectatorBetPools[bet.side] = math.max(0, (tonumber(match.spectatorBetPools[bet.side]) or 0) - bet.amount)
            syncMatch(match)
        end
    end
end

function crChessPlaceSpectatorBet(source, matchId, side, amount)
    matchId = tonumber(matchId)
    side = tostring(side or ''):lower()

    if side ~= 'white' and side ~= 'black' then
        return notify(source, 'Use /chess_bet white|black <amount> [matchId].')
    end

    local match = matchId and matches[matchId] or nil

    if not match then
        return notify(source, 'That chess match was not found.')
    end

    if match.white == source or match.black == source then
        return notify(source, 'Players in the match cannot place spectator bets.')
    end

    if not crChessIsHumanVsHumanMatch(match) then
        return notify(source, 'Spectator betting is only available on player vs player matches.')
    end

    if not crChessSpectatorBetsOpen(match) then
        return notify(source, 'Spectator betting is closed for that match.')
    end

    match.spectatorBets = match.spectatorBets or {}

    if match.spectatorBets[source] then
        return notify(source, 'You already placed a spectator bet on this match.')
    end

    local amountOk, normalizedAmount, amountError = crChessAllowedSpectatorBetAmount(amount)

    if not amountOk then
        return notify(source, amountError)
    end

    local account = crChessSpectatorBetsConfig().account or configuredWagerAccount()
    local ok, errorMessage = removePlayerMoney(source, normalizedAmount, account, ('cr-chess match %d spectator bet'):format(match.id))

    if not ok then
        return notify(source, ('Could not place spectator bet: %s'):format(errorMessage or 'not enough money'))
    end

    match.spectatorBetPools = match.spectatorBetPools or { white = 0, black = 0 }
    match.spectatorBetPools[side] = (tonumber(match.spectatorBetPools[side]) or 0) + normalizedAmount
    match.spectatorBets[source] = {
        source = source,
        identifier = getIdentifier(source),
        name = getName(source),
        side = side,
        amount = normalizedAmount,
        account = account,
        placedAt = now()
    }

    notify(source, ('Spectator bet placed: $%d on %s in match %d.'):format(normalizedAmount, side, match.id))
    syncMatch(match)
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

finishMatch = function(match, reason, winnerColor)
    if match.stateName == 'finished' then
        return
    end

    stopClock(match)
    match.stateName = 'finished'
    match.endedAt = now()
    match.finishReason = reason
    match.winner = winnerColor
    match.winnerIdentifier = winnerColor == 'white' and match.whiteIdentifier
        or (winnerColor == 'black' and match.blackIdentifier or nil)
    match.result = winnerColor and (winnerColor .. '_win') or 'draw'
    match.review = buildReview(match)

    if isDemoMatch(match) then
        if match.tableId and tables[match.tableId] then
            local tableData = tables[match.tableId]

            tableData.matchId = nil
            tableData.board = Engine.initialBoard()
            tableData.capturedWhite = {}
            tableData.capturedBlack = {}
            tableData.demoViewers = {}
            TriggerClientEvent('cr-chess:client:updateMatch', -1, matchSnapshot(match))
            broadcastTable(match.tableId)
        end

        return
    end

    payoutWager(match)
    crChessPayoutSpectatorBets(match)

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

    if status.insufficientMaterial then
        finishMatch(match, 'insufficient_material', nil)
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

local function botResignConfig()
    local botConfig = Config.BotAI or {}
    local resign = botConfig.resign or {}

    return {
        enabled = resign.enabled ~= false,
        minPly = tonumber(resign.minPly) or 24,
        materialDeficit = tonumber(resign.materialDeficit) or 900,
        scoreDeficit = tonumber(resign.scoreDeficit) or 1100,
        chancePercent = tonumber(resign.chancePercent) or 75
    }
end

local function botShouldResign(match, botColor)
    if not match or not botColor or match.stateName ~= 'active' then
        return false
    end

    local config = botResignConfig()

    if not config.enabled then
        return false
    end

    if #(match.moveHistory or {}) < config.minPly then
        return false
    end

    local status = Engine.status(match.state)

    if status.checkmate or status.stalemate or status.insufficientMaterial then
        return false
    end

    local materialScore = Engine.evaluateMaterial(match.state, botColor)

    if materialScore > -config.materialDeficit then
        return false
    end

    local positionalScore = scorePosition(match.state, botColor)

    if positionalScore > -config.scoreDeficit then
        return false
    end

    local chance = math.max(0, math.min(100, config.chancePercent))

    if chance <= 0 then
        return false
    end

    return math.random(100) <= chance
end

local function botDifficultyForColor(match, color)
    if not match or not color then
        return nil
    end

    if match.botDifficulties and match.botDifficulties[color] then
        return match.botDifficulties[color]
    end

    if match.mode == 'bot' and match.botColor == color then
        return match.botDifficulty or 'easy'
    end

    return nil
end

local function scheduleBotTurn(match)
    local botColor = match and match.state and match.state.turn or nil
    local difficulty = botDifficultyForColor(match, botColor)

    if not difficulty or match.stateName ~= 'active' then
        return
    end

    SetTimeout(Config.BotVsBotMoveDelayMs or 850, function()
        runBotTurn(match.id)
    end)
end

local function applyMove(match, color, from, to, promotion, actor, actorSource)
    if match.stateName ~= 'active' then
        return false, 'match is not active'
    end

    local timedOut, timedColor = accrueClock(match, nowMs())

    if timedOut then
        finishMatch(match, 'timeout', Engine.opposite(timedColor))
        return true
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

    switchClockAfterMove(match, color)

    if finishIfNeeded(match) then
        return true
    end

    syncMatch(match)
    scheduleBotTurn(match)

    return true
end

runBotTurn = function(matchId)
    local match = matches[matchId]
    local botColor = match and match.state and match.state.turn or nil
    local difficulty = botDifficultyForColor(match, botColor)

    if not match or match.stateName ~= 'active' or not difficulty then
        return
    end

    if finishIfNeeded(match) then
        return
    end

    if botShouldResign(match, botColor) then
        finishMatch(match, 'bot_resignation', Engine.opposite(botColor))
        return
    end

    local move = Bot.chooseMove(match.state, difficulty)

    if not move then
        finishIfNeeded(match)
        return
    end

    local ok, errorMessage = applyMove(match, botColor, move.from, move.to, move.promotion, 'bot:' .. difficulty, nil)

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
        clock = createMatchClock(),
        startingFen = Engine.toFen(state),
        botColor = options.botColor,
        botDifficulty = options.botDifficulty,
        botDifficulties = options.botDifficulties,
        wagerAmount = options.wagerAmount,
        wagerAccount = options.wagerAmount and configuredWagerAccount() or nil,
        wagerPot = options.wagerAmount and options.wagerAmount * 2 or nil,
        spectatorBets = {},
        spectatorBetPools = {
            white = 0,
            black = 0
        },
        spectatorBetsPaidOut = false
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
    startClock(match)
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

clearTableDemoMatch = function(tableData, shouldBroadcast)
    local match = tableData and tableData.matchId and matches[tableData.matchId] or nil

    if not isDemoMatch(match) then
        return false
    end

    stopClock(match)
    match.stateName = 'finished'
    match.endedAt = now()
    match.finishReason = 'demo_stop'
    match.winner = nil
    match.result = 'draw'

    TriggerClientEvent('cr-chess:client:updateMatch', -1, matchSnapshot(match))

    tableData.matchId = nil
    tableData.board = Engine.initialBoard()
    tableData.capturedWhite = {}
    tableData.capturedBlack = {}
    tableData.demoViewers = {}

    if shouldBroadcast ~= false then
        broadcastTable(tableData.id)
    end

    return true
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

    clearTableDemoMatch(tableData, true)

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

    if tableData then
        clearTableDemoMatch(tableData, true)
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
    startClock(match)

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

local function botDisplayName(difficulty, color)
    return ('%s %s bot'):format(color == 'white' and 'White' or 'Black', difficulty:gsub('^%l', string.upper))
end

local function startBotVsBotMatch(source, coords, whiteDifficulty, blackDifficulty)
    whiteDifficulty = validBotDifficulty(whiteDifficulty or 'easy')
    blackDifficulty = validBotDifficulty(blackDifficulty or whiteDifficulty or 'easy')

    if not whiteDifficulty or not blackDifficulty then
        return notify(source, 'Bot difficulty must be easy, medium, or hard.')
    end

    local tableData = nearestTable(coords)

    if not tableData then
        return notify(source, 'Spawn or stand near an idle chess table first.')
    end

    if tableData.matchId then
        local existing = matches[tableData.matchId]

        if isDemoMatch(existing) then
            clearTableDemoMatch(tableData, true)
            existing = nil
        end

        if existing and existing.stateName ~= 'finished' then
            return notify(source, 'That table already has an active or waiting match.')
        end
    end

    tableData.seats = {}

    local match = createEmptyMatch('bot_test', tableData, {
        botDifficulties = {
            white = whiteDifficulty,
            black = blackDifficulty
        }
    })

    match.stateName = 'active'
    match.startedAt = now()
    startClock(match)
    match.white = 0
    match.black = 0
    match.whiteIdentifier = 'bot:' .. whiteDifficulty .. ':white'
    match.blackIdentifier = 'bot:' .. blackDifficulty .. ':black'
    match.whiteName = botDisplayName(whiteDifficulty, 'white')
    match.blackName = botDisplayName(blackDifficulty, 'black')

    syncMatch(match)
    scheduleBotTurn(match)
    TriggerClientEvent('cr-chess:client:spectateMatch', source, matchSnapshot(match))
    notify(source, ('Started bot test match %d: %s vs %s. Use /chess_spectate %d to watch.'):format(
        match.id,
        match.whiteName,
        match.blackName,
        match.id
    ))
end

local function attractModeConfig()
    return Config.AttractMode or {}
end

local function attractModeEnabled()
    local config = attractModeConfig()

    return config.enabled ~= false
end

local function attractModeDifficulty(color)
    local config = attractModeConfig()
    local difficulty = color == 'black' and config.blackDifficulty or config.whiteDifficulty

    return validBotDifficulty(difficulty or 'easy') or 'easy'
end

local function tableHasRecentDemoViewer(tableData, at)
    if not tableData or not tableData.demoViewers then
        return false
    end

    at = at or nowMs()
    local ttl = tonumber(attractModeConfig().releaseAfterMs) or 15000
    local hasViewer = false

    for viewer, lastSeen in pairs(tableData.demoViewers) do
        local viewerSource = tonumber(viewer)
        local seenAt = tonumber(lastSeen) or 0

        if not viewerSource or not GetPlayerName(viewerSource) or at - seenAt > ttl then
            tableData.demoViewers[viewer] = nil
        else
            hasViewer = true
        end
    end

    return hasViewer
end

local function startDemoMatchForTable(tableData)
    if not attractModeEnabled() or not tableData or tableHasSeats(tableData) then
        return nil
    end

    local existing = tableData.matchId and matches[tableData.matchId] or nil

    if isDemoMatch(existing) and existing.stateName ~= 'finished' then
        return existing
    end

    if existing and existing.stateName ~= 'finished' then
        return nil
    end

    local whiteDifficulty = attractModeDifficulty('white')
    local blackDifficulty = attractModeDifficulty('black')
    local match = createEmptyMatch('demo', tableData, {
        botDifficulties = {
            white = whiteDifficulty,
            black = blackDifficulty
        }
    })

    match.demo = true
    match.stateName = 'active'
    match.startedAt = now()
    match.white = 0
    match.black = 0
    match.whiteIdentifier = 'bot:demo:' .. whiteDifficulty .. ':white'
    match.blackIdentifier = 'bot:demo:' .. blackDifficulty .. ':black'
    match.whiteName = botDisplayName(whiteDifficulty, 'white')
    match.blackName = botDisplayName(blackDifficulty, 'black')
    tableData.demoViewers = tableData.demoViewers or {}

    startClock(match)
    syncMatch(match)
    scheduleBotTurn(match)

    return match
end

local function markAttractTableSeen(source, tableId, coords)
    if not attractModeEnabled() then
        return
    end

    tableId = tonumber(tableId)

    if not tableId or not validCoords(coords) then
        return
    end

    local tableData = tables[tableId]

    if not tableData then
        return
    end

    local range = tonumber(Config.SpectatorDui and Config.SpectatorDui.drawDistance) or 12.0

    if distance(coords, tableData.coords) > range + 4.0 then
        return
    end

    if tableHasSeats(tableData) or tableHasLiveMatch(tableData) then
        return
    end

    tableData.demoViewers = tableData.demoViewers or {}
    tableData.demoViewers[source] = nowMs()
    startDemoMatchForTable(tableData)
end

local function cleanupStaleDemoMatches()
    if not attractModeEnabled() then
        return
    end

    local at = nowMs()

    for _, tableData in pairs(tables) do
        local match = tableData.matchId and matches[tableData.matchId] or nil

        if isDemoMatch(match) and not tableHasRecentDemoViewer(tableData, at) then
            clearTableDemoMatch(tableData, true)
        end
    end
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

    if tableData then
        clearTableDemoMatch(tableData, true)
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
    Stats.ensure(getIdentifier(source), getName(source))
    TriggerClientEvent('cr-chess:client:leaderboardData', source, Stats.leaderboardRows(25))
end

local function sendProfile(source, identifier)
    local sourceIdentifier = getIdentifier(source)

    if not identifier or identifier == sourceIdentifier then
        Stats.ensure(sourceIdentifier, getName(source))
        identifier = sourceIdentifier
    end

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

    clearTableDemoMatch(tableData, true)

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

local function rollParticipantKey(participant)
    if participant.isBot then
        return 'bot'
    end

    return tostring(participant.source)
end

local function sideRollPayload(roll, state)
    local players = {}

    for _, participant in ipairs(roll.players or {}) do
        local key = rollParticipantKey(participant)
        local picked = roll.picks and roll.picks[key] ~= nil

        players[#players + 1] = {
            source = participant.isBot and 0 or participant.source,
            name = participant.name,
            isBot = participant.isBot == true,
            picked = picked,
            pick = state == 'result' and roll.picks and roll.picks[key] or nil,
            distance = participant.distance,
            color = participant.color
        }
    end

    return {
        state = state,
        tableId = roll.tableId,
        target = roll.target,
        players = players,
        winnerName = roll.winnerName,
        whiteName = roll.whiteName,
        blackName = roll.blackName
    }
end

local function sendSideRollToHumans(roll, state)
    local payload = sideRollPayload(roll, state)

    for _, participant in ipairs(roll.players or {}) do
        if not participant.isBot and participant.source and GetPlayerName(participant.source) then
            TriggerClientEvent('cr-chess:client:sideRoll', participant.source, payload)
        end
    end
end

local function sideRollParticipant(roll, source)
    for _, participant in ipairs(roll.players or {}) do
        if not participant.isBot and participant.source == source then
            return participant
        end
    end

    return nil
end

local function sideRollTableHasLiveMatch(tableData)
    return tableHasLiveMatch(tableData)
end

local function sideRollHumanPlayers(roll)
    local players = {}

    for _, participant in ipairs(roll.players or {}) do
        if not participant.isBot and participant.source and GetPlayerName(participant.source) then
            players[#players + 1] = participant
        end
    end

    return players
end

local function assignSideRollSeats(tableData, whiteParticipant, blackParticipant)
    tableData.seats = {}

    local function assign(participant, color)
        participant.color = color

        if participant.isBot then
            return
        end

        tableData.seats[color] = participant.source
        seatedByPlayer[participant.source] = {
            tableId = tableData.id,
            color = color
        }
    end

    assign(whiteParticipant, 'white')
    assign(blackParticipant, 'black')
    broadcastTable(tableData.id)

    for _, participant in ipairs({ whiteParticipant, blackParticipant }) do
        if not participant.isBot and participant.source and GetPlayerName(participant.source) then
            TriggerClientEvent('cr-chess:client:seatedAtTable', participant.source, tableData.id, participant.color, tableSnapshot(tableData))
        end
    end
end

local function resolveSideRoll(roll)
    local tableData = getTable(roll.tableId)

    if tableData then
        clearTableDemoMatch(tableData, true)
    end

    if not tableData or sideRollTableHasLiveMatch(tableData) then
        pendingSideRolls[roll.tableId] = nil
        return
    end

    local first = roll.players[1]
    local second = roll.players[2]

    if not first or not second then
        pendingSideRolls[roll.tableId] = nil
        return
    end

    local firstPick = roll.picks[rollParticipantKey(first)]
    local secondPick = roll.picks[rollParticipantKey(second)]

    if not firstPick or not secondPick then
        return
    end

    local target = nil
    local firstDistance = nil
    local secondDistance = nil

    for _ = 1, 20 do
        target = math.random(1, 100)
        firstDistance = math.abs(firstPick - target)
        secondDistance = math.abs(secondPick - target)

        if firstDistance ~= secondDistance then
            break
        end
    end

    local firstWins = firstDistance < secondDistance

    if firstDistance == secondDistance then
        firstWins = math.random(1, 2) == 1
    end

    first.distance = firstDistance
    second.distance = secondDistance
    roll.target = target

    local whiteParticipant = firstWins and first or second
    local blackParticipant = firstWins and second or first

    roll.winnerName = whiteParticipant.name
    roll.whiteName = whiteParticipant.name
    roll.blackName = blackParticipant.name

    assignSideRollSeats(tableData, whiteParticipant, blackParticipant)
    sendSideRollToHumans(roll, 'result')
    pendingSideRolls[roll.tableId] = nil
end

local function startSideRoll(source, tableId, vsBot)
    tableId = tonumber(tableId)
    local tableData = getTable(tableId)

    if not tableData then
        return notify(source, 'Table not found.')
    end

    clearTableDemoMatch(tableData, true)

    if sideRollTableHasLiveMatch(tableData) then
        return notify(source, 'That table already has an active or waiting match.')
    end

    if activeByPlayer[source] then
        return notify(source, 'You are already in a chess match.')
    end

    local existingRoll = pendingSideRolls[tableId]

    if existingRoll then
        if sideRollParticipant(existingRoll, source) then
            TriggerClientEvent('cr-chess:client:sideRoll', source, sideRollPayload(existingRoll, 'pick'))
            return notify(source, 'Your side roll is already waiting for picks.')
        end

        return notify(source, 'That table already has a side roll in progress.')
    end

    tableData.seats = tableData.seats or {}

    local seated = seatedByPlayer[source]
    local sourceAtTable = seated and seated.tableId == tableId and tableData.seats[seated.color] == source

    if not sourceAtTable then
        local provisionalColor = not tableData.seats.white and 'white' or (not tableData.seats.black and 'black' or nil)

        if not provisionalColor then
            return notify(source, 'Both seats are already taken.')
        end

        local ok, errorMessage = occupySeat(source, tableData, provisionalColor)

        if not ok then
            return notify(source, errorMessage)
        end

        TriggerClientEvent('cr-chess:client:seatedAtTable', source, tableData.id, provisionalColor, tableSnapshot(tableData))
    end

    local opponent = nil

    for _, color in ipairs({ 'white', 'black' }) do
        local seatSource = tableData.seats[color]

        if seatSource and seatSource ~= source and GetPlayerName(seatSource) then
            opponent = seatSource
            break
        end
    end

    if not opponent and not vsBot then
        return notify(source, 'You are seated. Have another player sit, then roll for white.')
    end

    local players = {
        {
            source = source,
            name = getName(source),
            isBot = false
        }
    }

    if opponent then
        players[#players + 1] = {
            source = opponent,
            name = getName(opponent),
            isBot = false
        }
    else
        players[#players + 1] = {
            source = 0,
            name = 'Bot',
            isBot = true
        }
    end

    local roll = {
        tableId = tableId,
        players = players,
        picks = {},
        createdAt = nowMs()
    }

    for _, participant in ipairs(players) do
        if participant.isBot then
            roll.picks[rollParticipantKey(participant)] = math.random(1, 100)
        end
    end

    pendingSideRolls[tableId] = roll
    sendSideRollToHumans(roll, 'pick')
    notify(source, 'Pick a number from 1 to 100. Closest to the roll gets white.')
end

local function submitSideRollPick(source, tableId, number)
    tableId = tonumber(tableId)
    number = math.floor(tonumber(number) or 0)

    local roll = tableId and pendingSideRolls[tableId] or nil

    if not roll then
        return notify(source, 'No side roll is active for that table.')
    end

    local participant = sideRollParticipant(roll, source)

    if not participant then
        return notify(source, 'You are not part of that side roll.')
    end

    if number < 1 or number > 100 then
        TriggerClientEvent('cr-chess:client:sideRoll', source, sideRollPayload(roll, 'pick'))
        return notify(source, 'Choose a number between 1 and 100.')
    end

    roll.picks[rollParticipantKey(participant)] = number
    sendSideRollToHumans(roll, 'waiting')

    for _, player in ipairs(roll.players or {}) do
        if not roll.picks[rollParticipantKey(player)] then
            return
        end
    end

    resolveSideRoll(roll)
end

local function cancelSideRoll(source, tableId)
    tableId = tonumber(tableId)
    local roll = tableId and pendingSideRolls[tableId] or nil

    if not roll or not sideRollParticipant(roll, source) then
        return
    end

    pendingSideRolls[tableId] = nil

    for _, participant in ipairs(sideRollHumanPlayers(roll)) do
        TriggerClientEvent('cr-chess:client:sideRoll', participant.source, {
            visible = false
        })
        notify(participant.source, 'Side roll cancelled.')
    end
end

local function startSeatedBot(source, tableId, color, difficulty)
    local tableData = getTable(tableId)

    if not tableData then
        return notify(source, 'Table not found.')
    end

    if activeByPlayer[source] then
        return notify(source, 'You are already in a chess match.')
    end

    clearTableDemoMatch(tableData, true)

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

    for _, match in pairs(matches) do
        if match.stateName ~= 'finished' then
            TriggerClientEvent('cr-chess:client:updateMatch', source, matchSnapshot(match))
        end
    end
end)

RegisterNetEvent('cr-chess:server:attractTableSeen', function(tableId, coords)
    markAttractTableSeen(source, tableId, coords)
end)

CreateThread(function()
    while true do
        Wait(math.max(1000, math.floor((tonumber(attractModeConfig().heartbeatIntervalMs) or 4000) * 1.5)))
        cleanupStaleDemoMatches()
    end
end)

RegisterNetEvent('cr-chess:server:createTable', function(coords, heading, requestId)
    local source = source

    if not requireTableAdmin(source) then
        return
    end

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

    tables[tableId] = newTableData(tableId, coords, heading, source)

    broadcastTables()
    notify(source, ('Spawned chess table %d.'):format(tableId))

    if tablePersistenceEnabled() then
        if not savePersistentTable(tables[tableId], source) then
            notify(source, 'The table is live for this session, but SQL persistence is unavailable.')
        end
    end
end)

RegisterNetEvent('cr-chess:server:cleanupTablesNear', function(coords, range)
    local source = source

    if not requireTableAdmin(source) then
        return
    end

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

    if not requireTableAdmin(source) then
        return
    end

    if not tableId or not tables[tableId] then
        return notify(source, 'Table not found.')
    end

    local tableData = tables[tableId]

    if tableData.matchId then
        local match = matches[tableData.matchId]

        if isDemoMatch(match) then
            clearTableDemoMatch(tableData, false)
        elseif match and match.stateName ~= 'finished' then
            return notify(source, 'That table has an active or waiting match.')
        end
    end

    tables[tableId] = nil
    deletePersistentTable(tableId)
    broadcastTables()
    notify(source, ('Deleted chess table %d.'):format(tableId))
end)

RegisterNetEvent('cr-chess:server:setTableBlip', function(tableId, state, label)
    local source = source
    tableId = tonumber(tableId)

    if not requireTableAdmin(source) then
        return
    end

    local tableData = tableId and tables[tableId] or nil

    if not tableData then
        return notify(source, 'Table not found.')
    end

    state = tostring(state or ''):lower()

    if state ~= 'on' and state ~= 'off' and state ~= 'toggle' then
        return notify(source, 'Use /chess_table_blip <tableId> on|off|toggle [label].')
    end

    tableData.blip = normalizeTableBlip(tableData.id, tableData.blip)

    if state == 'toggle' then
        tableData.blip.enabled = not tableData.blip.enabled
    else
        tableData.blip.enabled = state == 'on'
    end

    label = trimName(label)

    if label then
        tableData.blip.label = label:sub(1, 64)
    end

    broadcastTable(tableId)

    if tablePersistenceEnabled() then
        if not savePersistentTableBlip(tableData, source) then
            notify(source, 'Updated the live blip, but SQL persistence is unavailable.')
        end
    else
        notify(source, ('Updated chess table %d blip.'):format(tableId))
    end
end)

RegisterNetEvent('cr-chess:server:createMatch', function(args, coords)
    createMatch(source, args or {}, coords)
end)

RegisterNetEvent('cr-chess:server:testBotMatch', function(coords, whiteDifficulty, blackDifficulty)
    startBotVsBotMatch(source, coords, whiteDifficulty, blackDifficulty)
end)

RegisterNetEvent('cr-chess:server:spectateMatch', function(matchId, coords)
    local source = source
    local match = nil

    matchId = tonumber(matchId)

    if matchId then
        match = matches[matchId]
    else
        local tableData = nearestMatchTable(coords)

        if tableData and tableData.matchId then
            match = matches[tableData.matchId]
        end
    end

    if not match then
        return notify(source, 'No chess match found to spectate.')
    end

    if not match.tableId or not tables[match.tableId] then
        return notify(source, 'That match is not bound to a spawned table.')
    end

    TriggerClientEvent('cr-chess:client:spectateMatch', source, matchSnapshot(match))
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

RegisterNetEvent('cr-chess:server:startSideRoll', function(tableId, vsBot)
    startSideRoll(source, tableId, vsBot == true)
end)

RegisterNetEvent('cr-chess:server:submitSideRollPick', function(tableId, number)
    submitSideRollPick(source, tableId, number)
end)

RegisterNetEvent('cr-chess:server:cancelSideRoll', function(tableId)
    cancelSideRoll(source, tableId)
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

RegisterNetEvent('cr-chess:server:placeSpectatorBet', function(matchId, side, amount)
    crChessPlaceSpectatorBet(source, matchId, side, amount)
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

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() and resourceName ~= 'oxmysql' then
        return
    end

    if not tablePersistenceEnabled() then
        return
    end

    SetTimeout(500, loadPersistentTables)
end)

AddEventHandler('playerDropped', function()
    local source = source
    local matchId = activeByPlayer[source]
    local match = matchId and matches[matchId] or nil

    pendingInvites[source] = nil
    lastTableSpawnByPlayer[source] = nil
    crChessRefundSpectatorBetsForSource(source)

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
