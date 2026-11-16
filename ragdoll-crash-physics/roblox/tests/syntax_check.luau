-- lune run tests/syntax_check.luau : compiles every source file with the Luau compiler.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local failed, count = 0, 0
local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.match(name, "%.luau$") then
			count += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failed += 1
				print("SYNTAX ERROR", path, err)
			end
		end
	end
end
walk("src")
print(string.format("%d files compiled, %d failed", count, failed))
process.exit(if failed > 0 then 1 else 0)
