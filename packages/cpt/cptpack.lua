local cptpack = {}
local filesystem = require("filesystem")
local cyan = require("cyan")
local shell = require("shell")

cptpack.root = "/"
function cptpack.toroot(file)
	if file:sub(1, 1) == "/" then
		return filesystem.concat(cptpack.root, file:sub(2))
	else
		return file
	end
end

function cptpack.loadindex(path)
	local data = cyan.readserialized(path)
	data.listing = cyan.keylist(data.contents)
	data.contents = nil
	return data
end

local function tryremoveparents(file)
	local parent = filesystem.path(file)
	if cyan.isDirectoryEmpty(parent) then
		print("Parent directory is no longer in use:", parent)
		filesystem.remove(parent)
		tryremoveparents(parent)
	end
end

function cptpack.uninstall(name, index)
	assert(name == index.name .. "-" .. index.version)
	print("Uninstalling", name)
	for i, file in ipairs(index.listing) do
		if not filesystem.exists(cptpack.toroot(file)) then
			print("Would remove", cptpack.toroot(file), "but it didn't exist.")
		else
			print("Removing", cptpack.toroot(file))
			if file:sub(1, 1) ~= "/" then
				error("Invalid path - no leading slash!")
			end
			cyan.removeSingleFile(cptpack.toroot(file))
			tryremoveparents(cptpack.toroot(file))
		end
	end
end

function cptpack.install(pname, path)
	local data = cyan.readserialized(path)
	assert(pname == data.name .. "-" .. data.version)
	print("Installing", pname)
	for name, data in pairs(data.contents) do
		if name:sub(1, 1) ~= "/" then
			error("Invalid path - no leading slash!")
		end
		print("Adding", cptpack.toroot(name))
		if filesystem.exists(cptpack.toroot(name)) then
			error("File already exists!")
		end
		cyan.makeParentDirectory(cptpack.toroot(name))
		cyan.writeall(cptpack.toroot(name), data)
	end
end

function cptpack.makepkg(dir) -- Ignores root
	dir = filesystem.concat(shell.getWorkingDirectory(), dir)
	local loaded, err = loadfile(filesystem.concat(dir, "PACKBUILD"))
	if not loaded then
		error("Cannot load PACKBUILD: " .. err)
	end
	local config = loaded(dir, fileout)
	local pack = config.package or {}
	if not pack.contents then pack.contents = {} end
	for target, source in pairs(config.include or {}) do
		if source:sub(1, 1) == "/" then
			pack.contents[target] = cyan.readall(source)
		else
			pack.contents[target] = cyan.readall(filesystem.concat(dir, source))
		end
	end
	for _, field in ipairs({"name", "version", "depends", "conflicts"}) do
		if config[field] then
			assert(pack[field] == nil)
			pack[field] = config[field]
		end
		assert(pack[field], "No package " .. field .. "!")
	end
	return pack
end

function cptpack.buildpkg(dir, fileout) -- Ignores root
	cyan.writeserialized(fileout, cptpack.makepkg(dir))
end

return cptpack