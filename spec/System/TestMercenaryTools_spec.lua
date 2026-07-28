describe("Mercenary tools", function()
	local tools = require("Modules/MercenaryTools")
	local data = {
		classes = {
			class = { name = "Test", skillIds = { "skill" } },
			ambiguous = { name = "Ambiguous", skillIds = { "skill", "other_skill" } },
		},
		builds = { build = {
			skillIds = { "skill", "other_skill" },
			skillPools = { { skillIds = { "skill", "other_skill" }, countMax = 1 } },
		} },
		skills = {
			skill = { supportCountId = "Low", possibleSupportIds = { "support_t1", "support_t2", "support_t3", "other_support", "support_no_family" } },
			other_skill = { supportCountId = "High", possibleSupportIds = { } },
		},
		supports = {
			support_t1 = { variant = 1, familyId = "family" },
			support_t2 = { variant = 2, familyId = "family" },
			support_t3 = { variant = 3, familyId = "family" },
			other_support = { variant = 1, familyId = "other_family" },
			support_no_family = { variant = 1 },
		},
		supportCounts = { Low = { maximum = 2 }, High = { maximum = 5 } },
		skillsByHash = { ["10"] = { "skill", "other_skill" } },
		supportsByHash = {
			["20"] = { "support_t1", "support_t2", "support_t3" },
			["21"] = { "other_support" },
			["22"] = { "support_no_family" },
		},
	}

	it("identifies Mercenary item slots without assuming string table keys", function()
		assert.are.equal("Helmet", tools.baseItemSlotName("Mercenary Helmet"))
		assert.is_nil(tools.baseItemSlotName("Helmet"))
		assert.is_nil(tools.baseItemSlotName(1))
	end)

	it("imports bounded Warrant data and resolves support hash by tier", function()
		local imported, err = tools.importWarrant([[{
			"mercenarySkills": [{ "hash": 10, "supports": [{ "hash": 20, "tier": 2 }] }]
		}]], data, "class")
		assert.is_nil(err)
		assert.same({ id = "support_t2", tier = 2 }, imported.skills[1].supports[1])
		assert.are.equal(68, tools.effectiveLevel(50, 84))
		assert.are.equal(48, tools.requiredFoundAreaLevel(68))
	end)

	it("interpolates exported passive stats from zero-based level breakpoints", function()
		local values = { 60, 120, 160 }
		assert.are.equal(60, tools.passiveStatValue(values, 1))
		assert.are.equal(118, tools.passiveStatValue(values, 50))
		assert.are.equal(120, tools.passiveStatValue(values, 51))
		assert.are.equal(133, tools.passiveStatValue(values, 68))
		assert.are.equal(159, tools.passiveStatValue(values, 100))
	end)

	it("selects exported alternate monster Life scaling", function()
		local tables = { monsterAllyLifeTable = { "ally" }, monsterLifeTable2 = { "alt1" }, monsterLifeTable3 = { "alt2" } }
		assert.are.equal("ally", tools.monsterLifeTable(tables)[1])
		assert.are.equal("alt1", tools.monsterLifeTable(tables, "AltLife1")[1])
		assert.are.equal("alt2", tools.monsterLifeTable(tables, "AltLife2")[1])
	end)

	it("rejects invalid data without returning a partial profile", function()
		local imported, err = tools.importWarrant([[{
			"mercenarySkills": [{ "hash": 10, "supports": [{ "hash": 20, "tier": 4 }] }]
		}]], data, "class")
		assert.is_nil(imported)
		assert.matches("does not have tier 4", err, nil, true)
	end)

	it("scopes hash resolution to the selected class", function()
		local noClass, noClassError = tools.importWarrant([[{"mercenarySkills":[{"hash":10}]}]], data)
		assert.is_nil(noClass)
		assert.matches("Select the Mercenary class", noClassError, nil, true)
		local imported, err = tools.importWarrant([[{"mercenarySkills":[{"hash":10}]}]], data, "class")
		assert.is_nil(err)
		assert.are.equal("skill", imported.skills[1].id)
		local rejected, ambiguousError = tools.importWarrant([[{"mercenarySkills":[{"hash":10}]}]], data, "ambiguous")
		assert.is_nil(rejected)
		assert.matches("Ambiguous skill hash", ambiguousError, nil, true)
	end)

	it("rejects malformed and oversized Warrant JSON", function()
		assert.is_nil(select(1, tools.importWarrant("{", data, "class")))
		local trailing, trailingError = tools.importWarrant([[{"mercenarySkills":[{"hash":10}]} garbage]], data, "class")
		assert.is_nil(trailing)
		assert.matches("trailing data", trailingError, nil, true)
		local imported, err = tools.importWarrant(string.rep(" ", 256 * 1024 + 1), data, "class")
		assert.is_nil(imported)
		assert.matches("exceeds 256 KiB", err, nil, true)
	end)

	it("accepts supports without a family", function()
		local imported, err = tools.importWarrant([[{"mercenarySkills":[{"hash":10,"supports":[{"hash":22,"tier":1}]}]}]], data, "class")
		assert.is_nil(err)
		assert.are.equal("support_no_family", imported.skills[1].supports[1].id)
	end)

	it("rejects duplicate skills, supports, and support families", function()
		local duplicateSkill, duplicateSkillError = tools.importWarrant([[{"mercenarySkills":[{"hash":10},{"hash":10}]}]], data, "class")
		assert.is_nil(duplicateSkill)
		assert.matches("Duplicate Mercenary skill", duplicateSkillError, nil, true)
		local duplicateSupport, duplicateSupportError = tools.importWarrant([[{"mercenarySkills":[{"hash":10,"supports":[{"hash":20,"tier":1},{"hash":20,"tier":1}]}]}]], data, "class")
		assert.is_nil(duplicateSupport)
		assert.matches("Duplicate support", duplicateSupportError, nil, true)
		local duplicateFamily, duplicateFamilyError = tools.importWarrant([[{"mercenarySkills":[{"hash":10,"supports":[{"hash":20,"tier":1},{"hash":20,"tier":2}]}]}]], data, "class")
		assert.is_nil(duplicateFamily)
		assert.matches("Duplicate support family", duplicateFamilyError, nil, true)
	end)

	it("enforces the exported support-count maximum", function()
		local imported, err = tools.importWarrant([[{"mercenarySkills":[{"hash":10,"supports":[{"hash":20,"tier":1},{"hash":21,"tier":1},{"hash":20,"tier":3}]}]}]], data, "class")
		assert.is_nil(imported)
		assert.matches("more than 2 supports", err, nil, true)
	end)

	it("validates saved profiles without repairing invalid data", function()
		local profile = {
			buildId = "build",
			foundAreaLevel = 0,
			mainSkillId = "missing",
			skills = { {
				id = "skill",
				enabled = true,
				supports = { { id = "support_t1", tier = 2 }, { id = "support_t2", tier = 2 } },
			} },
		}
		local errors = table.concat(tools.validateProfile(profile, data), "\n")
		assert.matches("Found%-area level", errors)
		assert.matches("Invalid tier", errors)
		assert.matches("Duplicate support family", errors)
		assert.matches("Selected Calcs skill", errors)
		assert.are.equal("missing", profile.mainSkillId)
		profile.foundAreaLevel = 68.5
		assert.matches("must be an integer", table.concat(tools.validateProfile(profile, data), "\n"))
	end)

	it("rejects unsafe Full DPS counts", function()
		for _, count in ipairs({ 0, 1.5, 100, "2" }) do
			local errors = table.concat(tools.validateProfile({
				buildId = "build",
				foundAreaLevel = 68,
				mainSkillId = "skill",
				skills = { { id = "skill", enabled = true, count = count, supports = { } } },
			}, data), "\n")
			assert.matches("must be an integer from 1 to 99", errors)
		end
	end)

	it("requires an enabled selected Calcs skill", function()
		local profile = {
			buildId = "build",
			foundAreaLevel = 68,
			skills = { { id = "skill", enabled = false, supports = { } } },
		}
		local errors = table.concat(tools.validateProfile(profile, data), "\n")
		assert.matches("Enable at least one", errors)
		profile.skills[1].enabled = true
		errors = table.concat(tools.validateProfile(profile, data), "\n")
		assert.matches("Select a Mercenary skill for Calcs", errors)
		profile.mainSkillId = "skill"
		profile.skills[1].enabled = false
		errors = table.concat(tools.validateProfile(profile, data), "\n")
		assert.matches("Enable at least one", errors)
	end)

	it("enforces exported build skill-pool limits", function()
		local errors = table.concat(tools.validateProfile({
			buildId = "build",
			foundAreaLevel = 68,
			mainSkillId = "skill",
			skills = {
				{ id = "skill", enabled = true, supports = { } },
				{ id = "other_skill", enabled = true, supports = { } },
			},
		}, data), "\n")
		assert.matches("Skill pool 1 allows at most 1", errors)
	end)
end)

describe("Generated Mercenary data", function()
	it("has deterministic orders and resolvable references", function()
		local mercenaries = data.mercenaries
		local function has(values, wanted)
			for _, value in ipairs(values) do if value == wanted then return true end end
			return false
		end
		assert.are.equal(2, mercenaries.version)
		assert.are.equal(13, #mercenaries.classOrder)
		for index = 2, #mercenaries.classOrder do
			assert.is_true(mercenaries.classOrder[index - 1] < mercenaries.classOrder[index])
		end
		for index = 2, #mercenaries.buildOrder do
			assert.is_true(mercenaries.buildOrder[index - 1] < mercenaries.buildOrder[index])
		end
		for _, classId in ipairs(mercenaries.classOrder) do
			local class = assert(mercenaries.classes[classId])
			assert.is_table(class.monster)
			for _, buildId in ipairs(class.buildIds) do
				assert.are.equal(classId, assert(mercenaries.builds[buildId]).classId)
			end
			for _, skillId in ipairs(class.skillIds) do
				assert.is_table(mercenaries.skills[skillId])
			end
		end
		for skillId, skill in pairs(mercenaries.skills) do
			assert.is_true(data.skills[skillId].mercenary, skillId)
			local resolved = mercenaries.skillsByHash[tostring(skill.hash)]
			assert.is_table(resolved)
			assert.is_true(has(resolved, skillId))
			for _, supportId in ipairs(skill.possibleSupportIds) do
				assert.is_table(mercenaries.supports[supportId])
			end
		end
		for supportId, support in pairs(mercenaries.supports) do
			local resolved = mercenaries.supportsByHash[tostring(support.hash)]
			assert.is_table(resolved)
			assert.is_true(has(resolved, supportId))
			for _, stat in ipairs(support.stats) do
				assert.are.equal("string", type(stat.id), supportId)
				assert.are.equal("number", type(stat.value), supportId..": "..stat.id)
				assert.is_table(data.mercenarySupportStatMap[stat.id], supportId..": "..stat.id)
			end
		end
		local seenKnownUncalculated = { }
		for skillId in pairs(mercenaries.skills) do
			local grantedEffect = assert(data.skills[skillId])
			for _, statId in ipairs(grantedEffect.stats or { }) do
				assert.is_true(grantedEffect.statMap[statId] ~= nil or data.knownUncalculatedSkillStats[statId] == true, skillId..": "..statId)
				if not grantedEffect.statMap[statId] then seenKnownUncalculated[statId] = true end
			end
			for _, stat in ipairs(grantedEffect.constantStats or { }) do
				assert.is_true(grantedEffect.statMap[stat[1]] ~= nil or data.knownUncalculatedSkillStats[stat[1]] == true, skillId..": "..stat[1])
				if not grantedEffect.statMap[stat[1]] then seenKnownUncalculated[stat[1]] = true end
			end
		end
		for statId in pairs(data.knownUncalculatedSkillStats) do
			assert.is_true(seenKnownUncalculated[statId] == true, "stale Mercenary stat exemption: "..statId)
		end
		for _, classId in ipairs(mercenaries.classOrder) do
			for _, stat in ipairs(mercenaries.classes[classId].monster.stats or { }) do
				assert.is_true(data.mercenaryStatData.knownMonsterStats[stat.id] == true, classId..": "..stat.id)
			end
		end
		for supportId, templateId in pairs(data.mercenaryStatData.supportTemplates) do
			assert.is_table(mercenaries.supports[supportId], supportId)
			assert.is_table(data.skills[templateId], templateId)
		end
		assert.are.equal(5, mercenaries.supportCounts.High.maximum)
	end)

	it("does not replace canonical item-granted skills with Mercenary variants", function()
		for modLine, expectedSkillId in pairs({
			["Grants Level 1 Icestorm Skill"] = "Icestorm",
			["Grants Level 15 Envy Skill"] = "Envy",
			["Grants Level 20 Aspect of the Spider Skill"] = "AspectOfTheSpider",
		}) do
			local mods = assert(modLib.parseMod(modLine))
			assert.are.equal(expectedSkillId, mods[1].value.skillId, modLine)
		end
	end)
end)
