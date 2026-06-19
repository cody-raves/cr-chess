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
    }
}

Config.BotPed = {
    model = 'mp_m_freemode_01',
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
