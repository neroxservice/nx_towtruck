ESX = exports['es_extended']:getSharedObject()

MySQL.ready(function()
    MySQL.Async.execute([[CREATE TABLE IF NOT EXISTS parking_tickets (
        id INT AUTO_INCREMENT PRIMARY KEY,
        identifier VARCHAR(64),
        plate VARCHAR(10),
        bought_at DATETIME,
        duration_hours INT,
        position TEXT NULL,
        heading FLOAT NULL,
        model TEXT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8;]])
end)

local function vecDist(v1, v2)
    return math.sqrt((v1.x - v2.x)^2 + (v1.y - v2.y)^2 + (v1.z - v2.z)^2)
end

local towJobs = {}

local function NotifyPlayer(playerId, title, desc, type)
    local notifyType = Config.Notification
    if notifyType == 'okokNotify' then
        TriggerClientEvent('okokNotify:Alert', playerId, title, desc, 8000, type)
    elseif notifyType == 'mythic' then
        TriggerClientEvent('mythic_notify:client:SendAlert', playerId, { type = type, text = desc })
    elseif notifyType == 'ox_lib' then
        TriggerClientEvent('ox_lib:notify', playerId, { title = title, description = desc, type = type })
    else
        TriggerClientEvent('esx:showNotification', playerId, desc)
    end
end

local function NotifyTowtruckers(title, desc, type)
    for _, playerId in ipairs(GetPlayers()) do
        local xPlayer = ESX.GetPlayerFromId(tonumber(playerId))
        if xPlayer and xPlayer.job and xPlayer.job.name == 'towtrucker' then
            NotifyPlayer(tonumber(playerId), title, desc, type)
            TriggerClientEvent('trs_parking:playTowJobSound', tonumber(playerId))
        end
    end
end

RegisterNetEvent('parking:tryBuyTicket')
AddEventHandler('parking:tryBuyTicket', function(plate, hours, x, y, z, heading, model)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local minHours = Config.Debug and 0.01 or 1
    if type(plate) ~= 'string' or type(hours) ~= 'number' or hours < minHours then
        TriggerClientEvent('esx:showNotification', src, 'Invalid command arguments!')
        SendDiscordLog("Error", "Invalid arguments for buy ticket: plate="..tostring(plate)..", hours="..tostring(hours), src)
        if Config.Debug then
            print("[PARKING][DEBUG][SERVER] Invalid buy ticket args: plate="..tostring(plate)..", hours="..tostring(hours))
        end
        return
    end

    local cost = hours * Config.PricePerHour
    local bank = xPlayer.getAccount('bank').money
    if bank < cost then
        TriggerClientEvent('esx:showNotification', src, "You don't have enough money in your bank account!")
        SendDiscordLog("Error", "Not enough money for buy ticket: plate="..tostring(plate)..", hours="..tostring(hours), src)
        return
    end

    local posData = json.encode({ x = x, y = y, z = z })
    local now = os.date('%Y-%m-%d-%H:%M:%S')

    MySQL.Async.fetchScalar('SELECT duration_hours FROM parking_tickets WHERE plate = @plate', {
        ['@plate'] = plate
    }, function(existing)
        if existing then
            MySQL.Async.execute('UPDATE parking_tickets SET duration_hours = duration_hours + @add, position = @pos, heading = @head WHERE plate = @plate', {
                ['@add'] = hours,
                ['@pos'] = posData,
                ['@head'] = heading,
                ['@plate'] = plate
            })
        else
            MySQL.Async.execute([[INSERT INTO parking_tickets (identifier, plate, bought_at, duration_hours, position, heading, model)
                VALUES (@id, @plate, @bought, @hours, @pos, @head, @model)]], {
                ['@id'] = xPlayer.identifier,
                ['@plate'] = plate,
                ['@bought'] = now,
                ['@hours'] = hours,
                ['@pos'] = posData,
                ['@head'] = heading,
                ['@model'] = model
            })
        end

        MySQL.Async.execute('UPDATE owned_vehicles SET parked_since = NULL WHERE plate = @plate', {
            ['@plate'] = plate
        })

        towJobs[plate] = nil
        TriggerClientEvent('trs_parking:removeTowJob', -1, plate)

        xPlayer.removeAccountMoney('bank', cost)
        -- Instead of ESX notification, trigger client event for custom notification
        TriggerClientEvent('parking:ticketBoughtNotify', src, plate, hours)
        SendDiscordLog("Ticket Bought", ("Plate: %s | Hours: %s | Model: %s | Pos: %.2f,%.2f,%.2f"):format(plate, hours, model, x, y, z), src)
        if Config.Debug then
            print("[PARKING][DEBUG][SERVER] Ticket bought: plate="..tostring(plate)..", hours="..tostring(hours))
        end
    end)
end)

RegisterNetEvent('parking:removeTicket')
AddEventHandler('parking:removeTicket', function(plate)
    local src = source
    MySQL.Async.execute('DELETE FROM parking_tickets WHERE plate = @plate', {
        ['@plate'] = plate
    })
    MySQL.Async.execute('UPDATE owned_vehicles SET parked_since = NOW() WHERE plate = @plate', {
        ['@plate'] = plate
    })
    NotifyTowtruckers('New unpaid parking ticket', 'Plate: '..plate..' has an unpaid ticket!', 'info')
    SendDiscordLog("Unpaid Ticket", "Plate: "..tostring(plate), src)
    local now = os.time()
    if not lastUnpaidTicketLog[plate] or now - lastUnpaidTicketLog[plate] > 300 then
        SendDiscordLog("Unpaid Ticket", "Plate: "..tostring(plate), src)
        lastUnpaidTicketLog[plate] = now
    end
end)

ESX.RegisterServerCallback('parking:getVehiclesStatus', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({}) return end

    MySQL.Async.fetchAll([[
        SELECT ov.plate, pt.bought_at, pt.duration_hours, pt.position, pt.heading, pt.model, ov.vehicle
        FROM owned_vehicles ov
        LEFT JOIN parking_tickets pt ON ov.plate = pt.plate
        WHERE ov.owner = @owner AND ov.stored = 0
    ]], {
        ['@owner'] = xPlayer.identifier
    }, function(result)
        local now = os.time()
        local vehicles = {}

        for _, row in ipairs(result or {}) do
            local hasTicket = false
            local duration = tonumber(row.duration_hours) or 0
            local expireTime = 0
            if row and row.bought_at then
                local bought = tostring(row.bought_at)
                local yy, mm, dd, hh, mi, ss = bought:match("(%d+)%-(%d+)%-(%d+)%-(%d+):(%d+):(%d+)")
                if yy and mm and dd and hh and mi and ss then
                    local boughtTimestamp = os.time({
                        year = tonumber(yy),
                        month = tonumber(mm),
                        day = tonumber(dd),
                        hour = tonumber(hh),
                        min = tonumber(mi),
                        sec = tonumber(ss)
                    })
                    expireTime = boughtTimestamp + (duration * 3600)
                end
                if expireTime > 0 and now <= expireTime then
                    hasTicket = true
                elseif expireTime > 0 then
                    MySQL.Async.execute('DELETE FROM parking_tickets WHERE plate = @plate', {
                        ['@plate'] = row.plate
                    })
                end
            end

            local pos = nil
            if row and row.position then
                local ok, dec = pcall(json.decode, row.position)
                if ok then pos = dec end
            end

            local vehicleData = {}
            if row and row.vehicle then
                local ok2, decoded = pcall(json.decode, row.vehicle or '{}')
                if ok2 then vehicleData = decoded end
            end

            if row and row.plate then
                vehicles[row.plate] = {
                    hasTicket = hasTicket,
                    position = pos,
                    heading = row.heading or 0.0,
                    model = row.model or '',
                    vehicle = vehicleData
                }
            end
        end

        cb(vehicles)
    end)
end)

ESX.RegisterServerCallback('parking:getUnpaidTickets', function(source, cb)
    MySQL.Async.fetchAll([[
        SELECT ov.plate, ov.vehicle, ov.owner, ov.stored, ov.parked_since
        FROM owned_vehicles ov
        LEFT JOIN parking_tickets pt ON ov.plate = pt.plate
        WHERE pt.plate IS NULL AND ov.stored = 0
    ]], {}, function(result)
        local now = os.time()
        local unpaid = {}
        for _, row in ipairs(result or {}) do
            local parkedSince = 0
            if row.parked_since then
                local yy, mm, dd, hh, mi, ss = tostring(row.parked_since):match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
                if yy and mm and dd and hh and mi and ss then
                    local ts = os.time({
                        year = tonumber(yy),
                        month = tonumber(mm),
                        day = tonumber(dd),
                        hour = tonumber(hh),
                        min = tonumber(mi),
                        sec = tonumber(ss)
                    })
                    parkedSince = now - ts
                end
            end
            local vehicleData = {}
            if row.vehicle then
                local ok, decoded = pcall(json.decode, row.vehicle)
                if ok then vehicleData = decoded end
            end
            unpaid[#unpaid+1] = {
                plate = row.plate,
                vehicle = vehicleData,
                parkedSince = parkedSince
            }
        end
        cb(unpaid)
    end)
end)

RegisterNetEvent('parking:towtruckerSetWaypoint')
AddEventHandler('parking:towtruckerSetWaypoint', function(plate)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or xPlayer.job.name ~= 'towtrucker' then return end

    MySQL.Async.fetchAll('SELECT position FROM owned_vehicles WHERE plate = @plate', {
        ['@plate'] = plate
    }, function(owned)
        local pos = nil
        if owned and owned[1] and owned[1].position then
            local ok, decoded = pcall(json.decode, owned[1].position)
            if ok and decoded and decoded.x and decoded.y and decoded.z then
                pos = decoded
            end
        end
        if pos then
            TriggerClientEvent('parking:towtruckerWaypoint', src, pos)
        else
            MySQL.Async.fetchAll('SELECT position FROM parking_tickets WHERE plate = @plate', {
                ['@plate'] = plate
            }, function(result)
                if result and result[1] and result[1].position then
                    local ok, pos2 = pcall(json.decode, result[1].position)
                    if ok and pos2 then
                        TriggerClientEvent('parking:towtruckerWaypoint', src, pos2)
                    end
                end
            end)
        end
    end)
end)

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer and xPlayer.job and xPlayer.job.name == 'towtrucker' then
        ESX.TriggerServerCallback('parking:getUnpaidTickets', function(tickets)
            TriggerClientEvent('trs_parking:syncTowJobs', src, tickets)
        end)
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)

        MySQL.Async.fetchAll('SELECT plate, position FROM parking_tickets', {}, function(tickets)
            for _, ticket in ipairs(tickets) do
                local plate = ticket.plate
                local posData = ticket.position
                if posData then
                    local ok, pos = pcall(json.decode, posData)
                    if ok and pos then
                        local found = false
                        local vehicles = GetGamePool('CVehicle')
                        for _, veh in ipairs(vehicles) do
                            local vehPlate = GetVehicleNumberPlateText(veh):gsub("%s+", "")
                            if vehPlate == plate:gsub("%s+", "") then
                                found = true
                                local vehPos = GetEntityCoords(veh)
                                if vecDist(vehPos, vector3(pos.x, pos.y, pos.z)) > 2.0 then
                                    MySQL.Async.execute('DELETE FROM parking_tickets WHERE plate = @plate', { ['@plate'] = plate })
                                    MySQL.Async.execute('UPDATE owned_vehicles SET parked_since = NOW(), position = @pos WHERE plate = @plate', {
                                        ['@plate'] = plate,
                                        ['@pos'] = json.encode({ x = vehPos.x, y = vehPos.y, z = vehPos.z })
                                    })
                                    towJobs[plate] = nil
                                    TriggerClientEvent('trs_parking:removeTowJob', -1, plate)
                                end
                                break
                            end
                        end
                        if not found then
                            MySQL.Async.execute('DELETE FROM parking_tickets WHERE plate = @plate', { ['@plate'] = plate })
                            MySQL.Async.execute('UPDATE owned_vehicles SET parked_since = NOW() WHERE plate = @plate', { ['@plate'] = plate })
                            towJobs[plate] = nil
                            TriggerClientEvent('trs_parking:removeTowJob', -1, plate)
                        end
                    end
                end
            end
        end)
    end
end)

RegisterNetEvent('parking:updateVehiclePosition')
AddEventHandler('parking:updateVehiclePosition', function(plate, x, y, z)
    if plate and x and y and z then
        local posJson = json.encode({ x = x, y = y, z = z })
        MySQL.Async.execute('UPDATE owned_vehicles SET position = @pos WHERE plate = @plate', {
            ['@pos'] = posJson,
            ['@plate'] = plate
        })
    end
end)

local lastUnpaidTicketLog = {}

RegisterNetEvent('parking:removeTicket')
AddEventHandler('parking:removeTicket', function(plate)
    local src = source
    MySQL.Async.execute('DELETE FROM parking_tickets WHERE plate = @plate', {
        ['@plate'] = plate
    })
    MySQL.Async.execute('UPDATE owned_vehicles SET parked_since = NOW() WHERE plate = @plate', {
        ['@plate'] = plate
    })
    NotifyTowtruckers('New unpaid parking ticket', 'Plate: '..plate..' has an unpaid ticket!', 'info')
    SendDiscordLog("Unpaid Ticket", "Plate: "..tostring(plate), src)
    -- Only log unpaid ticket once per 5 minutes per specific plate
    local now = os.time()
    if not lastUnpaidTicketLog[plate] or now - lastUnpaidTicketLog[plate] > 300 then
        SendDiscordLog("Unpaid Ticket", "Plate: "..tostring(plate), src)
        lastUnpaidTicketLog[plate] = now
    end
end)

local function GetDiscordId(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, v in ipairs(identifiers) do
        if v:match("^discord:") then
            return v:gsub("discord:", "")
        end
    end
    return "N/A"
end

local function SendDiscordLog(action, details, src)
    if not Config.DiscordWebhook or Config.DiscordWebhook == "" then return end
    local embed = {
        color = 16753920,
        title = "**Parking System Log**",
        fields = {
            { name = "Action", value = action, inline = false },
            { name = "Details", value = details or "-", inline = false }
        },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }
    if src then
        local name = GetPlayerName(src) or "N/A"
        local xPlayer = ESX.GetPlayerFromId(src)
        local charid = xPlayer and xPlayer.identifier or "N/A"
        local discord = GetDiscordId(src)
        table.insert(embed.fields, 1, { name = "Player", value = name, inline = true })
        table.insert(embed.fields, 2, { name = "Char ID", value = charid, inline = true })
        table.insert(embed.fields, 3, { name = "Discord", value = discord, inline = true })
    end
    PerformHttpRequest(Config.DiscordWebhook, function() end, 'POST', json.encode({embeds = {embed}}), { ['Content-Type'] = 'application/json' })
end

RegisterNetEvent('parking:logToDiscord')
AddEventHandler('parking:logToDiscord', function(msg)
    local src = source
    SendDiscordLog("Client Log", msg, src)
end)
