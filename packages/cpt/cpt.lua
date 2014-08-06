local args = {...}

if #args == 0 or args[1] == "help" then
	if #args > 1 then
		error("Too many parameters to help.")
	end
	print("Usage: cpt (install|remove|update) PACKAGES...")
	print("Usage: cpt (sync|flush|upgrade|init|init-installation|dump|force-lock|force-unlock|attempt-resume)")
	print("Usage: cpt build DIR FILEOUT")
	print("Usage: cpt no-preresolve (line from above)")
	print("Usage: cpt reroot ROOT (line from above)")
	return
end

local cptlock = require("cptlock")
local cptpack = require("cptpack")

local cmd = table.remove(args, 1)

local root = "/"

local preresolve = true

if cmd == "reroot" then
	rootmod = table.remove(args, 1)
	cmd = table.remove(args, 1)
	if not cmd then
		print("Path and command expected after reroot.")
		return
	end
end
if cmd == "no-preresolve" then
	cmd = table.remove(args, 1)
	if not cmd then
		print("Path and command expected after no-preresolve.")
		return
	end
	preresolve = false
end

if cmd == "force-lock" then
	if #args > 0 then
		error("Too many parameters to force-lock.")
	end
	cptlock.lock()
elseif cmd == "force-unlock" then
	if #args > 0 then
		error("Too many parameters to force-unlock.")
	end
	cptlock.unlock()
elseif cmd == "build" then
	if #args ~= 2 then
		error("Wrong number of parameters to build.")
	end
	require("cptpack").buildpkg(args[1], args[2])
else
	function main()
		if cmd == "sync" then
			if #args > 0 then
				error("Too many parameters to sync.")
			end
			require("cptcache").synchronizerepos()
		elseif cmd == "strap" then
			local cptcache = require("cptcache")
			cptcache.initcache()
			cptcache.synchronizerepos(true)
			local context = require("cptinstall").strap()
			context:resolve()
			for i, packname in ipairs(args) do
				context:add(packname)
			end
			context:getpackages()
			context:save(true)
			context:apply()
			context:save()
		elseif cmd == "init" then
			if #args > 0 then
				error("Too many parameters to init.")
			end
			require("cptcache").initcache()
		elseif cmd == "init-installation" then
			if #args > 0 then
				error("Too many parameters to init-installation.")
			end
			local context = require("cptinstall").strap()
			if preresolve then
				context:resolve()
			end
			context:getpackages()
			context:save(true)
			context:apply()
			context:save()
		elseif cmd == "flush" then
			if #args > 0 then
				error("Too many parameters to flush.")
			end
			require("cptcache").flushcache()
		elseif cmd == "upgrade" then
			if #args > 0 then
				error("Too many parameters to upgrade.")
			end
			local cptinstall = require("cptinstall")
			local context = cptinstall.begin()
			if preresolve then
				context:resolve()
			end
			context:upgrade()
			context:resolve()
			context:getpackages()
			context:save(true)
			context:apply()
			context:save()
		elseif cmd == "dump" then
			if #args > 0 then
				error("Too many parameters to dump.")
			end
			require("cptcache").dumpcache()
			local context = require("cptinstall").begin()
			context:resolve()
			context:dump()
		elseif cmd == "install" then
			if #args <= 0 then
				error("Too few parameters to install.")
			end
			local cptinstall = require("cptinstall")
			local context = cptinstall.begin()
			if preresolve then
				context:resolve()
			end
			for i, packname in ipairs(args) do
				context:add(packname)
			end
			context:resolve()
			context:getpackages()
			context:save(true)
			context:apply()
			context:save()
		elseif cmd == "resume" then
			if #args > 0 then
				error("Too many parameters to resume.")
			end
			local cptinstall = require("cptinstall")
			local context = cptinstall.resume()
			context:resolve()
			context:getpackages()
			context:apply()
			context:save()
		elseif cmd == "remove" then
			if #args <= 0 then
				error("Too few parameters to remove.")
			end
			local cptinstall = require("cptinstall")
			local context = cptinstall.begin()
			if preresolve then
				context:resolve()
			end
			for i, packname in ipairs(args) do
				context:remove(packname)
			end
			context:resolve()
			context:getpackages()
			context:save(true)
			context:apply()
			context:save()
		elseif cmd == "update" then
			if #args <= 0 then
				error("Too few parameters to update.")
			end
			local cptinstall = require("cptinstall")
			local context = cptinstall.begin()
			if preresolve then
				context:resolve()
			end
			for i, packname in ipairs(args) do
				context:remove(packname)
				context:add(packname)
			end
			context:resolve()
			context:getpackages()
			context:save(true)
			context:apply()
			context:save()
		else
			error("Unsupported command: " .. cmd)
		end
	end

	cptlock.lock()
	local opr = cptpack.root
	if rootmod then
		cptpack.root = rootmod
	end
	local success, err = pcall(main)
	if rootmod then
		cptpack.root = opr
	end
	cptlock.unlock()
	
	if not success then error(err) end
end