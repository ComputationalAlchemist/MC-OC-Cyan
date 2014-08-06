local cptcache = {}

-- TODO: include versioning in cache!

local cyan = require("cyan")
local cptpack = require("cptpack")
local filesystem = require("filesystem")
local serialization = require("serialization")

-- Remote packages and cache synchronization

function cptcache.remoteindexpath()
	return cptpack.toroot(filesystem.concat(cptcache.cachedir, "remoteindex"))
end

function cptcache.localindexpath()
	return cptpack.toroot(filesystem.concat(cptcache.cachedir, "localindex"))
end

local function mergeremote(index, source)
	local rindex
	if source:sub(1, 8) == "local://" then
		rindex = cptpack.readindex(source:sub(9))
	else
		rindex = cptpack.readremoteindex(source)
	end
	cptpack.setsources(rindex, source)
	cptpack.mergeindex(index, rindex)
end

cptcache.configpath = "/etc/cpt.list"
cptcache.cachedir = "/var/cache/cpt/"
function cptcache.synchronizerepos(unrootconfig)
	print("Synchronizing repository cache...")
	print("Building remote index...")
	local rindex = cptpack.makeindex()
	print("Loading remote repositories...")
	local path = cptpack.toroot(cptcache.configpath)
	if unrootconfig then
		path = cptcache.configpath
	end
	for _, v in ipairs(cyan.readserialized(path)) do
		mergeremote(rindex, v)
	end
	print("Saving remote index...")
	cyan.makeParentDirectory(cptcache.remoteindexpath())
	cptpack.writeindex(cptcache.remoteindexpath(), rindex)
	print("Completed index synchronization.")
end

function cptcache.loadlocalindex()
	return cptpack.readindex(cptcache.localindexpath())
end

function cptcache.loadremoteindex()
	return cptpack.readindex(cptcache.remoteindexpath())
end

local function downloadpkg(name, source, target)
	local data
	if source:sub(1, 8) == "local://" then
		print("Fetching", name, "locally...")
		data = cyan.readall(filesystem.concat(filesystem.path(source:sub(9)), name .. ".cpk"))
	elseif source:sub(1, 8) == "https://" then
		print("Fetching", name, "remotely...")
		data = cyan.readremote("https://" .. filesystem.concat(filesystem.path(source:sub(9)), name .. ".cpk"))
	elseif source:sub(1, 7) == "http://" then
		print("Fetching", name, "remotely...")
		data = cyan.readremote("http://" .. filesystem.concat(filesystem.path(source:sub(8)), name .. ".cpk"))
	else
		error("Unknown source: " .. source)
	end
	local hash = cptpack.packhash(data)
	cyan.writeall(target, data)
	return hash
end

-- Local packages

function cptcache.verifyindex(index)
	local toremove = {}
	for name in cptpack.listindex(index) do
		if not filesystem.exists(cptcache.getpath(name)) then
			print("WARNING: Cannot find indexed package in cache: " .. name)
			table.insert(toremove, name)
		end
	end
	for _, v in ipairs(toremove) do
		cptpack.removeindex(index, v)
	end
	if #toremove ~= 0 then
		print("Removed", #toremove, "missing packages from local index.")
	end
end

function cptcache.getpackages(names)
	print("Getting", #names, "packages...")
	print("Loading and verifying index...")
	local lindex = cptcache.loadlocalindex()
	local rindex = cptcache.loadremoteindex()
	cptcache.verifyindex(lindex)
	print("Calculating deltas...")
	local needed = {}
	for _, v in ipairs(names) do
		if not cptpack.hasindex(lindex, v) then
			table.insert(needed, v)
		end
	end
	if #needed == 0 then
		print("No packages need fetching.")
	else
		print("Fetching", #needed, "packages and modifying local index...")
		for _, name in ipairs(needed) do
			local hash = downloadpkg(name, cptpack.getsource(rindex, name), cptcache.getpath(name))
			if hash ~= cptpack.gethash(rindex, name) then
				error("Bad hash on package: " .. name .. ": got " .. hash .. " instead of " .. cptpack.gethash(rindex, name))
			end
			cptpack.mergesingleindex(lindex, rindex, name)
		end
	end
	print("Writing out local index...")
	cyan.makeParentDirectory(cptcache.localindexpath())
	cptpack.writeindex(cptcache.localindexpath(), lindex)
	print("Completed get of", #names, "packages.")
end

function cptcache.getpath(name)
	return cptpack.toroot(filesystem.concat(cptcache.cachedir, name .. ".cpk"))
end

function cptcache.dumpcache()
	print("Remote index:")
	cptpack.dumpindex(cptcache.loadremoteindex())
	print("Local index:")
	cptpack.dumpindex(cptcache.loadlocalindex())
end

function cptcache.initcache()
	print("Building empty local index...")
	if filesystem.exists(cptcache.localindexpath()) then
		error("Error: not overwriting existing local index.")
	end
	cyan.makeParentDirectory(cptcache.localindexpath())
	cptpack.writeindex(cptcache.localindexpath(), cptpack.makeindex())
	print("Built empty local index!")
end

function cptcache.flushcache()
	error("Cache flushing not currently implemented.") -- Remember that cptinstall.lua requires that the local cache contains all of the currently-installed packages.
	--[[print("Flushing repository cache...")
	local count = 0
	for name in filesystem.list(cptcache.cachedir) do
		if name:sub(#name - 3) == ".cpk" then
			count = count + 1
			cyan.removesinglefile(name)
		end
	end
	print("Removed", count, "packages from cache.")
	local cptcache.cachedir = dir or cptcache.cachedir
	local cached = cptcache.loadcache(cptcache.cachedir, initialize)
	local todelete = cyan.keylist(cached)
	print("Saving changes...")
	cyan.writeserialized(cptpack.toroot(filesystem.concat(cptcache.cachedir, "listing")), {})
	print("Removing", #todelete, "packages.")
	for i, name in ipairs(todelete) do
		print("Deleting cached version of", name)
		local path = cptpack.toroot(filesystem.concat(cptcache.cachedir, name .. ".cpk"))
		if filesystem.exists(path) then
			cyan.removeSingleFile(path)
		else
			print("(File did not exist, anyway.)")
		end
	end
	print("Completed cache flush.")]]
end

return cptcache