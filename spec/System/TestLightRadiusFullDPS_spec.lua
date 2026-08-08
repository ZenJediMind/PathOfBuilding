describe("Light Radius Full DPS integration", function()
	local expectedWeights = {
		{ stat = "FullDPS", weightMult = 1 },
		{ stat = "Life", weightMult = 0.2 },
		{ stat = "LifeRegen", weightMult = 0.1 },
		{ stat = "TotalEHP", weightMult = 0.02 },
		{ stat = "SecondMinimalMaximumHitTaken", weightMult = 0.02 },
		{ stat = "LightRadiusMod", weightMult = 0.2 },
	}

	local function loadFixture()
		local file = assert(io.open("Builds/Light Radius Test.xml", "r"))
		local xml = file:read("*a")
		file:close()
		loadBuildFromXML(xml, "Light Radius Test")
		build.calcsTab:BuildOutput()
		return assert(build.calcsTab.mainEnv)
	end

	local function findSkillDPS(output, name)
		for _, skillDPS in ipairs(output.SkillDPS or { }) do
			if skillDPS.name == name then
				return skillDPS
			end
		end
		return nil
	end

	local function sumSkillDPS(output, excludedName)
		local total = 0
		for _, skillDPS in ipairs(output.SkillDPS or { }) do
			if skillDPS.name ~= excludedName then
				total = total + skillDPS.dps * (skillDPS.count or 1)
			end
		end
		return total
	end

	local function tradeOptions(weights)
		return {
			influence1 = 1,
			influence2 = 1,
			includeTalisman = false,
			includeCorrupted = false,
			includeScourge = false,
			includeEldritch = false,
			includeMirrored = false,
			statWeights = weights,
			requiredMods = { },
		}
	end

	local function generateLightRadiusQuery(slotName, expectedBaseLightRadius, expectedWeight)
		local weights = build.itemsTab.tradeQuery.statSortSelectionList
		local slot = assert(build.itemsTab.slots[slotName])
		local queryGenerator = new("TradeQueryGenerator", build.itemsTab.tradeQuery)
		local queryJson, queryError
		queryGenerator.tradeTypeIndex = 1
		queryGenerator.requesterCallback = function(_, json, errMsg)
			queryJson, queryError = json, errMsg
		end
		queryGenerator:StartQuery(slot, tradeOptions(weights))
		queryGenerator.calcContext.co = nil

		local baseOutput = assert(queryGenerator.calcContext.baseOutput)
		assert.are.near(expectedBaseLightRadius, baseOutput.LightRadiusMod, 10 ^ -9)
		local blankOutput = queryGenerator.calcContext.calcFunc({
			repSlotName = slot.slotName,
			repItem = queryGenerator.calcContext.testItem,
		})
		assert.are.near(expectedBaseLightRadius, blankOutput.LightRadiusMod, 10 ^ -9)

		local lightRadiusMod = assert(queryGenerator.modData.Explicit["2529_LightRadiusAndAccuracyPercent"])
		assert.are.equal("explicit.stat_1263695895", lightRadiusMod.tradeMod.id)
		assert.are.same({ min = 5, max = 15 }, lightRadiusMod.Ring)

		queryGenerator.modWeights = { }
		queryGenerator.alreadyWeightedMods = { }
		queryGenerator:GenerateModWeights({ LightRadius = lightRadiusMod })
		assert.are.equal(1, #queryGenerator.modWeights)
		local generatedWeight = queryGenerator.modWeights[1]
		assert.are.equal("explicit.stat_1263695895", generatedWeight.tradeModId)
		assert.is_false(generatedWeight.invert)
		assert.is_true(generatedWeight.meanStatDiff > 0)
		assert.are.near(expectedWeight, generatedWeight.weight, 10 ^ -9)
		assert.are.near(generatedWeight.meanStatDiff / 10, generatedWeight.weight, 10 ^ -9)

		local weightedOutput = queryGenerator.calcContext.calcFunc({
			repSlotName = slot.slotName,
			repItem = queryGenerator.calcContext.testItem,
		})
		assert.are.near(expectedBaseLightRadius + 0.1, weightedOutput.LightRadiusMod, 10 ^ -9)
		if slotName == "Ring 1" then
			assert.is_true(weightedOutput.FullDPS > blankOutput.FullDPS)
		else
			assert.are.equal(blankOutput.FullDPS, weightedOutput.FullDPS)
		end

		queryGenerator:FinishQuery()
		assert.is_nil(queryError)
		local query = assert(require("dkjson").decode(queryJson))
		local category = query.query.filters.type_filters.filters.category.option
		assert.are.equal("accessory.ring", category)
		assert.are.equal("securable", query.query.status.option)
		assert.are.equal("weight", query.query.stats[1].type)
		assert.is_true(query.query.stats[1].value.min > 0)
		assert.are.equal(1, #query.query.stats[1].filters)
		assert.are.equal("explicit.stat_1263695895", query.query.stats[1].filters[1].id)
		assert.are.near(generatedWeight.weight, query.query.stats[1].filters[1].value.weight, 10 ^ -9)
	end

	it("keeps the saved actor, count, ailment, and culling Full DPS contract", function()
		local env = loadFixture()
		local profile = build.mercenaryTab.profile
		local output = assert(env.mercenary.output)

		assert.are.equal(95, build.characterLevel)
		assert.are.equal(84, env.enemyLevel)
		assert.are.equal(83, env.mercenary.level)
		assert.are.equal("EleBowRangerClones", profile.buildId)
		assert.are.equal("IceShotMercenary", profile.mainSkillId)
		assert.are.equal(5, profile.skills[1].count)
		assert.are.equal(1, profile.skills[2].count)
		assert.is_true(profile.skills[1].includeInFullDPS)
		assert.is_true(profile.skills[2].includeInFullDPS)
		assert.are.equal("Kraken Siege, Spine Bow", env.mercenary.itemList["Weapon 1"].name)
		assert.are.equal(env.mercenary, env.mercenary.calcEnv.player)

		assert.are.equal(260, env.player.modDB:Sum("INC", nil, "LightRadius"))
		assert.are.equal(0, env.mercenary.modDB:Sum("INC", nil, "LightRadius"))
		assert.are.near(3.6, env.player.output.LightRadiusMod, 10 ^ -9)
		assert.are.equal(1, env.mercenary.output.LightRadiusMod)

		assert.are.near(3125934.2085527, env.player.output.FullDPS, 10 ^ -6)
		assert.are.near(env.player.output.FullDPS, output.FullDPS, 10 ^ -6)
		assert.are.near(56974.168359429, env.player.output.FullDotDPS, 10 ^ -6)
		assert.are.near(env.player.output.FullDotDPS, output.FullDotDPS, 10 ^ -6)
		assert.are.near(533843.3569854, output.TotalDPS, 10 ^ -6)

		local iceShot = assert(findSkillDPS(output, "Ice Shot"))
		local vaalIceShot = assert(findSkillDPS(output, "Vaal Ice Shot"))
		local bestIgnite = assert(findSkillDPS(output, "Best Ignite DPS"))
		local fullCulling = assert(findSkillDPS(output, "Full Culling DPS"))
		assert.are.near(533843.3569854, iceShot.dps, 10 ^ -6)
		assert.are.equal(5, iceShot.count)
		assert.are.equal("Mercenary", iceShot.source)
		assert.are.equal("Arrow", iceShot.skillPart)
		assert.are.near(87149.834411037, vaalIceShot.dps, 10 ^ -6)
		assert.are.equal(1, vaalIceShot.count)
		assert.are.equal("Mercenary", vaalIceShot.source)
		assert.are.near(56974.168359429, bestIgnite.dps, 10 ^ -6)
		assert.are.equal("Ice Shot", bestIgnite.source)
		assert.are.near(312593.42085527, fullCulling.dps, 10 ^ -6)
		assert.are.near(sumSkillDPS(output), output.FullDPS, 10 ^ -6)
		assert.are.near(sumSkillDPS(output, "Full Culling DPS") / 9, fullCulling.dps, 10 ^ -6)

		profile.skills[2].includeInFullDPS = false
		build.mercenaryTab:Changed()
		build.calcsTab:BuildOutput()
		local withoutVaal = assert(build.calcsTab.mainEnv.mercenary.output)
		assert.is_nil(findSkillDPS(withoutVaal, "Vaal Ice Shot"))
		assert.is_true(withoutVaal.FullDPS < output.FullDPS)
		assert.is_true(withoutVaal.FullDotDPS <= output.FullDotDPS)
	end)

	it("calculates player and Mercenary Light Radius trade weights through the full query path", function()
		local env = loadFixture()
		local weights = build.itemsTab.tradeQuery.statSortSelectionList
		assert.are.equal(#expectedWeights, #weights)
		for index, expected in ipairs(expectedWeights) do
			assert.are.equal(expected.stat, weights[index].stat)
			assert.are.equal(expected.weightMult, weights[index].weightMult)
		end

		generateLightRadiusQuery("Ring 1", env.player.output.LightRadiusMod, 4.240494060752871)
		generateLightRadiusQuery("Mercenary Ring 1", env.mercenary.output.LightRadiusMod, 2)
	end)
end)
