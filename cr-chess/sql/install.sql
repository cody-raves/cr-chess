CREATE TABLE IF NOT EXISTS chess_players (
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
);

CREATE TABLE IF NOT EXISTS chess_matches (
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
);

CREATE TABLE IF NOT EXISTS chess_tables (
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
);
