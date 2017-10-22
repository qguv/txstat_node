esp8266 / nodemcu / mcp9808 wireless iot temperature sensor for distributed thermostat

`make upload`

dependencies:

- nodemcu-tool to upload code
- esptool to flash nodemcu-firmware
- nodemcu-firmware flashed onto on ESP with these extra modules:
  - gpio
  - i2c
  - mqtt
  - tmr
  - wifi
- make
- m4
- sed
