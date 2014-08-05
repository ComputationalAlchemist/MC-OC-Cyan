local cptpack = require("cptpack")
local cyan = require("cyan")

local packages = {"autofs", "binaries", "cpt", "init", "libcolors", "libcyan", "libnote", "libprocess", "libserialization", "libsides", "motd", "shellaliases", "libinternet"}

print("Building", #packages, "packages...")

local tout = ""

for _, pack in ipairs(packages) do
	print("Building:", pack)
	local out = cptpack.makepkg(pack)
	assert(out.name == pack)
	cyan.writeserialized(pack .. ".cpk", out)
	print("Built:", pack)
	tout = tout .. "package " .. out.name .. "-" .. out.version .. " local://" .. pack .. ".cpk\n"
end

cyan.writeall("core.cpt", tout)
