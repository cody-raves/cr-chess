CRChess = CRChess or {}

local Stats = {
    players = {},
    matches = {}
}

CRChess.Stats = Stats

local function defaultRating()
    return Config and Config.DefaultRating or 800
end

local function eloK()
    return Config and Config.EloK or 32
end

local function newPlayer(identifier, name)
    return {
        identifier = identifier,
        name = name or identifier,
        rating = defaultRating(),
        casualWins = 0,
        casualLosses = 0,
        casualDraws = 0,
        rankedWins = 0,
        rankedLosses = 0,
        rankedDraws = 0,
        botWins = 0,
        botLosses = 0,
        botDraws = 0,
        gamesPlayed = 0
    }
end

function Stats.ensure(identifier, name)
    if not identifier then
        return nil
    end

    if not Stats.players[identifier] then
        Stats.players[identifier] = newPlayer(identifier, name)
    elseif name and name ~= '' then
        Stats.players[identifier].name = name
    end

    return Stats.players[identifier]
end

local function expectedScore(ratingA, ratingB)
    return 1 / (1 + 10 ^ ((ratingB - ratingA) / 400))
end

local function applyElo(playerA, playerB, scoreA)
    local expectedA = expectedScore(playerA.rating, playerB.rating)
    local expectedB = expectedScore(playerB.rating, playerA.rating)
    local scoreB = 1 - scoreA
    local k = eloK()

    playerA.rating = math.max(0, math.floor(playerA.rating + k * (scoreA - expectedA) + 0.5))
    playerB.rating = math.max(0, math.floor(playerB.rating + k * (scoreB - expectedB) + 0.5))
end

local function markResult(player, bucket, result)
    player.gamesPlayed = player.gamesPlayed + 1

    if bucket == 'bot' then
        if result == 'win' then player.botWins = player.botWins + 1 end
        if result == 'loss' then player.botLosses = player.botLosses + 1 end
        if result == 'draw' then player.botDraws = player.botDraws + 1 end
        return
    end

    if bucket == 'ranked' then
        if result == 'win' then player.rankedWins = player.rankedWins + 1 end
        if result == 'loss' then player.rankedLosses = player.rankedLosses + 1 end
        if result == 'draw' then player.rankedDraws = player.rankedDraws + 1 end
        return
    end

    if result == 'win' then player.casualWins = player.casualWins + 1 end
    if result == 'loss' then player.casualLosses = player.casualLosses + 1 end
    if result == 'draw' then player.casualDraws = player.casualDraws + 1 end
end

function Stats.recordMatch(match)
    local whiteIsBot = match.whiteIdentifier and match.whiteIdentifier:sub(1, 4) == 'bot:'
    local blackIsBot = match.blackIdentifier and match.blackIdentifier:sub(1, 4) == 'bot:'
    local white = not whiteIsBot and Stats.ensure(match.whiteIdentifier, match.whiteName) or nil
    local black = not blackIsBot and Stats.ensure(match.blackIdentifier, match.blackName) or nil

    if match.mode == 'bot' then
        local player = white or black

        if player then
            if match.result == 'draw' then
                markResult(player, 'bot', 'draw')
            elseif match.winnerIdentifier == player.identifier then
                markResult(player, 'bot', 'win')
            else
                markResult(player, 'bot', 'loss')
            end
        end

        Stats.addMatchHistory(match)
        return
    end

    if not white or not black then
        Stats.addMatchHistory(match)
        return
    end

    local whiteResult = 'draw'
    local blackResult = 'draw'

    if match.winnerIdentifier == white.identifier then
        whiteResult = 'win'
        blackResult = 'loss'
    elseif match.winnerIdentifier == black.identifier then
        whiteResult = 'loss'
        blackResult = 'win'
    end

    markResult(white, match.mode, whiteResult)
    markResult(black, match.mode, blackResult)

    if match.mode == 'ranked' then
        local scoreA = whiteResult == 'win' and 1 or (whiteResult == 'draw' and 0.5 or 0)
        applyElo(white, black, scoreA)
    end

    Stats.addMatchHistory(match)
end

function Stats.leaderboard(limit)
    local rows = {}

    for _, player in pairs(Stats.players) do
        rows[#rows + 1] = player
    end

    table.sort(rows, function(a, b)
        if a.rating == b.rating then
            return a.name < b.name
        end

        return a.rating > b.rating
    end)

    limit = limit or 10

    while #rows > limit do
        rows[#rows] = nil
    end

    return rows
end

function Stats.leaderboardRows(limit)
    local players = Stats.leaderboard(limit)
    local rows = {}

    for index, player in ipairs(players) do
        rows[#rows + 1] = {
            rank = index,
            identifier = player.identifier,
            name = player.name,
            rating = player.rating,
            rankName = Stats.rankName(player.rating),
            gamesPlayed = player.gamesPlayed
        }
    end

    return rows
end

function Stats.playerSummary(identifier, name)
    if not identifier then
        return nil
    end

    if identifier:sub(1, 4) == 'bot:' then
        return {
            identifier = identifier,
            name = name or 'Bot',
            rating = nil,
            rankName = 'Bot',
            gamesPlayed = 0
        }
    end

    local player = Stats.ensure(identifier, name)

    if not player then
        return nil
    end

    return {
        identifier = player.identifier,
        name = player.name,
        rating = player.rating,
        rankName = Stats.rankName(player.rating),
        gamesPlayed = player.gamesPlayed
    }
end

function Stats.addMatchHistory(match)
    local record = {
        id = match.id,
        mode = match.mode,
        result = match.result,
        finishReason = match.finishReason,
        whiteIdentifier = match.whiteIdentifier,
        blackIdentifier = match.blackIdentifier,
        whiteName = match.whiteName,
        blackName = match.blackName,
        winnerIdentifier = match.winnerIdentifier,
        startedAt = match.startedAt,
        endedAt = match.endedAt,
        wagerAmount = match.wagerAmount,
        wagerPot = match.wagerPot,
        moveCount = #(match.moveHistory or {}),
        finalFen = match.state and CRChess.Engine and CRChess.Engine.toFen(match.state) or nil,
        review = match.review
    }

    Stats.matches[#Stats.matches + 1] = record

    while #Stats.matches > 200 do
        table.remove(Stats.matches, 1)
    end
end

local function averageAccuracyFor(identifier)
    local total = 0
    local count = 0

    for _, match in ipairs(Stats.matches) do
        if match.review then
            if match.whiteIdentifier == identifier and match.review.whiteAccuracy then
                total = total + match.review.whiteAccuracy
                count = count + 1
            elseif match.blackIdentifier == identifier and match.review.blackAccuracy then
                total = total + match.review.blackAccuracy
                count = count + 1
            end
        end
    end

    if count == 0 then
        return 0
    end

    return math.floor(total / count + 0.5)
end

function Stats.profile(identifier)
    local player = Stats.players[identifier]

    if not player then
        return nil
    end

    local recent = {}

    for index = #Stats.matches, 1, -1 do
        local match = Stats.matches[index]

        if match.whiteIdentifier == identifier or match.blackIdentifier == identifier then
            recent[#recent + 1] = match
        end

        if #recent >= 10 then
            break
        end
    end

    return {
        identifier = player.identifier,
        name = player.name,
        rating = player.rating,
        rankName = Stats.rankName(player.rating),
        gamesPlayed = player.gamesPlayed,
        casualWins = player.casualWins,
        casualLosses = player.casualLosses,
        casualDraws = player.casualDraws,
        rankedWins = player.rankedWins,
        rankedLosses = player.rankedLosses,
        rankedDraws = player.rankedDraws,
        botWins = player.botWins,
        botLosses = player.botLosses,
        botDraws = player.botDraws,
        accuracy = averageAccuracyFor(identifier),
        matches = recent
    }
end

function Stats.rankName(rating)
    if rating < 800 then return 'Bronze' end
    if rating < 1000 then return 'Silver' end
    if rating < 1200 then return 'Gold' end
    if rating < 1400 then return 'Platinum' end
    if rating < 1600 then return 'Diamond' end
    if rating < 1800 then return 'Master' end
    return 'Grandmaster'
end
