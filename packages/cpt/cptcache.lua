local cptcache = {}

-- TODO: include versioning in cache!

local cyan = require("cyan")
local cptpack = require("cptpack")

local internet = require("internet")
local filesystem = require("filesystem")
local serialization = require("serialization")

-- General utilities

local function processconfig(iterator)
	return function()
		repeat
			realline = iterator()
			if not realline then return nil end
			line = cyan.trim(realline)
		until line and line:sub(1, 1) ~= "#" -- not empty line nor comment.
		return cyan.cut(line, " ", "Unprocessable line: " .. realline)
	end
end

-- Generic package utilities

function cptcache.displaypkg(pkg)
	print("\tName", pkg.name)
	print("\tVersion", pkg.version)
	print("\tSource", pkg.source)
	print("\tPath", pkg.path)
end

-- Remote packages and cache synchronization

local function loadrepo(discovered, lineiter, source)
	local root = ""
	for cmd, arg in processconfig(lineiter) do
		if cmd == "root" then
			root = arg
		elseif cmd == "package" then
			ref, path = cyan.cut(arg, " ", "Bad package declaration: " .. arg)
			path = root .. path
			name, version = cyan.cut(ref, "-", "Bad package name declaration: " .. ref)
			pkg = {name=name, version=version, source=source, path=path}
			prev = discovered[name]
			if prev then
				print("Duplicate package declaration.")
				print("Previous entry:")
				cptcache.displaypkg(prev)
				print("Next entry:")
				cptcache.displaypkg(pkg)
				error("Error: aborted due to package duplication.")
			else
				discovered[name] = pkg
			end
		else
			error("Bad repository declaration: " .. cmd)
		end
	end
end

local function loadrepos(path)
	local discovered = {}
	for cmd, source in processconfig(io.lines(path)) do
		if cmd == "remote" then
			print("Fetching " .. source .. "...")
			loadrepo(discovered, internet.request(source), "remote:" .. source)
		elseif cmd == "local" then
			print("Loading " .. source .. "...")
			loadrepo(discovered, io.lines(source), "local:" .. source)
		else
			error("Bad configuration command: " .. cmd)
		end
	end
	return discovered
end

local function downloadpkg(path, source, target)
	if source:sub(1, 6) == "local:" and path:sub(1, 8) == "local://" then
		cyan.writeall(target, cyan.readall(path:sub(9))) -- TODO: Copy directly?
	else
		cyan.writeall(target, cyan.readremote(path))
	end
end

function cptcache.loadcache(dir, init)
	local listing = cptpack.toroot(filesystem.concat(dir or cptcache.cachedir, "listing"))
	if filesystem.exists(listing) and init then
		error("Cannot initialize when cache already exists!")
	elseif not filesystem.exists(listing) and not init then
		error("Cache does not yet exist!")
	end
	if init then
		return {}
	else
		return cyan.readserialized(listing)
	end
end

function cptcache.flushcache(dir)
	print("Flushing repository cache...")
	local realdir = dir or cptcache.cachedir
	local cached = cptcache.loadcache(realdir, initialize)
	local todelete = cyan.keylist(cached)
	print("Saving changes...")
	cyan.writeserialized(cptpack.toroot(filesystem.concat(realdir, "listing")), {})
	print("Removing", #todelete, "packages.")
	for i, name in ipairs(todelete) do
		print("Deleting cached version of", name)
		local path = cptpack.toroot(filesystem.concat(realdir, name .. ".cpk"))
		if filesystem.exists(path) then
			cyan.removeSingleFile(path)
		else
			print("(File did not exist, anyway.)")
		end
	end
	print("Completed cache flush.")
end

cptcache.configpath = "./cpt.list"
cptcache.cachedir = "/var/cache/cpt/"
function cptcache.synchronizerepos(path, dir, initialize)
	print("Synchronizing repository cache")
	local realdir = dir or cptcache.cachedir
	print("Loading remote repositories...")
	local remotes = loadrepos(path or cptcache.configpath)
	print("Loading cache...")
	local cached = cptcache.loadcache(realdir, initialize)
	print("Calculating deltas...")
	local todownload = {}
	local todelete = {}
	for k, v in pairs(cached) do
		assert(k == v.name)
		local matching = remotes[k]
		if matching == nil then
			print("Removing", k, "from cache.")
			table.insert(todelete, k)
			cached[k] = nil
		else
			assert(v.name == matching.name)
			local needsdownload = false
			if v.version ~= matching.version then
				print("Updating version of", k, "from", v.version, "to", matching.version)
				v.version = matching.version
				needsdownload = true
			end
			if v.path ~= matching.path then
				print("Updating path of", k, "from", v.path, "to", matching.path)
				v.path = matching.path
				needsdownload = true
			end
			if v.source ~= matching.source then
				print("Updating source of", k, "from", v.source, "to", matching.source)
			end
			if not filesystem.exists(cptpack.toroot(filesystem.concat(realdir, k .. ".cpk"))) then
				needsdownload = true
			end
			if needsdownload then
				table.insert(todownload, k)
			end
		end
	end
	for k, v in pairs(remotes) do
		assert(k == v.name)
		if cached[k] == nil then
			cached[k] = v
			table.insert(todownload, k)
		end
	end
	print("Saving changes...")
	cyan.writeserialized(cptpack.toroot(filesystem.concat(realdir, "listing")), cached)
	print("Removing", #todelete, "packages and downloading", #todownload, "new or updated packages.")
	for i, name in ipairs(todelete) do
		print("Deleting cached version of", name)
		local path = cptpack.toroot(filesystem.concat(realdir, name .. ".cpk"))
		if filesystem.exists(path) then
			cyan.removeSingleFile(path)
		else
			print("(File did not exist, anyway.)")
		end
	end
	for i, name in ipairs(todownload) do
		local pkg = cached[name]
		print("Downloading", name)
		downloadpkg(pkg.path, pkg.source, cptpack.toroot(filesystem.concat(realdir, name .. ".cpk")))
	end
	print("Completed database synchronization.")
end

-- Local packages

function cptcache.getpath(name, dir)
	return cptpack.toroot(filesystem.concat(dir or cptcache.cachedir, name .. ".cpk"))
end

function cptcache.dumpcache(packages, dir)
	local cache = cptcache.loadcache(dir or cptcache.cachedir)
	if packages and #packages > 0 then
		print("Listing of selected packages:")
		for i, name in ipairs(packages) do
			local pkg = cache[name]
			if pkg then
				cptcache.displaypkg(pkg)
			else
				error("No such package: " .. name)
			end
		end
	else
		print("Cache listing:")
		for k, v in pairs(cache) do
			assert(k == v.name)
			cptcache.displaypkg(v)
		end
		print("End of listing")
	end
end

return cptcache