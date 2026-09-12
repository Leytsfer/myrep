-- ============================================================
-- TRADE MARKET CLIENT v6.10.6 (DISCOUNT SYSTEM)
-- ============================================================
local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local computer = require("computer")
local fs = require("filesystem")
local math = require("math")
local os = require("os")
local internet = require("internet")
local serialization = require("serialization")
if type(collectgarbage) ~= "function" then collectgarbage = function() end end
local Config = {
WEB_URL = "https://trade-market.store/vipshop_web/api.php",
WEB_TOKEN = "T8YwYEPytuEbxM40mbwn6sDMEJ20naXz2AJf60t3XscFbkwdwVYURLGeN0CJIxkO",
TERMINAL_ID = "TERM-" .. computer.address():sub(1, 8),
CATALOG_RETRY_INTERVAL = 10, CATALOG_CHECK_INTERVAL = 60,
SCREEN_W = 160, SCREEN_H = 50,
TRANSACTION_TIMEOUT = 25, TRANSACTION_COOLDOWN = 0.5,
SAVE_DB_INTERVAL = 10, PENDING_FLUSH_THRESHOLD = 50, PENDING_FLUSH_INTERVAL = 60,
CATALOG_UPDATE_INTERVAL = 60, TIMEZONE_OFFSET = 3 * 3600,
PRESENCE_HOLD_DELAY = 2, PRESENCE_CONFIRM_DELAY = 1.5,
HEARTBEAT_INTERVAL = 30, PAUSE_GRACE_SECONDS = 30,
FILES = { players = "/home/players.db", buyCatalog = "/home/buyCatalog.lua", sellCatalog = "/home/sellCatalog.lua", reports = "/home/reports.json", pendingChanges = "/home/pending_changes.lua", catalogVersion = "/home/catalogVersion.dat", setsCatalog = "/home/setsCatalog.lua", setsProgress = "/home/setsProgress.lua" }
}
local State = {
currentPlayer = nil, currentSession = nil, pimActive = false, pimOwner = nil,
serverState = { maintenance = false, terminalPaused = false, connected = false },
isShuttingDown = false,
TRANSACTION_LOCK = false, activeTransactionId = nil, transactionStartTime = 0, lastTransactionEndTime = 0, transactionTimeoutShown = false,
catalogsLoaded = false, catalogLoadFailed = false, lastCatalogRetry = 0, lastCatalogCheck = 0,
syncInProgress = false, deferredEvents = {},
lastPimCheck = 0, pimAbsentCount = 0, presenceWorks = false,
autocraftJob = nil, autocraftCraftablesDirty = false, acLastCmd = 0,
acCraftCache = {}, acProbeQueue = {},
guiDirty = false, renderTimer = nil, pendingRenderPart = "full",
modalState = { active = false, kind = nil, data = nil },
currentCategory = "ВСЕ", categoryDropdownOpen = false, categoryDropdownHoverIndex = 0,
currentShopMode = "buy", lastCatalogUpdate = 0, lastStockRefresh = 0, needStockRefresh = false,
currentScreen = "welcome", searchInput = "", searchInputActive = false,
listScroll = 1, visibleRows = 0, selectedIndex = 0, hoveredIndex = 0, selectedItem = nil,
purchaseQuantity = 1, purchaseInputActive = false, sellQuantity = 1, sellInputActive = false, sellPlayerQty = 0,
modalData = nil, buttons = {}, lastRendered = false, screenInitialized = false,
logMessages = {}, logMessageColor = 0x555555, welcomeLog = {}, syncLogs = {}, MAX_SYNC_LOGS = 4,
lastPendingFlush = 0, pendingFullReload = false,
setView = "list", selectedSet = nil, selectedSetItem = nil,
helpPage = 1,
welcomeAnim = 0,
lastWelcomeAnim = 0,
bannedNow = false,
pauseGraceUntil = 0,
lastHeartbeat = 0
}
local Data = {
players = {}, buyCatalog = {}, sellCatalog = {}, reports = {}, pendingChanges = {},
versions = { buy = 0, sell = 0, users = 0, sets = 0 },
buyCatalogDisplay = {}, sellCatalogDisplay = {}, filteredItems = {},
setsCatalog = {}, setsDisplay = {}, setsProgress = {},
categoryOrder = { "ВСЕ", "AE2", "IC2", "OC | OS", "DraconicEvolution", "EnderIO", "Forestry", "MineFactory", "GenDustry | Genetics", "DwCity", "MetaDrive", "Skins" },
categoryTags = {
["ВСЕ"] = nil, ["AE2"] = { "#AE2" }, ["IC2"] = { "#IC2" }, ["OC | OS"] = { "#OC" },
["DraconicEvolution"] = { "#DE" }, ["EnderIO"] = { "#EIO" }, ["Forestry"] = { "#FR" },
["MineFactory"] = { "#MFR" }, ["GenDustry | Genetics"] = { "#GS-GD" }, ["DwCity"] = { "#DWC" },
["MetaDrive"] = { "#MD" }, ["Skins"] = { "#SKINS" } },
}
local UI = {
header = { height = 4, searchX = 2, searchW = 60, clearBtnW = 5, allBtnW = 10, dropdownW = 26, dropdownY = 3 },
list = { x = 1, y = 5, wRatio = 0.55 },
bottom = { height = 3, buttonW = 20, spacing = 2 },
modal = { smallW = 56, smallH = 10, helpW = 140, helpH = 44 },
account = { replenishBtnW = 6 }
}
local Colors = {
bg_main = 0x000000, bg_header = 0x000000, bg_panel = 0x111111, bg_input = 0x222222,
bg_search = 0x111111, bg_button = 0x333333, bg_selected = 0x003366, bg_modal = 0x000000,
bg_dropdown = 0x1a1a2e, bg_dropdown_hover = 0x2a2a4e,
accent_main = 0x8B5CF6, accent_secondary = 0x00E5C9, accent_cyan = 0x00BFFF,
text_main = 0xD0D0E0, text_bright = 0xFFFFFF, text_gray = 0x888888, text_dark = 0x555555,
success = 0x00FFAA, success_green = 0x42DA42, error = 0xFF4D7A, error_red = 0xFF5555,
inactive = 0x555566, warning = 0xFFAA00, tomato = 0xFF6347, white = 0xFFFFFF,
green_bright = 0x47C331, orange = 0xD87300, purple = 0xA252F1, line = 0x3598FC,
blue = 0x1669E4, cyan = 0x00b4ff, dark_gray = 0x666666,
dropdown_border = 0x00BFFF, dropdown_active = 0x0044AA
}
-- ===== КЭШ СНИМКА ME (глобальный, объявлен до всех функций) =====
meSnap = { at = -1, index = {} }

-- ===== СИСТЕМА СКИДОК =====
local DISCOUNT_TIERS = {
{ threshold = 1000, percent = 2 },
{ threshold = 3000, percent = 4 },
{ threshold = 10000, percent = 6 },
{ threshold = 25000, percent = 8 },
{ threshold = 50000, percent = 10 },
}
function getDiscountInfo(spentCoin, spentEma)
local total = (spentCoin or 0) + (spentEma or 0)
local level, percent = 0, 0
for i, t in ipairs(DISCOUNT_TIERS) do
if total >= t.threshold then level = i; percent = t.percent end
end
return level, percent, total
end
function currentDiscountPercent()
if not State.currentSession then return 0 end
return State.currentSession.discountPercent or 0
end
function buyPrice(item)
local p = currentDiscountPercent()
local c = item.priceCoin or 0
local e = item.priceEma or 0
if p > 0 then
c = c * (100 - p) / 100
e = e * (100 - p) / 100
end
return c, e
end
function formatPrice(v)
local n = tonumber(v) or 0
if n == 0 then return "0" end
local abs = math.abs(n)
local dec
if abs >= 1 then dec = 2 elseif abs >= 0.01 then dec = 4 else dec = 6 end
local mult = 10 ^ dec
local t = math.floor(abs * mult + 0.0000001) / mult
local s = string.format("%." .. dec .. "f", t)
if s:find(".", 1, true) then s = s:gsub("0+$", ""); s = s:gsub("%.$", "") end
return s
end
function cut(s, w)
s = tostring(s or "")
if unicode.len(s) > w then s = unicode.sub(s, 1, w - 1) .. "…" end
return s
end
function formatQtyCompact(n)
n = math.floor(tonumber(n) or 0)
if n >= 1000000000 then return math.floor(n / 1000000000) .. "kkk"
elseif n >= 1000000 then return math.floor(n / 1000000) .. "kk"
elseif n >= 1000 then return math.floor(n / 1000) .. "k"
else return tostring(n) end
end
function formatQtySpaces(n)
n = math.floor(tonumber(n) or 0)
local s = tostring(n)
local out = ""
while unicode.len(s) > 3 do
out = " " .. unicode.sub(s, -3) .. out
s = unicode.sub(s, 1, unicode.len(s) - 3)
end
return s .. out
end
function wrapText(text, width)
local lines = {}
local cur = ""
function pushCur()
if cur ~= "" then lines[#lines + 1] = cur; cur = "" end
end
for token in tostring(text or ""):gmatch("[^\n]+") do
for word in token:gmatch("%S+") do
if cur == "" then cur = word
elseif unicode.len(cur) + 1 + unicode.len(word) <= width then cur = cur .. " " .. word
else pushCur(); cur = word end
while unicode.len(cur) > width do
lines[#lines + 1] = unicode.sub(cur, 1, width)
cur = unicode.sub(cur, width + 1)
end
end
pushCur()
end
pushCur()
return lines
end
function lowerStr(s)
s = tostring(s or "")
if unicode and unicode.lower then
local ok, r = pcall(unicode.lower, s)
if ok and type(r) == "string" then return r end
end
s = s:gsub("%u", function(c) return c:lower() end)
s = s:gsub("\208\129", "\208\177")
s = s:gsub("\208([\144-\175])", function(cc) return "\208" .. string.char(cc:byte() + 32) end)
return s
end
function matchesSearch(nameLower, searchLower)
if searchLower == "" then return true end
for token in searchLower:gmatch("%S+") do
if not string.find(nameLower, token, 1, true) then return false end
end
return true
end

function meSnapshot()
if meSnap.at >= 0 and (computer.uptime() - meSnap.at) < 2 then return meSnap.index end
local idx = {}
if component.isAvailable("me_interface") then
local ok, items = pcall(function() return component.me_interface.getItemsInNetwork() end)
if ok and type(items) == "table" then
for _, it in ipairs(items) do
local k = it.name .. ":" .. (it.damage or 0)
idx[k] = (idx[k] or 0) + (it.size or 0)
end
end
end
meSnap.index, meSnap.at = idx, computer.uptime()
return idx
end
setProgressOf = function(set)
if not set then return nil end
return Data.setsProgress[set.id]
end
setDispensedFor = function(set, item)
local pr = Data.setsProgress[set and set.id]
if not pr or not pr.dispensed then return 0 end
return math.floor(pr.dispensed[tostring(item.internalName) .. ":" .. tostring(item.damage or 0)] or 0)
end
setTotalQty = function(set)
local t = 0
if set and set.items then
for _, it in ipairs(set.items) do t = t + (tonumber(it.qty) or 0) end
end
return t
end
setTotalDispensed = function(set)
local pr = Data.setsProgress[set and set.id]
if not pr or not pr.dispensed then return 0 end
local t = 0
for _, v in pairs(pr.dispensed) do t = t + v end
return math.floor(t)
end
setIsAvailable = function(set)
if not set or not set.items then return false end
local idx = meSnapshot()
for _, it in ipairs(set.items) do
if (idx[it.internalName .. ":" .. (it.damage or 0)] or 0) < (tonumber(it.qty) or 0) then return false end
end
return true
end
local tmpfs = component.proxy(computer.tmpAddress())
function getRealTimestamp()
local handle = tmpfs.open("/time", "w")
tmpfs.write(handle, "time")
tmpfs.close(handle)
return tmpfs.lastModified("/time") / 1000 + Config.TIMEZONE_OFFSET
end
function getRealTimeString() return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp()) end
local DEBUG_LOG_PATH = "/home/shop_debug.log"
function writeDebugLog(message)
pcall(function()
local file = io.open(DEBUG_LOG_PATH, "a")
if file then file:write("[" .. getRealTimeString() .. "] " .. tostring(message) .. "\n"); file:close() end
end)
end
local FileModule = {}
function FileModule.loadLuaFile(path)
if not fs.exists(path) then writeDebugLog("Файл не найден: " .. path) return nil end
local ok, data = pcall(dofile, path)
if not ok then writeDebugLog("Ошибка загрузки " .. path .. ": " .. tostring(data)) return nil end
return data
end
function FileModule.saveLuaFile(path, data)
local tmpPath = path .. ".tmp"
local file = io.open(tmpPath, "w")
if not file then writeDebugLog("Не удалось открыть " .. tmpPath) return false end
file:write("return " .. serialization.serialize(data)); file:close(); fs.rename(tmpPath, path)
return true
end
function FileModule.saveLuaList(path, list)
local tmpPath = path .. ".tmp"
local file = io.open(tmpPath, "w")
if not file then writeDebugLog("Не удалось открыть " .. tmpPath) return false end
file:write("return {\n")
for i = 1, #list do file:write(serialization.serialize(list[i])); file:write(",\n") end
file:write("}\n"); file:close(); fs.rename(tmpPath, path)
return true
end
function FileModule.saveLuaMap(path, map)
local tmpPath = path .. ".tmp"
local file = io.open(tmpPath, "w")
if not file then writeDebugLog("Не удалось открыть " .. tmpPath) return false end
file:write("return {\n")
for k, v in pairs(map) do file:write("[" .. serialization.serialize(k) .. "] = " .. serialization.serialize(v) .. ",\n") end
file:write("}\n"); file:close(); fs.rename(tmpPath, path)
return true
end
function FileModule.loadJsonFile(path)
if not fs.exists(path) then return {} end
local file = io.open(path, "r")
if not file then return {} end
local content = file:read("*a"); file:close()
if not content or #content == 0 then return {} end
local ok, data = pcall(serialization.unserialize, content)
if ok then return data or {} end
return {}
end
function FileModule.saveJsonFile(path, data)
local file = io.open(path, "w")
if not file then return false end
file:write(serialization.serialize(data)); file:close()
return true
end
local PlayerModule = {}
local dbDirty = false
function PlayerModule.load()
local data = FileModule.loadLuaFile(Config.FILES.players)
if data and type(data) == "table" then Data.players = data; return true end
Data.players = {}; return false
end
function PlayerModule.save()
if FileModule.saveLuaMap(Config.FILES.players, Data.players) then dbDirty = false; return true end
return false
end
function PlayerModule.get(name) if not name then return nil end return Data.players[name] end
function PlayerModule.getOrCreate(name)
if not Data.players[name] then
Data.players[name] = { balance = 0, emaBalance = 0, transactions = 0, regDate = getRealTimeString(), banned = false, banReason = "", transactionsList = {}, spentCoin = 0, spentEma = 0 }
dbDirty = true
end
return Data.players[name]
end
function PlayerModule.updateBalance(name, coin, ema)
local player = PlayerModule.getOrCreate(name)
player.balance = (player.balance or 0) + (coin or 0)
player.emaBalance = (player.emaBalance or 0) + (ema or 0)
dbDirty = true
return player
end
function PlayerModule.addSpent(name, coin, ema)
local player = PlayerModule.getOrCreate(name)
player.spentCoin = (player.spentCoin or 0) + (coin or 0)
player.spentEma = (player.spentEma or 0) + (ema or 0)
dbDirty = true
return player
end
function PlayerModule.addTransaction(name, txData)
local player = PlayerModule.getOrCreate(name)
player.transactions = (player.transactions or 0) + 1
if not player.transactionsList then player.transactionsList = {} end
table.insert(player.transactionsList, 1, txData)
while #player.transactionsList > 100 do table.remove(player.transactionsList) end
dbDirty = true
return player
end
function PlayerModule.flush()
if not dbDirty then return end
if State.TRANSACTION_LOCK then return end
PlayerModule.save()
end
local CatalogModule = {}
function CatalogModule.loadVersion()
local data = FileModule.loadLuaFile(Config.FILES.catalogVersion)
if type(data) == "table" then Data.versions = { buy = tonumber(data.buy) or 0, sell = tonumber(data.sell) or 0, users = tonumber(data.users) or 0, sets = tonumber(data.sets) or 0 }
else Data.versions = { buy = tonumber(data) or 0, sell = 0, users = 0, sets = 0 } end
return Data.versions
end
function CatalogModule.saveVersions()
FileModule.saveLuaFile(Config.FILES.catalogVersion, Data.versions)
writeDebugLog("Версии: buy=" .. Data.versions.buy .. " sell=" .. Data.versions.sell .. " users=" .. Data.versions.users .. " sets=" .. Data.versions.sets)
end
function CatalogModule.loadBuy()
local data = FileModule.loadLuaFile(Config.FILES.buyCatalog)
if data and type(data) == "table" then Data.buyCatalog = data; return true end
Data.buyCatalog = {}; return false
end
function CatalogModule.saveBuy(items) Data.buyCatalog = items or {}; return FileModule.saveLuaList(Config.FILES.buyCatalog, Data.buyCatalog) end
function CatalogModule.loadSell()
local data = FileModule.loadLuaFile(Config.FILES.sellCatalog)
if data and type(data) == "table" then Data.sellCatalog = data; return true end
Data.sellCatalog = {}; return false
end
function CatalogModule.saveSell(items) Data.sellCatalog = items or {}; return FileModule.saveLuaList(Config.FILES.sellCatalog, Data.sellCatalog) end
function CatalogModule.loadSets()
local data = FileModule.loadLuaFile(Config.FILES.setsCatalog)
if data and type(data) == "table" then Data.setsCatalog = data; return true end
Data.setsCatalog = {}; return false
end
function CatalogModule.saveSets(items) Data.setsCatalog = items or {}; return FileModule.saveLuaList(Config.FILES.setsCatalog, Data.setsCatalog) end
function CatalogModule.loadSetsProgress()
local data = FileModule.loadLuaFile(Config.FILES.setsProgress)
if data and type(data) == "table" then Data.setsProgress = data; return true end
Data.setsProgress = {}; return false
end
function CatalogModule.saveSetsProgress() return FileModule.saveLuaMap(Config.FILES.setsProgress, Data.setsProgress) end
local ReportModule = {}
function ReportModule.load() Data.reports = FileModule.loadJsonFile(Config.FILES.reports); return Data.reports end
function ReportModule.save() return FileModule.saveJsonFile(Config.FILES.reports, Data.reports) end
function to_json(val)
if type(val) == "table" then
local is_arr = #val > 0
local parts = {}
if is_arr then
for i, v in ipairs(val) do parts[#parts+1] = to_json(v) end
return "[" .. table.concat(parts, ",") .. "]"
else
for k, v in pairs(val) do if type(k) == "string" then parts[#parts+1] = '"' .. k .. '":' .. to_json(v) end end
return "{" .. table.concat(parts, ",") .. "}"
end
elseif type(val) == "string" then return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
elseif type(val) == "boolean" then return val and "true" or "false"
elseif type(val) == "number" then return tostring(val)
else return "null" end
end
function from_json(str)
if str == nil or type(str) ~= "string" then return str end
str = str:match("^%s*(.-)%s*$")
if str == "" or str == "null" then return nil end
if str == "true" then return true end
if str == "false" then return false end
if str:match("^-?%d+%.?%d*$") then return tonumber(str) end
if str:match('"status"%s*:%s*"ok"') and str:match('"items"%s*:%s*%[') and not str:match('"sets"%s*:%s*%[') then
local result = { status = "ok", items = {} }
local typeMatch = str:match('"type"%s*:%s*"([^"]+)"'); if typeMatch then result.type = typeMatch end
local versionMatch = str:match('"version"%s*:%s*(%d+)'); if versionMatch then result.version = tonumber(versionMatch) end
local pageMatch = str:match('"page"%s*:%s*(%d+)'); if pageMatch then result.page = tonumber(pageMatch) end
local totalPagesMatch = str:match('"totalPages"%s*:%s*(%d+)'); if totalPagesMatch then result.totalPages = tonumber(totalPagesMatch) end
local totalItemsMatch = str:match('"totalItems"%s*:%s*(%d+)'); if totalItemsMatch then result.totalItems = tonumber(totalItemsMatch) end
local itemsStr = str:match('"items"%s*:%s*%[(.-)%]%s*}')
if itemsStr then
for itemStr in itemsStr:gmatch('{[^}]+}') do
local item = {}
for key, value in itemStr:gmatch('"([^"]+)"%s*:%s*([^,}]+)') do
value = value:match("^%s*(.-)%s*$")
if value:sub(1,1) == '"' then item[key] = value:sub(2, -2)
elseif tonumber(value) then item[key] = tonumber(value)
elseif value == 'true' then item[key] = true
elseif value == 'false' then item[key] = false
else item[key] = value end
end
table.insert(result.items, item)
end
end
return result
end
if str:match('"status"%s*:%s*"ok"') and str:match('"syncedTransactions"') then
local result = { status = "ok" }
local syncedMatch = str:match('"syncedTransactions"%s*:%s*%[([^%]]*)%]')
if syncedMatch then local synced = {}; for id in syncedMatch:gmatch('"([^"]+)"') do table.insert(synced, id) end; result.syncedTransactions = synced else result.syncedTransactions = {} end
local errorsMatch = str:match('"errors"%s*:%s*%[([^%]]*)%]')
if errorsMatch then local errors = {}; for err in errorsMatch:gmatch('"([^"]+)"') do table.insert(errors, err) end; result.errors = errors else result.errors = {} end
return result
end
if str:sub(1,1) == '"' and str:sub(-1,-1) == '"' then
return str:sub(2, -2):gsub('\\"', '"'):gsub('\\\\', '\\'):gsub('\\/', '/'):gsub('\n', '\n'):gsub('\\r', '\r'):gsub('\\t', '\t')
end
if str:sub(1,1) == '[' and str:sub(-1,-1) == ']' then
local arr, depth, start, in_str, esc = {}, 0, 2, false, false
for i = 2, #str - 1 do
local c = str:sub(i, i)
if esc then esc = false
elseif c == '\\' and in_str then esc = true
elseif c == '"' then in_str = not in_str
elseif not in_str then
if c == '[' or c == '{' then depth = depth + 1
elseif c == ']' or c == '}' then depth = depth - 1
elseif c == ',' and depth == 0 then table.insert(arr, from_json(str:sub(start, i - 1))); start = i + 1 end
end
end
local last = str:sub(start, #str - 1)
if last:match("%S") then table.insert(arr, from_json(last)) end
return arr
end
if str:sub(1,1) == '{' and str:sub(-1,-1) == '}' then
local obj, depth, start, key, in_str, esc, is_key = {}, 0, 2, nil, false, false, true
for i = 2, #str - 1 do
local c = str:sub(i, i)
if esc then esc = false
elseif c == '\\' and in_str then esc = true
elseif c == '"' then in_str = not in_str
elseif not in_str then
if c == '[' or c == '{' then depth = depth + 1
elseif c == ']' or c == '}' then depth = depth - 1
elseif c == ':' and depth == 0 and is_key then key = from_json(str:sub(start, i - 1)); start = i + 1; is_key = false
elseif c == ',' and depth == 0 then
if key then obj[key] = from_json(str:sub(start, i - 1)); key = nil end
start = i + 1; is_key = true
end
end
end
if key then obj[key] = from_json(str:sub(start, #str - 1)) end
return obj
end
return str
end
local HttpModule = {}
function HttpModule.request(action, data)
local url = Config.WEB_URL .. "?action=" .. action
local headers = { ["Content-Type"] = "application/json", ["X-OC-Token"] = Config.WEB_TOKEN }
local body = data and to_json(data) or nil
local ok, response = pcall(function()
local req = internet.request(url, body, headers, "POST")
local chunks = {}
for chunk in req do chunks[#chunks + 1] = chunk end
return table.concat(chunks)
end)
if ok and response and type(response) == "string" and response ~= "" then
local success, result = pcall(from_json, response)
if success and result then return result end
if response:find('"status"%s*:%s*"ok"') then
writeDebugLog("Ответ получен, но не распарсен целиком — считаю ok: " .. action)
return { status = "ok", parsed = false }
end
writeDebugLog("Не удалось распарсить ответ: " .. tostring(response):sub(1, 300))
elseif not ok then
writeDebugLog("HTTP ошибка: " .. tostring(response))
end
return nil
end
local PendingModule = {}
local flushInProgress = false
function PendingModule.load()
local data = FileModule.loadLuaFile(Config.FILES.pendingChanges)
if data and type(data) == "table" then Data.pendingChanges = data; return true end
Data.pendingChanges = {}; return false
end
function PendingModule.save() return FileModule.saveLuaFile(Config.FILES.pendingChanges, Data.pendingChanges) end
function PendingModule.add(changeType, data)
local change = { id = changeType .. "_" .. os.time() .. "_" .. math.random(100000), type = changeType, timestamp = os.time(), data = data }
table.insert(Data.pendingChanges, change); PendingModule.save()
if #Data.pendingChanges >= Config.PENDING_FLUSH_THRESHOLD then PendingModule.flush() end
return change
end
function PendingModule.flush()
if #Data.pendingChanges == 0 then return true end
if flushInProgress then return false end
flushInProgress = true
writeDebugLog("Отправка " .. #Data.pendingChanges .. " изменений на сервер...")
local response = HttpModule.request("oc_sync_changes", { terminalId = Config.TERMINAL_ID, changes = Data.pendingChanges })
flushInProgress = false
if response and response.status == "ok" then
writeDebugLog("Синхронизация успешна"); Data.pendingChanges = {}; PendingModule.save(); return true
else
writeDebugLog("Ошибка синхронизации: " .. tostring(response and response.message or "нет ответа")); return false
end
end
local Buffer = { currChars = {}, currFg = {}, currBg = {}, dirtyRows = {}, initialized = false }
function makeSpaceRow() local t = {}; for x = 1, Config.SCREEN_W do t[x] = " " end; return t end
function Buffer.init()
if Buffer.initialized then return end
for y = 1, Config.SCREEN_H do
Buffer.currChars[y] = makeSpaceRow(); Buffer.currFg[y], Buffer.currBg[y] = {}, {}
for x = 1, Config.SCREEN_W do Buffer.currFg[y][x], Buffer.currBg[y][x] = Colors.text_bright, Colors.bg_main end
end
Buffer.initialized = true
end
function Buffer.clear()
for y = 1, Config.SCREEN_H do
Buffer.currChars[y] = makeSpaceRow()
for x = 1, Config.SCREEN_W do Buffer.currFg[y][x], Buffer.currBg[y][x] = Colors.text_bright, Colors.bg_main end
Buffer.dirtyRows[y] = true
end
end
function Buffer.set(x, y, char, fg, bg)
if x < 1 or x > Config.SCREEN_W or y < 1 or y > Config.SCREEN_H then return end
Buffer.currChars[y][x] = char
Buffer.currFg[y][x], Buffer.currBg[y][x] = fg or Colors.text_bright, bg or Colors.bg_main
Buffer.dirtyRows[y] = true
end
function Buffer.fill(x, y, w, h, char, fg, bg)
if w <= 0 or h <= 0 then return end
char, fg, bg = char or " ", fg or Colors.text_bright, bg or Colors.bg_main
for dy = 0, h - 1 do
local yy = y + dy
if yy >= 1 and yy <= Config.SCREEN_H then for dx = 0, w - 1 do Buffer.set(x + dx, yy, char, fg, bg) end end
end
end
function Buffer.write(x, y, text, fg, bg)
if y < 1 or y > Config.SCREEN_H or x > Config.SCREEN_W then return end
text = tostring(text or ""); if text == "" then return end
fg, bg = fg or Colors.text_bright, bg or Colors.bg_main
if x < 1 then text = unicode.sub(text, 2 - x); x = 1 end
local maxLen = Config.SCREEN_W - x + 1
if unicode.len(text) > maxLen then text = unicode.sub(text, 1, maxLen - 1) .. "…" end
for i = 1, unicode.len(text) do Buffer.set(x + i - 1, y, unicode.sub(text, i, i), fg, bg) end
end
function Buffer.flush()
local lastFg, lastBg = nil, nil
for y = 1, Config.SCREEN_H do
if Buffer.dirtyRows[y] then
local row = Buffer.currChars[y]
local cFg, cBg = Buffer.currFg[y], Buffer.currBg[y]
local x = 1
while x <= Config.SCREEN_W do
local fg, bg = cFg[x], cBg[x]
local startX = x
local seg = { row[x] }
x = x + 1
while x <= Config.SCREEN_W and cFg[x] == fg and cBg[x] == bg do seg[#seg + 1] = row[x]; x = x + 1 end
if lastFg ~= fg then gpu.setForeground(fg); lastFg = fg end
if lastBg ~= bg then gpu.setBackground(bg); lastBg = bg end
gpu.set(startX, y, table.concat(seg))
end
Buffer.dirtyRows[y] = nil
end
end
end
local PimModule = {}
local PUSH_DIRECTION = "down"
local PULL_DIRECTION = "up"
function PimModule.getAddr() for addr in component.list("pim") do return addr end; return nil end
function PimModule.normalizeName(name) if not name then return "" end; return name:match(".*:([^:]+)$") or name end
function PimModule.namesMatch(name1, name2)
if not name1 or not name2 then return false end
if name1 == name2 then return true end
return PimModule.normalizeName(name1) == PimModule.normalizeName(name2)
end
function PimModule.getPlayer()
local pimAddr = PimModule.getAddr()
if not pimAddr then return nil end
local pim = component.proxy(pimAddr)
local player = nil
if pim.getPlayer then local ok,res = pcall(pim.getPlayer, pim); if ok and res and res ~= "" then player=res end end
if not player and pim.getPlayerName then local ok,res = pcall(pim.getPlayerName, pim); if ok and res and res ~= "" then player=res end end
if not player and pim.getUsername then local ok,res = pcall(pim.getUsername, pim); if ok and res and res ~= "" then player=res end end
if not player then local ok,res = pcall(function() return pim.player end); if ok and res and res ~= "" then player=res end end
return player
end
function PimModule.isOwner(playerName) return playerName and State.pimOwner and playerName == State.pimOwner end
function PimModule.ensureValid(expectedPlayer)
if State.isShuttingDown or not State.currentPlayer or not State.pimOwner or not State.pimActive then return false end
if expectedPlayer and State.currentPlayer ~= expectedPlayer then return false end
return true
end
function pimPresenceState()
local addr = PimModule.getAddr()
if not addr then return "unknown" end
local okp, pim = pcall(component.proxy, addr)
if not okp or not pim or not pim.getInventorySize then return "unknown" end
local ok, r = pcall(pim.getInventorySize, pim)
if not ok or type(r) ~= "number" then return "unknown" end
if r > 0 then return "present" end
return "absent"
end
function readStack(pimAddr, slot)
local stack = component.invoke(pimAddr, "getStackInSlot", slot)
if not stack then return nil end
local size = stack.size or stack.qty or stack.count or 0
local rawName = stack.name or stack.label or stack.id or ""
local dmg = stack.damage or stack.dmg or 0
return { size = size, name = rawName, damage = dmg }
end
function PimModule.scanInventory(targetName, targetDamage)
local pimAddr = PimModule.getAddr()
if not pimAddr then return 0 end
targetDamage = targetDamage or 0
local total = 0
for slot = 1, 36 do
local st = readStack(pimAddr, slot)
if st and st.size > 0 then
local cleanName = st.name:gsub("§.", "")
if PimModule.namesMatch(cleanName, targetName) and st.damage == targetDamage then total = total + st.size end
end
end
return total
end
function PimModule.countOccupiedSlots()
local pimAddr = PimModule.getAddr()
if not pimAddr then return 0 end
local occupied = 0
for slot = 1, 36 do local st = readStack(pimAddr, slot); if st and st.size > 0 then occupied = occupied + 1 end end
return occupied
end
function PimModule.extractToME(targetName, amount, targetDamage)
local pimAddr = PimModule.getAddr()
if not pimAddr or amount <= 0 then return 0 end
targetDamage = targetDamage or 0
local extracted = 0
for slot = 1, 36 do
if extracted >= amount then break end
local st = readStack(pimAddr, slot)
if st and st.size > 0 then
local cleanName = st.name:gsub("§.", "")
if PimModule.namesMatch(cleanName, targetName) and st.damage == targetDamage then
local toTake = math.min(st.size, amount - extracted)
if toTake > 0 then
local moved = component.invoke(pimAddr, "pushItem", PUSH_DIRECTION, slot, toTake)
if type(moved) == "number" and moved > 0 then extracted = extracted + moved end
end
end
end
end
return extracted
end
local selector = nil
for addr in component.list("openperipheral_selector") do selector = component.proxy(addr); break end
if not selector then for addr in component.list("item_selector") do selector = component.proxy(addr); break end end
function safeSelectorSetSlot(slot, stack)
if not selector then return false end
local ok, res = pcall(function() return selector.setSlot(slot, stack) end)
if not ok then writeDebugLog("Selector: " .. tostring(res)) end
return ok, res
end
function updateSelectorDisplay(item)
if not selector then return end
if not item then safeSelectorSetSlot(0, nil); safeSelectorSetSlot(1, nil); return end
local raw = item.internalName or item.name or item.displayName
if not raw then return end
local id = raw:find(":") and raw or ("minecraft:" .. raw)
safeSelectorSetSlot(0, { id = id, dmg = item.damage or 0 })
safeSelectorSetSlot(1, { id = id, dmg = item.damage or 0 })
end
local TransactionModule = {}
function TransactionModule.lock(txid)
if State.TRANSACTION_LOCK then
if computer.uptime() - State.transactionStartTime > Config.TRANSACTION_TIMEOUT then
State.TRANSACTION_LOCK = false; State.activeTransactionId = nil; State.transactionStartTime = 0
State.transactionTimeoutShown = false; State.lastTransactionEndTime = computer.uptime()
else return false end
end
if computer.uptime() - State.lastTransactionEndTime < Config.TRANSACTION_COOLDOWN then return false end
State.TRANSACTION_LOCK = true
State.activeTransactionId = txid or ("tx_" .. tostring(computer.uptime()))
State.transactionStartTime = computer.uptime()
State.transactionTimeoutShown = false
return true
end
function TransactionModule.unlock()
if not State.TRANSACTION_LOCK then return end
State.TRANSACTION_LOCK = false; State.activeTransactionId = nil; State.transactionStartTime = 0
State.transactionTimeoutShown = false; State.lastTransactionEndTime = computer.uptime()
end
function TransactionModule.checkTimeout()
if State.TRANSACTION_LOCK and computer.uptime() - State.transactionStartTime > Config.TRANSACTION_TIMEOUT then
TransactionModule.unlock()
if not State.transactionTimeoutShown and State.currentScreen ~= "welcome" then
State.transactionTimeoutShown = true
State.modalState.active = true; State.modalState.kind = "error"
State.modalState.data = { title = "Транзакция прервана", text = "Операция заняла слишком много времени." }
State.modalData = State.modalState.data; State.currentScreen = "modal"; forceRender()
end
end
end
function clampQuantity(qty, maxAvailable)
if not qty or qty <= 0 or not maxAvailable or maxAvailable <= 0 then return 1 end
return qty > maxAvailable and maxAvailable or qty
end
function refreshSessionDiscount()
if not State.currentSession or not State.currentPlayer then return end
local player = PlayerModule.get(State.currentPlayer)
local sc = (player and player.spentCoin) or State.currentSession.spentCoin or 0
local se = (player and player.spentEma) or State.currentSession.spentEma or 0
local level, percent, total = getDiscountInfo(sc, se)
State.currentSession.spentCoin = sc
State.currentSession.spentEma = se
State.currentSession.discountLevel = level
State.currentSession.discountPercent = percent
State.currentSession.spentTotal = total
end
function craftCap()
local freeSlots = 36 - PimModule.countOccupiedSlots()
if freeSlots <= 0 then return 0 end
local cap = freeSlots * 64
local item = State.selectedItem
if item and State.currentSession then
local coin, ema = buyPrice(item)
local bal, emaBal = State.currentSession.balance or 0, State.currentSession.emaBalance or 0
if coin > 0 then cap = math.min(cap, math.floor(bal / coin + 0.000001)) end
if ema > 0 then cap = math.min(cap, math.floor(emaBal / ema + 0.000001)) end
end
return cap
end
function buyQtyCap(item)
if not item then return 0 end
local stock = item.qty or 0
if State.currentShopMode == "buy" and acAvailable(item) then return math.max(stock, craftCap()) end
return stock
end
function calculateMaxBuyQuantity()
local item = State.selectedItem
if not item then return 1 end
local cap = craftCap()
if not acAvailable(item) then
local stock = item.qty or 0
if stock < cap then cap = stock end
end
if cap < 1 then return 1 end
return cap
end
function refreshSellPlayerQty()
if State.currentShopMode ~= "sell" then return end
if State.selectedItem then
State.sellPlayerQty = PimModule.scanInventory(State.selectedItem.internalName, State.selectedItem.damage or 0)
State.sellQuantity = clampQuantity(State.sellQuantity, State.sellPlayerQty)
else State.sellPlayerQty = 0 end
end
function validateTerminalState()
if State.isShuttingDown then return false, "Терминал завершает работу" end
if State.serverState.maintenance then return false, "Сервер на обслуживании" end
if State.serverState.terminalPaused then
if not (State.pauseGraceUntil > 0 and computer.uptime() < State.pauseGraceUntil) then
return false, "Терминал на техническом обслуживании"
end
end
if not State.pimActive or not State.currentPlayer or not State.currentSession then return false, "Игрок не авторизован" end
if not PimModule.ensureValid(State.currentPlayer) then return false, "Игрок больше не на PIM" end
return true
end
function validateBuyRequest()
local ok, err = validateTerminalState()
if not ok then return false, err end
if State.currentShopMode ~= "buy" then return false, "Неверный режим магазина" end
if not State.selectedItem then return false, "Товар не выбран" end
if (State.selectedItem.qty or 0) <= 0 and not acAvailable(State.selectedItem) then return false, "Товар закончился" end
State.purchaseQuantity = clampQuantity(State.purchaseQuantity, buyQtyCap(State.selectedItem))
if State.purchaseQuantity <= 0 then return false, "Некорректное количество" end
local dc, de = buyPrice(State.selectedItem)
if (State.currentSession.balance or 0) < dc * State.purchaseQuantity then return false, "Недостаточно Coina" end
if (State.currentSession.emaBalance or 0) < de * State.purchaseQuantity then return false, "Недостаточно EMA" end
if not component.isAvailable("me_interface") then return false, "ME интерфейс недоступен" end
return true
end
function validateSellRequest()
local ok, err = validateTerminalState()
if not ok then return false, err end
if State.currentShopMode ~= "sell" then return false, "Неверный режим магазина" end
if not State.selectedItem then return false, "Товар не выбран" end
refreshSellPlayerQty()
if State.sellPlayerQty <= 0 then return false, "Предмет не найден в инвентаре" end
State.sellQuantity = clampQuantity(State.sellQuantity, State.sellPlayerQty)
if State.sellQuantity <= 0 then return false, "Некорректное количество" end
return true
end
function getSelectedItemKey(item) return item and (tostring(item.internalName or "") .. ":" .. tostring(item.damage or 0)) or nil end
function restoreSelectedItemByKey(selectedKey)
if not selectedKey then State.selectedItem, State.selectedIndex = nil, 0; return end
State.selectedItem, State.selectedIndex = nil, 0
for i, item in ipairs(Data.filteredItems) do
if getSelectedItemKey(item) == selectedKey then State.selectedItem, State.selectedIndex = item, i; break end
end
end
function getItemTags(item)
local tags = {}
for tag in tostring(item.article or ""):gmatch("([^,]+)") do
tag = tag:match("^%s*(.-)%s*$")
if tag ~= "" then table.insert(tags, tag) end
end
return tags
end
function itemInCategory(item, categoryTagList)
if not categoryTagList then return true end
local itemTags = getItemTags(item)
for _, ct in ipairs(categoryTagList) do for _, it in ipairs(itemTags) do if ct == it then return true end end end
return false
end
function applyFilter()
Data.filteredItems = {}
local searchLower = lowerStr(State.searchInput or "")
local src = State.currentShopMode == "buy" and Data.buyCatalogDisplay or Data.sellCatalogDisplay
local categoryTagList = Data.categoryTags[State.currentCategory]
for _, item in ipairs(src) do
local nameLower = lowerStr(item.displayName or item.internalName or "")
if matchesSearch(nameLower, searchLower) and itemInCategory(item, categoryTagList) then table.insert(Data.filteredItems, item) end
end
table.sort(Data.filteredItems, function(a, b)
local aQty, bQty = a.qty or 0, b.qty or 0
if aQty > 0 and bQty == 0 then return true end
if aQty == 0 and bQty > 0 then return false end
return lowerStr(a.displayName or "") < lowerStr(b.displayName or "")
end)
State.listScroll = 1
if #Data.filteredItems > 0 then
State.selectedIndex = math.min(State.selectedIndex > 0 and State.selectedIndex or 1, #Data.filteredItems)
State.selectedItem = Data.filteredItems[State.selectedIndex]
else State.selectedIndex, State.selectedItem = 0, nil end
end
function applyBuyCatalog(items)
local selectedKey = getSelectedItemKey(State.selectedItem)
Data.buyCatalogDisplay = {}
for _, item in ipairs(items or {}) do
if item.enabled ~= false and item.enabled ~= 0 then
table.insert(Data.buyCatalogDisplay, { internalName = item.internalName, displayName = item.displayName or item.internalName, priceCoin = tonumber(item.priceCoin) or 0, priceEma = tonumber(item.priceEma) or 0, damage = tonumber(item.damage) or 0, article = item.article or "", qty = 0 })
end
end
writeDebugLog("Каталог покупок: " .. #Data.buyCatalogDisplay .. " предметов")
applyFilter(); restoreSelectedItemByKey(selectedKey); updateBuyCatalogFromME()
end
function applySellCatalog(items)
local selectedKey = getSelectedItemKey(State.selectedItem)
Data.sellCatalogDisplay = {}
for _, item in ipairs(items or {}) do
if item.enabled ~= false and item.enabled ~= 0 then
table.insert(Data.sellCatalogDisplay, { internalName = item.internalName, displayName = item.displayName or item.internalName, priceCoin = tonumber(item.priceCoin) or 0, priceEma = tonumber(item.priceEma) or 0, price = (tonumber(item.priceEma) or 0) > 0 and (tonumber(item.priceEma) or 0) or (tonumber(item.priceCoin) or 0), damage = tonumber(item.damage) or 0, article = item.article or "", qty = 999999 })
end
end
writeDebugLog("Каталог продаж: " .. #Data.sellCatalogDisplay .. " предметов")
applyFilter(); restoreSelectedItemByKey(selectedKey)
end
function updateBuyCatalogFromME()
if State.currentShopMode == "sell" then return end
if not component.isAvailable("me_interface") then return end
local me = component.me_interface
local meIndex = {}
local ok, items = pcall(function() return me.getItemsInNetwork() end)
if not ok then return end
for _, meItem in ipairs(items or {}) do meIndex[meItem.name .. ":" .. (meItem.damage or 0)] = meItem.size or 0 end
meSnap.index, meSnap.at = meIndex, computer.uptime()
local changed = false
local selectedKey = getSelectedItemKey(State.selectedItem)
for i, item in ipairs(Data.buyCatalogDisplay) do
local newQty = meIndex[item.internalName .. ":" .. (item.damage or 0)] or 0
if item.qty ~= newQty then Data.buyCatalogDisplay[i].qty = newQty; changed = true end
end
if changed then applyFilter(); restoreSelectedItemByKey(selectedKey); markDirty("full"); writeDebugLog("ME обновлено") end
end
function applySetsFilter()
Data.setsDisplay = {}
local searchLower = lowerStr(State.searchInput or "")
for _, s in ipairs(Data.setsCatalog or {}) do
if (s.enabled == 1 or s.enabled == true) and matchesSearch(lowerStr(s.name or ""), searchLower) then table.insert(Data.setsDisplay, s) end
end
table.sort(Data.setsDisplay, function(a, b) return lowerStr(a.name or "") < lowerStr(b.name or "") end)
State.listScroll = 1
if #Data.setsDisplay > 0 then
State.selectedIndex = math.min(State.selectedIndex > 0 and State.selectedIndex or 1, #Data.setsDisplay)
State.selectedSet = Data.setsDisplay[State.selectedIndex]
else State.selectedIndex, State.selectedSet = 0, nil; State.selectedSetItem = nil end
end
function setItemKey(it) return tostring(it.internalName) .. ":" .. tostring(it.damage or 0) end
function setProgressGet(setId) if not setId then return nil end return Data.setsProgress[setId] end
function setDispensedForLocal(set, it)
local pr = setProgressGet(set and set.id)
if not pr or not pr.dispensed then return 0 end
return math.floor(pr.dispensed[setItemKey(it)] or 0)
end
function setTotalDispensedLocal(set)
local pr = setProgressGet(set and set.id)
if not pr or not pr.dispensed then return 0 end
local t = 0
for _, v in pairs(pr.dispensed) do t = t + v end
return math.floor(t)
end
function setTotalQtyLocal(set)
local t = 0
if set and set.items then for _, it in ipairs(set.items) do t = t + (tonumber(it.qty) or 0) end end
return t
end
function setCompleted(set)
local pr = setProgressGet(set and set.id)
if not pr then return false end
if pr.completed then return true end
for _, it in ipairs(set.items or {}) do
if (pr.dispensed or {})[setItemKey(it)] or 0 < (tonumber(it.qty) or 0) then return false end
end
return true
end
function meCountOf(internalName, damage)
return meSnapshot()[internalName .. ":" .. tostring(damage or 0)] or 0
end
function setIsAvailableLocal(set)
if not set or not set.items then return false end
local idx = meSnapshot()
for _, it in ipairs(set.items) do
if (idx[it.internalName .. ":" .. (it.damage or 0)] or 0) < (tonumber(it.qty) or 0) then return false end
end
return true
end
function loadCatalogPages(catalogType)
local allItems = {}
local page, totalPages = 1, 1
local logIndex = #State.welcomeLog + 1
table.insert(State.welcomeLog, { message = "Загрузка " .. string.upper(catalogType) .. "...", color = Colors.accent_cyan }); drawWelcomeScreen()
while page <= totalPages do
State.welcomeLog[logIndex] = { message = string.upper(catalogType) .. ": стр. " .. page .. "/" .. totalPages, color = Colors.accent_cyan }; drawWelcomeScreen()
os.sleep(0.1)
local data = HttpModule.request("oc_get_catalog", { type = catalogType, page = page, terminalId = Config.TERMINAL_ID })
if not data then State.welcomeLog[logIndex] = { message = "Ошибка: нет ответа", color = Colors.error_red }; drawWelcomeScreen(); return nil end
if data.status ~= "ok" then State.welcomeLog[logIndex] = { message = "Ошибка: " .. tostring(data.message), color = Colors.error_red }; drawWelcomeScreen(); return nil end
for _, item in ipairs(data.items or {}) do table.insert(allItems, item) end
totalPages = data.totalPages or 1
page = page + 1
end
State.welcomeLog[logIndex] = { message = string.upper(catalogType) .. ": " .. #allItems .. " предм.", color = Colors.success_green }; drawWelcomeScreen()
return allItems
end
function loadSetsPages()
local allSets = {}
local page, totalPages = 1, 1
local ver = 0
local logIndex = #State.welcomeLog + 1
table.insert(State.welcomeLog, { message = "Загрузка НАБОРОВ...", color = Colors.accent_cyan }); drawWelcomeScreen()
while page <= totalPages do
State.welcomeLog[logIndex] = { message = "НАБОРЫ: стр. " .. page .. "/" .. totalPages, color = Colors.accent_cyan }; drawWelcomeScreen()
os.sleep(0.1)
local data = HttpModule.request("oc_get_sets", { page = page, terminalId = Config.TERMINAL_ID })
if not data then State.welcomeLog[logIndex] = { message = "Наборы: нет ответа", color = Colors.error_red }; drawWelcomeScreen(); return nil, 0 end
if data.status ~= "ok" then State.welcomeLog[logIndex] = { message = "Наборы: " .. tostring(data.message), color = Colors.error_red }; drawWelcomeScreen(); return nil, 0 end
for _, s in ipairs(data.sets or {}) do table.insert(allSets, s) end
ver = tonumber(data.version) or ver
totalPages = data.totalPages or 1
page = page + 1
end
State.welcomeLog[logIndex] = { message = "НАБОРЫ: " .. #allSets .. " наборов", color = Colors.success_green }; drawWelcomeScreen()
return allSets, ver
end
function addWelcomeLog(message, color)
table.insert(State.welcomeLog, { message = message, color = color or Colors.text_main })
if #State.welcomeLog > 12 then table.remove(State.welcomeLog, 1) end
drawWelcomeScreen()
end
function applyUsersFromServer(users)
for _, user in ipairs(users) do
if user.name then
local existing = Data.players[user.name]
Data.players[user.name] = { balance = tonumber(user.balanceCoin) or 0, emaBalance = tonumber(user.balanceEma) or 0, transactions = tonumber(user.transactions) or 0, regDate = user.regDate or (existing and existing.regDate) or getRealTimeString(), banned = (tonumber(user.banned) or 0) == 1, banReason = user.banReason or "", transactionsList = (existing and existing.transactionsList) or {}, spentCoin = tonumber(user.spent_coin) or (existing and existing.spentCoin) or 0, spentEma = tonumber(user.spent_ema) or (existing and existing.spentEma) or 0 }
end
end
PlayerModule.save()
end
function applyCatalogDelta(catalogType, changes, newVersion)
local currentData = catalogType == "buy" and Data.buyCatalog or Data.sellCatalog
local saveFunc = catalogType == "buy" and CatalogModule.saveBuy or CatalogModule.saveSell
local index = {}
for i, item in ipairs(currentData) do index[tostring(item.internalName) .. ":" .. tostring(item.damage or 0)] = i end
local addCnt, updCnt, delCnt = 0, 0, 0
local toDelete = {}
for _, ch in ipairs(changes or {}) do
local it = ch.item or {}
local key = tostring(it.internalName) .. ":" .. tostring(it.damage or 0)
if ch.action == "delete" then toDelete[key] = true; delCnt = delCnt + 1
else
toDelete[key] = nil
local idx = index[key]
if idx then currentData[idx] = it; updCnt = updCnt + 1 else table.insert(currentData, it); index[key] = #currentData; addCnt = addCnt + 1 end
end
end
local newData = {}
for _, item in ipairs(currentData) do local key = tostring(item.internalName) .. ":" .. tostring(item.damage or 0); if not toDelete[key] then table.insert(newData, item) end end
if catalogType == "buy" then Data.buyCatalog = newData else Data.sellCatalog = newData end
saveFunc(newData)
if catalogType == "buy" then Data.versions.buy = newVersion else Data.versions.sell = newVersion end
CatalogModule.saveVersions()
if catalogType == "buy" then applyBuyCatalog(newData) else applySellCatalog(newData) end
addWelcomeLog(string.upper(catalogType) .. ": +" .. addCnt .. " / изм. " .. updCnt .. " / удал. " .. delCnt, Colors.success_green)
end
function applySetsDelta(changes, newVersion)
local currentData = Data.setsCatalog
local index = {}
for i, s in ipairs(currentData) do index[tonumber(s.id)] = i end
local addCnt, updCnt, delCnt = 0, 0, 0
for _, ch in ipairs(changes or {}) do
local s = ch.set or {}
local sid = tonumber(s.id)
if sid then
if ch.action == "REMOVE" or ch.action == "delete" then
local idx = index[sid]
if idx then
table.remove(currentData, idx); delCnt = delCnt + 1
index = {}
for i2, s2 in ipairs(currentData) do index[tonumber(s2.id)] = i2 end
end
if State.selectedSet and tonumber(State.selectedSet.id) == sid then State.selectedSet = nil; State.selectedSetItem = nil end
else
local norm = { id = sid, name = s.name, price_coin = tonumber(s.price_coin) or 0, price_ema = tonumber(s.price_ema) or 0, enabled = (s.enabled == 1 or s.enabled == true) and 1 or 0, rev = tonumber(s.rev) or 1, items = s.items or {} }
local idx = index[sid]
if idx then currentData[idx] = norm; updCnt = updCnt + 1
if State.selectedSet and tonumber(State.selectedSet.id) == sid then State.selectedSet = norm end
else table.insert(currentData, norm); index[sid] = #currentData; addCnt = addCnt + 1 end
end
end
end
Data.versions.sets = tonumber(newVersion) or Data.versions.sets
CatalogModule.saveSets(currentData)
CatalogModule.saveVersions()
if State.currentShopMode == "sets" then applySetsFilter() end
addWelcomeLog("НАБОРЫ: +" .. addCnt .. " / изм. " .. updCnt .. " / удал. " .. delCnt, Colors.success_green)
end
function fullReloadCatalogs(serverBuy, serverSell)
addWelcomeLog("Полная загрузка BUY...", Colors.accent_cyan)
local buyItems = loadCatalogPages("buy")
if buyItems then CatalogModule.saveBuy(buyItems); Data.versions.buy = serverBuy; applyBuyCatalog(buyItems) else addWelcomeLog("Ошибка загрузки BUY", Colors.error_red) end
addWelcomeLog("Полная загрузка SELL...", Colors.accent_cyan)
local sellItems = loadCatalogPages("sell")
if sellItems then CatalogModule.saveSell(sellItems); Data.versions.sell = serverSell; applySellCatalog(sellItems) else addWelcomeLog("Ошибка загрузки SELL", Colors.error_red) end
CatalogModule.saveVersions()
end
function syncEnd(result, source)
State.syncInProgress = false
if source ~= "player" and not State.pimActive then State.welcomeLog = {}; drawWelcomeScreen() end
return result
end
function syncCatalogsIfNeeded(source)
if State.syncInProgress then return "busy" end
State.syncInProgress = true
addWelcomeLog("Проверка версий с сервером...", Colors.accent_cyan)
local v = HttpModule.request("oc_get_versions", { terminalId = Config.TERMINAL_ID })
if not v or v.status ~= "ok" then addWelcomeLog("Сервер недоступен, работаем на локальных данных", Colors.warning); return syncEnd("error", source) end
local serverBuy, serverSell, serverUsers = tonumber(v.buyVersion) or 0, tonumber(v.sellVersion) or 0, tonumber(v.usersVersion) or 0
local serverSets = tonumber(v.setsVersion) or 0
local needBuy = serverBuy ~= (Data.versions.buy or 0)
local needSell = serverSell ~= (Data.versions.sell or 0)
local needUsers = serverUsers ~= (Data.versions.users or 0)
local needSets = serverSets ~= (Data.versions.sets or 0)
if not needBuy and not needSell and not needUsers and not needSets then addWelcomeLog("Версии: OK, начинаем запуск...", Colors.success_green); return syncEnd("ok", source) end
addWelcomeLog("Версии расходятся! Обновляем данные...", Colors.warning)
if needBuy or needSell then
local delta = HttpModule.request("oc_get_catalog_delta", { terminalId = Config.TERMINAL_ID, fromBuy = Data.versions.buy or 0, fromSell = Data.versions.sell or 0 })
if delta and delta.status == "ok" then
if needBuy then applyCatalogDelta("buy", delta.buyChanges or {}, serverBuy) end
if needSell then applyCatalogDelta("sell", delta.sellChanges or {}, serverSell) end
elseif source == "player" then
writeDebugLog("Полная перезагрузка каталогов отложена до выхода игрока")
State.pendingFullReload = true
else
addWelcomeLog("Дельта недоступна, грузим каталоги целиком...", Colors.warning); fullReloadCatalogs(serverBuy, serverSell)
end
end
if needSets then
local sd = HttpModule.request("oc_get_sets_delta", { terminalId = Config.TERMINAL_ID, fromVersion = Data.versions.sets or 0 })
if sd and sd.status == "ok" and sd.changes then
applySetsDelta(sd.changes, serverSets)
else
local allSets, ver = loadSetsPages()
if allSets then
Data.setsCatalog = allSets
Data.versions.sets = tonumber(ver) or serverSets
CatalogModule.saveSets(allSets)
CatalogModule.saveVersions()
applySetsFilter()
end
end
end
if needUsers then
addWelcomeLog("Обновляем данные игроков (балансы)...", Colors.accent_cyan)
local ud = HttpModule.request("oc_get_users", { terminalId = Config.TERMINAL_ID })
if ud and ud.status == "ok" then applyUsersFromServer(ud.users or {}); Data.versions.users = tonumber(ud.usersVersion) or serverUsers; CatalogModule.saveVersions(); addWelcomeLog("Данные игроков обновлены", Colors.success_green)
else addWelcomeLog("Не удалось обновить данные игроков", Colors.warning) end
end
addWelcomeLog("Обновление завершено", Colors.success_green)
return syncEnd("updated", source)
end
function loadFullInit()
writeDebugLog("Первый запуск: загрузка данных с сервера...")
table.insert(State.welcomeLog, { message = "Первичная синхронизация...", color = Colors.warning }); drawWelcomeScreen()
local buyItems = loadCatalogPages("buy")
if not buyItems then State.catalogLoadFailed = true; return end
local buyCount = #buyItems
local sellItems = loadCatalogPages("sell")
if not sellItems then State.catalogLoadFailed = true; return end
local sellCount = #sellItems
table.insert(State.welcomeLog, { message = "Загрузка пользователей...", color = Colors.accent_cyan }); drawWelcomeScreen()
local usersData = HttpModule.request("oc_get_users", { terminalId = Config.TERMINAL_ID })
if not usersData or usersData.status ~= "ok" then usersData = { users = {}, buyVersion = 0, sellVersion = 0, usersVersion = 0, setsVersion = 0, maintenance = false } end
local vBuy, vSell, vUsers = tonumber(usersData.buyVersion) or 0, tonumber(usersData.sellVersion) or 0, tonumber(usersData.usersVersion) or 0
local vSets = tonumber(usersData.setsVersion) or 0
State.serverState.maintenance = usersData.maintenance or false
CatalogModule.saveBuy(buyItems); buyItems = nil
CatalogModule.saveSell(sellItems); sellItems = nil
if usersData.users and type(usersData.users) == "table" then
for _, user in ipairs(usersData.users) do
if user.name then Data.players[user.name] = { balance = tonumber(user.balanceCoin) or 0, emaBalance = tonumber(user.balanceEma) or 0, transactions = tonumber(user.transactions) or 0, regDate = user.regDate or getRealTimeString(), banned = (tonumber(user.banned) or 0) == 1, banReason = user.banReason or "", transactionsList = {}, spentCoin = tonumber(user.spent_coin) or 0, spentEma = tonumber(user.spent_ema) or 0 } end
end
end
usersData = nil
PlayerModule.save()
local allSets, sver = loadSetsPages()
if allSets then Data.setsCatalog = allSets; vSets = tonumber(sver) or vSets; CatalogModule.saveSets(allSets) end
Data.versions = { buy = vBuy, sell = vSell, users = vUsers, sets = vSets }
CatalogModule.saveVersions()
applyBuyCatalog(Data.buyCatalog); applySellCatalog(Data.sellCatalog); applySetsFilter()
State.catalogsLoaded = true; State.catalogLoadFailed = false
State.lastCatalogUpdate = computer.uptime()
local userCount = 0
for _ in pairs(Data.players) do userCount = userCount + 1 end
table.insert(State.welcomeLog, { message = "Готово! Buy: " .. buyCount .. ", Sell: " .. sellCount .. ", Sets: " .. #Data.setsCatalog .. ", Users: " .. userCount, color = Colors.success_green }); drawWelcomeScreen()
end
function flushSessionToServer() PendingModule.flush(); PlayerModule.flush(); CatalogModule.saveSetsProgress() end
function safeOpenModal(kind, data)
local ok, err = pcall(function()
State.modalState.active = true; State.modalState.kind = kind; State.modalState.data = data or {}
State.modalData = State.modalState.data; State.currentScreen = "modal"
end)
if not ok then
State.modalState.active = true; State.modalState.kind = "error"
State.modalState.data = { title = "Ошибка UI", text = tostring(err) }; State.modalData = State.modalState.data; State.currentScreen = "modal"
end
forceRender()
end
function openErrorModal(title, text) safeOpenModal("error", { title = title or "Ошибка", text = text or "Неизвестная ошибка" }) end
function openInfoModal(title, lines) safeOpenModal("info", { title = title or "Информация", lines = lines or {} }) end
function closeModal()
State.modalState.active = false; State.modalState.kind = nil; State.modalState.data = nil; State.modalData = nil
State.currentScreen = State.pimActive and "shop" or "welcome"
forceRender()
end
function openReportModal()
State.modalState.active = true; State.modalState.kind = "report_select"; State.modalState.data = {}
State.modalData = State.modalState.data; State.currentScreen = "modal"; forceRender()
end
function openReportTypeForm(reportKind)
State.modalState.active = true; State.modalState.kind = "report_form"
State.modalState.data = { type = reportKind, text = "", item_id = "", comment = "", _active_field = "item" }
State.modalData = State.modalState.data; State.currentScreen = "modal"; forceRender()
end
function openMyReports()
local result = HttpModule.request("oc_get_my_reports", { terminalId = Config.TERMINAL_ID, player = State.currentPlayer or "" })
State.modalState.active = true; State.modalState.kind = "my_reports"
State.modalState.data = { reports = (result and result.status == "ok" and result.reports) or {} }
State.modalData = State.modalState.data; State.currentScreen = "modal"; forceRender()
end
function openDiscountModal()
State.modalState.active = true; State.modalState.kind = "discount"; State.modalState.data = {}
State.modalData = State.modalState.data; State.currentScreen = "modal"; forceRender()
end
function submitReport()
local data = State.modalState.data
if not data or not data.type then return end
local payload = { terminalId = Config.TERMINAL_ID, player = State.currentPlayer or "Неизвестный", type = data.type, text = data.text or "", itemId = data.item_id or "", comment = data.comment or "" }
local result = HttpModule.request("oc_submit_report", payload)
if result and result.status == "ok" then
closeModal()
safeOpenModal("info", { title = "Репорт отправлен", lines = { "Спасибо! Ваш репорт #" .. (result.reportId or "") .. " принят.", "Мы рассмотрим его в ближайшее время." } })
else safeOpenModal("error", { title = "Ошибка отправки", text = "Не удалось отправить репорт. Попробуйте позже." }) end
end
function checkRewardedReports()
if not State.currentPlayer then return end
local result = HttpModule.request("oc_get_rewarded_reports", { terminalId = Config.TERMINAL_ID, player = State.currentPlayer })
if result and result.status == "ok" and result.reports and #result.reports > 0 then
for _, rep in ipairs(result.reports) do
local coin, ema = tonumber(rep.reward_coin) or 0, tonumber(rep.reward_ema) or 0
safeOpenModal("reward", { reportId = rep.id, coin = coin, ema = ema, answer = rep.admin_comment or "" })
local freshUser = HttpModule.request("oc_get_balance", { name = State.currentPlayer, terminalId = Config.TERMINAL_ID })
if freshUser and freshUser.status == "ok" and freshUser.user then
State.currentSession.balance = tonumber(freshUser.user.balanceCoin) or 0
State.currentSession.emaBalance = tonumber(freshUser.user.balanceEma) or 0
end
HttpModule.request("oc_mark_report_notified", { terminalId = Config.TERMINAL_ID, reportId = rep.id })
end
markDirty("right")
end
end
function clearAllText() State.logMessages = {}; State.welcomeLog = {}; State.syncLogs = {}; Buffer.clear() end
function setLogMessage(text, color) State.logMessages = {}; if text and text ~= "" then table.insert(State.logMessages, {text = text, color = color or Colors.text_dark, gap = 1}) end; markDirty("right") end
function addLogMessage(text, color) if text and text ~= "" then table.insert(State.logMessages, {text = text, color = color or Colors.text_dark, gap = 1}) end; markDirty("right") end
function addLogSegs(segs)
local plain = ""
for _, s in ipairs(segs) do plain = plain .. s[1] end
table.insert(State.logMessages, { segs = segs, text = plain, gap = 1 })
markDirty("right")
end
function clearLog() State.logMessages = {} end
function scheduleClearLog(delay) event.timer(delay or 5, function() clearLog(); markDirty("right"); return false end) end
function fillBox(x, y, w, h, bg, ch) Buffer.fill(x, y, w, h, ch or " ", Colors.text_bright, bg or Colors.bg_main) end
function writeText(x, y, text, fg, bg) Buffer.write(x, y, text, fg or Colors.text_bright, bg or Colors.bg_main) end
function drawCenteredText(y, text, fg, bg, offsetX) text = tostring(text or ""); Buffer.write(math.floor((Config.SCREEN_W - unicode.len(text)) / 2) + 1 + (offsetX or 0), y, text, fg or Colors.text_bright, bg or Colors.bg_main) end
function drawBox(x, y, w, h, fg, bg)
if w < 2 or h < 2 then return end
fg, bg = fg or Colors.line, bg or Colors.bg_main
Buffer.write(x, y, "┌" .. string.rep("─", w - 2) .. "┐", fg, bg)
for r = y + 1, y + h - 2 do Buffer.write(x, r, "│", fg, bg); Buffer.write(x + w - 1, r, "│", fg, bg) end
Buffer.write(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘", fg, bg)
end
function drawButton(x, y, w, h, text, bg, fg, id)
fillBox(x, y, w, h, bg or Colors.bg_button)
writeText(x + math.floor((w - unicode.len(text)) / 2), y + math.floor((h - 1) / 2), text, fg or Colors.text_bright, bg or Colors.bg_button)
if id then table.insert(State.buttons, { id = id, x = x, y = y, w = w, h = h }) end
end
function isButtonClicked(btn, x, y) return y >= btn.y and y < btn.y + btn.h and x >= btn.x and x < btn.x + btn.w end
function drawModal()
if State.bannedNow then
local w, h = 70, 9
local x = math.floor((Config.SCREEN_W - w) / 2)
local y = math.floor((Config.SCREEN_H - h) / 2)
Buffer.fill(x, y, w, h, " ", Colors.text_bright, Colors.bg_modal)
drawBox(x, y, w, h, Colors.error_red, Colors.bg_modal)
drawCenteredText(y + 2, "ДОСТУП ЗАБЛОКИРОВАН", Colors.error_red, Colors.bg_modal)
drawCenteredText(y + 4, "Ваш аккаунт заблокирован администрацией.", Colors.text_bright, Colors.bg_modal)
local reason = (State.currentSession and State.currentSession.banReason) or ""
if reason ~= "" then drawCenteredText(y + 5, "Причина: " .. reason, Colors.warning, Colors.bg_modal) end
drawCenteredText(y + 7, "Обратитесь к администрации. Окно закроется после выхода с PIM.", Colors.text_gray, Colors.bg_modal)
return
end
if not State.modalState.active then return end
local kind = State.modalState.kind
local data = State.modalState.data or {}
if kind == "pause_countdown" then
local left = math.max(0, math.ceil(State.pauseGraceUntil - computer.uptime()))
local w, h = 70, 8
local x = math.floor((Config.SCREEN_W - w) / 2)
local y = math.floor((Config.SCREEN_H - h) / 2)
Buffer.fill(x, y, w, h, " ", Colors.text_bright, Colors.bg_modal)
drawBox(x, y, w, h, Colors.warning, Colors.bg_modal)
drawCenteredText(y + 2, "ТЕХНИЧЕСКОЕ ОБСЛУЖИВАНИЕ", Colors.warning, Colors.bg_modal)
drawCenteredText(y + 4, "Терминал уходит на ТО через " .. left .. " сек.", Colors.text_bright, Colors.bg_modal)
drawCenteredText(y + 5, "Завершите покупки и сойдите с PIM.", Colors.text_main, Colors.bg_modal)
drawButton(x + math.floor((w - 16) / 2), y + h - 2, 16, 1, "[ ПОНЯТНО ]", Colors.bg_button, Colors.white, "pause_close")
return
end
if kind == "discount" then
local modalW, modalH = 78, 19
local modalX = math.floor((Config.SCREEN_W - modalW) / 2)
local modalY = math.floor((Config.SCREEN_H - modalH) / 2)
Buffer.fill(modalX, modalY, modalW, modalH, " ", Colors.text_bright, Colors.bg_modal)
drawBox(modalX, modalY, modalW, modalH, Colors.accent_cyan, Colors.bg_modal)
drawCenteredText(modalY + 1, "Система скидок Trade Market Shop", Colors.accent_cyan, Colors.bg_modal)
function segLine(y, segs)
local total = 0
for _, s in ipairs(segs) do total = total + unicode.len(s[1]) end
local xx = modalX + math.floor((modalW - total) / 2) + 1
for _, s in ipairs(segs) do writeText(xx, y, s[1], s[2], Colors.bg_modal); xx = xx + unicode.len(s[1]) end
end
local Y = modalY + 3
segLine(Y, { { "В магазине работает система накопительных скидок:", Colors.text_main } }); Y = Y + 1
segLine(Y, { { "чем больше покупок, тем больше скидка.", Colors.text_main } }); Y = Y + 2
segLine(Y, { { "1 Уровень = Купить товара суммарно на 1000 ", Colors.text_main }, { "COINS", Colors.accent_cyan }, { " или ", Colors.text_main }, { "EM", Colors.tomato }, { " = 2%", Colors.success_green } }); Y = Y + 1
segLine(Y, { { "2 Уровень = Купить товара суммарно на 3000 ", Colors.text_main }, { "COINS", Colors.accent_cyan }, { " или ", Colors.text_main }, { "EM", Colors.tomato }, { " = 4%", Colors.success_green } }); Y = Y + 1
segLine(Y, { { "3 Уровень = Купить товара суммарно на 10000 ", Colors.text_main }, { "COINS", Colors.accent_cyan }, { " или ", Colors.text_main }, { "EM", Colors.tomato }, { " = 6%", Colors.success_green } }); Y = Y + 1
segLine(Y, { { "4 Уровень = Купить товара суммарно на 25000 ", Colors.text_main }, { "COINS", Colors.accent_cyan }, { " или ", Colors.text_main }, { "EM", Colors.tomato }, { " = 8%", Colors.success_green } }); Y = Y + 1
segLine(Y, { { "5 Уровень = Купить товара суммарно на 50000 ", Colors.text_main }, { "COINS", Colors.accent_cyan }, { " или ", Colors.text_main }, { "EM", Colors.tomato }, { " = 10%", Colors.success_green } }); Y = Y + 2
local sc = State.currentSession and State.currentSession.spentCoin or 0
local se = State.currentSession and State.currentSession.spentEma or 0
local level, percent, total = getDiscountInfo(sc, se)
segLine(Y, { { "Ваш текущий уровень " .. level .. " (скидка " .. percent .. "%).", Colors.success_green } }); Y = Y + 1
local scStr = formatPrice(sc)
local seStr = formatPrice(se)
if level >= #DISCOUNT_TIERS then
segLine(Y, { { "Всего вы купили товаров в магазине на ", Colors.text_main }, { scStr .. " COINS", Colors.accent_cyan }, { " и ", Colors.text_main }, { seStr .. " EM.", Colors.tomato } })
else
local nextTh = DISCOUNT_TIERS[level + 1].threshold
local remain = math.max(0, nextTh - total)
segLine(Y, { { "Всего вы купили товаров в магазине на ", Colors.text_main }, { scStr .. " COINS", Colors.accent_cyan }, { " и ", Colors.text_main }, { seStr .. " EM,", Colors.tomato } })
Y = Y + 1
segLine(Y, { { "до следующего уровня скидки осталось потратить суммарно:", Colors.text_main } })
Y = Y + 1
segLine(Y, {  formatPrice(remain) .. " COINS", Colors.accent_cyan }, { " или ", Colors.text_main }, { seStr .. " EM,", Colors.tomato  })
end
drawButton(modalX + math.floor((modalW - 20) / 2), modalY + modalH - 2, 20, 1, "[ ПОНЯТНО ]", Colors.bg_button, Colors.white, "modal_ok")
return
end
if kind == "help" then
local modalW, modalH = UI.modal.helpW, UI.modal.helpH
local modalX = math.floor((Config.SCREEN_W - modalW) / 2)
local modalY = math.floor((Config.SCREEN_H - modalH) / 2)
Buffer.fill(modalX, modalY, modalW, modalH, " ", Colors.text_bright, Colors.bg_modal)
drawBox(modalX, modalY, modalW, modalH, Colors.accent_cyan, Colors.bg_modal)
local titles = {
"КАК РАБОТАТЬ С МАГАЗИНОМ",
"РАБОТА С БАЛАНСАМИ МАГАЗИНА",
"ПРОЦЕСС ПОКУПКИ/ПРОДАЖИ",
"АВТОКРАФТ ПРЕДМЕТОВ",
"СИСТЕМА СКИДОК, НАБОРОВ И РЕПОРТОВ"
}
local title = titles[State.helpPage] or "HELP INFO:"
drawCenteredText(modalY + 1, title, Colors.accent_cyan, Colors.bg_modal)
local contentY = modalY + 4
local lines = {}
if State.helpPage == 1 then
lines = {
{ text = "--- НАЧАЛО ТОРГОВОЙ СЕССИИ ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Встаньте на PIM, дождитесь авторизации, синхронизации каталогов и загрузки магазина.", color = Colors.text_main, center = true },
{ text = "Пока вы стоите на PIM, магазин закрепляет текущую сессию за вами.", color = Colors.text_gray, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- КАТАЛОГ ТОВАРОВ ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "[ Покупки ] - обычный каталог товаров магазина.", color = Colors.text_main, center = true },
{ text = "Выбирайте товар из списка мышкой, в правом блоке вы увидите подробности.", color = Colors.text_main, center = true },
{ text = "Поиск не требует клика: фокус уже в строке, просто печатайте название.", color = Colors.text_main, center = true },
{ text = "Имеется сортировка каталога по конкретному моду.", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- ЧТО ТАКОЕ COINS & EMA ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "COINS - внутренняя валюта магазина (эквивалент 1 железного слитка)", color = Colors.accent_cyan, center = true },
{ text = "EM - эквивалент игровой валюты сервера, ЭМов.", color = Colors.tomato, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- КОЛИЧЕСТВО ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Выберите товар и нажмите на поле КОЛИЧЕСТВО.", color = Colors.text_main, center = true },
{ text = "Введите число. Магазин сразу пересчитает итоговую стоимость.", color = Colors.text_main, center = true },
{ text = "Кнопка [ МАКС ] вводит максимум с учётом баланса и места в инвентаре.", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- КАК РАБОТАЕТ PIM ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Экран и клавиатура принимают управление только от владельца текущей PIM-сессии.", color = Colors.tomato, center = true },
{ text = "Если сойти с PIM, сессия закрывается и магазин возвращается в режим ожидания.", color = Colors.text_main, center = true },
{ text = "Не сходите с PIM во время покупки, пополнения, выдачи набора или автокрафта.", color = Colors.text_main, center = true },
}
elseif State.helpPage == 2 then
lines = {
{ text = "--- COINS И EMA ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "TRADE MARKET использует 2 валюты для оплаты товаров: COINS & EM.", color = Colors.text_main, center = true },
{ text = "Предметы могут стоить отдельно в COINS, в EMA или в обеих сразу.", color = Colors.text_main, center = true },
{ text = "Баланс COINS & EMA всегда доступен в разделе АККАУНТ.", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- ЧТО НУЖНО ДЛЯ ПОКУПКИ ПРЕДМЕТА ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Для покупки предмета на балансе аккаунта должно быть достаточно COINS и/или EMA.", color = Colors.text_main, center = true },
{ text = "Итоговая стоимость = цена за один предмет * количество покупаемых предметов.", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- КАК ПОПОЛНЯЕТСЯ БАЛАНС ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Баланс магазина можно пополнить в разделе [ Пополнение ], продав скупаемый магазином предмет.", color = Colors.text_main, center = true },
{ text = "У каждого предмета есть цена, за которую магазин готов его купить у игрока.", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- АККАУНТ ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Справа показываются: Имя, COINS, EMA и число транзакций.", color = Colors.text_main, center = true },
{ text = "После совершения транзакции покупки/продажи, баланс обновляется в реальном времени.", color = Colors.success_green, center = true }
}
elseif State.helpPage == 3 then
lines = {
{ text = "", color = Colors.text_main },
{ text = "--- ПОКУПКА ТОВАРА ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "На странице [ Покупки ], выбирая товар вы можете видеть его наличие в МЭ магазина.", color = Colors.text_main, center = true },
{ text = "Введя количество, справа появится итог в COINS и EMA.", color = Colors.text_main, center = true },
{ text = "Нажимая [ Купить ] магазин проверяет баланс, сессию и свободное место в инвентаре игрока.", color = Colors.text_main, center = true },
{ text = "После ряда успешных проверок магазин списывает стоимость покупаемого предмета и выдает его игроку через PIM.", color = Colors.text_main, center = true },
{ text = "Если по какой-то причине будет выдано меньше предметов чем покупалось, магазин спишет оплату только за фактически выданные предметы.", color = Colors.success_green, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- ПОПОЛНЕНИЕ / ПРОДАЖА ПРЕДМЕТОВ ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Находясь на странице [ Пополнение ], у вас в инвентаре должен быть продаваемый предмет.", color = Colors.text_main, center = true },
{ text = "Выбирая этот предмет в каталоге, магазин определит каким количеством данного предмета вы владеете.", color = Colors.text_main, center = true },
{ text = "Введите желаемое количество или нажмите на кнопку [МАКС], для продажи всех предметов одного типа.", color = Colors.text_main, center = true },
{ text = "Нажмите [ ПРОДАТЬ ] и в разделе ЛОГИРОВАНИЯ вы увидите количество проданных предметов и за сколько они были проданы.", color = Colors.text_main, center = true },
{ text = "В результате успешной продажи магазин изымает продаваемые предметы.", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "Перед подтверждением всегда проверяйте название, количество и итоговую сумму.", color = Colors.tomato, center = true }
}
elseif State.helpPage == 4 then
lines = {
{ text = "--- АВТОКРАФТ ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Автокрафт позволяет покупать отсутствующие в наличие товары.", color = Colors.text_main, center = true },
{ text = "Главным условием для этого является наличие рецепта для крафта в МЭ магазина.", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- КАК ПОНЯТЬ, ЧТО АВТОКРАФТ ДОСТУПЕН ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "В правом информационном блоке ПОКУПАЕМЫЙ ПРЕДМЕТ должен быть статус АВТОКРАФТ: ДОСТУПЕН.", color = Colors.accent_cyan, center = true },
{ text = "При вводе количества предметов, превышающих доступное в МЭ количество, появится кнопка [ЗАКАЗАТЬ КРАФТ].", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- ЧТО ПРОИСХОДИТ ПОСЛЕ НАЖАТИЯ ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Нажатие на кнопку заказа крафта инициализирует финальную проверку перед заказом предмета.", color = Colors.text_main, center = true },
{ text = "В окне появится информация по предстоящей операции.", color = Colors.text_main, center = true },
{ text = "Кнопка [НАЧАТЬ КРАФТ] отправляет запрос на крафт в МЭ сеть.", color = Colors.text_main, center = true },
{ text = "Как только предметы будут созданы начнётся процесс выдачи.", color = Colors.success_green, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- ЛОГИРОВАНИЕ ПРОЦЕССА ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Весь процесс крафта логируется в соответствующем информационном блоке.", color = Colors.text_main, center = true },
{ text = "Как только готовые предметы попадают в сеть, происходит оплата и выдача.", color = Colors.text_main, center = true },
{ text = "Если у игрока закончится место в инвентаре в момент выдачи, оставшиеся предметы будут доступны для покупки в магазине.", color = Colors.text_main, center = true },
{ text = "При частичной выдачи оплата будет произведено за то количество предметов, которое фактически получил игрок.", color = Colors.success_green, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- ЕСЛИ УЙТИ С PIM ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Сессия игрока закрывается, а крафт отменяется.", color = Colors.text_main, center = true },
{ text = "Оплата производится только по факту выдачи товара минуя случайные списания.", color = Colors.success_green, center = true },
{ text = "Все лишние предметы окажутся в МЭ сети магазина.", color = Colors.text_gray, center = true },
{ text = "", color = Colors.text_main },
{ text = "Не сходите с PIM во время процесса крафта, в также заранее освободите место в инвентаре.", color = Colors.tomato, center = true }
}
elseif State.helpPage == 5 then
lines = {
{ text = "", color = Colors.text_main },
{ text = "--- СИСТЕМА СКИДОК ---", color = Colors.accent_cyan, center = true },
{ text = "Накопительная скидка растёт от суммарных трат и применяется к финальной цене.", color = Colors.text_main, center = true },
{ text = "Подробности — по кнопке [ ? ] в блоке АККАУНТ.", color = Colors.success_green, center = true },
{ text = "", color = Colors.text_main },
{ text = "--- КВЕСТЫ И НАБОРЫ ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "В разделе [ Наборы | Квесты ], вы можете купить готовые наборы предметов или квесты (испытания).", color = Colors.text_main, center = true },
{ text = "Переходя на страницу набора вы видите из каких предметов он состоит, а также их количество.", color = Colors.text_main, center = true },
{ text = "Купить набор можно только если в наличие есть все предметы набора. Купить отдельное предметы из набора не получится.", color = Colors.text_main, center = true },
{ text = "Сначала происходит покупка набора, а затем уже его выдача.", color = Colors.text_main, center = true },
{ text = "Вы сами решаете когда вам забирать набор, после покупки появится кнопка выдачи и подсчёт выданных предметов.", color = Colors.success_green, center = true },
{ text = "Если у вас закончилось место или вы случайно сошли с PIM в этом нет ничего страшного.", color = Colors.text_main, center = true },
{ text = "Освободите место в инвентаре и вернитесь к странице набора и продолжите выдачу предметов, пока не заберёте весь набор целиком.", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- ОШИБКИ И БАГИ МАГАЗИНА ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Магазин находится в открытом [BETA] тестировании.", color = Colors.tomato, center = true },
{ text = "Если во время работы с магазином вы столкнётесь с незапланированным багом или ошибкой, вы можете оставить на неё репорт.", color = Colors.text_main, center = true },
{ text = "В магазине присутствует активная система репортов и вознаграждений за них.", color = Colors.text_main, center = true },
{ text = "Вы можете с ней ознакомиться нажав на кнопку [ Нашёл ошибку ] в правой нижней части магазина.", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "", color = Colors.text_main },
{ text = "--- СИСТЕМА БЛОКИРОВОК ---", color = Colors.accent_cyan, center = true },
{ text = "", color = Colors.text_main },
{ text = "Если Вы будете пытаться как либо навредить магазину, Вы будете незамедлительно заблокированы.", color = Colors.text_main, center = true },
{ text = "", color = Colors.text_main },
{ text = "Если ваш аккаунт заблокирован, вы более не можете пользоваться магазином и всеми его функциями.", color = Colors.tomato, center = true },
{ text = "", color = Colors.text_main },
}
end
for i, line in ipairs(lines) do
if i <= modalH - 6 then
if line.center then
drawCenteredText(contentY + i - 1, line.text, line.color, Colors.bg_modal)
else
writeText(modalX + 2, contentY + i - 1, line.text, line.color, Colors.bg_modal)
end
end
end
local footerY = modalY + modalH - 3
drawCenteredText(footerY, "СТРАНИЦА " .. State.helpPage .. " / 5", Colors.text_gray, Colors.bg_modal)
local btnY = modalY + modalH - 2
local btnW = 12
local spacing = 4
local totalW = (btnW * 3) + (spacing * 2)
local startX = modalX + math.floor((modalW - totalW) / 2)
local prevColor = State.helpPage > 1 and Colors.purple or Colors.inactive
drawButton(startX, btnY, btnW, 1, "[ < НАЗАД ]", prevColor, Colors.white, "help_prev")
drawButton(startX + btnW + spacing, btnY, btnW + 4, 1, "[ ЗАКРЫТЬ ]", Colors.tomato, Colors.white, "help_close")
local nextColor = State.helpPage < 5 and Colors.success_green or Colors.inactive
drawButton(startX + (btnW * 2) + (spacing * 2) + 4, btnY, btnW, 1, "[ ДАЛЕЕ > ]", nextColor, Colors.white, "help_next")
return
end
local modalW, modalH = UI.modal.smallW, UI.modal.smallH
if kind == "report_select" then modalW, modalH = 70, 21
elseif kind == "report_form" then modalW, modalH = 60, 16
elseif kind == "my_reports" then modalW, modalH = 90, 26
elseif kind == "insufficient" then modalW, modalH = 60, 12 end
local modalX = math.floor((Config.SCREEN_W - modalW) / 2)
local modalY = math.floor((Config.SCREEN_H - modalH) / 2)
Buffer.fill(modalX, modalY, modalW, modalH, " ", Colors.text_bright, Colors.bg_modal)
local borderColor, title = Colors.error_red, "УВЕДОМЛЕНИЕ"
if kind == "error" then borderColor, title = Colors.error_red, data.title or "ОШИБКА"
elseif kind == "insufficient" then borderColor, title = Colors.warning, "НЕДОСТАТОЧНО СРЕДСТВ"
elseif kind == "inventory_full" then borderColor, title = Colors.warning, "ИНВЕНТАРЬ ПОЛОН"
elseif kind == "info" then borderColor, title = Colors.accent_secondary, data.title or "ИНФОРМАЦИЯ"
elseif kind == "reward" then borderColor, title = Colors.success_green, nil
elseif kind == "report_select" then borderColor, title = Colors.tomato, "НАШЁЛ ОШИБКУ?"
elseif kind == "report_form" then borderColor = Colors.tomato; title = data.type == "price" and "НЕКОРРЕКТНАЯ ЦЕНА" or (data.type == "missing_item" and "ОТСУТСТВУЕТ ПРЕДМЕТ" or "БАГ | ПРЕДЛОЖЕНИЕ")
elseif kind == "my_reports" then borderColor, title = Colors.accent_cyan, "МОИ РЕПОРТЫ" end
drawBox(modalX, modalY, modalW, modalH, borderColor, Colors.bg_modal)
if title then drawCenteredText(modalY + 1, title, borderColor, Colors.bg_modal) end
if kind == "reward" then
local icon = "✔ "
local head = "РЕПОРТ #" .. tostring(data.reportId) .. " РАССМОТРЕН!"
local totalW = unicode.len(icon) + unicode.len(head)
local sx = math.floor((Config.SCREEN_W - totalW) / 2) + 1
writeText(sx, modalY + 1, icon, Colors.success_green, Colors.bg_modal)
writeText(sx + unicode.len(icon), modalY + 1, head, Colors.accent_secondary, Colors.bg_modal)
drawCenteredText(modalY + 3, "Вам начислена награда:", Colors.text_bright, Colors.bg_modal)
local segs = {}
local coin, ema = tonumber(data.coin) or 0, tonumber(data.ema) or 0
if coin > 0 then table.insert(segs, { text = formatPrice(coin) .. " COINS", color = Colors.accent_cyan }) end
if coin > 0 and ema > 0 then table.insert(segs, { text = " и ", color = Colors.white }) end
if ema > 0 then table.insert(segs, { text = formatPrice(ema) .. " EMA", color = Colors.tomato }) end
if #segs == 0 then table.insert(segs, { text = "Благодарность", color = Colors.text_bright }) end
local rw = 0
for _, s in ipairs(segs) do rw = rw + unicode.len(s.text) end
local cx = math.floor((Config.SCREEN_W - rw) / 2) + 1
for _, s in ipairs(segs) do writeText(cx, modalY + 4, s.text, s.color, Colors.bg_modal); cx = cx + unicode.len(s.text) end
if data.answer and data.answer ~= "" then drawCenteredText(modalY + 6, "Ответ: " .. data.answer, Colors.text_main, Colors.bg_modal) end
drawButton(modalX + math.floor((modalW - 20) / 2), modalY + modalH - 2, 20, 1, "[ ПОНЯТНО ]", Colors.bg_button, Colors.white, "modal_ok")
elseif kind == "insufficient" then
function cLine(y, txt, color)
local xx = modalX + math.floor((modalW - unicode.len(txt)) / 2) + 1
writeText(xx, y, txt, color or Colors.text_bright, Colors.bg_modal)
end
cLine(modalY + 3, 'Вы пытались купить "' .. (data.itemName or "") .. '" ' .. (data.qty or 0) .. ' шт')
local missParts = {}
if (data.missC or 0) > 0 then table.insert(missParts, formatPrice(data.missC) .. " COINS") end
if (data.missE or 0) > 0 then table.insert(missParts, formatPrice(data.missE) .. " EM") end
cLine(modalY + 4, "Вам не хватает: " .. table.concat(missParts, " | ") .. " для завершения покупки.")
cLine(modalY + 6, "Пополнить баланс можно в разделе пополнения.")
local bw1, bw2 = 14, 12
local totalB = bw1 + bw2 + 2
local bx = modalX + math.floor((modalW - totalB) / 2)
drawButton(bx, modalY + modalH - 2, bw1, 1, "[ Пополнить ]", Colors.success_green, Colors.white, "replenish_go")
drawButton(bx + bw1 + 2, modalY + modalH - 2, bw2, 1, "[ Назад ]", Colors.bg_button, Colors.white, "modal_cancel")
elseif kind == "report_select" then
local info = {
"Добро пожаловать в магазин Trade Market!",
"Магазин по прежнему находится в стадии разработки.",
"Если ты нашел ошибку (например в цене) или другой баг,",
"ты можешь сообщить об этом и получить за это награду.",
"Каждый отправленный репорт будет рассмотрен, и если ",
"твой репорт окажется действительным, ты получишь награду ",
"в виде пополнения баланса магазина в COIN/EM.",
"Объем награды зависит от найденной проблемы.",
" ",
"Если ты получил награду за репорт, ты узнаешь это при входе ",
"в магазин, а также можешь отслеживать это в Мои репорты." }
local ty = modalY + 3
for _, line in ipairs(info) do writeText(modalX + 4, ty, line, Colors.text_main, Colors.bg_modal); ty = ty + 1 end
drawButton(modalX + 4, modalY + 15, 30, 1, "[ Общий / Баг ]", Colors.bg_button, Colors.white, "report_type_general")
drawButton(modalX + 36, modalY + 15, 30, 1, "[ Некорректная цена ]", Colors.bg_button, Colors.white, "report_type_price")
drawButton(modalX + 4, modalY + 17, 30, 1, "[ Отсутствует предмет ]", Colors.bg_button, Colors.white, "report_type_missing")
drawButton(modalX + 36, modalY + 17, 30, 1, "[ Мои репорты ]", Colors.accent_cyan, Colors.white, "report_my")
drawButton(modalX + 28, modalY + 19, 14, 1, "[ Отмена ]", Colors.bg_button, Colors.white, "modal_cancel")
elseif kind == "report_form" then
local curY = modalY + 3
if data.type == "general" then
writeText(modalX + 2, curY, "Опишите проблему:", Colors.text_main, Colors.bg_modal); curY = curY + 1
writeText(modalX + 2, curY, "[", Colors.cyan, Colors.bg_input)
Buffer.fill(modalX + 3, curY, modalW - 4, 5, " ", Colors.text_bright, Colors.bg_input)
writeText(modalX + modalW - 1, curY + 4, "]", Colors.cyan, Colors.bg_input)
local wl = wrapText(data.text or "", modalW - 5)
local startI = math.max(1, #wl - 4)
for i = startI, #wl do writeText(modalX + 3, curY + (i - startI), wl[i], Colors.text_bright, Colors.bg_input) end
curY = curY + 6
else
writeText(modalX + 2, curY, "ID предмета (internalName):", Colors.text_main, Colors.bg_modal); curY = curY + 1
local itemY = curY
writeText(modalX + 2, itemY, "[", Colors.cyan, Colors.bg_input)
Buffer.fill(modalX + 3, itemY, modalW - 4, 1, " ", Colors.text_bright, Colors.bg_input)
writeText(modalX + modalW - 1, itemY, "]", Colors.cyan, Colors.bg_input)
writeText(modalX + 3, itemY, cut(data.item_id or "", modalW - 5), Colors.text_bright, Colors.bg_input)
table.insert(State.buttons, { id = "report_field_item", x = modalX + 2, y = itemY, w = modalW - 4, h = 1 }); curY = itemY + 2
writeText(modalX + 2, curY, "Комментарий:", Colors.text_main, Colors.bg_modal); curY = curY + 1
local commentY = curY
writeText(modalX + 2, commentY, "[", Colors.cyan, Colors.bg_input)
Buffer.fill(modalX + 3, commentY, modalW - 4, 3, " ", Colors.text_bright, Colors.bg_input)
writeText(modalX + modalW - 1, commentY + 2, "]", Colors.cyan, Colors.bg_input)
local wl = wrapText(data.comment or "", modalW - 5)
local startI = math.max(1, #wl - 2)
for i = startI, #wl do writeText(modalX + 3, commentY + (i - startI), wl[i], Colors.text_bright, Colors.bg_input) end
table.insert(State.buttons, { id = "report_field_comment", x = modalX + 2, y = commentY, w = modalW - 4, h = 3 }); curY = commentY + 4
end
drawButton(modalX + 5, modalY + modalH - 2, 18, 1, "[ Отправить ]", Colors.success_green, Colors.white, "report_submit")
drawButton(modalX + 25, modalY + modalH - 2, 12, 1, "[ Назад ]", Colors.bg_button, Colors.white, "report_back")
elseif kind == "my_reports" then
local reps = data.reports or {}
for x = modalX + 1, modalX + modalW - 2 do Buffer.set(x, modalY + 1, "─", Colors.line, Colors.bg_modal) end
drawCenteredText(modalY + 1, " МОИ РЕПОРТЫ ", Colors.accent_cyan, Colors.bg_modal)
local sep = { modalX + 6, modalX + 27, modalX + 37, modalX + 64 }
local maxRows = modalH - 9
local tableBottom = modalY + 4 + maxRows
writeText(modalX + 2, modalY + 2, cut("ID", 4), Colors.cyan, Colors.bg_modal)
writeText(modalX + 7, modalY + 2, cut("Тип репорта", 20), Colors.cyan, Colors.bg_modal)
writeText(modalX + 28, modalY + 2, cut("Статус", 8), Colors.cyan, Colors.bg_modal)
writeText(modalX + 38, modalY + 2, cut("Награда", 26), Colors.cyan, Colors.bg_modal)
writeText(modalX + 65, modalY + 2, cut("Ответ", modalW - 67), Colors.cyan, Colors.bg_modal)
for x = modalX + 1, modalX + modalW - 2 do Buffer.set(x, modalY + 3, "─", Colors.line, Colors.bg_modal) end
for y = modalY + 2, tableBottom do for _, sxp in ipairs(sep) do Buffer.set(sxp, y, "│", Colors.line, Colors.bg_modal) end end
local ry = modalY + 4
for i = 1, math.min(#reps, maxRows) do
local r = reps[i]
local typeLabel = r.type == "price" and "Некорректная цена" or (r.type == "missing_item" and "Отсутствует предмет" or "Баг/Предложение")
local statusLabel = (r.status == "resolved" or r.status == "closed") and "Закрыт" or "Открыт"
local statusColor = statusLabel == "Закрыт" and Colors.error_red or Colors.success_green
writeText(modalX + 2, ry, cut(tostring(r.id), 4), Colors.text_bright, Colors.bg_modal)
writeText(modalX + 7, ry, cut(typeLabel, 20), Colors.text_bright, Colors.bg_modal)
writeText(modalX + 28, ry, cut(statusLabel, 8), statusColor, Colors.bg_modal)
local coin, ema = tonumber(r.reward_coin) or 0, tonumber(r.reward_ema) or 0
local rewarded = (tonumber(r.rewarded) or 0) == 1
local rx = modalX + 38
if rewarded and (coin > 0 or ema > 0) then
if coin > 0 then local s1 = formatPrice(coin) .. " COINS"; writeText(rx, ry, s1, Colors.accent_cyan, Colors.bg_modal); rx = rx + unicode.len(s1)
if ema > 0 then writeText(rx, ry, " & ", Colors.white, Colors.bg_modal); rx = rx + 3; writeText(rx, ry, formatPrice(ema) .. " EM", Colors.tomato, Colors.bg_modal) end
elseif ema > 0 then writeText(rx, ry, formatPrice(ema) .. " EM", Colors.tomato, Colors.bg_modal) end
else writeText(rx, ry, "Отсутствует", Colors.text_gray, Colors.bg_modal) end
writeText(modalX + 65, ry, cut(r.admin_comment or "", modalW - 67), Colors.text_main, Colors.bg_modal)
ry = ry + 1
end
if #reps == 0 then writeText(modalX + 2, ry, "У вас пока нет репортов.", Colors.text_gray, Colors.bg_modal) end
drawButton(modalX + math.floor((modalW - 12) / 2), modalY + modalH - 2, 12, 1, "[ Назад ]", Colors.bg_button, Colors.white, "my_reports_back")
else
local lines = data.lines or {}
if data.text and #lines == 0 then table.insert(lines, data.text) end
for i = 1, math.min(#lines, modalH - 5) do drawCenteredText(modalY + 2 + i, tostring(lines[i]), Colors.text_bright, Colors.bg_modal) end
drawButton(modalX + math.floor((modalW - 20) / 2), modalY + modalH - 2, 20, 1, "[ ПОНЯТНО ]", Colors.bg_button, Colors.white, "modal_ok")
end
end
function drawCategoryDropdown()
if not State.categoryDropdownOpen then return end
local dropdownX = UI.header.searchX + UI.header.searchW + UI.header.clearBtnW + 1 + UI.header.allBtnW
local dropdownY, dropdownW = UI.header.dropdownY, UI.header.dropdownW
local dropdownH = #Data.categoryOrder + 2
Buffer.fill(dropdownX, dropdownY, dropdownW, dropdownH, " ", Colors.text_bright, Colors.bg_dropdown)
drawBox(dropdownX, dropdownY, dropdownW, dropdownH, Colors.dropdown_border, Colors.bg_dropdown)
writeText(dropdownX + 2, dropdownY + 1, "КАТЕГОРИЯ", Colors.cyan, Colors.bg_dropdown)
for i, catName in ipairs(Data.categoryOrder) do
local isSelected = (catName == State.currentCategory)
local bg = isSelected and Colors.dropdown_active or Colors.bg_dropdown
local fg = isSelected and Colors.white or Colors.text_bright
Buffer.fill(dropdownX + 1, dropdownY + 1 + i, dropdownW - 2, 1, " ", fg, bg)
writeText(dropdownX + 2, dropdownY + 1 + i, (isSelected and "▸ " or "  ") .. catName, fg, bg)
table.insert(State.buttons, { id = "category_" .. i, x = dropdownX + 1, y = dropdownY + 1 + i, w = dropdownW - 2, h = 1, category = catName })
end
end
function drawHeader()
Buffer.fill(1, 1, Config.SCREEN_W, 3, " ", Colors.text_bright, Colors.bg_header)
local searchX, searchW = UI.header.searchX, UI.header.searchW
writeText(searchX, 2, "[", Colors.cyan, Colors.bg_search)
Buffer.fill(searchX + 1, 2, searchW - 2, 1, " ", Colors.text_bright, Colors.bg_search)
writeText(searchX + searchW - 1, 2, "]", Colors.cyan, Colors.bg_search)
local displayText = State.searchInputActive and State.searchInput or (State.searchInput == "" and "Поиск..." or State.searchInput)
writeText(searchX + 2, 2, displayText, State.searchInputActive and Colors.accent_cyan or (State.searchInput == "" and Colors.text_dark or Colors.text_bright), Colors.bg_search)
local clearBtnX = searchX + searchW + 1
fillBox(clearBtnX, 2, UI.header.clearBtnW, 1, Colors.bg_button)
writeText(clearBtnX + 1, 2, "[", Colors.white, Colors.bg_button)
writeText(clearBtnX + 2, 2, "X", Colors.blue, Colors.bg_button)
writeText(clearBtnX + 3, 2, "]", Colors.white, Colors.bg_button)
table.insert(State.buttons, { id = "clear_search", x = clearBtnX, y = 2, w = UI.header.clearBtnW, h = 1 })
if State.currentShopMode == "buy" then
local allBtnX = clearBtnX + UI.header.clearBtnW + 1
local allBtnText = State.currentCategory == "ВСЕ" and "ВСЕ ↓" or State.currentCategory .. " ↓"
fillBox(allBtnX, 2, UI.header.allBtnW, 1, State.categoryDropdownOpen and Colors.dropdown_active or Colors.bg_button)
writeText(allBtnX + 1, 2, "[", Colors.white, State.categoryDropdownOpen and Colors.dropdown_active or Colors.bg_button)
writeText(allBtnX + 2, 2, allBtnText, Colors.white, State.categoryDropdownOpen and Colors.dropdown_active or Colors.bg_button)
writeText(allBtnX + 2 + unicode.len(allBtnText), 2, "]", Colors.white, State.categoryDropdownOpen and Colors.dropdown_active or Colors.bg_button)
table.insert(State.buttons, { id = "toggle_category", x = allBtnX, y = 2, w = UI.header.allBtnW, h = 1 })
end
local panelXh = math.floor(Config.SCREEN_W * UI.list.wRatio) + 2
local panelWh = Config.SCREEN_W - panelXh
local caption = "ДОБРО ПОЖАЛОВАТЬ НА TRADE MARKET SHOP!"
local tradeMarketX = panelXh + math.floor((panelWh - unicode.len(caption)) / 2)
writeText(tradeMarketX, 2, caption, Colors.cyan, Colors.bg_header)
local listW = math.floor(Config.SCREEN_W * UI.list.wRatio)
Buffer.fill(1, 4, listW, 1, " ", Colors.text_bright, Colors.line)
Buffer.fill(listW + 2, 4, Config.SCREEN_W - listW - 1, 1, " ", Colors.text_bright, Colors.line)
end
function drawItemList()
local listX, listY = UI.list.x, UI.list.y
local listW = math.floor(Config.SCREEN_W * UI.list.wRatio)
local listH = Config.SCREEN_H - 7
Buffer.fill(listX, listY, listW, listH, " ", Colors.text_bright, Colors.bg_main)
drawBox(listX, listY, listW, listH, Colors.line, Colors.bg_main)
if State.currentShopMode == "sets" then
if State.setView == "list" then
local title = "КАТАЛОГ НАБОРОВ"
writeText(listX + 2, listY + 1, title, Colors.cyan, Colors.bg_main)
local dashStart = listX + 2 + unicode.len(title) + 1
local dashEnd = listX + listW - 2
if dashEnd > dashStart then for x = dashStart, dashEnd do Buffer.set(x, listY + 1, "-", Colors.line, Colors.bg_main) end end
local colY = listY + 2
Buffer.fill(listX + 1, colY, listW - 2, 1, " ", Colors.text_bright, Colors.bg_panel)
writeText(listX + 2, colY, "НАЗВАНИЕ", Colors.text_bright, Colors.bg_panel)
writeText(listX + listW - 32, colY, "СТАТУС", Colors.text_bright, Colors.bg_panel)
writeText(listX + listW - 22, colY, "COINS", Colors.accent_cyan, Colors.bg_panel)
writeText(listX + listW - 12, colY, "EM", Colors.tomato, Colors.bg_panel)
State.visibleRows = listH - 4
local maxScroll = math.max(0, #Data.setsDisplay - State.visibleRows)
State.listScroll = math.max(1, math.min(State.listScroll, maxScroll + 1))
for row = 1, State.visibleRows do
local idx = State.listScroll + row - 1
local s = Data.setsDisplay[idx]
local y = listY + 3 + row
if s then
local isSelected = (idx == State.selectedIndex)
local bg = isSelected and Colors.bg_selected or Colors.bg_main
Buffer.fill(listX + 1, y, listW - 2, 1, " ", Colors.text_bright, bg)
local symbol = isSelected and ">" or "*"
writeText(listX + 2, y, symbol, isSelected and Colors.cyan or Colors.purple, bg)
local name = s.name or ""
if unicode.len(name) > 38 then name = unicode.sub(name, 1, 37) .. "…" end
writeText(listX + 4, y, name, isSelected and Colors.white or Colors.text_bright, bg)
local st, stCol
local pr = setProgressGet(s.id)
if pr then st, stCol = "ОЖИДАЕТ", Colors.warning
elseif setIsAvailableLocal(s) then st, stCol = "ГОТОВ", Colors.success_green
else st, stCol = "НЕТ В МЭ", Colors.text_dark end
writeText(listX + listW - 32, y, st, stCol, bg)
writeText(listX + listW - 22, y, formatPrice(s.price_coin or 0), (s.price_coin or 0) > 0 and Colors.accent_cyan or Colors.text_dark, bg)
writeText(listX + listW - 12, y, formatPrice(s.price_ema or 0), (s.price_ema or 0) > 0 and Colors.tomato or Colors.text_dark, bg)
else Buffer.fill(listX + 1, y, listW - 2, 1, " ", Colors.text_bright, Colors.bg_main) end
end
else
local s = State.selectedSet
local title = "СОДЕРЖИМОЕ НАБОРА"
writeText(listX + 2, listY + 1, title, Colors.cyan, Colors.bg_main)
local dashStart = listX + 2 + unicode.len(title) + 1
local dashEnd = listX + listW - 2
if dashEnd > dashStart then for x = dashStart, dashEnd do Buffer.set(x, listY + 1, "-", Colors.line, Colors.bg_main) end end
if s then writeText(listX + listW - 2 - unicode.len("[" .. (s.name or "") .. "]"), listY + 1, "[" .. (s.name or "") .. "]", Colors.accent_cyan, Colors.bg_main) end
local colY = listY + 2
Buffer.fill(listX + 1, colY, listW - 2, 1, " ", Colors.text_bright, Colors.bg_panel)
writeText(listX + 2, colY, "ПРЕДМЕТ", Colors.text_bright, Colors.bg_panel)
writeText(listX + listW - 32, colY, "В МЭ", Colors.text_bright, Colors.bg_panel)
writeText(listX + listW - 16, colY, "ПОЛУЧЕНО", Colors.accent_cyan, Colors.bg_panel)
State.visibleRows = listH - 4
local items = (s and s.items) or {}
local maxScroll = math.max(0, #items - State.visibleRows)
State.listScroll = math.max(1, math.min(State.listScroll, maxScroll + 1))
for row = 1, State.visibleRows do
local idx = State.listScroll + row - 1
local it = items[idx]
local y = listY + 3 + row
if it then
local isSelected = (State.selectedSetItem and State.selectedSetItem.internalName == it.internalName and (State.selectedSetItem.damage or 0) == (it.damage or 0))
local bg = isSelected and Colors.bg_selected or Colors.bg_main
Buffer.fill(listX + 1, y, listW - 2, 1, " ", Colors.text_bright, bg)
local symbol = isSelected and ">" or "*"
writeText(listX + 2, y, symbol, isSelected and Colors.cyan or Colors.purple, bg)
local name = it.displayName or it.internalName or ""
if unicode.len(name) > 34 then name = unicode.sub(name, 1, 33) .. "…" end
writeText(listX + 4, y, name, isSelected and Colors.white or Colors.text_bright, bg)
local mc = meCountOf(it.internalName, it.damage)
writeText(listX + listW - 32, y, formatQtyCompact(mc), mc > 0 and Colors.success_green or Colors.text_dark, bg)
local got = setDispensedForLocal(s, it)
local need = tonumber(it.qty) or 0
local gotCol = (got >= need and need > 0) and Colors.success_green or (got > 0 and Colors.warning or Colors.text_dark)
writeText(listX + listW - 16, y, got .. "/" .. need, gotCol, bg)
else Buffer.fill(listX + 1, y, listW - 2, 1, " ", Colors.text_bright, Colors.bg_main) end
end
end
return
end
local title = State.currentShopMode == "buy" and "КАТАЛОГ ПРЕДМЕТОВ" or "МАГАЗИН ПОКУПАЕТ"
writeText(listX + 2, listY + 1, title, Colors.cyan, Colors.bg_main)
local dashStart = listX + 2 + unicode.len(title) + 1
local dashEnd = listX + listW - 2
if dashEnd > dashStart then for x = dashStart, dashEnd do Buffer.set(x, listY + 1, "-", Colors.line, Colors.bg_main) end end
if State.currentShopMode == "buy" then
if State.currentCategory ~= "ВСЕ" then writeText(listX + listW - 2 - unicode.len("[" .. State.currentCategory .. "]"), listY + 1, "[" .. State.currentCategory .. "]", Colors.accent_cyan, Colors.bg_main)
else writeText(listX + listW - 2 - unicode.len("ВСЕ МОДЫ"), listY + 1, "ВСЕ МОДЫ", Colors.text_dark, Colors.bg_main) end
end
local colY = listY + 2
Buffer.fill(listX + 1, colY, listW - 2, 1, " ", Colors.text_bright, Colors.bg_panel)
writeText(listX + 2, colY, "НАЗВАНИЕ", Colors.text_bright, Colors.bg_panel)
writeText(listX + listW - 32, colY, "В НАЛ.", Colors.text_bright, Colors.bg_panel)
writeText(listX + listW - 22, colY, "COINS", Colors.accent_cyan, Colors.bg_panel)
writeText(listX + listW - 12, colY, "EM", Colors.tomato, Colors.bg_panel)
State.visibleRows = listH - 4
local maxScroll = math.max(0, #Data.filteredItems - State.visibleRows)
State.listScroll = math.max(1, math.min(State.listScroll, maxScroll + 1))
for row = 1, State.visibleRows do
local idx = State.listScroll + row - 1
local item = Data.filteredItems[idx]
local y = listY + 3 + row
if item then
local isSelected = (idx == State.selectedIndex)
local bg = isSelected and Colors.bg_selected or Colors.bg_main
Buffer.fill(listX + 1, y, listW - 2, 1, " ", Colors.text_bright, bg)
local symbol = isSelected and ">" or "*"
local symbolColor = isSelected and Colors.cyan or ((item.qty or 0) > 0 and Colors.success_green or Colors.dark_gray)
writeText(listX + 2, y, symbol, symbolColor, bg)
local name = item.displayName or item.internalName or ""
if unicode.len(name) > 38 then name = unicode.sub(name, 1, 37) .. "…" end
local nameColor = isSelected and Colors.white or (State.currentShopMode == "buy" and (item.qty or 0) == 0 and Colors.text_dark or Colors.text_bright)
writeText(listX + 4, y, name, nameColor, bg)
writeText(listX + listW - 32, y, formatQtyCompact(item.qty or 0), (item.qty or 0) > 0 and Colors.success_green or Colors.text_dark, bg)
if State.currentShopMode == "buy" then
local dc, de = buyPrice(item)
writeText(listX + listW - 22, y, formatPrice(dc), dc > 0 and Colors.accent_cyan or Colors.text_dark, bg)
writeText(listX + listW - 12, y, formatPrice(de), de > 0 and Colors.tomato or Colors.text_dark, bg)
else
writeText(listX + listW - 22, y, formatPrice(item.priceCoin), (item.priceCoin or 0) > 0 and Colors.accent_cyan or Colors.text_dark, bg)
writeText(listX + listW - 12, y, formatPrice(item.priceEma), (item.priceEma or 0) > 0 and Colors.tomato or Colors.text_dark, bg)
end
else Buffer.fill(listX + 1, y, listW - 2, 1, " ", Colors.text_bright, Colors.bg_main) end
end
end
function drawLogBlock(panelX, panelW, logY, logH)
drawBox(panelX, logY, panelW, logH, Colors.line, Colors.bg_main)
writeText(panelX + 2, logY + 1, "ЛОГИРОВАНИЕ", Colors.cyan, Colors.bg_main)
local ds = panelX + 2 + unicode.len("ЛОГИРОВАНИЕ") + 1
local de = panelX + panelW - 2
if de > ds then for x = ds, de do Buffer.set(x, logY + 1, "-", Colors.line, Colors.bg_main) end end
local maxH = logH - 3
local entries = State.logMessages
local sel = {}
local used = 0
local i = #entries
while i >= 1 do
local g = (i < #entries) and (entries[i].gap or 1) or 0
local cost = 1 + g
if used + cost > maxH then break end
used = used + cost
table.insert(sel, 1, i)
i = i - 1
end
local y = logY + 3
for k, idx in ipairs(sel) do
local e = entries[idx]
if y > logY + logH - 2 then break end
if e.segs then
local w = 0
for _, s in ipairs(e.segs) do w = w + unicode.len(s[1]) end
local xx = panelX + math.floor((panelW - w) / 2)
for _, s in ipairs(e.segs) do writeText(xx, y, s[1], s[2], Colors.bg_main); xx = xx + unicode.len(s[1]) end
else
local msg = tostring(e.text or "")
writeText(panelX + math.floor((panelW - unicode.len(msg)) / 2), y, msg, e.color or Colors.text_bright, Colors.bg_main)
end
if k < #sel then y = y + 1 + (e.gap or 1) else y = y + 1 end
end
end
function drawAutocraftBox(panelX, panelY, panelW, topH, job)
drawBox(panelX, panelY, panelW, topH, Colors.line, Colors.bg_main)
local title = "АВТОКРАФТ"
writeText(panelX + 2, panelY + 1, title, Colors.cyan, Colors.bg_main)
local ds = panelX + 2 + unicode.len(title) + 1
local de = panelX + panelW - 2
if de > ds then for x = ds, de do Buffer.set(x, panelY + 1, "-", Colors.line, Colors.bg_main) end end
local segsList = {}
table.insert(segsList, { { "ПРЕДМЕТ: ", Colors.text_bright }, { tostring(job.displayName or ""), Colors.accent_cyan } })
table.insert(segsList, { { "ЗАКАЗАНО: ", Colors.text_bright }, { tostring(job.ordered or 0) .. " шт", Colors.accent_cyan } })
table.insert(segsList, { { "В ME СЕЙЧАС: ", Colors.text_bright }, { tostring(job.inStock or 0) .. " шт", Colors.accent_cyan } })
table.insert(segsList, { { "БУДЕТ СОЗДАНО: ", Colors.text_bright }, { tostring(job.toCraft or 0) .. " шт", Colors.accent_cyan } })
local tc = (job.unitCoin or 0) * (job.ordered or 0)
local te = (job.unitEma or 0) * (job.ordered or 0)
table.insert(segsList, { { "ИТОГО: ", Colors.text_bright }, { formatPrice(tc) .. " COINS", Colors.accent_cyan }, { " | ", Colors.text_bright }, { formatPrice(te) .. " EMA", Colors.tomato } })
local maxW = 0
for _, s in ipairs(segsList) do local w = 0; for _, seg in ipairs(s) do w = w + unicode.len(seg[1]) end; if w > maxW then maxW = w end end
local startX = panelX + math.floor((panelW - maxW) / 2)
local y = panelY + 4
for _, s in ipairs(segsList) do
local xx = startX
for _, seg in ipairs(s) do writeText(xx, y, seg[1], seg[2], Colors.bg_main); xx = xx + unicode.len(seg[1]) end
y = y + 2
end
if job.phase == "confirm" then
local bw = 18
local bx = panelX + math.floor((panelW - bw) / 2)
drawButton(bx, panelY + topH - 6, bw, 1, "[ Начать крафт ]", Colors.accent_cyan, Colors.bg_main, "autocraft_start")
local ow = 12
local ox = panelX + math.floor((panelW - ow) / 2)
drawButton(ox, panelY + topH - 3, ow, 1, "[ Отмена ]", Colors.bg_button, Colors.white, "autocraft_close")
else
local warn = "НЕ СХОДИТЕ С PIM ДО ВЫДАЧИ ПРЕДМЕТОВ"
writeText(panelX + math.floor((panelW - unicode.len(warn)) / 2), panelY + topH - 2, warn, Colors.error_red, Colors.bg_main)
end
end
function drawItemBox(panelX, panelY, panelW, topH, item)
drawBox(panelX, panelY, panelW, topH, Colors.line, Colors.bg_main)
local title = State.currentShopMode == "buy" and "ПОКУПАЕМЫЙ ПРЕДМЕТ" or "ПРОДАЖА ПРЕДМЕТА"
writeText(panelX + 2, panelY + 1, title, Colors.cyan, Colors.bg_main)
local ds = panelX + 2 + unicode.len(title) + 1
local de = panelX + panelW - 2
if de > ds then for x = ds, de do Buffer.set(x, panelY + 1, "-", Colors.line, Colors.bg_main) end end
local lineSpacing = 2
local baseY = panelY + 3
writeText(panelX + 2, baseY, "ПРЕДМЕТ: " .. (item.displayName or item.internalName or ""), Colors.text_bright, Colors.bg_main)
local hasCategory = (State.currentShopMode == "buy" and item.article and item.article ~= "")
if hasCategory then writeText(panelX + 2, baseY + lineSpacing, "ТЕГИ: " .. item.article, Colors.accent_cyan, Colors.bg_main) end
local availY = baseY + lineSpacing + (hasCategory and lineSpacing or 0)
local acY, priceY
if State.currentShopMode == "buy" then
writeText(panelX + 2, availY, "В НАЛИЧИИ: " .. formatQtySpaces(item.qty or 0) .. " шт.", (item.qty or 0) > 0 and Colors.success_green or Colors.text_dark, Colors.bg_main)
acY = availY + lineSpacing
local acSt = acStatusOf(item)
local acText = acSt == "yes" and "ДОСТУПЕН" or (acSt == "no" and "НЕТ ШАБЛОНА" or "ПРОВЕРКА...")
local acColor = acSt == "yes" and Colors.success_green or (acSt == "no" and Colors.text_dark or Colors.cyan)
writeText(panelX + 2, acY, "АВТОКРАФТ: " .. acText, acColor, Colors.bg_main)
priceY = acY + lineSpacing
else
writeText(panelX + 2, availY, "У ВАС: " .. formatQtySpaces(State.sellPlayerQty) .. " шт.", State.sellPlayerQty > 0 and Colors.success_green or Colors.text_dark, Colors.bg_main)
priceY = availY + lineSpacing
end
local coinPrice, emaPrice
if State.currentShopMode == "buy" then coinPrice, emaPrice = buyPrice(item) else coinPrice, emaPrice = item.priceCoin or 0, item.priceEma or 0 end
writeText(panelX + 2, priceY, "ЦЕНА: ", Colors.text_bright, Colors.bg_main)
local priceX = panelX + 2 + unicode.len("ЦЕНА: ")
local coinStr, emaStr = formatPrice(coinPrice), formatPrice(emaPrice)
if coinPrice > 0 and emaPrice > 0 then
writeText(priceX, priceY, coinStr .. " COINS", Colors.accent_cyan, Colors.bg_main); priceX = priceX + unicode.len(coinStr .. " COINS")
writeText(priceX, priceY, " & ", Colors.text_bright, Colors.bg_main); priceX = priceX + 3
writeText(priceX, priceY, emaStr .. " EM", Colors.tomato, Colors.bg_main)
elseif coinPrice > 0 then writeText(priceX, priceY, coinStr .. " COINS", Colors.accent_cyan, Colors.bg_main)
elseif emaPrice > 0 then writeText(priceX, priceY, emaStr .. " EM", Colors.tomato, Colors.bg_main)
else writeText(priceX, priceY, "Бесплатно", Colors.text_bright, Colors.bg_main) end
local qtyTitleY = priceY + lineSpacing
writeText(panelX + 2, qtyTitleY, "КОЛИЧЕСТВО", Colors.cyan, Colors.bg_main)
local qds = panelX + 2 + unicode.len("КОЛИЧЕСТВО") + 1
local qde = panelX + panelW - 2
if qde > qds then for x = qds, qde do Buffer.set(x, qtyTitleY, "-", Colors.line, Colors.bg_main) end end
local inputY = qtyTitleY + 2
local inputW = 12
writeText(panelX + 2, inputY, "[", Colors.cyan, Colors.bg_input)
Buffer.fill(panelX + 3, inputY, inputW, 1, " ", Colors.text_bright, Colors.bg_input)
writeText(panelX + 3 + inputW, inputY, "]", Colors.cyan, Colors.bg_input)
local qty = State.currentShopMode == "buy" and State.purchaseQuantity or State.sellQuantity
local isActive = State.currentShopMode == "buy" and State.purchaseInputActive or State.sellInputActive
writeText(panelX + 4, inputY, tostring(qty), isActive and Colors.accent_cyan or Colors.text_bright, Colors.bg_input)
local maxBtnX = panelX + 4 + inputW + 2
fillBox(maxBtnX, inputY, 8, 1, Colors.bg_button)
writeText(maxBtnX + 1, inputY, "[МАКС]", Colors.text_bright, Colors.bg_button)
table.insert(State.buttons, { id = "max_qty", x = maxBtnX, y = inputY, w = 8, h = 1 })
local buyBtnX = maxBtnX + 10
if State.currentShopMode == "buy" then
local overStock = qty > (item.qty or 0)
local useCraft = overStock and acAvailable(item)
local canBuy = qty > 0 and not State.TRANSACTION_LOCK and (useCraft or (item.qty or 0) > 0)
local btnW2 = useCraft and 19 or 10
local label = useCraft and " [ ЗАКАЗАТЬ КРАФТ ]" or " [КУПИТЬ]"
local btnId = useCraft and "order_craft" or "buy_item"
local btnBg = canBuy and (useCraft and Colors.purple or Colors.success_green) or Colors.text_dark
fillBox(buyBtnX, inputY, btnW2, 1, btnBg)
writeText(buyBtnX, inputY, label, Colors.white, btnBg)
table.insert(State.buttons, { id = btnId, x = buyBtnX, y = inputY, w = btnW2, h = 1 })
else
local canSell = State.sellPlayerQty > 0 and qty > 0 and not State.TRANSACTION_LOCK
fillBox(buyBtnX, inputY, 11, 1, canSell and Colors.success_green or Colors.text_dark)
writeText(buyBtnX, inputY, " [ПРОДАТЬ]", Colors.white, canSell and Colors.success_green or Colors.text_dark)
table.insert(State.buttons, { id = "sell_item", x = buyBtnX, y = inputY, w = 11, h = 1 })
end
local totalY = inputY + 2
local totalCoin, totalEma = coinPrice * qty, emaPrice * qty
writeText(panelX + 2, totalY, "Итого: ", Colors.text_bright, Colors.bg_main)
local totalX = panelX + 2 + unicode.len("Итого: ")
local totalCoinStr, totalEmaStr = formatPrice(totalCoin), formatPrice(totalEma)
if totalCoin > 0 and totalEma > 0 then
writeText(totalX, totalY, totalCoinStr .. " COINS", Colors.accent_cyan, Colors.bg_main); totalX = totalX + unicode.len(totalCoinStr .. " COINS")
writeText(totalX, totalY, " | ", Colors.text_bright, Colors.bg_main); totalX = totalX + 3
writeText(totalX, totalY, totalEmaStr .. " EM", Colors.tomato, Colors.bg_main)
elseif totalCoin > 0 then writeText(totalX, totalY, totalCoinStr .. " COINS", Colors.accent_cyan, Colors.bg_main)
elseif totalEma > 0 then writeText(totalX, totalY, totalEmaStr .. " EM", Colors.tomato, Colors.bg_main)
else writeText(totalX, totalY, "Бесплатно", Colors.text_bright, Colors.bg_main) end
end
function drawSetBox(panelX, panelY, panelW, topH, set)
drawBox(panelX, panelY, panelW, topH, Colors.line, Colors.bg_main)
local title = "ПОКУПАЕМЫЙ НАБОР"
writeText(panelX + 2, panelY + 1, title, Colors.cyan, Colors.bg_main)
local ds = panelX + 2 + unicode.len(title) + 1
local de = panelX + panelW - 2
if de > ds then for x = ds, de do Buffer.set(x, panelY + 1, "-", Colors.line, Colors.bg_main) end end
local lineSpacing = 2
local baseY = panelY + 3
writeText(panelX + 2, baseY, "НАБОР: " .. (set.name or ""), Colors.text_bright, Colors.bg_main)
local pr = setProgressOf(set)
local stText, stColor
if pr then stText, stColor = "ОЖИДАЕТ ВЫДАЧИ", Colors.warning
elseif setIsAvailableLocal(set) then stText, stColor = "ГОТОВ К ВЫДАЧЕ", Colors.success_green
else stText, stColor = "НЕДОСТУПЕН", Colors.text_dark end
writeText(panelX + 2, baseY + lineSpacing, "СТАТУС: " .. stText, stColor, Colors.bg_main)
local coinPrice, emaPrice = set.price_coin or 0, set.price_ema or 0
writeText(panelX + 2, baseY + lineSpacing * 2, "ЦЕНА: ", Colors.text_bright, Colors.bg_main)
local priceX = panelX + 2 + unicode.len("ЦЕНА: ")
local coinStr, emaStr = formatPrice(coinPrice), formatPrice(emaPrice)
if coinPrice > 0 and emaPrice > 0 then
writeText(priceX, baseY + lineSpacing * 2, coinStr .. " COINS", Colors.accent_cyan, Colors.bg_main); priceX = priceX + unicode.len(coinStr .. " COINS")
writeText(priceX, baseY + lineSpacing * 2, " & ", Colors.text_bright, Colors.bg_main); priceX = priceX + 3
writeText(priceX, baseY + lineSpacing * 2, emaStr .. " EMA", Colors.tomato, Colors.bg_main)
elseif coinPrice > 0 then writeText(priceX, baseY + lineSpacing * 2, coinStr .. " COINS", Colors.accent_cyan, Colors.bg_main)
elseif emaPrice > 0 then writeText(priceX, baseY + lineSpacing * 2, emaStr .. " EMA", Colors.tomato, Colors.bg_main)
else writeText(priceX, baseY + lineSpacing * 2, "Бесплатно", Colors.text_bright, Colors.bg_main) end
local bw = 22
local bx = panelX + math.floor((panelW - bw) / 2)
drawButton(bx, panelY + topH - 3, bw, 1, "[ Перейти к набору ]", Colors.purple, Colors.white, "set_open")
end
function drawSetContentsBox(panelX, panelY, panelW, topH, set)
drawBox(panelX, panelY, panelW, topH, Colors.line, Colors.bg_main)
local title = "СОДЕРЖИМОЕ НАБОРА"
writeText(panelX + 2, panelY + 1, title, Colors.cyan, Colors.bg_main)
local ds = panelX + 2 + unicode.len(title) + 1
local de = panelX + panelW - 2
if de > ds then for x = ds, de do Buffer.set(x, panelY + 1, "-", Colors.line, Colors.bg_main) end end
local lineSpacing = 2
local baseY = panelY + 3
writeText(panelX + 2, baseY, "НАБОР: " .. (set.name or ""), Colors.text_bright, Colors.bg_main)
local it = State.selectedSetItem
if it then
writeText(panelX + 2, baseY + lineSpacing, "ПРЕДМЕТ: " .. (it.displayName or it.internalName or ""), Colors.text_bright, Colors.bg_main)
writeText(panelX + 2, baseY + lineSpacing * 2, "В НАБОРЕ: " .. (tonumber(it.qty) or 0), Colors.text_bright, Colors.bg_main)
local got = setDispensedForLocal(set, it)
local need = tonumber(it.qty) or 0
local gotColor = (got >= need and need > 0) and Colors.success_green or (got > 0 and Colors.warning or Colors.text_dark)
writeText(panelX + 2, baseY + lineSpacing * 3, "ПОЛУЧЕНО: " .. got .. "/" .. need, gotColor, Colors.bg_main)
else
writeText(panelX + 2, baseY + lineSpacing, "ПРЕДМЕТ: не выбран", Colors.text_dark, Colors.bg_main)
end
local qtyTitleY = baseY + lineSpacing * 4
writeText(panelX + 2, qtyTitleY, "КОЛИЧЕСТВО", Colors.cyan, Colors.bg_main)
local qds = panelX + 2 + unicode.len("КОЛИЧЕСТВО") + 1
local qde = panelX + panelW - 2
if qde > qds then for x = qds, qde do Buffer.set(x, qtyTitleY, "-", Colors.line, Colors.bg_main) end end
local inputY = qtyTitleY + 2
writeText(panelX + 2, inputY, "[", Colors.cyan, Colors.bg_input)
Buffer.fill(panelX + 3, inputY, 12, 1, " ", Colors.text_bright, Colors.bg_input)
writeText(panelX + 3 + 12, inputY, "]", Colors.cyan, Colors.bg_input)
writeText(panelX + 4, inputY, "1", Colors.text_dark, Colors.bg_input)
local btnY = inputY + 2
local pr = setProgressOf(set)
local bought = pr and not pr.completed
local bw1, bw2 = 18, 11
local bx1 = panelX + 2
local bx2 = bx1 + bw1 + 2
if bought then
drawButton(bx1, btnY, bw1, 1, "[ Выдать набор ]", Colors.blue, Colors.white, "set_dispense")
else
drawButton(bx1, btnY, bw1, 1, "[ Купить набор ]", Colors.success_green, Colors.white, "set_buy")
end
drawButton(bx2, btnY, bw2, 1, "[ Назад ]", Colors.bg_button, Colors.white, "set_back")
local totalY = btnY + 2
if bought then
local dispTotal = setTotalDispensedLocal(set)
local reqTotal = setTotalQtyLocal(set)
writeText(panelX + 2, totalY, "ВЫДАНО: " .. dispTotal .. "/" .. reqTotal, Colors.warning, Colors.bg_main)
else
local coinPrice, emaPrice = set.price_coin or 0, set.price_ema or 0
writeText(panelX + 2, totalY, "ИТОГО: ", Colors.text_bright, Colors.bg_main)
local totalX = panelX + 2 + unicode.len("ИТОГО: ")
local totalCoinStr, totalEmaStr = formatPrice(coinPrice), formatPrice(emaPrice)
if coinPrice > 0 and emaPrice > 0 then
writeText(totalX, totalY, totalCoinStr .. " COINS", Colors.accent_cyan, Colors.bg_main); totalX = totalX + unicode.len(totalCoinStr .. " COINS")
writeText(totalX, totalY, " & ", Colors.text_bright, Colors.bg_main); totalX = totalX + 3
writeText(totalX, totalY, totalEmaStr .. " EMA", Colors.tomato, Colors.bg_main)
elseif coinPrice > 0 then writeText(totalX, totalY, totalCoinStr .. " COINS", Colors.accent_cyan, Colors.bg_main)
elseif emaPrice > 0 then writeText(totalX, totalY, totalEmaStr .. " EMA", Colors.tomato, Colors.bg_main)
else writeText(totalX, totalY, "Бесплатно", Colors.text_bright, Colors.bg_main) end
end
end
function drawAccBox(panelX, panelW, accY, accH)
fillBox(panelX, accY, panelW, accH, Colors.bg_panel)
drawBox(panelX, accY, panelW, accH, Colors.line, Colors.bg_panel)
local title = "АККАУНТ"
writeText(panelX + 2, accY + 1, title, Colors.cyan, Colors.bg_panel)
local ds = panelX + 2 + unicode.len(title) + 1
local de = panelX + panelW - 2
if de > ds then for x = ds, de do Buffer.set(x, accY + 1, "-", Colors.line, Colors.bg_panel) end end
if State.currentSession then
writeText(panelX + 2, accY + 3, "Имя: ", Colors.text_main, Colors.bg_panel)
writeText(panelX + 2 + unicode.len("Имя: "), accY + 3, (State.currentPlayer or "Неизвестно"), Colors.accent_cyan, Colors.bg_panel)
writeText(panelX + 2, accY + 5, "Баланс: ", Colors.text_main, Colors.bg_panel)
local balX = panelX + 2 + unicode.len("Баланс: ")
writeText(balX, accY + 5, string.format("%.3f", State.currentSession.balance or 0) .. " COINS", Colors.accent_cyan, Colors.bg_panel)
balX = balX + unicode.len(string.format("%.3f", State.currentSession.balance or 0) .. " COINS")
writeText(balX, accY + 5, " | ", Colors.text_main, Colors.bg_panel); balX = balX + 3
writeText(balX, accY + 5, string.format("%.2f", State.currentSession.emaBalance or 0) .. " EMA", Colors.tomato, Colors.bg_panel)
-- СТРОКА СКИДКИ + кнопка [ ? ]
local disc = State.currentSession.discountPercent or 0
local discTxt = "Скидка: " .. disc .. "%"
writeText(panelX + 2, accY + 7, discTxt, disc > 0 and Colors.success_green or Colors.text_gray, Colors.bg_panel)
local qBtnX = panelX + 2 + unicode.len(discTxt) + 1
fillBox(qBtnX, accY + 7, 3, 1, Colors.bg_button)
writeText(qBtnX, accY + 7, "[?]", Colors.cyan, Colors.bg_button)
table.insert(State.buttons, { id = "discount_info", x = qBtnX, y = accY + 7, w = 3, h = 1 })
writeText(panelX + 2, accY + 9, "Транзакции: ", Colors.text_main, Colors.bg_panel)
writeText(panelX + 2 + unicode.len("Транзакции: "), accY + 9, tostring(State.currentSession.transactions or 0), Colors.accent_cyan, Colors.bg_panel)
else writeText(panelX + 2, accY + 5, "Не авторизован", Colors.error_red, Colors.bg_panel) end
end
function drawRightPanel()
local panelX = math.floor(Config.SCREEN_W * UI.list.wRatio) + 2
local panelW = Config.SCREEN_W - (math.floor(Config.SCREEN_W * UI.list.wRatio) + 2)
local panelY, panelH = 5, Config.SCREEN_H - 7
local topH = 20
local gap = 1
local accH = 10
local accY = panelY + panelH - accH
local logY = panelY + topH + gap
local logH = accY - logY - gap
if State.currentShopMode == "sets" then
if State.setView == "contents" and State.selectedSet then
drawSetContentsBox(panelX, panelY, panelW, topH, State.selectedSet)
elseif State.selectedSet then
drawSetBox(panelX, panelY, panelW, topH, State.selectedSet)
else
drawBox(panelX, panelY, panelW, topH, Colors.line, Colors.bg_main)
writeText(panelX + 2, panelY + 4, "Набор не выбран", Colors.text_dark, Colors.bg_main)
end
drawLogBlock(panelX, panelW, logY, logH)
drawAccBox(panelX, panelW, accY, accH)
return
end
local job = State.autocraftJob
local acActive = job and (job.phase == "confirm" or job.phase == "crafting" or job.phase == "dispensing")
if acActive then
drawAutocraftBox(panelX, panelY, panelW, topH, job)
elseif State.selectedItem then
drawItemBox(panelX, panelY, panelW, topH, State.selectedItem)
else
drawBox(panelX, panelY, panelW, topH, Colors.line, Colors.bg_main)
writeText(panelX + 2, panelY + 4, "Предмет не выбран", Colors.text_dark, Colors.bg_main)
end
drawLogBlock(panelX, panelW, logY, logH)
drawAccBox(panelX, panelW, accY, accH)
end
function drawBottomBar()
local y = Config.SCREEN_H - 2
Buffer.fill(1, y, Config.SCREEN_W, 3, " ", Colors.text_bright, Colors.bg_panel)
drawBox(1, y, Config.SCREEN_W, 3, Colors.line, Colors.bg_panel)
local btnW, btnH, spacing = UI.bottom.buttonW, 1, UI.bottom.spacing
local totalWidth = (btnW * 3) + (spacing * 2)
local startX = math.floor((Config.SCREEN_W - totalWidth) / 2)
local helpBtnW = 18
drawButton(4, y + 1, helpBtnW, btnH, "[ Нужна помощь ]", Colors.accent_cyan, Colors.white, "help_open")
local buyColor = State.currentShopMode == "buy" and Colors.success_green or Colors.bg_button
drawButton(startX, y + 1, btnW, btnH, "[ Покупки ]", buyColor, Colors.white, "page_buy")
local sellX = startX + btnW + spacing
local sellColor = State.currentShopMode == "sell" and Colors.tomato or Colors.bg_button
drawButton(sellX, y + 1, btnW, btnH, "[ Пополнение ]", sellColor, Colors.white, "page_sell")
local questX = sellX + btnW + spacing
local questColor = State.currentShopMode == "sets" and Colors.purple or Colors.bg_button
drawButton(questX, y + 1, btnW, btnH, " [ Наборы | Квесты ]", questColor, Colors.white, "page_quests")
writeText(Config.SCREEN_W - 30, Config.SCREEN_H, "Coded By Leytsfer v 6.10.6", Colors.text_dark, Colors.bg_panel)
local reportBtnW = 18
drawButton(Config.SCREEN_W - reportBtnW - 2, y + 1, reportBtnW, 1, "[ Нашёл ошибку ]", Colors.tomato, Colors.white, "report_bug")
end

local function expand2(t)
local out = ""
for i = 1, unicode.len(t) do
local c = unicode.sub(t, i, i)
out = out .. c .. c
end
return out
end



-- AUTO-GENERATED PIXEL ART (Trade Market welcome screen)
-- source: trade-market-4.png | cells: 100x29 | colors: 16
local ART_PALETTE = {
0x131620,
0x000000,
0x010101,
0x030000,
0x020307,
0x844B4B,
0x5891A9,
0xFFF489,
0xC0A66D,
0x3C5070,
0x18406C,
0x000005,
0xB9CAC5,
0x011836,
0xFFFFFF,
0xE9F1EC,
}
local ART_FG = {
"2111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111121111111111122111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111051145454111244111111111111111111111111111111111111111111",
"111111111111111111111111111111111111123135211578015784939a111111111111111111111111111111111111111111",
"1111111111111111111111111111111111112553258858877777888c646a2411111111111111111111111111111111111111",
"111111111111111111111111111111111121001500888505555850169da0d012111111111111111111111111111111111111",
"1111111111111111111111111111111111214058888557777778000666660441111111111111111111111111111111111111",
"11111111111111111111111111111111121504058558885148518866a66add42111111111111111111111111111111111111",
"1111111111111111111113333333331133303888808851577587666699666a43311111333333333111111111111111111111",
"1111111111111111123d6ccccccccca46ccccccca55b5856ccc6666666ccccccca421acccccccccd12111111111111111111",
"1111111111111111123dcfcfeefcfca4ceeffcceec985acefcfef9a6aceefccfeeca4afeefffffca12111111111111111111",
"111111111111111111111319eecd313dcee903aeefa56eec9596ee6adcee603d6ee62afef9aaaad121111111111111111111",
"111111111111111111111319eecd3b3dceeeeeeeec959eec9696ee669cee9404cee6bafeeeeeeea121111111111111111111",
"111111111111111111111319eecd3b30cee66eeead556eeeeeeeee69acee944acee6bafefa44444211111111111111111111",
"111111111111111111111319eecd3b30cee649feef959eec9596ee669ceeeeeeef9d2afeeeeeeefd12111111111111111111",
"11111111111111111111112a669d1210966ab1a666d4a669d09966aaa96666666d3b1d666666666d12111111111111111111",
"1111111111111111111111113331111333323113331400333109032113333333333331233333332111111111111111111111",
"111111111111111111111111111121d69b196d1d6691466cc9b96dd6606ccc6d6c6c60121111111111111111111111111111",
"111111111111111111111111111121dfeffefd9e9aec4fcd6ed6e6e6d4cc99d4b9ea44111111111111111111111111111111",
"111111111111111111111111111121de6aa6ed9eeeec4ccce6b6e9cca4fcaad416ea22111111111111111111111111111111",
"111111111111111111111111111121d9a42a9dd9d4994994a60a6d49949996941a9d12111111111111111111111111111111",
"1111111111111111111111111111111221122122212212212212221221222221122211111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
}
local ART_BG = {
"0111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111112121111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111121112234104222111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111202404000000040466221111111111111111111111111111111111111111",
"11111111111111111111111111111111111111112255b5888888824601041111111111111111111111111111111111111111",
"1111111111111111111111111111111111111551108888888888785690041111111111111111111111111111111111111111",
"111111111111111111111111111111111113405888880577777801166666dd12111111111111111111111111111111111111",
"11111111111111111111111111111111112550b588558875877038c9966dda01211111111111111111111111111111111111",
"11111111111111111111222222222221222125888558851851158666a6666a1b221112222222222211111111111111111111",
"11111111111111111114dddddddddd04ddd5da555585b585558666669a6aadadd41210ddddddddd011111111111111111111",
"1111111111111111123dceeeeeeeeea4ceeeeeeeca0585aceeef9666aceeeeeeeca41afeeeeeeefd12111111111111111111",
"11111111111111111214ddd6eecdddd0cee6d99fef959ceecaceef96acee6ad6fee6bafefaddddd011111111111111111111",
"111111111111111111112226eecd343dcee6666eee909eec5896ee6aacee9134cee62afeefefefa221111111111111111111",
"111111111111111111111319eecd3b30ceeeeeee6a556eeefffeee699cee9d046ee6bafef66666d121111111111111111111",
"111111111111111111111319eecd3b30cee9aceef9556eef666cee699cee699ceec94afef666666d12111111111111111111",
"111111111111111111111316eecd3b3dcee61d9eeea49eecd056ee6ddceeeeeef9d31afeeeeeeefd12111111111111111111",
"11111111111111111111111bbbb21112bbbb222bbbb504200040dbbd0bbbbbbbb21112bbbbbbbbb211111111111111111111",
"111111111111111111111111111111211221122111111111114b122112111114111112122111112111111111111111111111",
"111111111111111111111111111121def9afeadceefa4fecffd6ea6e6dfecc6dcfecc0121111111111111111111111111111",
"111111111111111111111111111121decff6ed9e69ec4ceffcd6eeea14cefe9136ea32111111111111111111111111111111",
"111111111111111111111111111121de6116ed9e9dec4fcdfed6ed9ecdfeffc416ea12111111111111111111111111111111",
"1111111111111111111111111111111111111111121111111111112111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
"1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
}
local ART_W, ART_H = 100, 29




-- Прекомпил арта в сегменты (run-length), один раз при первом вызове
local ART_RENDERED = nil
local function buildArtRendered()
  if ART_RENDERED then return ART_RENDERED end
  local rows = {}
  for ry = 1, ART_H do
    local fgRow, bgRow = ART_FG[ry], ART_BG[ry]
    local segs = {}
    local cx = 1
    while cx <= ART_W do
      local f = tonumber(string.sub(fgRow, cx, cx), 16) or 0
      local b = tonumber(string.sub(bgRow, cx, cx), 16) or 0
      local x0 = cx
      while cx + 1 <= ART_W do
        local f2 = tonumber(string.sub(fgRow, cx + 1, cx + 1), 16) or 0
        local b2 = tonumber(string.sub(bgRow, cx + 1, cx + 1), 16) or 0
        if f2 == f and b2 == b then cx = cx + 1 else break end
      end
      local run = cx - x0 + 1
      local char, fg, bg
      if f == b then
        char, fg, bg = string.rep(" ", run), Colors.text_bright, ART_PALETTE[b + 1]
      else
        char, fg, bg = string.rep("▄", run), ART_PALETTE[f + 1], ART_PALETTE[b + 1]
      end
      table.insert(segs, { x = x0, text = char, fg = fg, bg = bg })
      cx = cx + 1
    end
    rows[ry] = segs
  end
  ART_RENDERED = rows
  return rows
end



function drawWelcomeScreen()
  Buffer.clear()
  State.buttons = {}
  drawBox(1, 1, Config.SCREEN_W, Config.SCREEN_H, Colors.line, Colors.bg_main)
  -- Логотип: центрирован, строки 2..41
  local ax = math.floor((Config.SCREEN_W - ART_W) / 2) + 1
  local ay = 2
  for ry, segs in ipairs(buildArtRendered()) do
    local y = ay + ry - 1
    for _, s in ipairs(segs) do
      Buffer.write(ax + s.x - 1, y, s.text, s.fg, s.bg)
    end
  end
  -- Строка 42: сразу под артом — статус / приглашение
  local STATUS_Y = 42
  local LOG_START, LOG_END = 43, 48
  local AUTHOR_Y = 49
  if State.serverState.maintenance or State.serverState.terminalPaused then
    drawCenteredText(STATUS_Y, "⚠ Терминал на техническом обслуживании — вход закрыт", Colors.warning, Colors.bg_main)
  elseif State.syncInProgress then
    drawCenteredText(STATUS_Y, "⏳ Идёт синхронизация с сервером...", Colors.warning, Colors.bg_main)
  elseif not State.catalogsLoaded then
    if State.catalogLoadFailed then
      drawCenteredText(STATUS_Y, "⚠ Ошибка загрузки каталогов, повтор через " .. Config.CATALOG_RETRY_INTERVAL .. " сек", Colors.error_red, Colors.bg_main)
    else
      drawCenteredText(STATUS_Y, "⏳ Синхронизация каталогов с сервером...", Colors.warning, Colors.bg_main)
    end
  else
    drawCenteredText(STATUS_Y, "↓ Встаньте на PIM для входа ↓", Colors.accent_main, Colors.bg_main)
  end
  -- Лог загрузки (6 строк, ниже приглашения)
  if #State.welcomeLog > 0 then
    local maxLines = LOG_END - LOG_START + 1
    local startIndex = math.max(1, #State.welcomeLog - maxLines + 1)
    for i = startIndex, #State.welcomeLog do
      local y = LOG_START + (i - startIndex)
      if y <= LOG_END then drawCenteredText(y, State.welcomeLog[i].message, State.welcomeLog[i].color, Colors.bg_main) end
    end
  end
  -- Авторская метка в самом низу
  drawCenteredText(AUTHOR_Y, "Trade Shop by Leytsfer — v 6.10.6", Colors.text_dark, Colors.bg_main)
  Buffer.flush()
  State.screenInitialized = true
end


function drawMainScreen()
if State.currentScreen == "welcome" then drawWelcomeScreen(); return end
State.buttons = {}
Buffer.clear()
drawHeader()
drawItemList()
drawRightPanel()
drawBottomBar()
if State.modalState.active or State.bannedNow then drawModal() end
if State.categoryDropdownOpen then drawCategoryDropdown() end
Buffer.flush()
State.lastRendered = true
end
function markDirty(part)
if not State.screenInitialized then return end
State.guiDirty = true
State.pendingRenderPart = part or "full"
if not State.renderTimer then
State.renderTimer = event.timer(0.05, function()
State.renderTimer = nil
if State.guiDirty then
if State.currentScreen == "welcome" then drawWelcomeScreen() else drawMainScreen() end
State.guiDirty = false; State.pendingRenderPart = "full"
end
return false
end)
end
end
function forceRender()
if not State.screenInitialized then return end
State.guiDirty = false; State.pendingRenderPart = "full"
if State.renderTimer then pcall(event.cancel, State.renderTimer); State.renderTimer = nil end
if State.currentScreen == "welcome" then drawWelcomeScreen() else drawMainScreen() end
end
function asBoolFlag(v)
return v == true or v == 1 or v == "1"
end
function heartbeatTick()
if computer.uptime() - State.lastHeartbeat < Config.HEARTBEAT_INTERVAL then return end
State.lastHeartbeat = computer.uptime()
local r = HttpModule.request("oc_heartbeat", {
terminalId = Config.TERMINAL_ID,
terminalName = "Terminal-" .. computer.address():sub(1, 8),
address = computer.address(),
online = true,
player = State.currentPlayer or ""
})
if not r or r.status ~= "ok" then return end
local changed = false
if r.maintenance ~= nil then
local maint = asBoolFlag(r.maintenance)
if maint ~= State.serverState.maintenance then State.serverState.maintenance = maint; changed = true end
end
if r.paused ~= nil then
local paused = asBoolFlag(r.paused)
if paused ~= State.serverState.terminalPaused then
State.serverState.terminalPaused = paused
if paused and State.pimActive and State.currentPlayer then
State.pauseGraceUntil = computer.uptime() + Config.PAUSE_GRACE_SECONDS
State.modalState.active = true; State.modalState.kind = "pause_countdown"; State.modalState.data = {}
State.modalData = State.modalState.data
else
State.pauseGraceUntil = 0
if State.modalState.kind == "pause_countdown" then
State.modalState.active = false; State.modalState.kind = nil; State.modalState.data = nil; State.modalData = nil
end
end
changed = true
end
end
if State.pimActive and State.currentPlayer then
local bu = HttpModule.request("oc_get_balance", { name = State.currentPlayer, terminalId = Config.TERMINAL_ID })
if bu and bu.status == "ok" and bu.user then
local nowBanned = (tonumber(bu.user.banned) or 0) == 1
if nowBanned ~= State.bannedNow then
State.bannedNow = nowBanned
if State.currentSession then
State.currentSession.banned = nowBanned
State.currentSession.banReason = bu.user.banReason or State.currentSession.banReason
end
changed = true
end
local p = PlayerModule.get(State.currentPlayer)
if p then
p.spentCoin = tonumber(bu.user.spent_coin) or p.spentCoin or 0
p.spentEma = tonumber(bu.user.spent_ema) or p.spentEma or 0
refreshSessionDiscount()
changed = true
end
end
end
if changed then markDirty("full") end
end
function acKey(name, dmg)
local n = tostring(name or "")
if n ~= "" and not n:find(":", 1, true) then n = "minecraft:" .. n end
return n .. ":" .. tostring(dmg or 0)
end
function callMethod(obj, name)
if type(obj) ~= "table" then return nil end
local m = obj[name]
if m == nil then return nil end
local ok, r = pcall(function() return m() end)
if ok then return r end
return nil
end
function cancelCraftReq(req)
if not req then return false end
pcall(function() req.cancel() end)
local ic = callMethod(req, "isCanceled")
if ic == true then return true end
pcall(function() req:cancel() end)
ic = callMethod(req, "isCanceled")
if ic == true then return true end
local st = callMethod(req, "getStatus")
if type(st) == "table" and (st.isCanceled or st.canceled or st.state == "canceled") then return true end
writeDebugLog("⚠️ Отмену крафта не удалось подтвердить")
return false
end
function acFullName(raw)
local n = tostring(raw or "")
if n ~= "" and not n:find(":", 1, true) then n = "minecraft:" .. n end
return n
end
function acStackOf(c)
if type(c) ~= "table" then return nil end
if c.getItemStack ~= nil then
local ok, r = pcall(function() return c.getItemStack() end)
if ok and type(r) == "table" then return r end
end
if type(c.item) == "table" then return c.item end
if type(c.stack) == "table" then return c.stack end
if type(c.name) == "string" then return c end
return nil
end
function acDoProbe(item)
if not item then return end
local k = acKey(item.internalName, item.damage or 0)
if State.acCraftCache[k] ~= nil then return end
if not component.isAvailable("me_interface") then State.acCraftCache[k] = false; return end
local me = component.me_interface
local full = acFullName(item.internalName)
local ok1, list = pcall(function() return me.getCraftables({ name = full }) end)
if not ok1 or type(list) ~= "table" or #list == 0 then
State.acCraftCache[k] = false
State.autocraftCraftablesDirty = true
return
end
local pattern = list[1]
local st = acStackOf(pattern)
State.acCraftCache[k] = { name = (st and (st.name or st.label or st.id)) or full, damage = item.damage or 0, size = (st and tonumber(st.size)) or 1, raw = pattern, canCraft = true }
State.autocraftCraftablesDirty = true
writeDebugLog("🔎 Probe " .. full .. " => шаблон найден")
end
function acProbeItem(item)
if not item then return end
local k = acKey(item.internalName, item.damage or 0)
if State.acCraftCache[k] ~= nil then return end
for _, q in ipairs(State.acProbeQueue) do
if q.internalName == item.internalName and (q.damage or 0) == (item.damage or 0) then return end
end
table.insert(State.acProbeQueue, { internalName = item.internalName, damage = item.damage or 0 })
end
acAvailable = function(item)
if not item then return false end
return type(State.acCraftCache[acKey(item.internalName, item.damage or 0)]) == "table"
end
acCanCraft = acAvailable
acStatusOf = function(item)
if not item then return "unknown" end
local v = State.acCraftCache[acKey(item.internalName, item.damage or 0)]
if type(v) == "table" then return "yes"
elseif v == false then return "no" end
return "unknown"
end
function acEntryFor(item)
if not item then return nil end
local v = State.acCraftCache[acKey(item.internalName, item.damage or 0)]
if type(v) == "table" then return v end
return nil
end
function acLogJob(job, segs, live)
local plain = ""
for _, s in ipairs(segs) do plain = plain .. s[1] end
local entry = { segs = segs, text = plain, gap = 0 }
table.insert(State.logMessages, entry)
if #State.logMessages > 40 then table.remove(State.logMessages, 1) end
if job then
if live == "stock" then job.lineStock = entry
elseif live == "time" then job.lineTime = entry end
table.insert(job.pendingLogs, { text = plain, time = os.time(), player = State.currentPlayer or "", event = job.phase or "info" })
if #job.pendingLogs > 20 then table.remove(job.pendingLogs, 1) end
end
markDirty("right")
return entry
end
acReport = function()
local job = State.autocraftJob
local payload = { terminalId = Config.TERMINAL_ID }
if State.autocraftCraftablesDirty then
local list = {}
for _, v in pairs(State.acCraftCache) do
if type(v) == "table" then table.insert(list, { name = v.name, damage = v.damage, display = v.name }) end
end
payload.craftables = list
State.autocraftCraftablesDirty = false
end
if job then
payload.job = { player = State.currentPlayer or "", item = job.displayName, internalName = job.internalName, ordered = job.ordered, toCraft = job.toCraft, dispensed = job.dispensed or 0, status = job.phase, elapsed = math.floor(job.elapsed or 0) }
if #job.pendingLogs > 0 then payload.logs = job.pendingLogs; job.pendingLogs = {} end
end
HttpModule.request("oc_autocraft_report", payload)
end
function craftStatus(req)
if type(req) ~= "table" then return "running" end
local hf = callMethod(req, "hasFinished")
if hf == true then return "done" end
local ic = callMethod(req, "isCanceled")
if ic == true then return "canceled" end
local s = callMethod(req, "getStatus")
if type(s) == "table" then
if s.isComplete or s.complete or s.state == "done" or s.state == "completed" then return "done" end
if s.isCanceled or s.canceled or s.state == "canceled" then return "canceled" end
if s.state == "error" then return "error" end
if (type(s.missing) == "table" and #s.missing > 0) or (type(s.missingItems) == "table" and #s.missingItems > 0) then return "missing" end
end
return "running"
end
function acDecrementSnapshot(internalName, damage, amount)
for i, it in ipairs(Data.buyCatalogDisplay) do
if it.internalName == internalName and it.damage == damage then it.qty = math.max(0, (it.qty or 0) - amount); break end
end
end
function acFinishAndClose(job, success)
acReport()
State.needStockRefresh = true
scheduleClearLog(10)
State.autocraftJob = nil
forceRender()
end
function acFail(job)
cancelCraftReq(job.req)
acLogJob(job, { { "Результат крафта: ", Colors.text_bright }, { "Неудача (не хватает ресурсов в МЭ)", Colors.error_red } })
acLogJob(job, { { "Попробуйте заказать меньше предметов", Colors.warning } })
acFinishAndClose(job, false)
end
function acDispense(job)
job.phase = "dispensing"
local stockBefore = meCountOf(job.internalName, job.damage)
acLogJob(job, { { "Подготовка предмета к выдаче...", Colors.warning } })
local fullCoin = (job.unitCoin or 0) * (job.ordered or 0)
local fullEma = (job.unitEma or 0) * (job.ordered or 0)
PlayerModule.updateBalance(State.currentPlayer, -fullCoin, -fullEma)
job.paid = true
local me = component.me_interface
local id = job.internalName
if not id:find(":", 1, true) then id = "minecraft:" .. id end
local fingerprint = { id = id, dmg = job.damage }
local remaining, extracted = job.ordered, 0
while remaining > 0 do
if not State.currentPlayer or not PimModule.ensureValid(State.currentPlayer) then break end
local toTake = math.min(remaining, 64)
local okExport, result = pcall(function() return me.exportItem(fingerprint, PULL_DIRECTION, toTake) end)
local got = 0
if okExport then
if type(result) == "number" then got = result
elseif type(result) == "boolean" and result then got = toTake
elseif type(result) == "table" then got = result.count or result.amount or result.size or toTake end
end
if got > 0 then extracted = extracted + got; remaining = remaining - got else break end
end
job.dispensed = extracted
acDecrementSnapshot(job.internalName, job.damage, extracted)
meSnap.at = -1
if extracted < job.ordered then
local refCoin = (job.unitCoin or 0) * (job.ordered - extracted)
local refEma = (job.unitEma or 0) * (job.ordered - extracted)
if refCoin > 0 or refEma > 0 then PlayerModule.updateBalance(State.currentPlayer, refCoin, refEma) end
end
local netCoin = (job.unitCoin or 0) * extracted
local netEma = (job.unitEma or 0) * extracted
PlayerModule.addTransaction(State.currentPlayer, { time = getRealTimeString(), type = "buy", item = job.displayName, qty = extracted, coin = netCoin, ema = netEma })
PlayerModule.addSpent(State.currentPlayer, netCoin, netEma)
refreshSessionDiscount()
PendingModule.add("transaction", { player = State.currentPlayer, type = "buy", item = job.internalName, displayName = job.displayName, qty = extracted, totalCoin = netCoin, totalEma = netEma, timestamp = os.time() })
local p = PlayerModule.get(State.currentPlayer)
if p and State.currentSession then State.currentSession.balance = p.balance; State.currentSession.emaBalance = p.emaBalance; State.currentSession.transactions = p.transactions end
if netCoin > 0 or netEma > 0 then
local segs = { { "Оплата подтверждена: ", Colors.text_bright } }
if netCoin > 0 then table.insert(segs, { formatPrice(netCoin) .. " COINS", Colors.accent_cyan }) end
if netCoin > 0 and netEma > 0 then table.insert(segs, { " / ", Colors.text_bright }) end
if netEma > 0 then table.insert(segs, { formatPrice(netEma) .. " EMA", Colors.tomato }) end
acLogJob(job, segs)
else
acLogJob(job, { { "Оплата не выполнена: ничего не выдано", Colors.warning } })
end
acLogJob(job, { { "✔ Выдано: ", Colors.success_green }, { extracted .. "шт из " .. job.ordered .. "шт", Colors.accent_cyan } })
if extracted >= job.ordered then
acLogJob(job, { { "Результат крафта: ", Colors.text_bright }, { "Успешно", Colors.success_green } })
job.phase = "done"
elseif stockBefore < job.ordered then
acLogJob(job, { { "Результат крафта: ", Colors.text_bright }, { "Неудача (не хватает ресурсов в МЭ)", Colors.error_red } })
acLogJob(job, { { "Попробуйте заказать меньше предметов", Colors.warning } })
job.phase = "partial"
else
local freeSlots = 36 - PimModule.countOccupiedSlots()
if freeSlots <= 0 then
acLogJob(job, { { "⚠ Не хватило места в инвентаре: выдано только " .. extracted .. " шт.", Colors.warning } })
if extracted > 0 then acLogJob(job, { { "Списано только за выданное количество.", Colors.warning } }) end
else
acLogJob(job, { { "⚠ Произошла ошибка выдачи, попробуйте ещё раз заказать предмет", Colors.error_red } })
if extracted > 0 then acLogJob(job, { { "Списано только за выданное количество.", Colors.warning } }) end
end
job.phase = "partial"
end
acFinishAndClose(job, true)
end
acOpenConfirm = function()
local item = State.selectedItem
if not item then return end
if State.autocraftJob then return end
local k = acKey(item.internalName, item.damage or 0)
if State.acCraftCache[k] == nil then acDoProbe(item) end
local entry = acEntryFor(item)
if not entry then
openErrorModal("Автокрафт", "Для этого предмета нет шаблона крафта в ME.")
return
end
local inStock = meCountOf(item.internalName, item.damage or 0)
local ordered = State.purchaseQuantity
local needCoin, needEma = buyPrice(item)
needCoin = needCoin * ordered
needEma = needEma * ordered
local missC = math.max(0, needCoin - (State.currentSession.balance or 0))
local missE = math.max(0, needEma - (State.currentSession.emaBalance or 0))
if missC > 0 or missE > 0 then
safeOpenModal("insufficient", { itemName = item.displayName, qty = ordered, missC = missC, missE = missE })
return
end
local toCraft = math.max(0, ordered - inStock)
local outSize = entry.size or 1
local ops = math.ceil(toCraft / outSize)
local uc, ue = buyPrice(item)
State.autocraftJob = { phase = "confirm", internalName = item.internalName, displayName = item.displayName, damage = item.damage or 0, unitCoin = uc, unitEma = ue, ordered = ordered, inStock = inStock, toCraft = toCraft, ops = ops, dispensed = 0, elapsed = 0, pendingLogs = {} }
forceRender()
end
acStart = function()
local job = State.autocraftJob
if not job or job.phase ~= "confirm" then return end
local inStock = meCountOf(job.internalName, job.damage)
job.inStock = inStock
job.toCraft = math.max(0, job.ordered - inStock)
State.logMessages = {}
local entry = acEntryFor({ internalName = job.internalName, damage = job.damage })
if not entry then
acLogJob(job, { { "Результат крафта: ", Colors.text_bright }, { "Неудача (нет шаблона)", Colors.error_red } })
acFinishAndClose(job, false)
return
end
local me = component.me_interface
local req = nil
local shapes = {
function() return entry.raw.request(job.toCraft) end,
function() return me.requestCrafting(entry.raw, job.toCraft) end,
function() return entry.raw:request(job.toCraft) end,
}
for _, fn in ipairs(shapes) do
local okk, rr = pcall(fn)
if okk and rr then req = rr; break end
end
if not req then
acLogJob(job, { { "Результат крафта: ", Colors.text_bright }, { "Неудача (ME не приняла запрос)", Colors.error_red } })
acLogJob(job, { { "Попробуйте заказать меньше предметов", Colors.warning } })
acFinishAndClose(job, false)
return
end
job.req = req
job.phase = "crafting"
job.startUptime = computer.uptime(); job.elapsed = 0; job.lastStockTick = 0; job.lastReportU = 0
acLogJob(job, { { "Начался крафт: ", Colors.text_bright }, { tostring(job.displayName), Colors.accent_cyan } })
acLogJob(job, { { "Заказано предметов: ", Colors.text_bright }, { job.ordered .. "шт", Colors.accent_cyan } })
acLogJob(job, { { "Сейчас в МЭ: ", Colors.text_bright }, { inStock .. "шт", Colors.accent_cyan } }, "stock")
acLogJob(job, { { "Прошло времени: ", Colors.text_bright }, { "0 сек", Colors.accent_cyan } }, "time")
forceRender()
end
acStep = function()
local job = State.autocraftJob
if not job or job.phase ~= "crafting" then return end
local now = computer.uptime()
job.elapsed = now - job.startUptime
if job.lineTime then
job.lineTime.segs = { { "Прошло времени: ", Colors.text_bright }, { math.floor(job.elapsed) .. " сек", Colors.accent_cyan } }
end
if now - (job.lastStockTick or 0) >= 2 then
job.lastStockTick = now
local stock = meCountOf(job.internalName, job.damage)
if job.lineStock then job.lineStock.segs = { { "Сейчас в МЭ: ", Colors.text_bright }, { stock .. "шт", Colors.accent_cyan } } end
markDirty("right")
if stock >= job.ordered then acDispense(job); return end
end
if job.req then
local st = craftStatus(job.req)
if st == "canceled" or st == "missing" or st == "error" then
acFail(job); return
elseif st == "done" then
local stock = meCountOf(job.internalName, job.damage)
if stock >= job.ordered then acDispense(job); return end
end
end
if job.elapsed > 600 then
acFail(job); return
end
if now - (job.lastReportU or 0) >= 3 then job.lastReportU = now; acReport() end
end
acCancel = function(byPlayer)
local job = State.autocraftJob
if not job then return end
if job.phase == "crafting" or job.phase == "confirm" then
cancelCraftReq(job.req)
acLogJob(job, { { "Результат крафта: ", Colors.text_bright }, { "Отменён игроком", Colors.warning } })
acFinishAndClose(job, false)
end
end
acPlayerLeft = function()
local job = State.autocraftJob
if not job then return end
if job.req then cancelCraftReq(job.req) end
if job.phase == "crafting" or job.phase == "confirm" then
writeDebugLog("⚠️ Игрок ушёл — крафт отменён в ME")
end
State.autocraftJob = nil
State.modalState.active = false; State.modalState.kind = nil; State.modalState.data = nil; State.modalData = nil
end
function performBuy()
TransactionModule.checkTimeout()
if State.currentScreen == "welcome" and computer.uptime() - State.lastWelcomeAnim > 0.6 then
State.lastWelcomeAnim = computer.uptime()
State.welcomeAnim = 1 - State.welcomeAnim
markDirty("welcome")
end
local ok, err = validateBuyRequest()
if not ok then
if err == "Недостаточно Coina" or err == "Недостаточно EMA" then
local item = State.selectedItem
local qty = State.purchaseQuantity
local dc, de = buyPrice(item)
local missC = math.max(0, dc * qty - (State.currentSession.balance or 0))
local missE = math.max(0, de * qty - (State.currentSession.emaBalance or 0))
safeOpenModal("insufficient", { itemName = item.displayName, qty = qty, missC = missC, missE = missE })
else openErrorModal("Ошибка покупки", err) end
return
end
local item = State.selectedItem
local requestedQty = State.purchaseQuantity
local freeSlots = 36 - PimModule.countOccupiedSlots()
local capacity = freeSlots * 64
if capacity <= 0 then safeOpenModal("inventory_full", { lines = { "Недостаточно места в инвентаре!", "Освободите слоты для покупки." } }); return end
local partial = false
if requestedQty > capacity then requestedQty = capacity; State.purchaseQuantity = capacity; partial = true end
local txid = computer.address():sub(1, 8) .. "_" .. computer.uptime()
if not TransactionModule.lock(txid) then openErrorModal("Подожди", "Транзакция уже выполняется или слишком частые запросы."); return end
setLogMessage("Выполняется покупка...", Colors.accent_main)
function finishBuy(success, extracted, wasPartial)
TransactionModule.unlock()
if success then
local uc, ue = buyPrice(item)
local totalCoin = uc * extracted
local totalEma = ue * extracted
local player = PlayerModule.updateBalance(State.currentPlayer, -totalCoin, -totalEma)
PlayerModule.addSpent(State.currentPlayer, totalCoin, totalEma)
refreshSessionDiscount()
PlayerModule.addTransaction(State.currentPlayer, { time = getRealTimeString(), type = "buy", item = item.displayName, qty = extracted, coin = totalCoin, ema = totalEma })
PendingModule.add("transaction", { player = State.currentPlayer, type = "buy", item = item.internalName, displayName = item.displayName, qty = extracted, totalCoin = totalCoin, totalEma = totalEma, timestamp = os.time() })
State.currentSession.balance = player.balance; State.currentSession.emaBalance = player.emaBalance; State.currentSession.transactions = player.transactions
acDecrementSnapshot(item.internalName, item.damage or 0, extracted)
meSnap.at = -1
applyFilter(); restoreSelectedItemByKey(getSelectedItemKey(item))
clearLog()
addLogMessage("✅ Куплено: " .. item.displayName .. " x" .. math.floor(extracted + 0.5) .. " шт.", Colors.success_green)
local segs = { { "Списано: ", Colors.text_bright } }
if totalCoin > 0 then table.insert(segs, { formatPrice(totalCoin) .. " COIN", Colors.accent_cyan }) end
if totalCoin > 0 and totalEma > 0 then table.insert(segs, { " | ", Colors.text_bright }) end
if totalEma > 0 then table.insert(segs, { formatPrice(totalEma) .. " EM", Colors.tomato }) end
if totalCoin > 0 or totalEma > 0 then addLogSegs(segs) end
if wasPartial then addLogMessage("⚠ Вы купили лишь часть желаемых предметов, инвентарь переполнен!", Colors.warning) end
scheduleClearLog(5)
else
openErrorModal("Ошибка покупки", extracted or "Неизвестная ошибка"); clearLog(); addLogMessage("Ошибка покупки", Colors.error_red)
end
markDirty("full")
end
local me = component.me_interface
if not me then finishBuy(false, "ME интерфейс не найден", false); return end
local id = item.internalName
if not id:find(":", 1, true) then id = "minecraft:" .. id end
local fingerprint = { id = id, dmg = item.damage or 0 }
local remaining, extracted, maxStackSize = requestedQty, 0, 64
while remaining > 0 do
if not PimModule.ensureValid(State.currentPlayer) then finishBuy(false, "Игрок покинул терминал", false); return end
local toTake = math.min(remaining, maxStackSize)
local okExport, result = pcall(function() return me.exportItem(fingerprint, PULL_DIRECTION, toTake) end)
local got = 0
if okExport then
if type(result) == "number" then got = result
elseif type(result) == "boolean" and result then got = toTake
elseif type(result) == "table" then got = result.count or result.amount or result.size or toTake end
end
if got > 0 then extracted = extracted + got; remaining = remaining - got else break end
end
finishBuy(extracted > 0, extracted > 0 and extracted or "Не удалось выдать предмет", partial)
end
function performSell()
TransactionModule.checkTimeout()
local ok, err = validateSellRequest()
if not ok then openErrorModal("Ошибка продажи", err); return end
local item = State.selectedItem
local qty = State.sellQuantity
local txid = computer.address():sub(1, 8) .. "_" .. computer.uptime()
if not TransactionModule.lock(txid) then openErrorModal("Подожди", "Транзакция уже выполняется или слишком частые запросы."); return end
setLogMessage("Выполняется продажа...", Colors.accent_main)
function finishSell(success, realExtracted)
TransactionModule.unlock()
if success then
local totalCoin = (item.priceCoin or 0) * realExtracted
local totalEma = (item.priceEma or 0) * realExtracted
local player = PlayerModule.updateBalance(State.currentPlayer, totalCoin, totalEma)
PlayerModule.addTransaction(State.currentPlayer, { time = getRealTimeString(), type = "sell", item = item.displayName, qty = realExtracted, coin = totalCoin, ema = totalEma })
PendingModule.add("transaction", { player = State.currentPlayer, type = "sell", item = item.internalName, displayName = item.displayName, qty = realExtracted, totalCoin = totalCoin, totalEma = totalEma, timestamp = os.time() })
State.currentSession.balance = player.balance; State.currentSession.emaBalance = player.emaBalance; State.currentSession.transactions = player.transactions
meSnap.at = -1
clearLog()
addLogMessage("✅ Продано: " .. item.displayName .. " x" .. math.floor(realExtracted + 0.5) .. " шт.", Colors.success_green)
local segs = { { "Получено: ", Colors.text_bright } }
if totalCoin > 0 then table.insert(segs, { formatPrice(totalCoin) .. " COIN", Colors.accent_cyan }) end
if totalCoin > 0 and totalEma > 0 then table.insert(segs, { " | ", Colors.text_bright }) end
if totalEma > 0 then table.insert(segs, { formatPrice(totalEma) .. " EM", Colors.tomato }) end
if totalCoin > 0 or totalEma > 0 then addLogSegs(segs) end
scheduleClearLog(5)
else
openErrorModal("Ошибка продажи", realExtracted or "Неизвестная ошибка"); clearLog(); addLogMessage("Ошибка продажи", Colors.error_red)
end
markDirty("full")
end
local realExtracted = PimModule.extractToME(item.internalName, qty, item.damage or 0)
if realExtracted == 0 then finishSell(false, "Не удалось изъять предметы из инвентаря"); return end
if not PimModule.ensureValid(State.currentPlayer) then finishSell(false, "Игрок покинул терминал"); return end
finishSell(true, realExtracted)
end
function performSetPurchase()
TransactionModule.checkTimeout()
local ok, err = validateTerminalState()
if not ok then openErrorModal("Ошибка покупки", err); return end
local set = State.selectedSet
if not set then openErrorModal("Ошибка", "Набор не выбран"); return end
local pr = setProgressOf(set)
if pr and not pr.completed then openErrorModal("Ошибка", "Набор уже куплен, заберите содержимое"); return end
if not setIsAvailableLocal(set) then openErrorModal("Недоступно", "В МЭ нет всех предметов набора"); return end
local coin, ema = set.price_coin or 0, set.price_ema or 0
if (State.currentSession.balance or 0) < coin or (State.currentSession.emaBalance or 0) < ema then
safeOpenModal("insufficient", { itemName = set.name, qty = 1, missC = math.max(0, coin - (State.currentSession.balance or 0)), missE = math.max(0, ema - (State.currentSession.emaBalance or 0)) })
return
end
local txid = computer.address():sub(1, 8) .. "_" .. computer.uptime()
if not TransactionModule.lock(txid) then openErrorModal("Подожди", "Транзакция уже выполняется или слишком частые запросы."); return end
local player = PlayerModule.updateBalance(State.currentPlayer, -coin, -ema)
PlayerModule.addSpent(State.currentPlayer, coin, ema)
refreshSessionDiscount()
PlayerModule.addTransaction(State.currentPlayer, { time = getRealTimeString(), type = "buy", item = set.name, qty = 1, coin = coin, ema = ema })
PendingModule.add("transaction", { player = State.currentPlayer, type = "buy", item = "SET:" .. tostring(set.id), displayName = set.name, qty = 1, totalCoin = coin, totalEma = ema, timestamp = os.time() })
State.currentSession.balance = player.balance; State.currentSession.emaBalance = player.emaBalance; State.currentSession.transactions = player.transactions
Data.setsProgress[set.id] = { dispensed = {}, completed = false }
CatalogModule.saveSetsProgress()
PendingModule.add("set_progress", { player = State.currentPlayer, setId = set.id, dispensed = {}, completed = false })
TransactionModule.unlock()
clearLog()
addLogMessage("✅ Куплен набор: " .. (set.name or ""), Colors.success_green)
local segs = { { "Списано: ", Colors.text_bright } }
if coin > 0 then table.insert(segs, { formatPrice(coin) .. " COIN", Colors.accent_cyan }) end
if coin > 0 and ema > 0 then table.insert(segs, { " | ", Colors.text_bright }) end
if ema > 0 then table.insert(segs, { formatPrice(ema) .. " EM", Colors.tomato }) end
if coin > 0 or ema > 0 then addLogSegs(segs) end
addLogMessage("Вы можете забрать содержимое набора выше.", Colors.warning)
markDirty("full")
end
function performSetDispense()
TransactionModule.checkTimeout()
local ok, err = validateTerminalState()
if not ok then openErrorModal("Ошибка выдачи", err); return end
local set = State.selectedSet
if not set then openErrorModal("Ошибка", "Набор не выбран"); return end
local pr = setProgressOf(set)
if not pr or pr.completed then openErrorModal("Ошибка", "Набор не куплен или уже выдан полностью"); return end
if not component.isAvailable("me_interface") then openErrorModal("Ошибка", "ME интерфейс недоступен"); return end
local txid = computer.address():sub(1, 8) .. "_" .. computer.uptime()
if not TransactionModule.lock(txid) then openErrorModal("Подожди", "Транзакция уже выполняется или слишком частые запросы."); return end
local me = component.me_interface
local meIdx = meSnapshot()
clearLog()
addLogMessage("📦 Выдача набора: " .. (set.name or ""), Colors.accent_main)
local inventoryFull = false
local meMissing = false
for _, it in ipairs(set.items or {}) do
if inventoryFull or meMissing then break end
local key = it.internalName .. ":" .. (it.damage or 0)
local need = (tonumber(it.qty) or 0) - (pr.dispensed[key] or 0)
if need > 0 then
local avail = meIdx[key] or 0
if avail <= 0 then meMissing = true
else
local canTake = math.min(need, avail)
local id = it.internalName
if not id:find(":", 1, true) then id = "minecraft:" .. id end
local fingerprint = { id = id, dmg = it.damage or 0 }
while canTake > 0 do
if not PimModule.ensureValid(State.currentPlayer) then inventoryFull = true; break end
local freeSlots = 36 - PimModule.countOccupiedSlots()
if freeSlots <= 0 then inventoryFull = true; break end
local toTake = math.min(canTake, 64, freeSlots * 64)
local okExport, result = pcall(function() return me.exportItem(fingerprint, PULL_DIRECTION, toTake) end)
local got = 0
if okExport then
if type(result) == "number" then got = result
elseif type(result) == "boolean" and result then got = toTake
elseif type(result) == "table" then got = result.count or result.amount or result.size or toTake end
end
if got > 0 then
canTake = canTake - got
pr.dispensed[key] = (pr.dispensed[key] or 0) + got
meIdx[key] = (meIdx[key] or 0) - got
else inventoryFull = true; break end
end
end
end
end
local completed = true
for _, it in ipairs(set.items or {}) do
local key = it.internalName .. ":" .. (it.damage or 0)
if (pr.dispensed[key] or 0) < (tonumber(it.qty) or 0) then completed = false; break end
end
if completed then
Data.setsProgress[set.id] = nil
CatalogModule.saveSetsProgress()
PendingModule.add("set_progress", { player = State.currentPlayer, setId = set.id, dispensed = {}, completed = true })
addLogMessage("✅ Набор полностью выдан: " .. (set.name or ""), Colors.success_green)
else
pr.completed = false
CatalogModule.saveSetsProgress()
PendingModule.add("set_progress", { player = State.currentPlayer, setId = set.id, dispensed = pr.dispensed, completed = false })
if inventoryFull then
local dispTotal = setTotalDispensedLocal(set)
local reqTotal = setTotalQtyLocal(set)
addLogMessage("Инвентарь переполнен, Выдано " .. dispTotal .. "/" .. reqTotal, Colors.warning)
addLogMessage("Освободите место в инвентаре и нажмите \"Выдать набор\"", Colors.warning)
elseif meMissing then
local dispTotal = setTotalDispensedLocal(set)
local reqTotal = setTotalQtyLocal(set)
addLogMessage("⚠ В МЭ не хватает предметов. Выдано " .. dispTotal .. "/" .. reqTotal .. ".", Colors.warning)
end
end
meSnap.at = -1
TransactionModule.unlock()
State.needStockRefresh = true
markDirty("full")
end
function abortOpen(playerName)
writeDebugLog("⚠️ Вход отменён: игрок " .. tostring(playerName) .. " уже не на PIM")
State.currentPlayer = nil; State.currentSession = nil; State.pimOwner = nil; State.pimActive = false; State.pimAbsentCount = 0
State.bannedNow = false; State.pauseGraceUntil = 0
State.currentScreen = "welcome"; State.screenInitialized = false
State.modalState.active = false; State.modalState.kind = nil; State.modalState.data = nil; State.modalData = nil
drawWelcomeScreen()
end
function openShopForPlayer(playerName)
local player = PlayerModule.getOrCreate(playerName)
local userData = HttpModule.request("oc_get_balance", { name = playerName, terminalId = Config.TERMINAL_ID })
if userData and userData.status == "ok" and userData.user then
player.balance = tonumber(userData.user.balanceCoin) or 0
player.emaBalance = tonumber(userData.user.balanceEma) or 0
player.transactions = tonumber(userData.user.transactions) or 0
player.regDate = userData.user.regDate or player.regDate or getRealTimeString()
player.banned = (tonumber(userData.user.banned) or 0) == 1
player.banReason = userData.user.banReason or ""
player.spentCoin = tonumber(userData.user.spent_coin) or player.spentCoin or 0
player.spentEma = tonumber(userData.user.spent_ema) or player.spentEma or 0
PlayerModule.save()
end
State.currentPlayer = playerName; State.pimOwner = playerName; State.pimActive = true; State.pimAbsentCount = 0
if pimPresenceState() ~= "unknown" then State.presenceWorks = true end
State.currentSession = { balance = player.balance or 0, emaBalance = player.emaBalance or 0, transactions = player.transactions or 0, regDate = player.regDate or getRealTimeString(), banned = player.banned or false, banReason = player.banReason or "" }
refreshSessionDiscount()
State.bannedNow = (State.currentSession.banned == true or State.currentSession.banned == 1)
if pimPresenceState() == "absent" then
abortOpen(playerName)
return
end
State.currentCategory = "ВСЕ"
State.categoryDropdownOpen = false
State.searchInput = ""
State.searchInputActive = true
State.listScroll = 1
State.selectedIndex = 0
State.selectedItem = nil
State.selectedSet = nil
State.selectedSetItem = nil
State.setView = "list"
State.currentShopMode = "buy"
State.logMessages = {}
State.currentScreen = "shop"
if State.currentShopMode == "sets" then
applySetsFilter()
else
applyFilter()
if #Data.filteredItems > 0 then
State.selectedIndex = 1; State.selectedItem = Data.filteredItems[1]
if State.currentShopMode == "sell" then refreshSellPlayerQty() else State.purchaseQuantity = clampQuantity(State.purchaseQuantity, buyQtyCap(State.selectedItem)) end
updateSelectorDisplay(State.selectedItem)
else State.selectedIndex = 0; State.selectedItem = nil; State.sellPlayerQty = 0; updateSelectorDisplay(nil) end
end
forceRender()
State.needStockRefresh = true
event.timer(1, function() checkRewardedReports(); return false end)
end
function handlePlayerEnter(playerName)
writeDebugLog("👤 Игрок вошёл: " .. tostring(playerName))
if State.serverState.maintenance or State.serverState.terminalPaused then
writeDebugLog("⚠️ Терминал на ТО — вход отклонён")
State.welcomeLog = {}; drawWelcomeScreen()
return
end
addWelcomeLog("⏳ Подключение к серверу...", Colors.warning)
local holdDeadline = computer.uptime() + Config.PRESENCE_HOLD_DELAY
local stillHere = true
while computer.uptime() < holdDeadline and stillHere do
local pst = pimPresenceState()
if pst == "absent" then stillHere = false; break end
local pulled = { pcall(event.pull, 0.05) }
if pulled[1] and pulled[2] then
table.remove(pulled, 1)
local e2, a1 = pulled[1], pulled[2]
if e2 == "player_off" or e2 == "pim_player_leave" then stillHere = false
elseif not (e2 == "player_on" or e2 == "pim" or e2 == "pim_player_enter") then table.insert(State.deferredEvents, pulled) end
end
end
if not stillHere then
writeDebugLog("⚠️ Игрок ушёл во время выдержки — синхронизация не начиналась")
State.welcomeLog = {}; drawWelcomeScreen()
return
end
syncCatalogsIfNeeded("player")
addWelcomeLog("🔍 Загружаю магазин...", Colors.warning)
local stillHere2 = true
local confDeadline = computer.uptime() + Config.PRESENCE_CONFIRM_DELAY
while computer.uptime() < confDeadline and stillHere2 do
local pst = pimPresenceState()
if pst == "absent" then stillHere2 = false; break end
local pulled = { pcall(event.pull, 0.05) }
if pulled[1] and pulled[2] then
table.remove(pulled, 1)
local e2, a1 = pulled[1], pulled[2]
if e2 == "player_off" or e2 == "pim_player_leave" then stillHere2 = false
elseif not (e2 == "player_on" or e2 == "pim" or e2 == "pim_player_enter") then table.insert(State.deferredEvents, pulled) end
end
end
if stillHere2 and pimPresenceState() == "absent" then stillHere2 = false end
if not stillHere2 then
writeDebugLog("⚠️ Игрок ушёл во время синхронизации/подтверждения — магазин не открывается")
State.welcomeLog = {}; drawWelcomeScreen()
return
end
openShopForPlayer(playerName)
end
function handlePlayerLeave()
writeDebugLog("👋 Игрок вышел: " .. tostring(State.currentPlayer))
acPlayerLeft()
CatalogModule.saveSetsProgress()
flushSessionToServer()
State.logMessages = {}; State.syncLogs = {}
if not State.syncInProgress then State.welcomeLog = {} end
Buffer.clear()
State.currentCategory = "ВСЕ"
State.categoryDropdownOpen = false
State.searchInput = ""
State.searchInputActive = false
State.listScroll = 1
State.selectedIndex = 0
State.selectedItem = nil
State.selectedSet = nil
State.selectedSetItem = nil
State.setView = "list"
State.currentShopMode = "buy"
State.bannedNow = false; State.pauseGraceUntil = 0
State.currentPlayer = nil; State.currentSession = nil; State.pimOwner = nil; State.pimActive = false; State.pimAbsentCount = 0
State.currentScreen = "welcome"; State.screenInitialized = false
if not State.syncInProgress then drawWelcomeScreen() end
end
function isCraftingBusy()
local job = State.autocraftJob
return job and (job.phase == "crafting" or job.phase == "dispensing")
end
function handleTouch(x, y, playerName)
if not State.pimActive or not State.currentPlayer then return end
if not PimModule.isOwner(playerName) then return end
if not PimModule.ensureValid(State.currentPlayer) then safeExit("invalid PIM state on touch"); return end
if isCraftingBusy() then return end
if State.bannedNow then return end
if State.modalState.active and State.modalState.kind == "help" then
for _, btn in ipairs(State.buttons) do
if isButtonClicked(btn, x, y) then
if btn.id == "help_close" then closeModal()
elseif btn.id == "help_prev" and State.helpPage > 1 then State.helpPage = State.helpPage - 1; forceRender()
elseif btn.id == "help_next" and State.helpPage < 5 then State.helpPage = State.helpPage + 1; forceRender()
end
return
end
end
return
end
if State.categoryDropdownOpen and State.currentShopMode == "buy" then
local dropdownX = UI.header.searchX + UI.header.searchW + UI.header.clearBtnW + 1 + UI.header.allBtnW
local dropdownW = UI.header.dropdownW
for i, catName in ipairs(Data.categoryOrder) do
if y == UI.header.dropdownY + 1 + i and x >= dropdownX + 1 and x < dropdownX + dropdownW - 1 then
State.currentCategory = catName; State.categoryDropdownOpen = false; applyFilter(); markDirty("full"); return
end
end
State.categoryDropdownOpen = false; markDirty("full"); return
end
if State.modalState.active then
for _, btn in ipairs(State.buttons) do
if isButtonClicked(btn, x, y) then
if btn.id == "modal_ok" or btn.id == "modal_cancel" then closeModal(); return end
if btn.id == "pause_close" then closeModal(); return end
if btn.id == "replenish_go" then closeModal(); switchToMode("sell"); return end
if btn.id == "report_type_general" then openReportTypeForm("general"); return end
if btn.id == "report_type_price" then openReportTypeForm("price"); return end
if btn.id == "report_type_missing" then openReportTypeForm("missing_item"); return end
if btn.id == "report_back" then openReportModal(); return end
if btn.id == "report_submit" then submitReport(); return end
if btn.id == "report_my" then openMyReports(); return end
if btn.id == "my_reports_back" then openReportModal(); return end
if btn.id == "report_field_item" then local d = State.modalState.data; if d then d._active_field = "item"; forceRender() end; return end
if btn.id == "report_field_comment" then local d = State.modalState.data; if d then d._active_field = "comment"; forceRender() end; return end
end
end
return
end
local searchX, searchW = UI.header.searchX, UI.header.searchW
if State.currentShopMode == "buy" then
local allBtnX = searchX + searchW + UI.header.clearBtnW + 1
if y == 2 and x >= allBtnX and x < allBtnX + UI.header.allBtnW then State.categoryDropdownOpen = not State.categoryDropdownOpen; markDirty("full"); return end
end
if y == 2 and x >= searchX and x < searchX + searchW then State.searchInputActive = true; markDirty("header"); return end
for _, btn in ipairs(State.buttons) do
if isButtonClicked(btn, x, y) then
if btn.id == "clear_search" then
State.searchInput = ""; State.searchInputActive = false
if State.currentShopMode == "sets" then
applySetsFilter()
else
applyFilter()
if #Data.filteredItems > 0 then State.selectedIndex = 1; State.selectedItem = Data.filteredItems[1]; updateSelectorDisplay(State.selectedItem)
else State.selectedIndex = 0; State.selectedItem = nil; updateSelectorDisplay(nil) end
if State.currentShopMode == "sell" then refreshSellPlayerQty() end
end
markDirty("full")
elseif btn.id == "page_buy" or btn.id == "force_buy" then switchToMode("buy")
elseif btn.id == "page_sell" or btn.id == "force_sell" then switchToMode("sell")
elseif btn.id == "page_quests" then switchToMode("sets")
elseif btn.id == "buy_item" then performBuy()
elseif btn.id == "order_craft" then acOpenConfirm()
elseif btn.id == "autocraft_start" then acStart()
elseif btn.id == "autocraft_close" then State.autocraftJob = nil; forceRender()
elseif btn.id == "sell_item" then performSell()
elseif btn.id == "set_open" then
if State.selectedSet then
State.setView = "contents"; State.listScroll = 1; State.selectedIndex = 1
State.selectedSetItem = (State.selectedSet.items or {})[1]
clearLog()
addLogMessage("После покупки вы сможете забрать набор в любое удобное вам время", Colors.text_gray)
markDirty("full")
end
elseif btn.id == "set_back" then
State.setView = "list"; State.listScroll = 1; State.selectedIndex = 1
State.selectedSetItem = nil
clearLog()
applySetsFilter()
markDirty("full")
elseif btn.id == "set_buy" then performSetPurchase()
elseif btn.id == "set_dispense" then performSetDispense()
elseif btn.id == "max_qty" then
if State.currentShopMode == "buy" then State.purchaseQuantity = calculateMaxBuyQuantity(); State.purchaseInputActive = false
elseif State.sellPlayerQty > 0 then State.sellQuantity = State.sellPlayerQty; State.sellInputActive = false end
markDirty("right")
elseif btn.id == "report_bug" then
if not State.pimActive or not State.currentPlayer then openErrorModal("Ошибка", "Сначала встаньте на PIM") else openReportModal() end
elseif btn.id == "help_open" then
State.helpPage = 1
safeOpenModal("help", {})
elseif btn.id == "discount_info" then
openDiscountModal()
end
return
end
end
local listX, listY = UI.list.x, UI.list.y
local listW = math.floor(Config.SCREEN_W * UI.list.wRatio)
if x >= listX and x < listX + listW and y >= listY + 4 and y < listY + 4 + State.visibleRows then
local idx = State.listScroll + (y - (listY + 4))
if State.currentShopMode == "sets" then
if State.setView == "list" then
local set = Data.setsDisplay[idx]
if set then State.selectedIndex = idx; State.selectedSet = set; State.selectedSetItem = nil; markDirty("full") end
else
local set = State.selectedSet
if set then
local it = (set.items or {})[idx]
if it then State.selectedIndex = idx; State.selectedSetItem = it; markDirty("full") end
end
end
return
end
local item = Data.filteredItems[idx]
if item then
State.selectedIndex = idx; State.selectedItem = item
if State.currentShopMode == "sell" then refreshSellPlayerQty() else acProbeItem(item); State.purchaseQuantity = clampQuantity(State.purchaseQuantity, buyQtyCap(item)) end
State.purchaseInputActive = false; State.sellInputActive = false
updateSelectorDisplay(State.selectedItem); markDirty("full")
end
return
end
if State.currentShopMode == "sets" then return end
local panelX = math.floor(Config.SCREEN_W * UI.list.wRatio) + 2
if not State.selectedItem then return end
local item = State.selectedItem
local baseY = 5 + 3
local lineSpacing = 2
local hasCategory = (State.currentShopMode == "buy" and item.article and item.article ~= "")
local availY = baseY + lineSpacing + (hasCategory and lineSpacing or 0)
local acY = availY
local priceY
if State.currentShopMode == "buy" then acY = availY + lineSpacing; priceY = acY + lineSpacing else priceY = availY + lineSpacing end
local qtyTitleY = priceY + lineSpacing
local inputY = qtyTitleY + 2
local inputX = panelX + 2
local inputW = 12
if x >= inputX and x < inputX + inputW + 2 and y == inputY then
if State.currentShopMode == "buy" then State.purchaseInputActive = true; State.sellInputActive = false; State.searchInputActive = false
else State.sellInputActive = true; State.purchaseInputActive = false; State.searchInputActive = false end
markDirty("right"); return
end
if State.purchaseInputActive or State.sellInputActive then State.purchaseInputActive = false; State.sellInputActive = false; markDirty("right") end
end
function switchToMode(mode)
State.currentShopMode = mode
State.selectedIndex = 0; State.selectedItem = nil
State.purchaseQuantity = 1; State.sellQuantity = 1
State.purchaseInputActive = false; State.sellInputActive = false
State.logMessages = {}; State.currentCategory = "ВСЕ"; State.categoryDropdownOpen = false
State.searchInputActive = true
State.autocraftJob = nil
if mode == "sets" then
State.setView = "list"
State.selectedSetItem = nil
applySetsFilter()
updateSelectorDisplay(nil)
elseif mode == "buy" then
updateBuyCatalogFromME()
State.lastStockRefresh = computer.uptime()
applyFilter()
if #Data.filteredItems > 0 then
State.selectedIndex = 1; State.selectedItem = Data.filteredItems[1]
State.sellPlayerQty = 0
updateSelectorDisplay(State.selectedItem)
else State.sellPlayerQty = 0; updateSelectorDisplay(nil) end
else
applyFilter()
if #Data.filteredItems > 0 then
State.selectedIndex = 1; State.selectedItem = Data.filteredItems[1]
refreshSellPlayerQty()
updateSelectorDisplay(State.selectedItem)
else State.sellPlayerQty = 0; updateSelectorDisplay(nil) end
end
State.currentScreen = "shop"; markDirty("full")
end
function safeExit(reason)
if State.isShuttingDown then return end
State.isShuttingDown = true
writeDebugLog("🚪 safeExit(): " .. tostring(reason or "no reason"))
if State.TRANSACTION_LOCK then TransactionModule.unlock() end
if State.autocraftJob and State.autocraftJob.req then cancelCraftReq(State.autocraftJob.req) end
State.autocraftJob = nil
clearAllText()
State.selectedItem = nil; State.selectedIndex = 0
State.purchaseQuantity = 1; State.purchaseInputActive = false
State.sellQuantity = 1; State.sellInputActive = false; State.sellPlayerQty = 0
State.searchInput = ""; State.searchInputActive = false
State.modalData = nil; State.modalState.active = false; State.modalState.kind = nil; State.modalState.data = nil
State.listScroll = 1; Data.filteredItems = {}; State.logMessages = {}
State.currentCategory = "ВСЕ"; State.categoryDropdownOpen = false
State.setView = "list"; State.selectedSet = nil; State.selectedSetItem = nil
State.bannedNow = false; State.pauseGraceUntil = 0
updateSelectorDisplay(nil); safeSelectorSetSlot(0, nil); safeSelectorSetSlot(1, nil)
State.buttons = {}; State.lastRendered = false
State.currentPlayer = nil; State.currentSession = nil; State.pimOwner = nil; State.pimActive = false; State.pimAbsentCount = 0
State.currentScreen = "welcome"; State.screenInitialized = false
drawWelcomeScreen()
State.isShuttingDown = false
end
function logEvent(e, ...)
if e == "player_on" or e == "player_off" or e == "pim" or e == "pim_player_enter" or e == "pim_player_leave" then
local args = {...}
local argsStr = ""
for i, v in ipairs(args) do
argsStr = argsStr .. (i > 1 and ", " or "") .. tostring(v)
end
writeDebugLog("📡 EVENT: " .. tostring(e) .. " [" .. argsStr .. "]")
end
end
function main()
Buffer.init()
gpu.setBackground(Colors.bg_main)
gpu.fill(1, 1, Config.SCREEN_W, Config.SCREEN_H, " ")
PlayerModule.load(); CatalogModule.loadBuy(); CatalogModule.loadSell(); CatalogModule.loadSets(); CatalogModule.loadSetsProgress(); ReportModule.load(); PendingModule.load(); CatalogModule.loadVersion()
drawWelcomeScreen()
if type(pimIntrospect) == "function" then pimIntrospect() end
if #Data.buyCatalog == 0 and #Data.sellCatalog == 0 then
loadFullInit()
if State.catalogsLoaded then drawWelcomeScreen() end
else
applyBuyCatalog(Data.buyCatalog); applySellCatalog(Data.sellCatalog); applySetsFilter()
State.catalogsLoaded = true
syncCatalogsIfNeeded("boot")
drawWelcomeScreen()
end
heartbeatTick()
event.timer(Config.SAVE_DB_INTERVAL, function() PlayerModule.flush(); return true end, math.huge)
while true do
local ev
if #State.deferredEvents > 0 then ev = table.remove(State.deferredEvents, 1)
else ev = {pcall(event.pull, 0.5)}; if not ev[1] then ev = {} else table.remove(ev, 1) end end
local e = ev[1]
logEvent(e, table.unpack(ev, 2))
TransactionModule.checkTimeout()
heartbeatTick()
if State.modalState.kind == "pause_countdown" then
if computer.uptime() >= State.pauseGraceUntil then
State.modalState.active = false; State.modalState.kind = nil; State.modalState.data = nil; State.modalData = nil
markDirty("full")
else
markDirty("full")
end
end
if State.needStockRefresh and State.pimActive and State.currentScreen == "shop" then
State.needStockRefresh = false
updateBuyCatalogFromME()
if State.currentShopMode == "sets" then markDirty("full") end
end
if not State.pimActive and not State.syncInProgress and computer.uptime() - State.lastCatalogCheck > Config.CATALOG_CHECK_INTERVAL then
State.lastCatalogCheck = computer.uptime(); syncCatalogsIfNeeded("timer")
end
if not State.pimActive and State.pendingFullReload and not State.syncInProgress then
State.pendingFullReload = false
syncCatalogsIfNeeded("idle")
end
if not State.pimActive and computer.uptime() - State.lastPendingFlush > Config.PENDING_FLUSH_INTERVAL then
State.lastPendingFlush = computer.uptime()
if #Data.pendingChanges > 0 then PendingModule.flush() end
end
if not State.pimActive and State.catalogsLoaded and computer.uptime() - State.lastCatalogUpdate > Config.CATALOG_UPDATE_INTERVAL then
State.lastCatalogUpdate = computer.uptime(); updateBuyCatalogFromME()
end
if State.pimActive and State.currentScreen == "shop" and computer.uptime() - State.lastStockRefresh > 10 then
State.lastStockRefresh = computer.uptime()
updateBuyCatalogFromME()
if State.currentShopMode == "sets" then markDirty("full") end
end
if #State.acProbeQueue > 0 and not State.syncInProgress and not State.TRANSACTION_LOCK then
local it = table.remove(State.acProbeQueue, 1)
acDoProbe(it)
markDirty("right")
end
acStep()
if State.autocraftJob and State.autocraftJob.phase == "crafting" then
if computer.uptime() - State.acLastCmd > 10 then
State.acLastCmd = computer.uptime()
local cmds = HttpModule.request("oc_get_cmds", { terminalId = Config.TERMINAL_ID })
if cmds and cmds.commands then
for _, c in ipairs(cmds.commands) do
local okp, pl = pcall(from_json, c.payload or "{}")
if okp and type(pl) == "table" and (pl.terminalId == nil or pl.terminalId == Config.TERMINAL_ID) then
if c.command_type == "autocraft_cancel" then acCancel(false) end
end
end
end
end
end
if State.pimActive and not State.syncInProgress and computer.uptime() - State.lastPimCheck > 1 then
State.lastPimCheck = computer.uptime()
local pst = pimPresenceState()
if pst == "present" then
State.presenceWorks = true
elseif pst == "absent" then
State.presenceWorks = true
writeDebugLog("⚠️ Watchdog: PIM пуст — закрываем магазин")
handlePlayerLeave()
end
end
if e == "touch" then
local x, y = ev[3], ev[4]
local playerName = ev[6] or "Неизвестный"
if State.pimActive and State.currentPlayer then handleTouch(x, y, playerName) end
elseif e == "key_down" then
local ch = ev[3]
local playerName = ev[5] or "Неизвестный"
if State.pimActive and State.currentPlayer and PimModule.isOwner(playerName) and PimModule.ensureValid(State.currentPlayer) then
if State.bannedNow then
-- забанен: игнорируем весь ввод
elseif isCraftingBusy() then
-- игрок ждёт крафт
elseif State.autocraftJob and ch == 27 then
if State.autocraftJob.phase == "confirm" then State.autocraftJob = nil; forceRender()
else acCancel(true) end
elseif State.modalState.active and State.modalState.kind == "help" then
if ch == 27 then closeModal()
elseif ch == 203 and State.helpPage > 1 then State.helpPage = State.helpPage - 1; forceRender()
elseif ch == 205 and State.helpPage < 5 then State.helpPage = State.helpPage + 1; forceRender()
end
elseif State.modalState.active and State.modalState.kind == "report_form" then
local data = State.modalState.data
if ch == 27 then closeModal()
elseif ch == 9 then data._active_field = (data._active_field == "comment") and "item" or "comment"; forceRender()
elseif ch == 13 then submitReport()
elseif ch == 8 then
if data.type == "general" then data.text = unicode.sub(data.text or "", 1, -2)
elseif data.type == "price" or data.type == "missing_item" then
if data._active_field == "comment" then data.comment = unicode.sub(data.comment or "", 1, -2) else data.item_id = unicode.sub(data.item_id or "", 1, -2) end
end
forceRender()
elseif ch >= 32 then
if data.type == "general" then data.text = (data.text or "") .. unicode.char(ch)
elseif data.type == "price" or data.type == "missing_item" then
if data._active_field == "comment" then data.comment = (data.comment or "") .. unicode.char(ch) else data.item_id = (data.item_id or "") .. unicode.char(ch) end
end
forceRender()
end
elseif State.modalState.active and State.modalState.kind == "my_reports" then
if ch == 27 or ch == 13 then openReportModal() end
elseif State.categoryDropdownOpen then
if ch == 27 then State.categoryDropdownOpen = false; markDirty("full") end
elseif State.modalState.active then
if ch == 13 or ch == 27 then closeModal() end
elseif State.searchInputActive then
if ch == 27 then
State.searchInput = ""
if State.currentShopMode == "sets" then applySetsFilter() else applyFilter() end
markDirty("full")
elseif ch == 13 then
State.searchInputActive = false
if State.currentShopMode == "sets" then
applySetsFilter()
else
applyFilter()
State.selectedIndex = #Data.filteredItems > 0 and 1 or 0
State.selectedItem = Data.filteredItems[State.selectedIndex]
if State.currentShopMode == "sell" then refreshSellPlayerQty() end
updateSelectorDisplay(State.selectedItem)
end
markDirty("full")
elseif ch == 8 then
State.searchInput = unicode.sub(State.searchInput or "", 1, -2)
if State.currentShopMode == "sets" then
applySetsFilter()
else
applyFilter()
State.selectedIndex = #Data.filteredItems > 0 and 1 or 0
State.selectedItem = Data.filteredItems[State.selectedIndex]; updateSelectorDisplay(State.selectedItem)
end
markDirty("full")
elseif ch >= 32 then
State.searchInput = (State.searchInput or "") .. unicode.char(ch)
if State.currentShopMode == "sets" then
applySetsFilter()
else
applyFilter()
State.selectedIndex = #Data.filteredItems > 0 and 1 or 0
State.selectedItem = Data.filteredItems[State.selectedIndex]; updateSelectorDisplay(State.selectedItem)
end
markDirty("full")
end
elseif State.purchaseInputActive or State.sellInputActive then
if ch == 13 then State.purchaseInputActive = false; State.sellInputActive = false; State.searchInputActive = true; markDirty("right")
elseif ch == 8 then
local qty = State.currentShopMode == "buy" and State.purchaseQuantity or State.sellQuantity
qty = math.floor(qty / 10)
if State.currentShopMode == "buy" then State.purchaseQuantity = qty else State.sellQuantity = qty end
markDirty("right")
elseif ch >= 48 and ch <= 57 then
local digit = ch - 48
local qty = State.currentShopMode == "buy" and State.purchaseQuantity or State.sellQuantity
qty = qty == 0 and digit or qty * 10 + digit
if State.selectedItem then
if State.currentShopMode == "buy" then State.purchaseQuantity = clampQuantity(qty, buyQtyCap(State.selectedItem)) else State.sellQuantity = clampQuantity(qty, State.sellPlayerQty) end
end
markDirty("right")
end
end
end
elseif e == "scroll" then
local direction = ev[5]
local x, y = ev[3], ev[4]
local playerName = ev[6] or "Неизвестный"
if State.pimActive and State.currentPlayer and PimModule.isOwner(playerName) and PimModule.ensureValid(State.currentPlayer) and not State.categoryDropdownOpen and not isCraftingBusy() and not State.bannedNow then
local listX, listY = UI.list.x, UI.list.y
local listW = math.floor(Config.SCREEN_W * UI.list.wRatio)
if x >= listX and x < listX + listW and y >= listY + 4 and y < listY + 4 + State.visibleRows then
local total
if State.currentShopMode == "sets" then
if State.setView == "list" then total = #Data.setsDisplay
else total = #((State.selectedSet and State.selectedSet.items) or {}) end
else
total = #Data.filteredItems
end
local maxScroll = math.max(0, total - State.visibleRows)
if direction == -1 then State.listScroll = math.max(1, State.listScroll - 3)
elseif direction == 1 then State.listScroll = math.min(maxScroll + 1, State.listScroll + 3) end
markDirty("list")
end
end
elseif e == "player_on" or e == "pim" or e == "pim_player_enter" then
if not State.catalogsLoaded then writeDebugLog("⚠️ Игрок на PIM, но каталоги ещё не загружены. Игнорируем.")
elseif State.syncInProgress then writeDebugLog("⚠️ Идёт обновление, событие входа пропущено")
else
local playerName = ev[2] or "Игрок"
playerName = playerName:match("^%s*(.-)%s*$") or playerName
if not playerName or playerName == "" then playerName = "Неизвестный" end
if State.pimActive and State.currentPlayer == playerName then writeDebugLog("ℹ️ Дубль события входа, игрок уже в магазине")
else
if State.currentPlayer and State.currentPlayer ~= playerName then safeExit("new player replaced old one") end
handlePlayerEnter(playerName)
end
end
elseif e == "player_off" or e == "pim_player_leave" then
local playerName = ev[2]
writeDebugLog("👋 player_off: " .. tostring(playerName))
if State.currentPlayer then
handlePlayerLeave()
end
end
end
end
gpu.setResolution(Config.SCREEN_W, Config.SCREEN_H)
gpu.setBackground(Colors.bg_main)
event.listen("terminate", function() State.isShuttingDown = true; PlayerModule.save(); PendingModule.save(); CatalogModule.saveSetsProgress() end)
event.listen("computer_shutdown", function() State.isShuttingDown = true; PlayerModule.save(); PendingModule.save(); CatalogModule.saveSetsProgress() end)
while true do
local ok, err = pcall(main)
if not ok then
local errText = tostring(err)
local lowerErr = string.lower(errText)
if string.find(lowerErr, "interrupted", 1, true) or string.find(lowerErr, "terminate", 1, true) then writeDebugLog("⚠️ Завершение: " .. errText)
else
writeDebugLog("❌ КРИТИЧЕСКАЯ ОШИБКА: " .. errText)
local popupWidth, popupHeight = 70, 8
local popupX = math.floor((Config.SCREEN_W - popupWidth) / 2)
local popupY = math.floor((Config.SCREEN_H - popupHeight) / 2)
Buffer.clear()
drawBox(popupX, popupY, popupWidth, popupHeight, Colors.error_red, Colors.bg_main)
writeText(popupX + 2, popupY + 2, "ОШИБКА", Colors.error_red, Colors.bg_main)
writeText(popupX + 2, popupY + 4, tostring(errText):sub(1, popupWidth - 4), Colors.text_main, Colors.bg_main)
Buffer.flush()
for i = 3, 1, -1 do
Buffer.fill(1, popupY + 6, Config.SCREEN_W, 1, " ", Colors.text_bright, Colors.bg_main)
drawCenteredText(popupY + 6, "Перезагрузка через " .. i .. " сек...", Colors.success_green, Colors.bg_main)
Buffer.flush(); os.sleep(1)
end
end
os.sleep(1)
end
end
