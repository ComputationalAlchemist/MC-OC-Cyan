local cptpack = require("cptpack")
local cyan = require("cyan")
local serialization = require("serialization")
local filesystem = require("filesystem")
local shell = require("shell")

local packages = {}

for name in filesystem.list(shell.getWorkingDirectory()) do
	if name:sub(#name) == "/" then
		table.insert(packages, name:sub(1, #name - 1))
	end
end

print("Building", #packages, "packages...")

outfile = "core.cpt"

local tout = cptpack.makeindex()
local old = cptpack.makeindex()
if filesystem.exists(filesystem.concat(shell.getWorkingDirectory(), outfile)) then
	old = cptpack.readindex(outfile)
end

local versions = {}

for _, pack in ipairs(packages) do
	print("Building:", pack)
	local version = nil
	local out = cptpack.makepkg(pack, function(config)
		local path = filesystem.concat(shell.getWorkingDirectory(), tostring(config.name) .. "-" .. tostring(config.version) .. ".cpk")
		version = config.version
		versions[config.name] = config.version
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

-- Installer installation packages

print("Building installer...")
local installer_packages = {"cpt", "libcrypto", "libcyan"}
local fout, err = io.open("installer.lua", "w")
assert(fout, "Cannot open installer.lua for writing: " .. tostring(err))
function putinst(line)
	local out, err = fout:write(line)
	assert(out, "Cannot write installer.lua: " .. tostring(err))
end
putinst([[
-- Cyan OS Installer
local filesystem = require("filesystem")
local shell = require("shell")
io.write("Enter absolute directory to install to: ")
local dirout = io.read()
assert(not dirout:match(" "), "Spaces are not allowed in this path.")
assert(filesystem.isDirectory(dirout), "That's not a directory that exists!")
shell.setWorkingDirectory(dirout)
function handle(file, data)
	file = filesystem.concat(dirout, file)
	if not filesystem.exists(filesystem.path(file)) then
		assert(filesystem.makeDirectory(filesystem.path(file)), 'Could not create parent directory: ' .. file)
	end
	local out, err = io.open(file, 'w')
	assert(out, "Cannot open " .. file .. " for writing: " .. tostring(err))
	local out, err = out:write(data)
	assert(out, "Cannot write " .. file .. ": " .. tostring(err))
	out:close()
end
]])
local toremove = {}
for _, name in ipairs(installer_packages) do
	local pkg = cyan.readserialized(name .. "-" .. versions[name] .. ".cpk")
	local keys = cyan.keylist(pkg.contents)
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = pkg.contents[k]
		local fname = filesystem.name(k)
		putinst("handle(" .. serialization.serialize(fname) .. ", " .. serialization.serialize(v) .. ")\n")
		table.insert(toremove, fname)
	end
end
putinst([[
require("cptcache").configpath = filesystem.concat(dirout, "cpt.list")
local success, reason = os.execute("cpt reroot " .. dirout .. " strap")
]])
for _, name in ipairs(toremove) do
	putinst("assert((filesystem.remove(filesystem.concat(dirout, " .. serialization.serialize(name) .. "))), " .. serialization.serialize("Could not remove: " .. name) .. ")")
end
putinst([[
assert(success, "Installation failed: " .. tostring(reason) .. "\nMake sure to remove /var/cache/cpt and /var/lib/cpt in the target directory before trying again.")
]])
fout:close()
