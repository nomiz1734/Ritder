--[[--
Battery status for the TrimUI Brick Pro (Ritder). Backlight and sleep stay with the stock OS.

The battery is found by scanning /sys/class/power_supply for a supply of type "Battery"
(axp2202-battery on current firmwares), so a renamed node does not break it.

@module device.trimui.powerd
]]

local BasePowerD = require("device/generic/powerd")
local lfs = require("libs/libkoreader-lfs")

local SUPPLY_DIR = "/sys/class/power_supply"

local TrimUIPowerD = BasePowerD:new{
    battery_dir = nil,
}

local function readLine(path)
    local f = io.open(path, "re")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
end

function TrimUIPowerD:init()
    local ok, iter, state = pcall(lfs.dir, SUPPLY_DIR)
    if not ok then return end
    for name in iter, state do
        if name ~= "." and name ~= ".." then
            local dir = SUPPLY_DIR .. "/" .. name
            if readLine(dir .. "/type") == "Battery" and lfs.attributes(dir .. "/capacity", "mode") then
                self.battery_dir = dir
                break
            end
        end
    end
end

function TrimUIPowerD:getCapacityHW()
    if not self.battery_dir then return 0 end
    return self:read_int_file(self.battery_dir .. "/capacity")
end

function TrimUIPowerD:isChargingHW()
    if not self.battery_dir then return false end
    return readLine(self.battery_dir .. "/status") == "Charging"
end

function TrimUIPowerD:isChargedHW()
    if not self.battery_dir then return false end
    return readLine(self.battery_dir .. "/status") == "Full"
end

return TrimUIPowerD
