--[[--------------------------------------------------------------------------
    luahttpd: Lua-powered httpd server project
    Copyright (C) 2013  AfterLifeLochie <afterlifelochie@afterlifelochie.net>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
--------------------------------------------------------------------------]]--

-- PHP-like split() function, probably has issues with non-sanitized
-- patterns.
split=function(sString, sSeparator, nMax, bRegexp)
	assert(sSeparator ~= '')
	assert(nMax == nil or nMax >= 1)
	if (sString == nil) then error("String expected!", 2) end

	local aRecord = {}

	if sString:len() > 0 then
		local bPlain = not bRegexp
		nMax = nMax or -1

		local nField = 1 nStart = 1
		local nFirst, nLast = string.find(sString, sSeparator, nStart, bPlain)
		while nFirst and nMax ~= 0 do
			aRecord[nField] = string.sub(sString, nStart, nFirst-1)
			nField = nField + 1
			nStart = nLast + 1
			nFirst,nLast = string.find(sString, sSeparator, nStart, bPlain)
			nMax = nMax - 1
		end
		aRecord[nField] = string.sub(sString, nStart)
	end

	return aRecord
end

splitstr = function(str, pat)
   local t = {}  -- NOTE: use {n = 0} in Lua-5.0
   local fpat = "(.-)" .. pat
   local last_end = 1
   local s, e, cap = str:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= "" then
	 table.insert(t,cap)
      end
      last_end = e+1
      s, e, cap = str:find(fpat, last_end)
   end
   if last_end <= #str then
      cap = str:sub(last_end)
      table.insert(t, cap)
   end
   return t
end

-- Gets the dir a file is in
getDir=function(path)
	local splitPath=splitstr(path:gsub("\\","/"),"/")
    splitPath[#splitPath]=nil
    return table.concat(splitPath,"/")
end
-- Gets a module file
getModule=function(name) 
	local modpath = "module/" .. name .. ".mod.lua"
	local fhandle, ex = io.open(modpath, "r")
	if not fhandle then error(ex) end
	local fdata = fhandle:read("*a")
	fhandle:close()
	
	local fx, ex = loadstring(fdata, "module-" .. name)
	if not fx then error(ex) end
	
	setfenv(fx, _G)
	local result = fx()
	if (type(result) == "table") then
		for k, v in pairs(result) do
			if (type(v) == "function") then setfenv(v, _G) end
		end
	else
		error("Unexpected module data; expected table, got " .. (type(result) or 'nil'))
	end
	return result
end

-- Parses a path
parsePath=function(path)
	local fragments = split(path:gsub("\\","/"), "/")
	local parsed = {}
	local parsedIndex = 1
	for i, name in ipairs(fragments) do
		if name == "" or name == "." then
		elseif name == ".." then
			if parsedIndex == 1 then
				error("Underflow: no previous directory")
			else
				parsedIndex = parsedIndex - 1
				parsed[parsedIndex] = nil
			end
		else
			parsed[parsedIndex] = name
			parsedIndex = parsedIndex + 1
		end
	end
	return parsed
end

-- Copy a table
table.copy = function(t)
	local result = {}
	for k, v in pairs(t) do
		if (type(v) == "table") then
			if (k ~= "_G") and (k ~= "_M") and (k ~= "package") then result[k] = table.copy(v) end
		else result[k] = v end
	end
	return result
end

-- Pad a string
string.pad = function(str, len, padWith, padEnd)
	if (#str == len) then return str end
	if (#str > len) then return str end
	while (#str < len) do if (padEnd) then str = str .. padWith else str = padWith .. str end end
	return str
end

-- HTTP URL utilities
url = {}
url.decode = function(str)
	-- Encoded URL: `+` => ` `, `%xx` => char(xx), `\r\n` => `\n`
	str = string.gsub(str, "+", " ")
	str = string.gsub(str, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
	str = string.gsub(str, "\r\n", "\n")
	return str
end

url.encode = function(str)
	-- Decoded URL: ` ` => `+`, char(xx) => `%xx`, `\n` (not `\r\n) => `\r\n`
	str = string.gsub(str, "\n", "\r\n")
	str = string.gsub(str, "([^0-9a-zA-Z ])", 
			function(c) return string.format ("%%%02X", string.byte(c)) end)
	str = string.gsub(str, " ", "+")
	return str
end

url.insertfield = function(args, name, value)
	if not args[name] then
		args[name] = value
	else
		local t = type(args[name])
		if t == "string" then
			args[name] = { args[name], value, }
		elseif t == "table" then
			table.insert (args[name], value)
		end
	end
end

-- Parses an encoded blob
url.parse = function(query, args)
	if type(query) == "string" then
		local insertfield, decode = url.insertfield, url.decode
		string.gsub(query, "([^&=]+)=([^&=]*)&?", function(key, val)
			url.insertfield(args, decode(key), decode(val))
		end)
	end
end

-- Encodes a table
url.encodetable = function(args)
	if args == nil or next(args) == nil then return "" end
	local strp = ""
	for key, vals in pairs(args) do
		if type(vals) ~= "table" then vals = { vals } end
		for i, val in ipairs(vals) do strp = strp .. "&" .. url.encode(key) .. "=" .. url.encode(val) end
	end
	return string.sub(strp, 2)
end

-- Pattern utilities
patterns = {}
-- Sanitizes a string so it won't be treated as a pattern
-- in things like string.gsub
patterns.sanitize = function(args)
	if args == nil or type(args) ~= "string" then return "" end
	local result = args
	result = string.gsub(result, "%%", "%%")
	for _, i in pairs({ "(", ")", ".", "+", "-", "*", "?", "[", "^", "$" }) do
		result = string.gsub(result, "%" .. i, "%%" .. i)
	end
	return result
end
