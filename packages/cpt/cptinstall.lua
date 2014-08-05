local filesystem = require("filesystem")
local cyan = require("cyan")
local cptcache = require("cptcache")
local cptpack = require("cptpack")

local cptinstall = {}
local context = {}

cptinstall.datadir = "/var/lib/cpt/"

function cptinstall.loadstatus()
	return cyan.readserialized(cptpack.toroot(filesystem.concat(cptinstall.datadir, "status")))
end

function cptinstall.resume()
	return cptinstall.begin(nil, true)
end

function cptinstall.strap()
	return cptinstall.begin({installed={}})
end

function cptinstall.begin(base, resume)
	local out = cyan.instance(context, base or cptinstall.loadstatus())
	out.resolved = false
	out.haspackages = false
	out.localindex = cptcache.loadlocalindex()
	out.remoteindex = cptcache.loadremoteindex()
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
	local lindex = self.localindex
	local rindex = self.remoteindex
	self.localindex = nil
	self.remoteindex = nil
	cyan.writeinstance(cptpack.toroot(filesystem.concat(cptinstall.datadir, "status")), self)
	self.localindex = lindex
	self.remoteindex = rindex
end

function context:getpackages()
	if #self.deltaadd ~= 0 then
		cptcache.getpackages(self.deltaadd)
	end
	self.haspackages = true
end

function context:apply()
	assert(self.resolved and self.haspackages)
	print("About to apply", #self.deltadel, "deletions and", #self.deltaadd, "additions.")
	for i, name in ipairs(self.deltadel) do
		cptpack.uninstall(self.localindex, name)
	end
	for i, name in ipairs(self.deltaadd) do
		cptpack.install(name, cptcache.getpath(name))
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
		local depends, conflicts
		if cptpack.hasindex(self.localindex, name) then
			depends = cptpack.dependsfromindex(self.localindex, name)
			conflicts = cptpack.conflictsfromindex(self.localindex, name)
		elseif cptpack.hasindex(self.remoteindex, name) then
			depends = cptpack.dependsfromindex(self.remoteindex, name)
			conflicts = cptpack.conflictsfromindex(self.remoteindex, name)
		else
			error("Cannot find package " .. name .. " in any index!")
		end
		for i, needed in ipairs(depends) do
			if not included[needed] and not includedfull[needed] then
				error("Dependency failed: " .. name .. " requires " .. needed .. " but it is not selected.")
			end
		end
		for i, conflicted in ipairs(conflicts) do
			if included[needed] or includedfull[needed] then
				error("Conflict detected: " .. name .. " conflicts with " .. needed .. " and both are selected.")
			end
		end
	end
	self.resolved = true
end

function context:upgrade()
	assert(self.resolved)
	local toremove = {}
	for i, namever in ipairs(self.installed) do
		local name, ver = cyan.cut(namever, "-", "Bad name&version string: " .. namever)
		local over = ver
		for k, v in cptpack.listindex(self.remoteindex) do
			local fname, fver = cyan.cut(k, "-", "Bad name&version: " .. k)
			if fname == name and ((not ver) or cptpack.compareversion(fver, ver) > 0) then
				ver = fver
			end
		end
		for k, v in cptpack.listindex(self.localindex) do
			local fname, fver = cyan.cut(k, "-", "Bad name&version: " .. k)
			if fname == name and ((not ver) or cptpack.compareversion(fver, ver) > 0) then
				ver = fver
			end
		end
		namever = name .. "-" .. ver
		if over ~= ver then
			self.resolved = false
			self.haspackages = false
			table.insert(toremove, i)
			table.insert(self.deltaadd, namever)
			table.insert(self.installed, namever)
			print("Found upgrade for " .. name .. " from " .. over .. " to " .. ver)
		end
	end
	for _, i in ipairs(toremove) do
		table.insert(self.deltadel, self.installed[i])
		table.remove(self.installed, i)
	end
	print("Found", #toremove, "upgrades.")
end

function context:add(namever)
	local name, ver = cyan.cut(namever, "-")
	if not ver then
		for k, v in cptpack.listindex(self.remoteindex) do
			local fname, fver = cyan.cut(k, "-", "Bad name&version: " .. k)
			if fname == name and ((not ver) or cptpack.compareversion(fver, ver) > 0) then
				ver = fver
			end
		end
		for k, v in cptpack.listindex(self.localindex) do
			local fname, fver = cyan.cut(k, "-", "Bad name&version: " .. k)
			if fname == name and ((not ver) or cptpack.compareversion(fver, ver) > 0) then
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
	if not cptpack.hasindex(self.remoteindex, namever) and not cptpack.hasindex(self.localindex, namever) then
		error("Package not in index: " .. namever)
	end
	self.resolved = false
	self.haspackages = false
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
	print(table.unpack(self.installed))
	print("Packages in index:", cptpack.countindex(self.localindex))
	cptpack.dumpindex(self.localindex) -- TODO: Some way to dump complete info about a package.
	print("Deltas:", #self.deltadel + #self.deltaadd)
	for i, v in ipairs(self.deltadel) do
		print("Remove package", v)
	end
	for i, v in ipairs(self.deltaadd) do
		print("Add package", v)
	end
end

return cptinstall
