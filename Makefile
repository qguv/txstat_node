.PHONY = upload clean
DEPS = config.m4 mcp9808.m4

init.lua: init.lua.m4 $(DEPS)
	m4 init.lua.m4 | sed '/^\s*$$/d' | sed '/--.*$$/d' > init.lua

upload: init.lua
	sudo nodemcu-tool upload init.lua
	sudo nodemcu-tool reset

clean:
	rm -f init.lua
