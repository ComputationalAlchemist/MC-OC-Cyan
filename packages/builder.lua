local cptpack = require("cptpack")
local cyan = require("cyan")
local serialization = require("serialization")
local filesystem = require("filesystem")
local shell = require("shell")

local packages = {"group_base", "autofs", "binaries", "cpt", "init", "libcolors", "libcyan", "libnote", "libprocess", "libserialization", "libsides", "motd", "shellaliases", "libinternet", "libcrypto"}

print("Building", #packages, "packages...")

outfile = "core.cpt"

local tout = cptpack.makeindex()
local old = cptpack.makeindex()
if filesystem.exists(filesystem.concat(shell.getWorkingDirectory(), outfile)) then
	old = cptpack.readindex(outfile)
end

for _, pack in ipairs(packages) do
	print("Building:", pack)
	local version = nil
	local out = cptpack.makepkg(pack, function(config)
		local path = filesystem.concat(shell.getWorkingDirectory(), tostring(config.name) .. "-" .. tostring(config.version) .. ".cpk")
		version = config.version
		return config.name and config.version and filesystem.exists(path) and cptpack.hasindex(old, config.name .. "-" .. config.version)
	end)
	if out == nil then
		print("Already up-to-date. Importing old index.")
		cptpack.mergesingleindex(tout, old, pack .. "-" .. version)
	else
		assert(out.name == pack)
		local ser = serialization.serialize(out)
		cyan.writeall(pack .. "-" .. out.version .. ".cpk", ser)
		print("Built:", pack .. "-" .. out.version)
		cptpack.addindex(tout, out, cptpack.packhash(ser))
	end
end

cptpack.writeindex(outfile, tout)