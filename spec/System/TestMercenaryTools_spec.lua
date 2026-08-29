describe("Mercenary tools", function()
	local tools = require("Modules.MercenaryTools")
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

	it("does not substitute player output for a missing Mercenary actor", function()
		local playerOutput = { CombinedDPS = 100 }
		local actorOutputs = { PLAYER = playerOutput }
		assert.is_nil(tools.comparisonBaseOutput(playerOutput, actorOutputs, "Mercenary Helmet"))
		assert.are.equal(playerOutput, tools.comparisonBaseOutput(playerOutput, actorOutputs, "Helmet"))
		assert.is_true(not tools.mercenaryOutputAvailable(nil))
		assert.is_true(not tools.mercenaryOutputAvailable({ ActorUnavailableMessage = "missing" }))
	end)

	it("uses the Mercenary output when the actor is present", function()
		local playerOutput = { CombinedDPS = 100 }
		local mercenaryOutput = { CombinedDPS = 50 }
		assert.are.equal(mercenaryOutput, tools.comparisonBaseOutput(playerOutput, {
			PLAYER = playerOutput,
			MERCENARY = mercenaryOutput,
		}, "Mercenary Helmet"))
		assert.is_true(tools.mercenaryOutputAvailable(mercenaryOutput))
	end)

	it("treats a dedicated Mercenary item set as the Mercenary comparison actor", function()
		assert.are.equal("MERCENARY", tools.comparisonActorForItemSet(2, {
			activeItemSetId = 1,
			build = { mercenaryTab = { itemSetId = 2 } },
		}))
		assert.are.equal("PLAYER", tools.comparisonActorForItemSet(1, {
			activeItemSetId = 1,
			build = { mercenaryTab = { itemSetId = 1 } },
		}))
		assert.are.equal("PLAYER", tools.comparisonActorForItemSet(3, {
			activeItemSetId = 1,
			build = { mercenaryTab = { itemSetId = 2 } },
		}))
		assert.are.equal("MERCENARY", tools.comparisonActorForSlot("Helmet", 2, {
			activeItemSetId = 1,
			build = { mercenaryTab = { itemSetId = 2 } },
		}))
		assert.are.equal("MERCENARY", tools.comparisonActorForSlot("Mercenary Helmet", 1, {
			activeItemSetId = 1,
			build = { mercenaryTab = { itemSetId = 2 } },
		}))
	end)

	it("uses explicit view comparison actor when the Mercenary shares the active item set", function()
		local shared = {
			activeItemSetId = 1,
			viewItemSetId = 1,
			viewComparisonActor = "MERCENARY",
			build = { mercenaryTab = { itemSetId = 1 } },
		}
		assert.are.equal("MERCENARY", tools.comparisonActorForItemSet(1, shared))
		assert.are.equal("MERCENARY", tools.comparisonActorForSlot("Helmet", 1, shared))
		shared.viewComparisonActor = "PLAYER"
		assert.are.equal("PLAYER", tools.comparisonActorForItemSet(1, shared))
		assert.are.equal("PLAYER", tools.comparisonActorForSlot("Helmet", 1, shared))
	end)

	it("identifies dedicated Mercenary item sets without using the current view", function()
		assert.is_true(tools.isDedicatedMercenaryItemSet(2, {
			activeItemSetId = 1,
			viewItemSetId = 1,
			viewComparisonActor = "MERCENARY",
			build = { mercenaryTab = { itemSetId = 2 } },
		}))
		assert.is_true(not tools.isDedicatedMercenaryItemSet(1, {
			activeItemSetId = 1,
			viewItemSetId = 1,
			viewComparisonActor = "MERCENARY",
			build = { mercenaryTab = { itemSetId = 1 } },
		}))
	end)

	it("builds a comparison override for a viewed item set", function()
		local itemsTab = {
			activeItemSetId = 1,
			build = { mercenaryTab = { itemSetId = 2 } },
		}
		local item = { name = "hat" }
		local override = tools.itemCalculationOverride(2, "Helmet", item, itemsTab)
		assert.are.equal(2, override.itemSetId)
		assert.are.equal("MERCENARY", override.comparisonActor)
		assert.are.equal("Helmet", override.repSlotName)
		assert.are.equal(item, override.repItem)
	end)

	it("keeps tree jewel comparisons on the player", function()
		local itemsTab = {
			activeItemSetId = 1,
			viewItemSetId = 2,
			build = { mercenaryTab = { itemSetId = 2 } },
		}
		assert.are.equal("PLAYER", tools.comparisonActorForSlot("Jewel 12345", 2, itemsTab))
		local override = tools.itemCalculationOverride(2, "Jewel 12345", { name = "jewel" }, itemsTab)
		assert.is_nil(override.itemSetId)
		assert.are.equal("PLAYER", override.comparisonActor)
		assert.are.equal("Jewel 12345", override.repSlotName)
	end)

	it("does not replace the other actor's gear when the comparison actor is explicit", function()
		local playerOverride = { itemSetId = 1, comparisonActor = "PLAYER", repSlotName = "Helmet", repItem = { } }
		assert.is_true(tools.overrideReplacesPlayerItem(playerOverride, 1))
		assert.is_false(tools.overrideReplacesMercenarySlot(playerOverride, "Helmet", 1))
		local mercOverride = { itemSetId = 1, comparisonActor = "MERCENARY", repSlotName = "Helmet", repItem = { } }
		assert.is_false(tools.overrideReplacesPlayerItem(mercOverride, 1))
		assert.is_true(tools.overrideReplacesMercenarySlot(mercOverride, "Helmet", 1))
		local dedicatedMerc = { itemSetId = 2, repSlotName = "Helmet", repItem = { } }
		assert.is_false(tools.overrideReplacesPlayerItem(dedicatedMerc, 1))
		assert.is_true(tools.overrideReplacesMercenarySlot(dedicatedMerc, "Helmet", 2))
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

	it("accepts a complete Toxicologist Warrant roster", function()
		local mercenaryData = LoadModule("Data/Mercenaries")
		mercenaryData.supportCounts = _G.data.mercenaryStatData.supportCounts
		local imported, err = tools.importWarrant([[
Item Class: Map Fragments
Rarity: Normal
Mercenary Warrant
--------
Vreka, the Killer
--------
Build: Toxicologist
Mercenary Level: 83
--------
Withering Step
Increased Area of Effect (Tier: 2)
Gilded Wither Stacks (Tier: 3)
--------
Chaotic Burst
Wither on Hit (Tier: 2)
Increased Area of Effect (Tier: 2)
--------
Chaotic Shot
Physical as Extra Chaos (Tier: 2)
Chance to Poison (Tier: 2)
Chaos Penetration (Tier: 2)
Faster Projectiles (Tier: 2)
Greater Multiple Projectiles (Tier: 3)
--------
Scourge Arrow of Menace
Greater Faster Attacks (Tier: 3)
Greater DoT Multiplier (Tier: 3)
Physical as Extra Chaos (Tier: 2)
Chance to Poison (Tier: 2)
--------
Blink Arrow
Faster Attacks (Tier: 2)
Minion Life (Tier: 2)
Greater Minion Damage (Tier: 3)
--------
Trarthan Agility
Cooldown Recovery (Tier: 2)
Greater Area of Effect (Tier: 3)
--------
Right click this item to view Mercenary details.
Can be used in a personal Map Device alongside a Map to have this previously fought Mercenary reappear in the area for a rematch.
]], mercenaryData)
		assert.is_nil(err)
		assert.is_table(mercenaryData.builds[imported.buildId])
		assert.are.equal("Toxicologist", mercenaryData.builds[imported.buildId].name)
		assert.are.equal(6, #imported.skills)
		assert.same({
			"Withering Step",
			"Chaotic Burst",
			"Chaotic Shot",
			"Scourge Arrow of Menace",
			"Blink Arrow",
			"Trarthan Agility",
		}, (function()
			local names = { }
			for _, skill in ipairs(imported.skills) do table.insert(names, mercenaryData.skills[skill.id].name) end
			return names
		end)())
		local firstSupport = imported.skills[1].supports[1]
		assert.are.equal("Increased Area of Effect", mercenaryData.supports[firstSupport.id].name)
		assert.are.equal(2, firstSupport.tier)
		assert.are.equal("Withering Step", mercenaryData.skills[imported.mainSkillId].name)
		assert.is_true(imported.importedWarrant)
	end)

	it("rejects oversized, malformed, and ambiguous Warrant input", function()
		local mercenaryData = LoadModule("Data/Mercenaries")
		mercenaryData.supportCounts = _G.data.mercenaryStatData.supportCounts
		local _, err = tools.importWarrant(string.rep("x", 256 * 1024 + 1), mercenaryData)
		assert.matches("256 KiB", err)

		local header = "Mercenary Warrant\n--------\nBuild: Toxicologist\nMercenary Level: 83\n--------\n"
		_, err = tools.importWarrant(header.."Withering Step\nNot a support\n", mercenaryData)
		assert.matches("Invalid support line", err)
		_, err = tools.importWarrant(header.."Withering Step\nIncreased Area of Effect (Tier: 2)\nIncreased Area of Effect (Tier: 2)\n", mercenaryData)
		assert.matches("Duplicate support", err)
		_, err = tools.importWarrant(header.."Withering Step\nIncreased Area of Effect (Tier: 9)\n", mercenaryData)
		assert.matches("is not valid", err)
		_, err = tools.importWarrant(header.."Withering Step\nIncreased Area of Effect (Tier: 2)\n--------\nLeftover garbage\n", mercenaryData)
		assert.matches("Unknown Mercenary skill", err)

		local fake = {
			builds = {
				a = { id = "a", name = "Dup", classId = "c", skillIds = { "s" } },
				b = { id = "b", name = "Dup", classId = "c", skillIds = { "s" } },
			},
			buildOrder = { "a", "b" },
			skills = { s = { id = "s", name = "Skill", possibleSupportIds = { }, supportCountId = "None" } },
			supports = { },
			supportCounts = { None = { maximum = 0 } },
		}
		_, err = tools.importWarrant("Mercenary Warrant\n--------\nBuild: Dup\nMercenary Level: 10\n--------\nSkill\n", fake)
		assert.matches("Ambiguous Mercenary build", err)

		local familyData = {
			builds = { only = { id = "only", name = "Solo", classId = "c", skillIds = { "s" }, skillPools = { { skillIds = { "s" } } } } },
			buildOrder = { "only" },
			skills = { s = { id = "s", name = "Skill", possibleSupportIds = { "s1", "s2" }, supportCountId = "Low" } },
			supports = {
				s1 = { id = "s1", name = "SuppA", variant = 1, familyId = "fam" },
				s2 = { id = "s2", name = "SuppB", variant = 1, familyId = "fam" },
			},
			supportCounts = { Low = { maximum = 2 } },
		}
		_, err = tools.importWarrant("Mercenary Warrant\n--------\nBuild: Solo\nMercenary Level: 10\n--------\nSkill\nSuppA (Tier: 1)\nSuppB (Tier: 1)\n", familyData)
		assert.matches("Duplicate support family", err)
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

	it("tapers the permanent Mercenary damage penalty from level 45 to 83", function()
		local maxMore = -30
		assert.are.equal(0, tools.permanentDamageMore(1, maxMore))
		assert.are.equal(0, tools.permanentDamageMore(44, maxMore))
		assert.are.equal(0, tools.permanentDamageMore(45, maxMore))
		assert.are.equal(-1, tools.permanentDamageMore(46, maxMore))
		assert.are.equal(-29, tools.permanentDamageMore(82, maxMore))
		assert.are.equal(-30, tools.permanentDamageMore(83, maxMore))
		assert.are.equal(-30, tools.permanentDamageMore(100, maxMore))
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

	it("reports a selected skill with no id instead of crashing", function()
		local ok, errors = pcall(tools.validateProfile, {
			buildId = "build",
			foundAreaLevel = 68,
			mainSkillId = "skill",
			skills = { { enabled = true, supports = { } } },
		}, data)
		assert.is_true(ok)
		assert.matches("Invalid skill", table.concat(errors, "\n"))
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

	it("treats a missing support-count policy as an error rather than zero", function()
		assert.are.equal(2, tools.supportLimit(data, data.skills.skill))
		data.supportCounts.None = { maximum = 0 }
		assert.are.equal(0, tools.supportLimit(data, { id = "zero", supportCountId = "None" }))
		assert.is_nil(tools.supportLimit(data, { id = "drift", supportCountId = "MissingPolicy" }))
		data.skills.skill.supportCountId = "MissingPolicy"
		local errors = table.concat(tools.validateProfile({
			buildId = "build",
			foundAreaLevel = 68,
			mainSkillId = "skill",
			skills = { { id = "skill", enabled = true, supports = { } } },
		}, data), "\n")
		assert.matches("Missing support%-count policy for MissingPolicy", errors)
		data.skills.skill.supportCountId = "Low"
		data.supportCounts.None = nil
	end)

	it("rejects illegal editor skill and support candidates before mutation", function()
		local profile = {
			buildId = "build",
			foundAreaLevel = 68,
			mainSkillId = "skill",
			skills = { { id = "skill", enabled = true, supports = { } } },
		}
		assert.matches("Duplicate skill", tools.skillCandidateError(profile, data, 2, "skill"))
		assert.matches("allows at most 1", tools.skillCandidateError(profile, data, 2, "other_skill"))
		assert.is_nil(tools.firstLegalSkillId(profile, data))
		assert.matches("Duplicate support family", tools.supportCandidateError({
			skills = { { id = "skill", supports = { { id = "support_t1", tier = 1 } } } },
		}, data, 1, 2, "support_t2"))
		assert.is_nil(tools.supportCandidateError({
			skills = { { id = "skill", supports = { } } },
		}, data, 1, 1, "support_t1"))
	end)

	it("does not attach a membership cache onto generated skill lists", function()
		local skillIds = data.builds.build.skillIds
		local possibleSupportIds = data.skills.skill.possibleSupportIds
		tools.validateProfile({
			buildId = "build",
			foundAreaLevel = 68,
			mainSkillId = "skill",
			skills = { { id = "skill", enabled = true, supports = { { id = "support_t1", tier = 1 } } } },
		}, data)
		tools.skillCandidateError({
			buildId = "build",
			skills = { { id = "skill", enabled = true, supports = { } } },
		}, data, 2, "other_skill")
		assert.is_nil(rawget(skillIds, "_set"))
		assert.is_nil(rawget(possibleSupportIds, "_set"))
		local keys = { }
		for key in pairs(skillIds) do
			keys[key] = true
		end
		assert.is_nil(keys._set)
	end)
end)

describe("Generated Mercenary data", function()
	local tools = require("Modules.MercenaryTools")
	local export = require("Export.MercenaryExport")

	it("has deterministic orders and resolvable references", function()
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
			assert.is_table(mercenaries.supportCounts[skill.supportCountId], skillId..": "..tostring(skill.supportCountId))
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
		local seenKnownUncalculatedMinion = { }
		local unmappedMinionStats = { }
		for minionId, minion in pairs(mercenaries.minions or { }) do
			for _, stat in ipairs(minion.stats or { }) do
				local mapped = data.mercenarySupportStatMap[stat.id] ~= nil
				local knownMinion = data.knownUncalculatedMinionStats[stat.id] == true
				local knownMonster = data.mercenaryStatData.knownMonsterStats[stat.id] == true
				if not (mapped or knownMinion or knownMonster) then
					table.insert(unmappedMinionStats, minionId..": "..stat.id)
				end
				if knownMinion then seenKnownUncalculatedMinion[stat.id] = true end
			end
		end
		table.sort(unmappedMinionStats)
		assert.same({ }, unmappedMinionStats)
		for statId in pairs(data.knownUncalculatedMinionStats) do
			assert.is_true(seenKnownUncalculatedMinion[statId] == true, "stale Mercenary minion stat exemption: "..statId)
			assert.is_true(data.mercenarySupportStatMap[statId] == nil, "mapped minion stat listed as uncalculated: "..statId)
		end
		local relic = assert(data.minions["Metadata/Monsters/Mercenaries/MercenaryUnholyRelic_"])
		local curseImmune
		for _, mod in ipairs(relic.modList) do
			if mod.name == "CurseImmune" then curseImmune = true break end
		end
		assert.is_true(curseImmune)
		for supportId, templateId in pairs(data.mercenaryStatData.supportTemplates) do
			assert.is_table(mercenaries.supports[supportId], supportId)
			assert.is_table(data.skills[templateId], templateId)
		end
		assert.are.equal(5, mercenaries.supportCounts.High.maximum)
		assert.are.equal(0, mercenaries.supportCounts.None.maximum)
		for skillId, skill in pairs(mercenaries.skills) do
			assert.are.equal(skillId, skill.id)
		end
		for _, buildId in ipairs(mercenaries.buildOrder) do
			assert.is_table(assert(mercenaries.builds[buildId]).weaponConfiguration, buildId)
		end
		for policyId in pairs(data.mercenaryStatData.supportCounts) do
			local used = false
			for _, skill in pairs(mercenaries.skills) do
				if skill.supportCountId == policyId then used = true break end
			end
			assert.is_true(used, "unused support-count policy: "..policyId)
		end
	end)

	it("populates every input of an inherited preDamageFunc", function()
		local tools = require("Modules.MercenaryTools")
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

	it("derives monster speed/damage fixup from the exported stat value", function()
		assert.are.equal(0.11, export.monsterSpeedAndDamageFixup("MonsterSpeedAndDamageFixupSmall", {
			{ id = "monster_base_type_attack_cast_speed_+%_and_damage_-%_final", value = 11 },
		}))
		assert.are.equal(0.33, export.monsterSpeedAndDamageFixup("MonsterSpeedAndDamageFixupComplete", {
			{ id = "monster_base_type_attack_cast_speed_+%_and_damage_-%_final", value = 33 },
		}))
		assert.is_nil(export.monsterSpeedAndDamageFixup("MonsterImplicitDamage", {
			{ id = "monster_base_type_attack_cast_speed_+%_and_damage_-%_final", value = 33 },
		}))
		assert.has_error(function()
			export.monsterSpeedAndDamageFixup("MonsterSpeedAndDamageFixupVeryLarge", {
				{ id = "some_other_stat", value = 44 },
			})
		end)
	end)

	it("rejects equal-rank display-name base-skill ties", function()
		local first = export.considerRankedCandidate(nil, "Snipe", 0)
		local tied = export.considerRankedCandidate(first, "AtlasEyrieArcherSnipe", 0)
		assert.are.equal("AtlasEyrieArcherSnipe", tied.id)
		assert.has_error(function()
			export.requireUniqueRankedCandidate(tied, "display name 'Snipe'")
		end)
		local unique = export.considerRankedCandidate(nil, "Snipe", 0)
		assert.are.equal("Snipe", export.requireUniqueRankedCandidate(unique, "display name 'Snipe'").id)
		local gem = export.considerRankedCandidate({ id = "NpcCopy", rank = 1, ids = { "NpcCopy" } }, "Snipe", 0)
		assert.are.equal("Snipe", export.requireUniqueRankedCandidate(gem, "display name 'Snipe'").id)
	end)

	it("rejects equal-rank ActiveSkill base-skill ties", function()
		local first = export.considerRankedCandidate(nil, "Snipe", 0)
		local tied = export.considerRankedCandidate(first, "AtlasEyrieArcherSnipe", 0)
		assert.has_error(function()
			export.requireUniqueRankedCandidate(tied, "ActiveSkill 'Snipe'")
		end, "Ambiguous ActiveSkill 'Snipe': AtlasEyrieArcherSnipe, Snipe")
	end)

	it("resolves Mercenary bases without a previously generated mercenary.lua", function()
		local unique = export.considerRankedCandidate(nil, "Absolution", 0)
		local resolved = export.resolveBaseSkill({
			effectId = "AbsolutionMercenary",
			activeSkillId = "absolution",
			displayName = "Absolution",
			byActiveSkill = unique,
		})
		assert.are.equal("Absolution", resolved.id)
		assert.are.equal("activeSkill", resolved.source)

		local first = export.considerRankedCandidate(nil, "AfflictionMinionPhysSlamCircleBig", 1)
		local tied = export.considerRankedCandidate(first, "OtherGeometryAttack", 1)
		local overridden = export.resolveBaseSkill({
			effectId = "TriggeredFireSlamMercenary",
			activeSkillId = "geometry_attack",
			displayName = "Triggerslam",
			byActiveSkill = tied,
			overrideId = "AfflictionMinionPhysSlamCircleBig",
			isExportedSkill = function(id) return id == "AfflictionMinionPhysSlamCircleBig" end,
		})
		assert.are.equal("AfflictionMinionPhysSlamCircleBig", overridden.id)
		assert.are.equal("override", overridden.source)

		local src = assert(io.open("Export/Scripts/skills.lua", "r"))
		local text = src:read("*a")
		src:close()
		assert.is_nil(text:match("previousInheritedFrom"))
		assert.is_nil(text:match('io%.open%("%.%./Data/Skills/mercenary%.lua", "r"%)'))
	end)

	it("fails an unrecognized ActiveSkill tie rather than inheriting a stale generated selection", function()
		local first = export.considerRankedCandidate(nil, "NewSpellA", 1)
		local tied = export.considerRankedCandidate(first, "NewSpellB", 1)
		assert.has_error(function()
			export.resolveBaseSkill({
				effectId = "MercenaryEffectA",
				activeSkillId = "geometry_spell",
				displayName = "MercenaryEffectA",
				byActiveSkill = tied,
			})
		end, "Ambiguous Mercenary base skill ActiveSkill 'geometry_spell': NewSpellA, NewSpellB")
	end)

	it("keeps exporter validation helpers out of runtime Mercenary tools", function()
		assert.is_nil(tools.monsterSpeedAndDamageFixup)
		assert.is_nil(tools.considerRankedCandidate)
		assert.is_nil(tools.requireUniqueRankedCandidate)
		assert.is_nil(tools.uniqueCandidate)
		assert.is_nil(tools.resolveBaseSkill)
		assert.is_nil(tools.shieldPolicyError)
		assert.is_nil(tools.MONSTER_SPEED_DAMAGE_FIXUP_STAT)
		assert.is_function(export.monsterSpeedAndDamageFixup)
		assert.is_function(export.considerRankedCandidate)
		assert.is_function(export.requireUniqueRankedCandidate)
		assert.is_function(export.uniqueCandidate)
		assert.is_function(export.resolveBaseSkill)
		assert.is_function(export.shieldPolicyError)
	end)

	it("requires an exhaustive shield policy for every shield-capable build", function()
		local builds = {
			RequiredShield = { weaponTypes = { "One Handed Mace", "Shield" } },
			OptionalShield = { weaponTypes = { "Wand", "Shield" } },
			NoShield = { weaponTypes = { "Staff" } },
		}
		assert.is_nil(export.shieldPolicyError(builds, {
			RequiredShield = "required",
			OptionalShield = "optional",
		}))
		assert.matches("missing shield policy", export.shieldPolicyError(builds, {
			OptionalShield = "optional",
		}))
		assert.matches("unknown Mercenary build", export.shieldPolicyError(builds, {
			RequiredShield = "required",
			OptionalShield = "optional",
			RemovedBuild = "optional",
		}))
		assert.matches("does not include a Shield", export.shieldPolicyError(builds, {
			RequiredShield = "required",
			OptionalShield = "optional",
			NoShield = "required",
		}))
		assert.matches("unknown shield policy", export.shieldPolicyError(builds, {
			RequiredShield = "maybe",
			OptionalShield = "optional",
		}))
	end)

	it("classifies every exported shield-capable Mercenary build", function()
		local function stub() return { } end
		local statMap = LoadModule("Data/MercenaryStatMap")(stub, stub, stub)
		assert.is_nil(export.shieldPolicyError(data.mercenaries.builds, statMap.shieldPolicy))
		for buildId, mercBuild in pairs(data.mercenaries.builds) do
			local hasShield = false
			for _, itemType in ipairs(mercBuild.weaponTypes or { }) do
				if itemType == "Shield" then hasShield = true break end
			end
			if hasShield then
				local optional = statMap.shieldPolicy[buildId] == "optional"
				assert.are.equal(not optional, mercBuild.weaponConfiguration.offHandRequired, buildId)
			end
		end
	end)
end)
