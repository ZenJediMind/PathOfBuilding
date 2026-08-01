describe("Mercenary tools", function()
	local tools = require("Modules/MercenaryTools")
	local data = {
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
	}

	it("identifies Mercenary item slots without assuming string table keys", function()
		assert.are.equal("Helmet", tools.baseItemSlotName("Mercenary Helmet"))
		assert.is_nil(tools.baseItemSlotName("Helmet"))
		assert.is_nil(tools.baseItemSlotName(1))
	end)

	it("groups numbered class variants for the picker", function()
		local groups, byClassId = tools.classGroups({
			classOrder = { "templar2", "witch2", "templar1", "scion" },
			classes = {
				templar2 = { name = "[DNT] Merc Templar 2", attributeName = "Str / Int", buildIds = { "build2" } },
				witch2 = { name = "[DNT] Witch Merc 2", attributeName = "Int", buildIds = { "build3" } },
				templar1 = { name = "[DNT] Merc Templar 1", attributeName = "Str / Int", buildIds = { "build1" } },
				scion = { name = "[DNT] Merc Scion 1", attributeName = "Str / Dex / Int", buildIds = { "scionBuild" } },
			},
		})
		assert.are.equal(3, #groups)
		assert.are.equal("Templar (Str / Int)", groups[1].label)
		assert.same({ "templar2", "templar1" }, groups[1].classIds)
		assert.same({ "build2", "build1" }, groups[1].buildIds)
		assert.are.equal(groups[1], byClassId.templar1)
		assert.are.equal("Scion (Str / Dex / Int)", groups[3].label)
		assert.are.equal(byClassId.scion, groups[3])
	end)

	it("calculates effective Mercenary levels and found-area requirements", function()
		assert.are.equal(68, tools.effectiveLevel(50, 84))
		assert.are.equal(100, tools.effectiveLevel(100, 85))
		assert.are.equal(100, tools.effectiveLevel(150, 85))
		assert.are.equal(1, tools.effectiveLevel(0, 0))
		assert.are.equal(48, tools.requiredFoundAreaLevel(68))
	end)

	it("interpolates exported passive stats between the level 24, 68 and 84 anchors", function()
		local values = { 60, 120, 160 }
		assert.are.equal(60, tools.passiveStatValue(values, 1))
		assert.are.equal(60, tools.passiveStatValue(values, 24))
		assert.are.equal(95, tools.passiveStatValue(values, 50))
		assert.are.equal(120, tools.passiveStatValue(values, 68))
		assert.are.equal(140, tools.passiveStatValue(values, 76))
		assert.are.equal(160, tools.passiveStatValue(values, 84))
		-- Levels outside the anchor range clamp to the end values.
		assert.are.equal(60, tools.passiveStatValue(values, 0))
		assert.are.equal(160, tools.passiveStatValue(values, 120))
		assert.are.equal(93, tools.passiveStatValue({ 38, 75, 100 }, 80))
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
		local tools = require("Modules/MercenaryTools")
		local mercenaries = data.mercenaries
		local classGroups = select(1, tools.classGroups(mercenaries))
		local classLabels = { }
		for _, group in ipairs(classGroups) do table.insert(classLabels, group.label) end
		assert.same({
			"Templar (Str / Int)",
			"Witch (Int)",
			"Shadow (Dex / Int)",
			"Ranger (Dex)",
			"Marauder (Str)",
			"Duelist (Str / Dex)",
			"Scion (Str / Dex / Int)",
		}, classLabels)
		local function has(values, wanted)
			for _, value in ipairs(values) do if value == wanted then return true end end
			return false
		end
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
			end
		end
		-- A support stat is implemented by the skill it supports or, where its meaning
		-- is the same everywhere, by the shared map. This is the order
		-- `mercenarySupportEffect` resolves them in.
		for skillId, skill in pairs(mercenaries.skills) do
			local grantedEffect = data.skills[skillId]
			for _, supportId in ipairs(skill.possibleSupportIds) do
				for _, stat in ipairs(mercenaries.supports[supportId].stats) do
					assert.is_true(grantedEffect.statMap[stat.id] ~= nil or data.mercenarySupportStatMap[stat.id] ~= nil, skillId.." + "..supportId..": "..stat.id)
				end
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

	it("populates every input of an inherited preDamageFunc", function()
		local tools = require("Modules/MercenaryTools")
		local statData = data.mercenaryStatData
		local problems = { }
		local declarationUsedBy = { }
		for skillId, grantedEffect in pairs(data.skills) do
			if grantedEffect.mercenary then
				local baseEffect = grantedEffect.inheritedFrom and data.skills[grantedEffect.inheritedFrom]
				for _, message in ipairs(tools.preDamageFuncErrors(grantedEffect, baseEffect, statData) or { }) do
					table.insert(problems, message)
				end
				if grantedEffect.inheritedFrom then
					assert.is_table(baseEffect, skillId)
					if grantedEffect.preDamageFunc == baseEffect.preDamageFunc then
						declarationUsedBy[grantedEffect.inheritedFrom] = skillId
					end
				end
			end
		end
		table.sort(problems)
		assert.are.equal("", table.concat(problems, "\n"))
		-- Dropping an inherited function is only justified while the Mercenary skill still
		-- lacks the stats that function reads.
		for skillId, reason in pairs(statData.droppedPreDamageFuncs) do
			local grantedEffect = assert(data.skills[skillId], skillId)
			assert.is_true(grantedEffect.mercenary, skillId)
			assert.is_string(reason)
			assert.is_nil(grantedEffect.preDamageFunc, skillId)
			assert.is_function(assert(data.skills[grantedEffect.inheritedFrom], skillId).preDamageFunc, skillId)
			local missing = assert(tools.missingPreDamageFuncInputs(grantedEffect, grantedEffect.inheritedFrom, statData), skillId)
			assert.is_true(#missing > 0, "no longer needs to drop its preDamageFunc: "..skillId)
			declarationUsedBy[grantedEffect.inheritedFrom] = skillId
		end
		for baseSkillId in pairs(statData.preDamageFuncInputs) do
			assert.is_function(assert(data.skills[baseSkillId], baseSkillId).preDamageFunc, baseSkillId)
			assert.is_string(declarationUsedBy[baseSkillId], "stale preDamageFunc input declaration: "..baseSkillId)
		end
	end)

	it("inherits from the skill gem version of a skill rather than an NPC copy", function()
		local gemSkills = { }
		for _, gem in pairs(data.gems) do
			if not gem.support then
				for _, skillId in ipairs({ gem.grantedEffectId, gem.secondaryGrantedEffectId }) do
					if skillId then gemSkills[skillId] = true end
				end
			end
		end
		local gemSkillByName = { }
		for skillId in pairs(gemSkills) do
			local name = data.skills[skillId].name
			if name and (not gemSkillByName[name] or skillId < gemSkillByName[name]) then
				gemSkillByName[name] = skillId
			end
		end
		for skillId, grantedEffect in pairs(data.skills) do
			local base = grantedEffect.mercenary and grantedEffect.inheritedFrom
			if base and not gemSkills[base] then
				-- NPC and monster copies of a skill share its name but not its
				-- implementation, so the gem is the base whenever one exists.
				assert.is_nil(gemSkillByName[data.skills[base].name], skillId.." inherits from "..base)
			end
		end
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
