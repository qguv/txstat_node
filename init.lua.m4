-- reads temperature from the mcp9808 temperature sensor module
-- vim: syntax=lua

include(config.m4)
local gpio = require("gpio")
local i2c = require("i2c")
local mqtt = require("mqtt")
local tmr = require("tmr")
local wifi = require("wifi")

function flash(pin, delay_ms)
    local t = tmr.create()
    t:alarm(delay_ms, tmr.ALARM_AUTO, function (_)
        gpio.write(pin, (gpio.read(pin) + 1) % 2)
    end)
    return t
end

function idle()
    wifi.eventmon.unregister(wifi.eventmon.STA_DISCONNECTED)
    wifi.eventmon.unregister(wifi.eventmon.STA_DHCP_TIMEOUT)
    awaiting_ip:unregister()
    gpio.write(LED_IDLE, gpio.LOW)
end

function panic(msg)
    idle()
    flash(LED_BAD, FLASH_FAST_MS)
    print(msg)
    --wifi.setmode(wifi.NULLMODE, false)
end

mcp9808 = {}

function mcp9808.write(reg, data)
    i2c.start(MCP9808_HOST_ADDR)
    i2c.address(MCP9808_HOST_ADDR, MCP9808_CHIP_ADDR, i2c.TRANSMITTER)
    i2c.write(MCP9808_HOST_ADDR, reg)
    for _, datum in pairs(data) do
        i2c.write(MCP9808_HOST_ADDR, datum)
    end
    i2c.stop(MCP9808_HOST_ADDR)
end

function mcp9808.read(reg, bytes)

    -- request the register address
    mcp9808.write(reg, {})

    -- read the response
    i2c.start(MCP9808_HOST_ADDR)
    i2c.address(MCP9808_HOST_ADDR, MCP9808_CHIP_ADDR, i2c.RECEIVER)
    local c = i2c.read(MCP9808_HOST_ADDR, bytes)
    i2c.stop(MCP9808_HOST_ADDR)

    return c
end

-- get the ambient temperature in Celsius
function mcp9808.temp()
    local raw = mcp9808.read(MCP9808_REG_AMBIENT_TEMP, 2)

    -- store register contents as an integer
    local msb = string.byte(raw, 1)
    local lsb = string.byte(raw, 2)

    -- detect a powered-off chip
    if (msb == 0xff and lsb == 0xff) then
        return nil
    end

    -- mathletics: because I don't trust this firmware to handle uints
    local temp = (lsb - (lsb % 16)) / 8 +
           (msb % 16) * 8 +
           (lsb % 16) / 8

    -- check for sign bit and correct
    if ((msb % 32) >= 16) then
        temp = temp - 256
    end

    return temp
end

function get_temp(cb)
    -- wake, read, go back to sleep
    mcp9808.write(MCP9808_REG_CONFIG, MCP9808_CONFIG_CLEAR)
    tmr.create():alarm(350, tmr.ALARM_SINGLE, function()
        local temp = mcp9808.temp()
        if (temp ~= nil) then
            mcp9808.write(MCP9808_REG_CONFIG, MCP9808_CONFIG_SHUTDOWN)
        end

        print(temp, "C")
        cb(temp)
    end)
end

function mqtt_publish(topic, message, cb)
    local c = mqtt.Client("txstat-" .. MQTT_NAME, MQTT_TIMEOUT)
    c:connect(
        MQTT_IP,
        1883,
        0,
        function (client)
            client:publish(topic, message, 0, 0)
            client:close()
            cb()
        end,
        function (_, reason)
            gpio.write(LED_TX, gpio.HIGH)
            panic("couldn't connect to mqtt: error " .. reason)
        end
    )
end

function main(netinfo)
    awaiting_ip:unregister()
    gpio.write(LED_IDLE, gpio.LOW)
    print("got ip", netinfo.ip)

    get_temp(function (temp)

        -- temperature sensor disconnected
        if (temp == nil) then
            gpio.write(LED_IDLE, gpio.HIGH)
            panic("no connection to mcp9808")
            return
        end

        gpio.write(LED_TX, gpio.HIGH)
        mqtt_publish(MQTT_TOPIC, temp, function ()
            gpio.write(LED_TX, gpio.LOW)
            idle()
            tmr.create():alarm(IDLE_MS, tmr.ALARM_SINGLE, node.restart)

            -- success
            local good_flash = flash(LED_GOOD, FLASH_FAST_MS)
            tmr.create():alarm(500, tmr.ALARM_SINGLE, function()
                good_flash:unregister()
                gpio.write(LED_GOOD, gpio.LOW)
                tmr.create():alarm(1000, tmr.ALARM_SINGLE, function ()
                    gpio.write(LED_IDLE, gpio.HIGH)
                end)
            end)

        end)
    end)
end

-- register wifi callbacks
wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, node.restart)
wifi.eventmon.register(wifi.eventmon.STA_DHCP_TIMEOUT, node.restart)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, main)

-- connect to wifi
wifi.setphymode(wifi.PHYMODE_N)
wifi.setmode(wifi.STATION, true)
wifi.sta.config({
    ssid = AP;
    pwd = AP_PASS;
    auto = true;
    save = true;
})

-- prepare LEDs
for led in pairs({LED_BAD, LED_GOOD, LED_IDLE, LED_TX}) do
    gpio.mode(led, gpio.OUTPUT)
    gpio.write(led, gpio.LOW)
end

awaiting_ip = flash(LED_IDLE, FLASH_SLOW_MS)

-- prepare temperature sensor
i2c.setup(MCP9808_HOST_ADDR, I2C_SDA, I2C_SCL, i2c.SLOW)
mcp9808.write(MCP9808_REG_CONFIG, MCP9808_CONFIG_CLEAR)
