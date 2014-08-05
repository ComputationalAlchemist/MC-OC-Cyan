local cptlock = {}

local locktaken = false

function cptlock.lock() -- TODO: more robust locking?
	if locktaken then
		error("CPT caches already locked!")
	end
	locktaken = true
end

function cptlock.unlock()
	if not locktaken then
		error("CPT caches not locked!")
	end
	locktaken = false
end

return cptlock