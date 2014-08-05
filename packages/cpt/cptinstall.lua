local filesystem = require("filesystem")
local cyan = require("cyan")
local cptcache = require("cptcache")
local cptpack = require("cptpack")

local cptinstall = {}
local context = {}

cptinstall.datadir = "/var/lib/cpt/"

function cptinstall.loadstatus()
	return cyan.readserialized(cptpack.toroot(filesystem.concat(cptinstall.datadir, "index")))
end

function cptinstall.resume()
	return cptinstall.begin(nil, true)
end

function cptinstall.strap()
	return cptinstall.begin({installed={}, index={}})
end

function cptinstall.begin(base, resume)
	local out = cyan.instance(context, base or cptinstall.loadstatus())
	out.resolved = false
	if resume then
		if not out.intermediate then
			error("Installation set is not in an intermediate state! Cannot continue transaction.")
		end
	else
		if out.intermediate then
			error("Installation set is in an intermediate state! Cannot begin transaction.")
		end
		out.deltaadd = {}
		out.deltadel = {}
	end
	return out
end

function context:save(intermediate)
	assert(self.resolved)
	if not filesystem.isDirectory(cptpack.toroot(cptinstall.datadir)) then
		local success, err = filesystem.makeDirectory(cptpack.toroot(cptinstall.datadir))
		if not success then
			error("Cannot create directory " .. cptpack.toroot(cptinstall.datadir) .. ": " .. err)
		end
	end
	self.intermediate = intermediate
	cyan.writeinstance(cptpack.toroot(filesystem.concat(cptinstall.datadir, "index")), self)
end

function context:apply()
	assert(self.resolved)
	print("About to apply", #self.deltadel, "deletions and", #self.deltaadd, "additions.")
	for i, name in ipairs(self.deltadel) do
		cptpack.uninstall(name, self.index[name])
	end
	for i, name in ipairs(self.deltaadd) do
		local rname, rver = cyan.cut(name, "-", "Bad name&version: " .. name)
		cptpack.install(name, cptcache.getpath(rname))
	end
	print("Applied", #self.deltadel + #self.deltaadd, "changes.")
end

function context:resolve()
	if self.resolved then return end
	local includedfull = cyan.valueset(self.installed)
	local included = {}
	for i, namever in ipairs(self.installed) do
		local name, version = cyan.cut(namever, "-", "Bad name&version string: " .. namever)
		if included[name] then
			error("Multiple versions of " .. name .. " are selected: " .. version .. " and " .. included[name])
		end
		included[name] = version
	end
	for i, name in ipairs(self.installed) do
		local data = self.index[name]
		for i, needed in ipairs(data.depends) do
			if not included[needed] and not includedfull[needed] then
				error("Dependency failed: " .. name .. " requires " .. needed .. " but it is not selected.")
			end
		end
		for i, conflicted in ipairs(data.conflicts) do
			if included[needed] or includedfull[needed] then
				error("Conflict detected: " .. name .. " conflicts with " .. needed .. " and both are selected.")
			end
		end
	end
	self.resolved = true
end

function context:update(dir)
	local cache = cptcache.loadcache()
	self.resolved = false
	for k, v in pairs(cache) do
		assert(k == v.name)
		local index = cptpack.loadindex(cptcache.getpath(k))
		assert(k == index.name)
		assert(index.version == v.version)
		self.index[index.name .. "-" .. index.version] = index
	end
end

function context:add(namever)
	local name, ver = cyan.cut(namever, "-")
	if not ver then
		for k, v in pairs(self.index) do
			local fname, fver = cyan.cut(k, "-", "Bad name&version: " .. k)
			if fname == name and ((not ver) or tonumber(ver) < tonumber(fver)) then
				ver = fver
			end
		end
		if not ver then
			error("Cannot find any package for: " .. name)
		end
		namever = name .. "-" .. ver
	end
	for i, found in ipairs(self.installed) do
		if found == namever then
			error("Already selected: " .. namever)
		end
	end
	if not self.index[namever] then
		error("Package not in index: " .. namever)
	end
	self.resolved = false
	table.insert(self.installed, namever)
	table.insert(self.deltaadd, namever)
end

function context:remove(name)
	for i, namever in ipairs(self.installed) do
		local lname, lver = cyan.cut(namever, "-")
		if name == lname or name == namever then
			self.resolved = false
			table.remove(self.installed, i)
			table.insert(self.deltadel, namever)
			return
		end
	end
	error("Package not installed: " .. name)
end

function context:dump()
	print("Packages installed:", #self.installed)
	for i, name in ipairs(self.installed) do
		print(name)
		local index = self.index[name]
		assert(name == index.name .. "-" .. index.version)
		print("\tContains", #index.listing, "files.")
		print("\tDepends on", #index.depends, "packages:")
		for i, v in ipairs(index.depends) do
			print("\t", v)
		end
		print("\tConflicts with", #index.conflicts, "packages:")
		for i, v in ipairs(index.conflicts) do
			print("\t", v)
		end
	end
	print("Packages in index:", #self.index)
	print("Deltas:", #self.deltadel + #self.deltaadd)
	for i, v in ipairs(self.deltadel) do
		print("Remove package", v)
	end
	for i, v in ipairs(self.deltaadd) do
		print("Add package", v)
	end
end

return cptinstall
