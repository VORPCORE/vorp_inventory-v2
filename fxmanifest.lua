fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

game 'rdr3'
author 'VORP @outsider'
name 'vorp inventory'
description 'Inventory System for vorp core framework'


shared_scripts {
  "@vorp_lib/import.lua",
  "config/config.lua",
  "config/crafting.lua",
  "config/weapons.lua",
  "config/ammo.lua",
  "languages/*.lua",
  "shared/models/*.lua",
  "shared/services/*.lua",
  "shared/services/Regex.js",
}

client_scripts {
  'client/exports.lua',
  "config/groups.lua",
  'client/client.lua',
  'client/models/*.lua',
  'client/services/*.lua',
  'client/controllers/*.lua',
}

server_scripts {
  "config/config_server.lua",
  '@oxmysql/lib/MySQL.lua',
  'server/vorpInventoryApi.lua',
  'server/server.lua',
  'server/models/*.lua',
  'server/services/*.lua',
  'server/controllers/*.lua',

}

files {
  'files/reloadspeeds.meta',
  'html/**/*'
}
ui_page 'html/ui.html'

---@deprecated
server_exports { 'vorp_inventoryApi' }


version '1.1'
vorp_checker 'yes'
vorp_name '^4Resource version Check^3'
vorp_github 'https://github.com/VORPCORE/vorp_inventory-v2'


data_file 'WEAPONINFO_FILE_PATCH' 'files/reloadspeeds.meta'
