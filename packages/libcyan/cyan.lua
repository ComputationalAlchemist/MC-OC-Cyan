local cyan = {}

local serialization = require("serialization")
local filesystem = require("filesystem")

-- Internet utilities

function cyan.readremote(source)
	local text = ""
	for line in internet.request(source) do
		if #line == 0 then
			-- do nothing
		elseif #line >= 2 and line:sub(#line-1) == "\r\n" then
			text = text .. line:sub(1, #line - 2) .. "\n"
		elseif line:sub(#line) == "\n" then
			text = text .. line
		else
			text = text .. line .. "\n"
		end
	end
	return text
end

-- IO utilities

function cyan.readall(source)
	local f, err = io.open(source)
	if not f then
		error("Cannot read " .. source .. ": " .. err)
	end
	local out = f:read("*a")
	assert(out)
	f:close()
	return out
end

function cyan.readserialized(source)
	return serialization.unserialize(cyan.readall(source))
end

function cyan.writeall(target, data)
	local f, err = io.open(target, "w")
	if not f then
		error("Cannot write " .. target .. ": " .. err)
	end
	local out, err = f:write(data)
	if not out then
		error("Cannot write " .. target .. ": " .. err)
	end
	f:close()
end

function cyan.writeserialized(target, data)
	cyan.writeall(target, serialization.serialize(data))
end

function cyan.isDirectoryEmpty(dir)
	local listing, err = filesystem.list(dir)
	if not listing then
		error("Cannot list directory" .. dir .. ": " .. err)
	end
	local empty = true
	for entry in listing do
		empty = false
	end
	return empty
end

function cyan.removeSingleFile(file)
	if filesystem.isDirectory(file) then
		error("Cannot remove file " .. file .. ": Not supposed to be a directory!")
	end
	if not filesystem.exists(file) then
		error("Cannot remove file " .. file .. ": Does not exist!")
	end
	local out, err = filesystem.remove(file) -- TODO: Check error returning from this.
	if not out then
		error("Cannot remove file " .. file .. ": " .. err)
	end
end

function cyan.makeParentDirectory(file)
	local parent = filesystem.path(file)
	if not filesystem.exists(parent) then
		local out, err = filesystem.makeDirectory(parent)
		if not out then
			error("Cannot make parent directory " .. parent .. ": " .. err)
		end
	elseif not filesystem.isDirectory(parent) then
		error("Parent directory is not a directory: " .. parent)
	end
end

-- Table utilities

function cyan.keylist(map)
	local out = {}
	for k, _ in pairs(map) do
		table.insert(out, k)
	end
	return out
end

function cyan.valueset(list)
	local out = {}
	for _, v in ipairs(list) do
		out[v] = true
	end
	return out
end

function cyan.instance(class, object)
	return setmetatable(object or {}, {__index=class})
end

function cyan.writeinstance(target, self)
	local meta = getmetatable(self)
	setmetatable(self, {})
	cyan.writeserialized(target, self)
	setmetatable(self, meta)
end

-- String utilities

function cyan.cut(str, pattern, errmsg)
	at = str:find(pattern)
	if not at then
		if errmsg then
			error(errmsg)
		end
		return str, nil
	end
	return str:sub(1, at - 1), str:sub(at + 1)
end

function cyan.ltrim(str)
	if not str then return end
	index = str:find("[^ \t\r\n]")
	if not index then return end
	return str:sub(index)
end

function cyan.rtrim(str)
	if not str then return end
	return str:match("^(.*[^ \t\r\n])[ \t\r\n]*$")
end

function cyan.trim(str)
	return cyan.rtrim(cyan.ltrim(str))
end

return cyan
