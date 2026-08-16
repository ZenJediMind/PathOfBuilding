describe("Light Radius integration", function()
	local MercenaryTools = require("Modules/MercenaryTools")

	local function selectScionLuminary()
		local scionId
		for classId, class in pairs(build.spec.tree.classes) do
			if class.name == "Scion" then scionId = classId break end
		end
		build.spec:SelectClass(assert(scionId))

		local luminaryId
		for ascendClassId, ascendClass in pairs(build.spec.curClass.classes) do
			if ascendClass.name == "Luminary" then luminaryId = ascendClassId break end
		end
		build.spec:SelectAscendClass(assert(luminaryId))
	end

	local function allocate(name)
		local node = build.spec.tree.ascendancyMap[name]
		if not node then
			for _, candidate in pairs(build.spec.nodes) do
				if candidate.name == name then node = candidate break end
			end
		end
		node = assert(node, name)
		node = build.spec.nodes[node.id] or node
		if node.path then
			build.spec:AllocNode(node)
		else
			node.alloc = true
			build.spec.allocNodes[node.id] = node
		end
	end

	local function configureMercenary()
		local profile = build.mercenaryTab.profile
		profile.classId = "TrapsMinesShadow"
		profile.buildId = "TrapsMinesShadowLightning"
		profile.foundAreaLevel = 83
		profile.mainSkillId = "LightningTrapMercenary"
		profile.skills = { {
			id = profile.mainSkillId,
			enabled = true,
			includeInFullDPS = true,
			count = 1,
			supports = { },
		} }
		build.mercenaryTab:Changed()
	end

	local function equipRings()
		local itemsTab = build.itemsTab
		local playerRing = new("Item"):Item("Rarity: Normal\nPaua Ring")
		local mercenaryRing = new("Item"):Item("Rarity: Normal\nPaua Ring")
		itemsTab:AddItem(playerRing, true)
		itemsTab:AddItem(mercenaryRing, true)
		itemsTab.activeItemSet["Ring 1"].selItemId = playerRing.id
		local mercenaryItemSet = assert(build.mercenaryTab:GetItemSet(true))
		mercenaryItemSet[MercenaryTools.itemSlotName("Ring 1")].selItemId = mercenaryRing.id
		return mercenaryItemSet
	end

	local function calculate()
		build.configTab.input.enemyLevel = 83
		build.configTab:BuildModList()
		build.spec.modFlag = true
		build.buildFlag = true
		runCallback("OnFrame")
		runCallback("OnFrame")
		return assert(build.calcsTab.mainEnv)
	end

	local function tradeOptions(statWeights)
		return {
			influence1 = 1,
			influence2 = 1,
			includeTalisman = false,
			includeCorrupted = false,
			includeScourge = false,
			includeEldritch = false,
			includeMirrored = false,
			statWeights = statWeights,
			requiredMods = { },
		}
	end

	local function lightRadiusStat()
		for _, stat in ipairs(data.powerStatList) do
			if stat.stat == "LightRadiusMod" then return stat end
		end
		return assert(nil, "LightRadiusMod is missing from the power stat list")
	end

	local function findRingLightRadiusMod(queryGenerator)
		for _, mod in pairs(queryGenerator.modData.Explicit) do
			if mod.tradeMod and mod.tradeMod.id == "explicit.stat_1263695895" and mod.Ring then
				return mod
			end
		end
		return assert(nil, "Light Radius ring trade modifier is missing")
	end

	local function generateLightRadiusQuery(slotName, expectedBaseLightRadius)
		local stat = lightRadiusStat()
		local slot = assert(build.itemsTab.slots[slotName])
		local queryGenerator = new("TradeQueryGenerator"):TradeQueryGenerator(build.itemsTab.tradeQuery)
		local queryJson, queryError
		queryGenerator.tradeTypeIndex = 1
		queryGenerator.requesterCallback = function(_, json, errMsg)
			queryJson, queryError = json, errMsg
		end
		queryGenerator:StartQuery(slot, tradeOptions({ { stat = stat.stat, weightMult = 1 } }))
		queryGenerator.calcContext.co = nil

		local baseOutput = assert(queryGenerator.calcContext.baseOutput)
		assert.are.near(expectedBaseLightRadius, baseOutput.LightRadiusMod, 10 ^ -9)
		local blankOutput = queryGenerator.calcContext.calcFunc({
			repSlotName = slot.slotName,
			repItem = queryGenerator.calcContext.testItem,
		})
		assert.are.near(expectedBaseLightRadius, blankOutput.LightRadiusMod, 10 ^ -9)

		local lightRadiusMod = findRingLightRadiusMod(queryGenerator)
		queryGenerator.modWeights = { }
		queryGenerator.alreadyWeightedMods = { }
		queryGenerator:GenerateModWeights({ LightRadius = lightRadiusMod })
		assert.are.equal(1, #queryGenerator.modWeights)
		local generatedWeight = queryGenerator.modWeights[1]
		assert.are.equal("explicit.stat_1263695895", generatedWeight.tradeModId)
		assert.is_false(generatedWeight.invert)
		local weightedOutput = queryGenerator.calcContext.calcFunc({
			repSlotName = slot.slotName,
			repItem = queryGenerator.calcContext.testItem,
		})
		local modValue = tonumber(queryGenerator.calcContext.testItem.explicitModLines[1].line:match("^(%d+)%% increased Light Radius$"))
		assert.is_number(modValue)
		local expectedWeight = (
			weightedOutput.LightRadiusMod / baseOutput.LightRadiusMod
			- blankOutput.LightRadiusMod / baseOutput.LightRadiusMod
		) * 1000 / modValue
		assert.are.near(expectedWeight, generatedWeight.weight, 10 ^ -9)

		queryGenerator:FinishQuery()
		assert.is_nil(queryError)
		local query = assert(require("dkjson").decode(queryJson))
		assert.are.equal("accessory.ring", query.query.filters.type_filters.filters.category.option)
		assert.are.equal("securable", query.query.status.option)
		assert.are.equal("explicit.stat_1263695895", query.query.stats[1].filters[1].id)
		assert.are.near(generatedWeight.weight, query.query.stats[1].filters[1].value.weight, 10 ^ -9)
	end

	before_each(function()
		newBuild()
		selectScionLuminary()
		allocate("Noble Blood")
		build.characterLevel = 90
		build.characterLevelAutoMode = false
		configureMercenary()
		equipRings()
	end)

	it("calculates Light Radius and Full DPS from programmatic equipment", function()
		build.configTab.input.customMods = "100% increased Light Radius"
		local baseline = calculate()
		local baselinePlayerLightRadiusInc = baseline.player.modDB:Sum("INC", nil, "LightRadius")
		local baselineMercenaryLightRadiusInc = baseline.mercenary.modDB:Sum("INC", nil, "LightRadius")
		local baselinePlayerLightRadius = baseline.player.output.LightRadiusMod
		local baselineMercenaryLightRadius = baseline.mercenary.output.LightRadiusMod
		local mercenaryItemSet = assert(build.mercenaryTab:GetItemSet(true))
		local lightRadiusRing = new("Item"):Item([[Rarity: Rare
Mercenary Light Radius Test
Paua Ring
--------
100% increased Light Radius]])
		build.itemsTab:AddItem(lightRadiusRing, true)
		mercenaryItemSet[MercenaryTools.itemSlotName("Ring 1")].selItemId = lightRadiusRing.id

		local env = calculate()
		assert.are.equal(baselinePlayerLightRadiusInc, env.player.modDB:Sum("INC", nil, "LightRadius"))
		assert.are.equal(baselineMercenaryLightRadiusInc + 100, env.mercenary.modDB:Sum("INC", nil, "LightRadius"))
		assert.are.near(baselinePlayerLightRadius, env.player.output.LightRadiusMod, 10 ^ -9)
		assert.are.near(baselineMercenaryLightRadius + 1, env.mercenary.output.LightRadiusMod, 10 ^ -9)
		assert.is_true(env.mercenary.output.FullDPS > 0)
		assert.are.near(env.mercenary.output.FullDPS, env.player.output.FullDPS, 10 ^ -6)
	end)

	it("uses the selected actor for Light Radius trade weights", function()
		build.configTab.input.customMods = "100% increased Light Radius"
		local env = calculate()
		generateLightRadiusQuery("Ring 1", env.player.output.LightRadiusMod)
		generateLightRadiusQuery("Mercenary Ring 1", env.mercenary.output.LightRadiusMod)
	end)
end)
