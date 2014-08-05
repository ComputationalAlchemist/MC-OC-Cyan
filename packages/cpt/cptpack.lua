local cptpack = {}
local filesystem = require("filesystem")
local cyan = require("cyan")
local shell = require("shell")
local crypto = require("crypto")

cptpack.root = "/"

function cptpack.compareversion(a, b)
	if a == nil and b == nil then
		return 0
	elseif a == nil then
		return -1
	elseif b == nil then
		return 1
	end
	local ab, ar = cyan.cut(a, "[.]")
	local bb, br = cyan.cut(b, "[.]")
	local abn = tonumber(ab)
	if abn == nil then
		error("Bad version: not a number: " .. ab .. " in " .. a)
	end
	local bbn = tonumber(bb)
	if bbn == nil then
		error("Bad version: not a number: " .. bb .. " in " .. b)
	end
	if abn > bbn then
		return 1
	elseif abn < bbn then
		return -1
	else
		return cptpack.compareversion(ar, br)
	end
end

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

function cptpack.uninstall(index, name)
	assert(cptpack.hasindex(index, name))
	print("Uninstalling", name)
	for i, file in ipairs(cptpack.listingfromindex(index, name)) do
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

function cptpack.makeindex()
	return {}
end

function cptpack.packhash(textual)
	return crypto.sha256(textual)
end

function cptpack.hasindex(index, name)
	return index[name] ~= nil
end

function cptpack.removeindex(index, name)
	index[name] = nil
end

function cptpack.listindex(index)
	return pairs(index)
end

function cptpack.addindex(index, pkg, hash, source)
	local ref = pkg.name .. "-" .. pkg.version
	if index[ref] then
		error("Ref already found in index: " .. ref)
	end
	assert(hash ~= nil)
	index[ref] = {source=source, name=pkg.name, version=pkg.version, depends=pkg.depends, conflicts=pkg.conflicts, listing=cyan.keylist(pkg.contents), hash=hash}
end

function cptpack.gethash(index, name)
	return index[name].hash
end

function cptpack.listingfromindex(index, name)
	local pkg = index[name]
	assert(pkg, "Package not found in index: " .. name)
	return pkg.listing
end

function cptpack.dependsfromindex(index, name)
	return index[name].depends
end

function cptpack.conflictsfromindex(index, name)
	return index[name].conflicts
end

function cptpack.setsources(index, sourcename)
	for k, v in pairs(index) do
		v.source = sourcename
	end
end

function cptpack.getsource(index, name)
	local pkg = index[name]
	assert(pkg, "Package not found in index: " .. name)
	return pkg.source
end

function cptpack.mergeindex(target, source)
	for k, v in pairs(source) do
		if target[k] then
			error("Cannot merge indexes: duplicate on " .. k)
		end
		target[k] = v
	end
end

function cptpack.mergesingleindex(target, source, name)
	if target[name] then
		error("Cannot merge indexes: duplicate on " .. name)
	end
	target[name] = source[name]
end

function cptpack.writeindex(target, index)
	cyan.writeserialized(target, index)
end

function cptpack.readindex(source)
	return cyan.readserialized(source)
end

function cptpack.readremoteindex(url)
	return cyan.readremoteserialized(url)
end

function cptpack.countindex(index)
	local count = 0
	for k, v in pairs(index) do
		count = count + 1
	end
	return count
end

function cptpack.dumpindex(index)
	print(table.unpack(cyan.keylist(index)))
end

return cptpack