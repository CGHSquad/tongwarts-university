--[[
	typecheck — runs Luau's type checker over src/, the way Roblox Studio would see it.

	Run from the repo root, after `rokit install`:
		lune run tools/typecheck

	It uses luau-lsp (pinned in rokit.toml) rather than plain luau-analyze because luau-lsp knows
	Roblox's API (game, Instance, Part, ...) and follows require()s through a Rojo sourcemap. The
	first run downloads the Roblox type definitions that match the pinned luau-lsp version into
	tools/.cache/ (gitignored). Exits 1 if there are any type errors.

	Only src/ is checked: tests/ and tools/ are Lune scripts, which would need Lune's own types.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local CACHE = "tools/.cache"
local SOURCEMAP = "sourcemap.json" -- gitignored; editors running luau-lsp use it too

local function quit(message: string)
	print(message)
	process.exit(1)
end

-- Runs a tool, or quits with a hint if it isn't installed or fails to start.
local function run(program: string, args: { string })
	local ok, result = pcall(process.exec, program, args)
	if not ok then
		quit(`Couldn't run {program}. Is it installed? Run \`rokit install\` in the repo root.`)
	end
	return result
end

if not fs.isFile("default.project.json") then
	quit("Run this from the repo root: lune run tools/typecheck")
end

-- The definitions have to match the luau-lsp version, so they're cached per version.
local version = string.match(run("luau-lsp", { "--version" }).stdout, "[%d%.]+")
if version == nil then
	quit("Couldn't tell which luau-lsp version is installed.")
end
local definitions = `{CACHE}/roblox-{version}.d.luau`
if not fs.isFile(definitions) then
	print(`Downloading the Roblox type definitions for luau-lsp {version}...`)
	local response = net.request(
		`https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/{version}/scripts/globalTypes.d.luau`
	)
	if not response.ok then
		quit(`Couldn't download them: HTTP {response.statusCode} {response.statusMessage}`)
	end
	if not fs.isDir(CACHE) then
		fs.writeDir(CACHE)
	end
	fs.writeFile(definitions, response.body)
end

local sourcemap = run("rojo", { "sourcemap", "default.project.json", "--output", SOURCEMAP })
if not sourcemap.ok then
	print(sourcemap.stderr)
	quit("Couldn't build the Rojo sourcemap.")
end

local analyze = run("luau-lsp", {
	"analyze",
	`--definitions={definitions}`,
	`--sourcemap={SOURCEMAP}`,
	"src",
})
-- luau-lsp logs progress as [INFO]/[WARN] lines; only the diagnostics are worth showing.
local problems = {}
for _, output in { analyze.stdout, analyze.stderr } do
	for line in string.gmatch(output, "[^\r\n]+") do
		if not string.match(line, "^%[INFO%]") and not string.match(line, "^%[WARN%]") then
			table.insert(problems, line)
		end
	end
end
if #problems > 0 then
	print(table.concat(problems, "\n"))
end
if analyze.ok then
	print("No type errors in src/.")
else
	quit(`Type errors in src/ (see above).`)
end
