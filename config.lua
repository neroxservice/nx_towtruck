Config = {}

-- (see locales folder)
Config.Locale = 'en'

-- Notification system: 'esx', 'okokNotify', 'ox_lib'
Config.Notification = 'esx'

-- Debug mode: if true, prints debug info 
Config.Debug = false

-- Price per hour for parking ticket (from bank)
Config.PricePerHour = 1000

-- Interval for checking parked vehicles (ms)
Config.CheckInterval = 60000

-- Distance for showing blips (meters)
Config.BlipDistance = 50.0

-- Free zones where unpaid tickets are ignored (add more as needed)
Config.FreeZones = {
    -- { x = 0.0, y = 0.0, z = 0.0, radius = 50.0 }
{ x = 227.6665, y = -781.7689, z =  30.7232, radius = 50.0 },
    
}

-- If true, /buyparkingticket expects plate with space (e.g. "ABC 123"), if false, expects plate without space (e.g. "ABC123")
Config.PlateWithSpace = true

-- Discord webhook for logs (set to "" to disable)
Config.DiscordWebhook = ""
-- Blip settings
Config.Blip = {
    sprite = 225,
    scale = 0.7,
    colorPaid = 2,
    colorUnpaid = 1,
    textPaid = 'Paid ticket',
    textUnpaid = 'Unpaid ticket'
}

-- Towtruck vehicle models
Config.TowtruckModels = {
    'towtruck', 'towtruck2', 'flatbed'
}

-- Ignore vehicles by model name (case-insensitive)
Config.IgnoreModels = {
    "police", "ambulance", "firetruk", "towtruck", "towtruck2", "flatbed"
}

-- Ignore vehicles by plate (case-sensitive, no spaces)
Config.IgnorePlates = {
    "ADMIN001", "VIP123"
}

