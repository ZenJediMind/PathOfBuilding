describe("ConfigScope source-owned enemy semantics", function()
	local ConfigScope = require("Modules.ConfigScope")
	local configOptions = LoadModule("Modules/ConfigOptions")

	local function reindex()
		ConfigScope.index(configOptions)
	end

	it("does not treat ByYou names as source-owned without explicit metadata", function()
		assert.is_true(ConfigScope.isSourceOwnedEnemyVar("FrozenByYou"))
		assert.is_false(ConfigScope.isSourceOwnedEnemyVar("InventedByYou"))
		assert.is_false(ConfigScope.isSourceOwnedEnemyMod({ name = "Condition:InventedByYou" }))
		assert.is_true(ConfigScope.isSourceOwnedEnemyMod({ name = "Condition:FrozenByYou" }))
		assert.is_false(ConfigScope.isSourceOwnedEnemyMod({ name = "Condition:Chilled" }))
		assert.is_true(ConfigScope.isSourceOwnedEnemyMod({ name = "Condition:Chilled", sourceOwned = true }))
	end)

	it("requires explicit enemyState for ByYou option names", function()
		local ok, err = pcall(ConfigScope.index, {
			{ section = "Skill Options", scope = "actor" },
			{ var = "conditionEnemyInventedByYou", type = "check", ifEnemyCond = "InventedByYou" },
		})
		reindex()
		assert.is_false(ok)
		assert.matches("needs explicit enemyState", tostring(err))
	end)

	it("stamps sourceOwned on FrozenByYou tags from parse, including ModCache hits", function()
		local mods = modLib.parseMod("Enemies permanently take 5% increased Damage for each second they've ever been Frozen by you, up to a maximum of 50%")
		assert.is_table(mods)
		local inner = mods[1] and mods[1].value and mods[1].value.mod
		assert.is_table(inner)
		local seen = { FrozenByYou = false, FrozenByYouSeconds = false }
		for _, tag in ipairs(inner) do
			if tag.var == "FrozenByYou" then
				assert.is_true(tag.sourceOwned)
				seen.FrozenByYou = true
			elseif tag.var == "FrozenByYouSeconds" then
				assert.is_true(tag.sourceOwned)
				seen.FrozenByYouSeconds = true
			end
		end
		assert.is_true(seen.FrozenByYou)
		assert.is_true(seen.FrozenByYouSeconds)
	end)
end)
