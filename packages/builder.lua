local cptpack = require("cptpack")
local cyan = require("cyan")
local serialization = require("serialization")
local filesystem = require("filesystem")

local packages = {"autofs", "binaries", "cpt", "init", "libcolors", "libcyan", "libnote", "libprocess", "libserialization", "libsides", "motd", "shellaliases", "libinternet", "libcrypto"}

print("Building", #packages, "packages...")

outfile = "core.cpt"

local tout = cptpack.makeindex()
local old = cptpack.makeindex()
if filesystem.exists(outfile) then
	old = cptpack.readindex(outfile)
end

for _, pack in ipairs(packages) do
	print("Building:", pack)
	local out = cptpack.makepkg(pack, function(config)
		return config.name and config.version and filesystem.exists(config.name .. "-" .. config.version .. ".cpk") and cptpack.hasindex(old, config.name)
	end)
	if out == nil then
		print("Already up-to-date. Importing old index.")
		cptpack.mergesingleindex(tout, old, pack)
	else
		assert(out.name == pack)
		local ser = serialization.serialize(out)
		cyan.writeall(pack .. "-" .. out.version .. ".cpk", ser)
		print("Built:", pack)
		cptpack.addindex(tout, out, cptpack.packhash(ser))
	end
end

cptpack.writeindex(outfile, tout)