# cr-chess

Standalone FiveM chess POC with server-authoritative rules and local BZZZ prop rendering.

## Install

1. Keep the `bzzz_chess` prop resource installed and started.
2. Start `oxmysql` before `cr-chess` when `Config.TablePersistence.enabled = true`.
3. `cr-chess` auto-creates its SQL tables by default with `Config.TablePersistence.autoInstall = true`.
4. Put this `cr-chess` folder in your server resources.
5. Add the resources to `server.cfg` in this order:

```cfg
ensure bzzz_chess
ensure oxmysql
ensure cr-chess
```

## Commands

```text
/chess_help
/chess_table_spawn
/chess_table_delete <tableId>
/chess_table_cleanup [range]
/chess_table_blip <tableId> on|off|toggle [label]
/chess_create casual
/chess_create ranked
/chess_create bot easy
/chess_create bot medium
/chess_create bot hard
/chess_interact
/chess_menu
/chess_sound take|taken|win|lose|draw [index]
/chess_sound <soundName> <soundSet>
/chess_anim take|taken|win|lose|draw
/chess_tune
/chess_tune_target seat_white|seat_black|camera_white|camera_black
/chess_light
/chess_uv_debug
/chess_gizmo_seat white
/chess_gizmo_seat black
/chess_sit
/chess_stand
/chess_join <matchId> white
/chess_join <matchId> black
/chess_move <from> <to> [q|r|b|n]
/chess_board
/chess_resign
/chess_stats
/chess_leaderboard
```

`/chess_table_spawn` uses the placement preview and saves the table to SQL when table persistence is enabled. `/chess_table_delete` and `/chess_table_cleanup` remove saved rows too. Map blips are saved with the table row and can be changed with `/chess_table_blip`.

`sql/install.sql` is still included as a reference/manual fallback, but admins do not need to run it when auto-install is enabled.

## Physical Interaction

Use `/chess_interact` while near your chess table or while in a table-bound match.

In interaction mode:

- A table-focused scripted camera opens.
- The NUI cursor is enabled, so selection uses your mouse instead of player aim.
- Invisible UV picking maps mouse clicks to `a1` through `h8`.
- Right-click a physical board piece to ask the server for legal moves.
- Green squares are legal empty destinations.
- Red squares are legal captures.
- Right-click a highlighted physical square to move there.
- The NUI side panel also has a clickable 2D board, move list, review summary, leaderboard, and player profile view.
- Selected pieces get a glow/outline and a floating piece-name label.
- Captures show a short NUI message and play local feedback sounds for taking or losing a piece.
- Finished games show a win, draw, or lose overlay with the review metrics.

The client only uses highlights as guidance. The server still validates the final move before applying it.

Use `/chess_uv_debug` to show the UV grid. While it is enabled, clicks print their resolved square to F8.

Use `/chess_light` to toggle the client-side board spotlight. It is configured in `Config.BoardLight` and draws for every chess table within `Config.BoardLight.drawDistance`, so nearby spectators can see the lit board too.

## Target Seating and Table Menu

If `ox_target` or `qb-target` is started, each spawned chess table gets target options:

- Sit as White
- Sit as Black
- Chess Menu

Use `/chess_menu` near a table as a fallback when no target resource is running.

After sitting, the table menu can start:

- Bot games with easy, medium, or hard difficulty
- Casual 1v1 by inviting a nearby player or waiting for the opponent seat
- Ranked 1v1 by inviting a nearby player or waiting for the opponent seat
- Ranked wager matches using the configured wager presets

Dead positions such as king vs king, king and bishop vs king, and king and knight vs king are automatically drawn. Bots can also resign late-game hopeless positions using `Config.BotAI.resign`.

Wagers are optional server-side escrow. `Config.Wagers` auto-detects Qbox, QBCore, or ESX and removes each stake only when both players are ready. A draw refunds both players; a decisive result pays the pot to the winner.

## Seating and Tuning

Players are seated automatically when they join a table-bound match. Bot matches spawn a local bot ped in the opposite seat. Use `/chess_sit` to re-seat yourself and `/chess_stand` to release your ped during testing.

For the local player, `Config.Animations.useSeatAvatarForPlayer = true` uses a cloned seated avatar while the real player ped is hidden/frozen. `Config.Animations.showLocalSeatAvatar = false` keeps your own fake ped hidden from your camera. `Config.Animations.useSeatAvatarsForRemotePlayers = true` shows stable fake seated peds for opponents and spectators.

Captured pieces disappear from the board after a legal capture.

Move landing sounds are played from `html/sfx/*.ogg` after the animated piece reaches its destination. Capture/result sounds use local `.ogg` files from `html/sfx`. Adjust or disable them in `Config.Sounds`.

Capture and result sounds first use local files configured in `Config.Sounds.feedback`, then fall back to native GTA frontend sounds configured in `Config.Sounds.native`.

Test local or native sounds in-game:

```text
/chess_sound take
/chess_sound taken 2
/chess_sound win
/chess_sound draw
/chess_sound lose_piece.ogg
/chess_sound sfx/win_match.ogg
/chess_sound CHECKPOINT_PERFECT HUD_MINI_GAME_SOUNDSET
```

The command prints a Lua snippet to F8 for whichever configured or native sound you played.

Test seated reaction animations in-game:

```text
/chess_anim take
/chess_anim taken
/chess_anim win
/chess_anim lose
/chess_anim draw
```

Reaction animations are configured in `Config.Animations.reactions`. They play as upper-body clips while the ped stays seated, then the ped is snapped back to the tuned seat offset.

Ped hand animations for normal piece movement are disabled by default with `Config.Animations.playMoveAnimation = false`; capture and match-result reactions still play.

Tune offsets in-game:

```text
/chess_tune
/chess_tune_target seat_white
/chess_tune_target seat_black
/chess_tune_target camera_white
/chess_tune_target camera_black
/chess_gizmo_seat white
/chess_gizmo_seat black
```

Tuning controls:

- Mouse wheel: adjust current field
- Shift + mouse wheel: larger adjustment
- E: cycle field
- Q: cycle target
- Backspace: exit tuning

Seat tuning shows a translucent preview ped and supports X/Y/Z plus rotX/rotY/rotZ. Camera tuning supports X/Y/Z for the camera point, lookX/lookY/lookZ for the point it looks at, and FOV. `/chess_tune_target camera` aliases to your current side. The chat output and F8 console print a Lua config line you can copy into `shared/config.lua`.

`/chess_gizmo_seat white|black` optionally uses `object_gizmo` if that resource is installed and started. It is useful for seat placement, but gameplay piece clicking still uses the board UV grid.

## Test

From this folder:

```powershell
lua tests\run.lua
```

The tests cover legal moves, illegal moves, turn order, self-check rejection, captures, checkmate, stalemate, castling, en passant, promotion, FEN output, bot move legality, and ranked leaderboard behavior.
