local cptpack = require("cptpack")
local cyan = require("cyan")
local serialization = require("serialization")

local packages = {"autofs", "binaries", "cpt", "init", "libcolors", "libcyan", "libnote", "libprocess", "libserialization", "libsides", "motd", "shellaliases", "libinternet", "libcrypto"}

print("Building", #packages, "packages...")

local tout = cptpack.makeindex()

for _, pack in ipairs(packages) do
	print("Building:", pack)
	local out = cptpack.makepkg(pack)
	assert(out.name == pack)
	local ser = serialization.serialize(out)
	cyan.writeall(pack .. "-" .. out.version .. ".cpk", ser)
	print("Built:", pack)
	cptpack.addindex(tout, out, cptpack.packhash(ser))
end

cptpack.writeindex("core.cpt", tout)