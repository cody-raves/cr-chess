fx_version 'cerulean'
lua54 'yes'
game 'gta5'

name 'cr-chess'
version '0.1.0'
description 'Standalone server-authoritative chess with BZZZ prop rendering'
author 'CR'

dependency 'bzzz_chess'

ui_page 'html/index.html'

shared_scripts {
    'shared/config.lua'
}

server_scripts {
    'server/chess_engine.lua',
    'server/bot.lua',
    'server/stats.lua',
    'server/main.lua'
}

client_scripts {
    'client/commands.lua',
    'client/renderer.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/spectator.html',
    'html/spectator.css',
    'html/spectator.js',
    'html/sfx/*.ogg'
}
