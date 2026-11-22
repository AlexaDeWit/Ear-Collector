-- Secret values and tables, as the client hands them to addons.
--
-- A secret value may be displayed but not inspected: here it errors on
-- comparison, concatenation, indexing and tostring, so a spec fails loudly if
-- the addon touches one. (Lua 5.1 only calls __eq between two tables, so
-- `secret == "x"` silently returns false; Context.Readable must still be
-- checked first.) A secret table can't be indexed; Lua 5.1 ignores __len on
-- tables, so #t is 0 and stubs that report a count check for it explicitly.
local Secrets = {}

local function forbid(op)
	return function()
		error("addon code tried to " .. op .. " a secret value", 2)
	end
end

local valueMeta = {
	__index = forbid("index"),
	__newindex = forbid("write to"),
	__concat = forbid("concatenate"),
	__lt = forbid("compare"),
	__le = forbid("compare"),
	__eq = forbid("compare"),
	__len = forbid("take the length of"),
	__call = forbid("call"),
	__tostring = forbid("convert to string"),
}

local tableMeta = {
	__index = function()
		error("addon code tried to index a secret table", 2)
	end,
	__newindex = function()
		error("addon code tried to write to a secret table", 2)
	end,
}

function Secrets.value()
	return setmetatable({}, valueMeta)
end

function Secrets.table()
	return setmetatable({}, tableMeta)
end

function Secrets.isValue(v)
	return type(v) == "table" and getmetatable(v) == valueMeta
end

function Secrets.isTable(v)
	return type(v) == "table" and getmetatable(v) == tableMeta
end

return Secrets
