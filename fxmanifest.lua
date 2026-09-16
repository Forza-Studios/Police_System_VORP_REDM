fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'coi_police'
author '_forza'
description 'Complete police script for VORP'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    'server/server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/img/sheriff_wagon.jpg',
    'html/img/prison_wagon.jpg',
    'html/img/gatling_wagon.jpg',
    'html/img/army_supply_wagon.jpg',
    'html/img/deputy_stagecoach.jpg',
    'html/img/utility_wagon.jpg'
}