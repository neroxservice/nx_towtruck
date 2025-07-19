# nx_towtruck

**Creator:** [NeroX](https://github.com/neroxservice)

A modern, configurable parking ticket system for ESX-based FiveM servers.

---

## Features

- Parking ticket system with configurable price per hour
- Towtrucker job with interactive dispatch UI
- Blip system for unpaid tickets
- Configurable notification system (`esx`, `okokNotify`, `ox_lib`)
- Free zones, ignored vehicles/plates, and more
- Discord webhook logging for all major actions

---

## Supported Languages

- Only English (`en`)

---

## Installation

1. Import the SQL from `sql/install.sql` to your database.
2. Configure `config.lua` as needed.
3. Add the resource to your `server.cfg` and ensure dependencies (`es_extended`, `oxmysql`, and your chosen notification resource) are started before this script.

---

## Configuration

See `config.lua` for all options:

- `Notification`: Notification system (`esx`, `okokNotify`, `mythic`, `ox_lib`)
- `PricePerHour`: Price for parking ticket per hour
- `BlipDistance`, `SpawnDistance`, `FreeZones`, `TowtruckModels`, `IgnoreModels`, `IgnorePlates`
- `DiscordWebhook`: Set your Discord webhook for logs
- `PlateWithSpace`: If `true`, `/buyparkingticket` expects a plate with a space (e.g. `ABC 123`). If `false`, expects plate without space (e.g. `ABC123`).

---

## How to Use

- Players can buy parking tickets using `/buyparkingticket [PLATE] [hours]`
  - If `Config.PlateWithSpace` is `true`, use `/buyparkingticket [PLATE with space] [hours]` (e.g. `/buyparkingticket ABC 123 2`)
  - If `Config.PlateWithSpace` is `false`, use `/buyparkingticket [PLATE] [hours]` (e.g. `/buyparkingticket ABC123 2`)
- Towtruckers can open dispatch with `/towdispatch` and use arrow keys or mouse to navigate jobs
- Press `G` to set a waypoint to the selected job
- Blips show unpaid tickets

**Note:**  
If the car moves from its original parked position, the parking ticket will be automatically deleted.

**Important:**  
This script does **not** respawn or restore parked vehicles after a server restart or resource reload. The parking ticket system is only for ticketing and tracking, not for persistent vehicle parking.  

---

## How It Works

- When a player parks and buys a ticket, the ticket is stored in the database
- Towtruckers see unpaid tickets in their dispatch UI and can set waypoints
- If a car moves, the ticket is removed and the location is updated
- All major actions are logged to Discord if webhook is set

---

Thank you for using and supporting my work!
