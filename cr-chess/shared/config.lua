Config = Config or {}

Config.Debug = false
Config.TableBindRange = 3.0
Config.TableSpawnReuseRange = 1.25
Config.TableCleanupRange = 3.0
Config.TableSpawnCooldownMs = 1500
Config.TablePlacement = {
    rayDistance = 8.0,
    fallbackDistance = 2.0,
    rotateStep = 5.0,
    rotateFastStep = 15.0,
    previewAlpha = 165
}
Config.TableAdmin = {
    requireAce = false,
    ace = 'cr-chess.admin'
}
Config.TablePersistence = {
    enabled = true,
    driver = 'oxmysql',
    table = 'chess_tables',
    autoInstall = true
}
Config.TableBlips = {
    enabled = true,
    labelFormat = 'Chess Table %d',
    sprite = 280,
    color = 25,
    scale = 0.72,
    shortRange = true
}
Config.BotVsBotMoveDelayMs = 850
Config.BotAI = {
    hardDepth = 2,
    hardRootMoveLimit = 14,
    hardBranchMoveLimit = 10,
    resign = {
        enabled = true,
        minPly = 24,
        materialDeficit = 900,
        scoreDeficit = 1100,
        chancePercent = 75
    }
}
Config.Clock = {
    enabled = true,
    initialMinutes = 10,
    incrementSeconds = 0,
    lowTimeMs = 30000,
    timeoutSlackMs = 250
}
Config.Spectator = {
    radius = 0.95,
    minRadius = 0.55,
    maxRadius = 1.65,
    height = 0.72,
    minHeight = 0.35,
    maxHeight = 1.15,
    mouseSensitivity = 135.0,
    verticalSensitivity = 0.55,
    zoomStep = 0.08,
    focusLerp = 2.2,
    cameraLerp = 8.0,
    focusHeight = 0.08,
    lastMoveFocusMs = 2600,
    moveFollowExtraMs = 450,
    fov = 55.0,
    topDown = {
        offset = { x = 0.0, y = 0.0, z = 1.25 },
        lookAt = { x = 0.0, y = 0.0, z = 0.035 },
        fov = 42.0
    }
}
Config.SpectatorDui = {
    enabled = true,
    ambient = true,
    showIdleTables = true,
    drawDistance = 8.0,
    maxAmbientDuis = 4,
    syncIntervalMs = 5000,
    hideSidePanel = true,
    width = 576,
    height = 792,
    screenWidth = 0.205,
    screenHeight = 0.282,
    offset = { x = 0.0, y = 0.0, z = 1.20 },
    distanceScale = {
        enabled = true,
        nearDistance = 2.0,
        farDistance = 8.0,
        nearScreenWidth = 0.205,
        nearScreenHeight = 0.282,
        farScreenWidth = 0.078,
        farScreenHeight = 0.107,
        nearOffsetZ = 1.20,
        farOffsetZ = 1.80,
        nearAlpha = 242,
        farAlpha = 210
    },
    alpha = 242,
    perspective = 'white'
}
Config.AttractMode = {
    enabled = true,
    whiteDifficulty = 'easy',
    blackDifficulty = 'easy',
    heartbeatIntervalMs = 4000,
    releaseAfterMs = 15000
}
Config.SpectatorBets = {
    enabled = true,
    closeAfterSeconds = 30,
    account = 'cash',
    amounts = { 100, 500, 1000 },
    houseCutPercent = 0
}
Config.DefaultRating = 800
Config.EloK = 32

Config.Props = {
    table = 'bzzz_chess_table_a',
    board = 'bzzz_chess_board_a',
    chair = 'bzzz_chess_chair_a',

    pieces = {
        wP = 'bzzz_chess_color_a1',
        wR = 'bzzz_chess_color_a2',
        wN = 'bzzz_chess_color_a3',
        wB = 'bzzz_chess_color_a4',
        wQ = 'bzzz_chess_color_a5',
        wK = 'bzzz_chess_color_a6',

        bP = 'bzzz_chess_color_b1',
        bR = 'bzzz_chess_color_b2',
        bN = 'bzzz_chess_color_b3',
        bB = 'bzzz_chess_color_b4',
        bQ = 'bzzz_chess_color_b5',
        bK = 'bzzz_chess_color_b6'
    }
}

Config.TableBoardOffset = { x = 0.0, y = 0.0, z = 0.4 }

Config.Chairs = {
    { offset = { x = 0.0, y = 0.595, z = -0.180 }, headingOffset = 180.0 },
    { offset = { x = 0.0, y = -0.595, z = -0.180 }, headingOffset = 0.0 }
}

Config.PlayerSeats = {
    white = {
        offset = { x = -0.000, y = -0.850, z = 0.100 },
        headingOffset = 0.0,
        rotation = { x = -3.0, y = -2.0, z = 0.0 }
    },
    black = {
        offset = { x = 0.000, y = 0.850, z = 0.100 },
        headingOffset = 180.0,
        rotation = { x = -2.0, y = 0.0, z = 180.0 }
    }
}

Config.Target = {
    enabled = true,
    system = 'auto', -- auto, ox, qb
    distance = 2.2
}

Config.Invites = {
    range = 4.0
}

Config.Wagers = {
    enabled = true,
    framework = 'auto', -- auto, qbox, qb, esx
    account = 'cash',
    amounts = { 100, 500, 1000 },
    houseCutPercent = 0
}

Config.Identity = {
    framework = 'auto' -- auto, qbox, qb, esx, none
}

Config.Camera = {
    white = {
        offset = { x = 0.000, y = -0.620, z = 0.520 },
        lookAt = { x = 0.000, y = 0.040, z = 0.045 },
        fov = 75.0
    },
    black = {
        offset = { x = 0.000, y = 0.620, z = 0.520 },
        lookAt = { x = 0.000, y = -0.040, z = 0.045 },
        fov = 75.0
    },
    topDown = {
        white = {
            offset = { x = 0.000, y = -0.020, z = 0.900 },
            lookAt = { x = 0.000, y = 0.000, z = 0.020 },
            fov = 42.0
        },
        black = {
            offset = { x = 0.000, y = 0.020, z = 0.900 },
            lookAt = { x = 0.000, y = 0.000, z = 0.020 },
            fov = 42.0
        }
    }
}

Config.CapturedPieces = {
    white = {
        offset = { x = -0.315, y = -0.215, z = 0.000 },
        headingOffset = 0.0,
        rotation = { x = 0.0, y = 0.0, z = 90.0 },
        rowSize = 8,
        columnStep = { x = 0.060, y = 0.000, z = 0.000 },
        rowStep = { x = 0.000, y = -0.050, z = 0.000 }
    },
    black = {
        offset = { x = 0.270, y = -0.210, z = 0.010 },
        headingOffset = 180.0,
        rotation = { x = 0.0, y = 0.0, z = -90.0 },
        rowSize = 8,
        columnStep = { x = -0.060, y = 0.000, z = 0.000 },
        rowStep = { x = 0.000, y = 0.050, z = 0.000 }
    }
}

Config.BotPed = {
    model = 'a_m_y_business_01',
    models = {
        'a_m_y_business_01',
        'a_m_y_business_02',
        'a_m_y_business_03',
        'a_m_m_business_01',
        'a_f_y_business_01',
        'a_f_y_business_02',
        'a_f_y_business_03',
        'a_f_m_business_02',
        'a_m_y_bevhills_01',
        'a_m_y_bevhills_02',
        'a_f_y_bevhills_01',
        'a_f_y_bevhills_02',
        'a_m_y_hipster_01',
        'a_m_y_hipster_02',
        'a_f_y_hipster_01',
        'a_f_y_hipster_02',
        'a_m_y_vinewood_01',
        'a_m_y_vinewood_02',
        'a_f_y_vinewood_01',
        'a_f_y_vinewood_02',
        'a_m_m_tourist_01',
        'a_f_m_tourist_01'
    },
    alpha = 255
}

Config.Tuning = {
    nudgeSmall = 0.005,
    nudgeLarge = 0.025,
    rotateSmall = 1.0,
    rotateLarge = 5.0
}

Config.BoardLight = {
    enabled = true,
    drawDistance = 22.0,
    color = { r = 255, g = 238, b = 205 },
    point = {
        enabled = true,
        offset = { x = 0.0, y = 0.0, z = 0.42 },
        range = 1.15,
        intensity = 3.2
    },
    spot = {
        enabled = true,
        offset = { x = 0.0, y = 0.0, z = 0.95 },
        direction = { x = 0.0, y = 0.0, z = -1.0 },
        distance = 3.2,
        brightness = 2.0,
        hardness = 0.0,
        radius = 90.0,
        falloff = 1.0
    }
}

Config.Sounds = {
    enabled = true,
    volume = 0.55,
    drawDistance = 8.0,
    fadeStartDistance = 4.5,
    move = {
        'sfx/1.ogg',
        'sfx/2.ogg',
        'sfx/3.ogg',
        'sfx/4.ogg',
        'sfx/5.ogg',
        'sfx/6.ogg',
        'sfx/7.ogg',
        'sfx/8.ogg'
    },
    feedback = {
        captureByPlayer = {
            'sfx/take_piece.ogg'
        },
        capturedByOpponent = {
            'sfx/lose_piece.ogg'
        },
        win = {
            'sfx/win_match.ogg'
        },
        draw = {
            'sfx/match_draw.ogg'
        },
        lose = {
            'sfx/lose_match.ogg'
        }
    },
    native = {
        enabled = true,
        captureByPlayer = {
            { name = 'CHECKPOINT_PERFECT', set = 'HUD_MINI_GAME_SOUNDSET' },
            { name = 'PICK_UP', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' }
        },
        capturedByOpponent = {
            { name = 'ERROR', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
            { name = 'TIMER_STOP', set = 'HUD_MINI_GAME_SOUNDSET' }
        },
        win = {
            { name = 'BASE_JUMP_PASSED', set = 'HUD_AWARDS' },
            { name = 'PROPERTY_PURCHASE', set = 'HUD_AWARDS' }
        },
        draw = {
            { name = 'TIMER_STOP', set = 'HUD_MINI_GAME_SOUNDSET' }
        },
        lose = {
            { name = 'LOSER', set = 'HUD_AWARDS' },
            { name = 'ERROR', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' }
        }
    }
}

Config.Animations = {
    dict = 'amb@prop_human_seat_chair@male@generic@base',
    waiting = 'base',
    seat = {
        dict = 'amb@prop_human_seat_chair@male@generic@base',
        name = 'base',
        flag = 1,
        blendIn = 8.0,
        blendOut = -8.0
    },
    bzzzSeat = {
        dict = 'bzzz_chess_animations',
        name = 'bzzz_chess_sit_a',
        flag = 1
    },
    move = {
        dict = 'bzzz_chess_animations',
        name = 'bzzz_chess_sit_b',
        flag = 0
    },
    playMoveAnimation = false,
    playingDuration = 1500,
    pieceMoveDelay = 350,
    useSeatAvatarForPlayer = true,
    showLocalSeatAvatar = false,
    useSeatAvatarsForRemotePlayers = true,
    freezePlayerSeat = true,
    seatRestoreDelays = { 175, 500, 1000 },
    reactionSeat = {
        enabled = false,
        dict = 'amb@prop_human_seat_chair@male@generic@base',
        name = 'base',
        flag = 1,
        settleDelay = 120,
        restoreDelay = 120
    },
    reactions = {
        captureByPlayer = {
            dict = 'gestures@m@standing@casual',
            name = 'gesture_i_will',
            duration = 950,
            flag = 48
        },
        capturedByOpponent = {
            dict = 'gestures@m@standing@casual',
            name = 'gesture_damn',
            duration = 1100,
            flag = 48
        },
        win = {
            dict = 'anim@mp_player_intcelebrationmale@thumbs_up',
            name = 'thumbs_up',
            duration = 1600,
            flag = 48
        },
        lose = {
            dict = 'anim@mp_player_intcelebrationmale@face_palm',
            name = 'face_palm',
            duration = 1700,
            flag = 48
        },
        draw = {
            dict = 'gestures@m@standing@casual',
            name = 'gesture_shrug_hard',
            duration = 1300,
            flag = 48
        }
    }
}

Config.PieceOffset = {
    startX = -0.21,
    startY = -0.21,
    step = 0.06,
    z = 0.002
}

Config.PieceNames = {
    wP = 'White Pawn',
    wR = 'White Rook',
    wN = 'White Knight',
    wB = 'White Bishop',
    wQ = 'White Queen',
    wK = 'White King',
    bP = 'Black Pawn',
    bR = 'Black Rook',
    bN = 'Black Knight',
    bB = 'Black Bishop',
    bQ = 'Black Queen',
    bK = 'Black King'
}
