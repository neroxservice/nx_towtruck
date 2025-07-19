fx_version 'cerulean'
game 'gta5'

author 'mikrovonka366'
description 'Parking ticket'
version '1.0.0'


dependencies {
    'es_extended',
    'oxmysql'
}

server_scripts {
	'@mysql-async/lib/MySQL.lua',
	'server.lua'
}

client_script 'client.lua'
shared_script 'config.lua'

ui_page 'html/dispatch.html'
files {
    'html/dispatch.html',
    'html/dispatch.js',
    'html/dispatch.css'
}