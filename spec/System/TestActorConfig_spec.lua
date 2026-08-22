describe("Player and mercenary configuration", function()
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
		local node
		for _, candidate in pairs(build.spec.nodes) do
			if candidate.name == name and (not node or candidate.id < node.id) then node = candidate end
		end
		node = node or build.spec.tree.ascendancyMap[name]
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
		allocate("Noble Blood")
		local profile = build.mercenaryTab.profile
		profile.classId = "MeleeAOEMarauder"
		profile.buildId = "MeleeAOEMarauderFireSlam"
		profile.foundAreaLevel = 68
		profile.mainSkillId = "TectonicSlamFireMercenary"
		profile.skills = { { id = "TectonicSlamFireMercenary", enabled = true, supports = { } } }
		build.mercenaryTab:Changed()
		build.mercenaryTab:GetItemSet(true)
	end

	local function calculate()
		build.configTab:BuildModList()
		build.spec.modFlag = true
		build.buildFlag = true
		runCallback("OnFrame")
		runCallback("OnFrame")
		return build.calcsTab.mainEnv
	end

	before_each(function()
		newBuild()
		selectScionLuminary()
		configureMercenary()
	end)

	it("applies shared encounter config to both actors", function()
		build.configTab.input.PvpScaling = true
		local env = calculate()
		assert.is_true(env.player.modDB:Flag(nil, "HasPvpScaling"))
		assert.is_true(env.mercenary.modDB:Flag(nil, "HasPvpScaling"))
	end)

	it("does not apply the player's custom modifiers to the mercenary", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		configSet.customModsList[1].text = "100000% increased Accuracy Rating"
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_true(env.player.modDB:Sum("INC", nil, "Accuracy") >= 100000)
		assert.is_true(env.mercenary.modDB:Sum("INC", nil, "Accuracy") < 100000)
	end)

	it("applies mercenary custom modifiers only to the mercenary", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.customModsList[1].text = "100000% increased Accuracy Rating"
		local env = calculate()
		assert.is_true(env.mercenary.modDB:Sum("INC", nil, "Accuracy") >= 100000)
		assert.is_true(env.player.modDB:Sum("INC", nil, "Accuracy") < 100000)
	end)

	it("does not apply the player's power-charge config to the mercenary", function()
		build.configTab.input.usePowerCharges = true
		local env = calculate()
		assert.is_true(env.player.modDB:Flag(nil, "UsePowerCharges"))
		assert.is_not_true(env.mercenary.modDB:Flag(nil, "UsePowerCharges"))
	end)

	it("applies mercenary combat config only to the mercenary", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.input.usePowerCharges = true
		local env = calculate()
		assert.is_true(env.mercenary.modDB:Flag(nil, "UsePowerCharges"))
		assert.is_not_true(env.player.modDB:Flag(nil, "UsePowerCharges"))
	end)

	it("keeps the player's equipped item set on the active config set", function()
		local itemsTab = build.itemsTab
		local secondSet = itemsTab:NewItemSet()
		secondSet.title = "Alternate"
		table.insert(itemsTab.itemSetOrderList, secondSet.id)
		itemsTab:SetActiveItemSet(secondSet.id)
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		assert.are.equal(secondSet.id, configSet.actors.player.itemSetId)
	end)

	it("applies stored item sets when switching config sets", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local originalPlayerId = itemsTab.activeItemSetId
		local originalMercId = build.mercenaryTab.itemSetId
		local mapping = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(mapping)

		local altPlayer = itemsTab:NewItemSet()
		altPlayer.title = "Bossing"
		table.insert(itemsTab.itemSetOrderList, altPlayer.id)
		local altMerc = itemsTab:NewItemSet()
		altMerc.title = "Merc Bossing"
		table.insert(itemsTab.itemSetOrderList, altMerc.id)

		local bossing = configTab:NewConfigSet()
		table.insert(configTab.configSetOrderList, bossing.id)
		configTab:EnsureActorConfig(bossing)
		bossing.actors.player.itemSetId = altPlayer.id
		bossing.actors.mercenary.itemSetId = altMerc.id

		assert.are.equal(originalPlayerId, itemsTab.activeItemSetId)
		assert.are.equal(originalMercId, build.mercenaryTab.itemSetId)

		configTab:SetActiveConfigSet(bossing.id)
		assert.are.equal(altPlayer.id, itemsTab.activeItemSetId)
		assert.are.equal(altMerc.id, build.mercenaryTab.itemSetId)
		assert.are.equal(altPlayer.id, itemsTab.viewItemSetId)
		assert.are.equal(originalPlayerId, mapping.actors.player.itemSetId)
		assert.are.equal(originalMercId, mapping.actors.mercenary.itemSetId)

		configTab:SetActiveConfigSet(mapping.id)
		assert.are.equal(originalPlayerId, itemsTab.activeItemSetId)
		assert.are.equal(originalMercId, build.mercenaryTab.itemSetId)
		assert.are.equal(originalPlayerId, itemsTab.viewItemSetId)
	end)

	it("does not copy the previous build's Mercenary item set into a new build", function()
		assert(build.mercenaryTab:SetItemSet(build.itemsTab.activeItemSetId, false))
		assert.are.equal(build.itemsTab.activeItemSetId, build.mercenaryTab.itemSetId)
		newBuild()
		assert.is_nil(build.mercenaryTab.itemSetId)
	end)

	it("does not switch the Items view to Mercenary gear when applying actor item sets", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local playerSetId = itemsTab.activeItemSetId
		local mercSetId = build.mercenaryTab.itemSetId
		assert.are.equal(playerSetId, itemsTab.viewItemSetId)
		configTab:ApplyActorItemSets()
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert.are.equal(mercSetId, build.mercenaryTab.itemSetId)
		assert.are.equal(playerSetId, itemsTab.viewItemSetId)
	end)

	it("does not snap Items view away from Mercenary gear when applying actor item sets", function()
		local itemsTab = build.itemsTab
		local mercSet = assert(build.mercenaryTab:GetItemSet(true))
		assert(itemsTab:SetViewItemSet(mercSet.id, "MERCENARY"))
		local playerSetId = itemsTab.activeItemSetId
		build.configTab:ApplyActorItemSets()
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert.are.equal(mercSet.id, itemsTab.viewItemSetId)
		assert.are.equal("MERCENARY", itemsTab.viewComparisonActor)
		assert.are.equal(mercSet.id, build.mercenaryTab.itemSetId)
	end)

	it("does not clear Mercenary comparison when applying config on a shared item set", function()
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		assert(build.mercenaryTab:SetItemSet(playerSetId, false))
		assert(itemsTab:SetViewItemSet(playerSetId, "MERCENARY"))
		build.configTab:ApplyActorItemSets()
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert.are.equal(playerSetId, itemsTab.viewItemSetId)
		assert.are.equal("MERCENARY", itemsTab.viewComparisonActor)
		assert.are.equal(playerSetId, build.mercenaryTab.itemSetId)
	end)

	it("keeps Items on Mercenary gear when switching config sets", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local mercSet = assert(build.mercenaryTab:GetItemSet(true))
		assert(itemsTab:SetViewItemSet(mercSet.id, "MERCENARY"))
		local originalPlayerId = itemsTab.activeItemSetId
		local mapping = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(mapping)
		local altPlayer = itemsTab:NewItemSet()
		altPlayer.title = "Bossing"
		table.insert(itemsTab.itemSetOrderList, altPlayer.id)
		local bossing = configTab:NewConfigSet()
		table.insert(configTab.configSetOrderList, bossing.id)
		configTab:EnsureActorConfig(bossing)
		bossing.actors.player.itemSetId = altPlayer.id
		bossing.actors.mercenary.itemSetId = mercSet.id
		configTab:SetActiveConfigSet(bossing.id)
		assert.are.equal(altPlayer.id, itemsTab.activeItemSetId)
		assert.are.equal(mercSet.id, itemsTab.viewItemSetId)
		assert.are.equal("MERCENARY", itemsTab.viewComparisonActor)
		assert.are.equal(originalPlayerId, mapping.actors.player.itemSetId)
	end)

	it("equips the player from Config without taking Items comparison context", function()
		local MercenaryTools = require("Modules/MercenaryTools")
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local playerSetId = itemsTab.activeItemSetId
		local altPlayer = itemsTab:NewItemSet()
		altPlayer.title = "Config Wear"
		table.insert(itemsTab.itemSetOrderList, altPlayer.id)
		assert(itemsTab:SetViewItemSet(playerSetId, "PLAYER"))
		configTab:SetViewActor("player")
		configTab:UpdateActorItemSetSelect()
		configTab.controls.itemSetSelect.selFunc(nil, { id = altPlayer.id })
		assert.are.equal(altPlayer.id, itemsTab.activeItemSetId)
		assert.are.equal(playerSetId, itemsTab.viewItemSetId)
		assert.are.equal("PLAYER", MercenaryTools.comparisonActorForItemSet(playerSetId, itemsTab))
	end)

	it("writes actor-scoped options to the viewed actor", function()
		local configTab = build.configTab
		local configSet = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(configSet)
		configTab:SetViewActor("mercenary")
		configTab:SetConfigValue("usePowerCharges", true)
		assert.is_true(configSet.actors.mercenary.input.usePowerCharges)
		assert.is_not_true(configSet.input.usePowerCharges)
		configTab:SetViewActor("player")
		configTab:SetConfigValue("usePowerCharges", true)
		assert.is_true(configSet.input.usePowerCharges)
	end)

	it("equips the viewed actor from the Config item set dropdown", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local altPlayer = itemsTab:NewItemSet()
		altPlayer.title = "Config Wear"
		table.insert(itemsTab.itemSetOrderList, altPlayer.id)
		configTab:UpdateActorItemSetSelect()
		configTab.controls.itemSetSelect.selFunc(nil, { id = altPlayer.id })
		assert.are.equal(altPlayer.id, itemsTab.activeItemSetId)
		assert.are.equal(altPlayer.id, configTab.configSets[configTab.activeConfigSetId].actors.player.itemSetId)
	end)

	it("equips the Mercenary from Config without taking Items comparison context", function()
		local MercenaryTools = require("Modules/MercenaryTools")
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local playerSetId = itemsTab.activeItemSetId
		local viewItemSetId = itemsTab.viewItemSetId
		configTab:SetViewActor("mercenary")
		configTab:UpdateActorItemSetSelect()
		configTab.controls.itemSetSelect.selFunc(nil, { id = playerSetId })
		assert.are.equal(playerSetId, build.mercenaryTab.itemSetId)
		assert.are.equal(viewItemSetId, itemsTab.viewItemSetId)
		assert.is_nil(itemsTab.viewComparisonActor)
		assert.are.equal("PLAYER", MercenaryTools.comparisonActorForItemSet(playerSetId, itemsTab))
	end)

	it("saves mercenary actor config separately from the player", function()
		local configTab = build.configTab
		local configSet = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(configSet)
		configSet.customModsList[1].text = "10% increased Damage"
		configSet.actors.mercenary.customModsList[1].text = "20% increased Damage"
		configSet.actors.mercenary.input.usePowerCharges = true
		configTab.input.enemyIsBoss = "Uber"
		local xml = { elem = "Config" }
		configTab:Save(xml)
		local configSetNode = xml[1]
		assert.are.equal("ConfigSet", configSetNode.elem)
		local actorIds, mercenaryMods, sharedBoss = { }, nil, nil
		for _, child in ipairs(configSetNode) do
			if child.elem == "Actor" then
				actorIds[child.attrib.id] = child
				if child.attrib.id == "mercenary" then
					for _, grand in ipairs(child) do
						if grand.elem == "CustomModifierBlock" then
							mercenaryMods = grand[1]
						end
					end
				end
			elseif child.elem == "Input" and child.attrib.name == "enemyIsBoss" then
				sharedBoss = child.attrib.string
			end
		end
		assert.is_not_nil(actorIds.player)
		assert.is_not_nil(actorIds.mercenary)
		assert.are.equal("20% increased Damage", mercenaryMods)
		assert.are.equal("Uber", sharedBoss)
	end)

	it("reloads mercenary actor config from saved XML", function()
		local configTab = build.configTab
		local configSet = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.customModsList[1].text = "20% increased Damage"
		configSet.actors.mercenary.input.usePowerCharges = true
		configTab.input.enemyIsBoss = "Uber"
		local xml = { elem = "Config" }
		configTab:Save(xml)

		newBuild()
		selectScionLuminary()
		configureMercenary()
		build.configTab:Load(xml, "actor-config.xml")
		build.configTab:PostLoad()
		local loaded = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(loaded)
		assert.are.equal("Uber", loaded.input.enemyIsBoss)
		assert.is_true(loaded.actors.mercenary.input.usePowerCharges)
		assert.are.equal("20% increased Damage", loaded.actors.mercenary.customModsList[1].text)
	end)

	it("keeps the previous config set's player item set when a loadout applies a named item set", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local mapping = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(mapping)
		local originalPlayerId = itemsTab.activeItemSetId
		local originalMercId = build.mercenaryTab.itemSetId

		local altPlayer = itemsTab:NewItemSet()
		altPlayer.title = "Bossing"
		table.insert(itemsTab.itemSetOrderList, altPlayer.id)
		local bossing = configTab:NewConfigSet()
		bossing.title = "Bossing"
		table.insert(configTab.configSetOrderList, bossing.id)
		configTab:EnsureActorConfig(bossing)
		local altMerc = itemsTab:NewItemSet()
		altMerc.title = "Merc Bossing"
		table.insert(itemsTab.itemSetOrderList, altMerc.id)
		bossing.actors.mercenary.itemSetId = altMerc.id

		configTab:SetActiveConfigSet(bossing.id, false, { player = false })
		itemsTab:SetActiveItemSet(altPlayer.id)

		assert.are.equal(originalPlayerId, mapping.actors.player.itemSetId)
		assert.are.equal(originalMercId, mapping.actors.mercenary.itemSetId)
		assert.are.equal(altPlayer.id, itemsTab.activeItemSetId)
		assert.are.equal(altPlayer.id, bossing.actors.player.itemSetId)
		assert.are.equal(altMerc.id, build.mercenaryTab.itemSetId)
	end)

	it("fills missing item-set ids from live gear after loading a legacy config", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local xml = {
			elem = "Config",
			attrib = { activeConfigSet = "1" },
			{
				elem = "ConfigSet",
				attrib = { id = "1", title = "Mapping" },
				{ elem = "Input", attrib = { name = "usePowerCharges", boolean = "true" } },
			},
			{
				elem = "ConfigSet",
				attrib = { id = "2", title = "Bossing" },
			},
		}
		configTab:Load(xml, "legacy-config.xml")

		local altPlayer = itemsTab:NewItemSet()
		altPlayer.title = "Worn"
		table.insert(itemsTab.itemSetOrderList, altPlayer.id)
		itemsTab.skipConfigItemSetSync = true
		itemsTab:SetActiveItemSet(altPlayer.id)
		itemsTab.skipConfigItemSetSync = false
		configTab:PostLoad()

		local mapping = configTab.configSets[1]
		local bossing = configTab.configSets[2]
		configTab:EnsureActorConfig(mapping)
		configTab:EnsureActorConfig(bossing)
		assert.are.equal(altPlayer.id, itemsTab.activeItemSetId)
		assert.are.equal(altPlayer.id, mapping.actors.player.itemSetId)
		assert.are.equal(altPlayer.id, bossing.actors.player.itemSetId)
		assert.is_true(mapping.input.usePowerCharges)
	end)

	it("keeps XML actor item-set ids as the source of truth after Items load", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local mappingSet = itemsTab.activeItemSetId
		local bossingSet = itemsTab:NewItemSet()
		bossingSet.title = "Boss Gear"
		table.insert(itemsTab.itemSetOrderList, bossingSet.id)

		local xml = {
			elem = "Config",
			attrib = { activeConfigSet = "1" },
			{
				elem = "ConfigSet",
				attrib = { id = "1", title = "Mapping" },
				{ elem = "Actor", attrib = { id = "player", itemSetId = tostring(mappingSet) } },
				{ elem = "Actor", attrib = { id = "mercenary" } },
			},
			{
				elem = "ConfigSet",
				attrib = { id = "2", title = "Bossing" },
				{ elem = "Actor", attrib = { id = "player", itemSetId = tostring(bossingSet.id) } },
				{ elem = "Actor", attrib = { id = "mercenary" } },
			},
		}
		configTab:Load(xml, "actor-ids.xml")
		itemsTab.skipConfigItemSetSync = true
		itemsTab:SetActiveItemSet(mappingSet)
		itemsTab.skipConfigItemSetSync = false
		configTab:PostLoad()

		assert.are.equal(mappingSet, configTab.configSets[1].actors.player.itemSetId)
		assert.are.equal(bossingSet.id, configTab.configSets[2].actors.player.itemSetId)
		assert.are.equal(mappingSet, itemsTab.activeItemSetId)
		configTab:SetActiveConfigSet(2)
		assert.are.equal(bossingSet.id, itemsTab.activeItemSetId)
	end)

	it("saves mercenary combat values that match the player placeholder", function()
		local configTab = build.configTab
		local configSet = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(configSet)
		configSet.placeholder.meleeDistance = 15
		configSet.actors.mercenary.input.meleeDistance = 15
		local xml = { elem = "Config" }
		configTab:Save(xml)
		local saved
		for _, child in ipairs(xml[1]) do
			if child.elem == "Actor" and child.attrib.id == "mercenary" then
				for _, grand in ipairs(child) do
					if grand.elem == "Input" and grand.attrib.name == "meleeDistance" then
						saved = tonumber(grand.attrib.number)
					end
				end
			end
		end
		assert.are.equal(15, saved)
	end)

	it("writes the loadout player item set even when it is already equipped", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local mapping = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(mapping)
		local equippedId = itemsTab.activeItemSetId
		local bossingSet = itemsTab:NewItemSet()
		bossingSet.title = "Bossing"
		table.insert(itemsTab.itemSetOrderList, bossingSet.id)
		local bossing = configTab:NewConfigSet()
		bossing.title = "Bossing"
		table.insert(configTab.configSetOrderList, bossing.id)
		configTab:EnsureActorConfig(bossing)
		bossing.actors.player.itemSetId = bossingSet.id

		configTab:SetActiveConfigSet(bossing.id, false, { player = false })
		itemsTab:SetActiveItemSet(equippedId)

		assert.are.equal(equippedId, bossing.actors.player.itemSetId)
		assert.are.equal(equippedId, mapping.actors.player.itemSetId)
	end)

	it("applies enemy stack config once", function()
		build.configTab:BuildModList()
		local shockMods = 0
		for _, mod in ipairs(build.configTab.enemyModList) do
			if mod.name == "Multiplier:ShockStacks" then
				shockMods = shockMods + 1
			end
		end
		assert.are.equal(1, shockMods)
	end)

	it("classifies skill options as actor-scoped and enemy wither stacks as shared", function()
		local ConfigScope = require("Modules/ConfigScope")
		assert.are.equal("actor", ConfigScope.forVar("VigilantStrikeBypassCD"))
		assert.are.equal("actor", ConfigScope.forVar("toxicRainPodOverlap"))
		assert.are.equal("actor", ConfigScope.forVar("detonateDeadCorpseLife"))
		assert.are.equal("shared", ConfigScope.forVar("multiplierWitheredStackCount"))
		assert.are.equal("player", ConfigScope.forVar("resistancePenalty"))
		assert.are.equal("player", ConfigScope.forVar("pantheonMajorGod"))
		assert.are.equal("player", ConfigScope.forVar("pantheonMinorGod"))
		assert.are.equal("player", ConfigScope.forVar("bandit"))
		assert.are.equal("actor", ConfigScope.forVar("conditionEnemyChilledByYourHits"))
		assert.are.equal("actor", ConfigScope.forVar("multiplierChilledByYouSeconds"))
		assert.are.equal("actor", ConfigScope.forVar("multiplierFrozenByYouSeconds"))
		assert.are.equal("source", ConfigScope.enemyStateForVar("conditionEnemyChilledByYourHits"))
		assert.are.equal("source", ConfigScope.enemyStateForVar("multiplierChilledByYouSeconds"))
		assert.are.equal("source", ConfigScope.enemyStateForVar("multiplierFrozenByYouSeconds"))
		assert.are.equal("encounter", ConfigScope.enemyStateForVar("conditionEnemyChilled"))
		assert.are.equal("encounter", ConfigScope.enemyStateForVar("multiplierWitheredStackCount"))
		assert.are.equal("actor", ConfigScope.forVar("conditionBetweenYouAndLinkedTarget"))
		assert.are.equal("actor", ConfigScope.forVar("conditionNearLinkedTarget"))
		assert.are.equal("actor", ConfigScope.forVar("conditionChampionIntimidate"))
		assert.are.equal("source", ConfigScope.enemyStateForVar("conditionBetweenYouAndLinkedTarget"))
		assert.are.equal("source", ConfigScope.enemyStateForVar("conditionChampionIntimidate"))
		assert.are.equal("source", ConfigScope.enemyStateForVar("conditionEnemyLifeHigherThanPlayer"))
		assert.is_true(ConfigScope.isSourceOwnedEnemyTag({ type = "Condition", var = "ChilledByYourHits" }))
		assert.is_true(ConfigScope.isSourceOwnedEnemyTag({ type = "Condition", varList = { "Shocked", "FrozenByYou" } }))
		assert.is_false(ConfigScope.isSourceOwnedEnemyTag({ type = "Condition", var = "Chilled" }))
		assert.is_false(ConfigScope.isSourceOwnedEnemyTag({ type = "SkillName", var = "ChilledByYourHits" }))
		assert.is_true(ConfigScope.impliesChilledByYourHits("ChillEffectIncDamageTaken"))
		assert.is_true(ConfigScope.impliesChilledByYourHits("ChillEffectLessDamageDealt"))
		assert.is_false(ConfigScope.impliesChilledByYourHits("ChillingAreaIncColdDamageTaken"))
		for _, var in ipairs({
			"multiplierNearbyRareOrUniqueEnemies",
			"multiplierRuptureStacks",
			"multiplierWitheredStackCount",
			"multiplierCorrosionStackCount",
			"multiplierEnsnaredStackCount",
			"overrideBuffBlinded",
			"conditionScorchedEffect",
			"HoarfrostStacks",
			"multiplierBarnacleStacks",
			"conditionBrittleEffect",
			"conditionShockEffect",
			"conditionSapEffect",
			"multiplierEnemyHallowingFlame",
			"maniaDebuffsCount",
		}) do
			assert.are.equal("shared", ConfigScope.forVar(var), var)
		end
		assert.are.equal("actor", ConfigScope.forVar("enemyConditionHitByFireDamage"))
		assert.are.equal("source", ConfigScope.enemyStateForVar("enemyConditionHitByFireDamage"))
		assert.is_true(ConfigScope.isSourceOwnedEnemyTag({ type = "Condition", var = "Ignited", sourceOwned = true }))
		assert.is_true(ConfigScope.isSourceOwnedEnemyTag({ type = "Condition", var = "HitByFireDamage" }))
		assert.is_false(ConfigScope.isSourceOwnedEnemyTag({ type = "Condition", var = "Ignited" }))
		assert.is_nil(ConfigScope.applyWritesToEnemy)
	end)

	it("requires enemy-list config writes to be shared or source-owned", function()
		local ConfigScope = require("Modules/ConfigScope")
		local varList = LoadModule("Modules/ConfigOptions")
		local sourceLines = { }
		local file = assert(io.open("Modules/ConfigOptions.lua", "r"))
		local lineNo = 0
		for line in file:lines() do
			lineNo = lineNo + 1
			sourceLines[lineNo] = line
		end
		file:close()

		local sawWithered = false
		local failures = { }
		for _, varData in ipairs(varList) do
			if varData.var and type(varData.apply) == "function" then
				local info = debug.getinfo(varData.apply, "S")
				local writesEnemy = false
				if info and info.linedefined and info.lastlinedefined then
					for i = info.linedefined, info.lastlinedefined do
						if sourceLines[i] and sourceLines[i]:find("enemyModList:", 1, true) then
							writesEnemy = true
							break
						end
					end
				end
				if writesEnemy then
					if varData.var == "multiplierWitheredStackCount" then
						sawWithered = true
					end
					local scope = ConfigScope.forVar(varData.var)
					local enemyState = ConfigScope.enemyStateForVar(varData.var)
					if not (scope == "shared" or (scope == "actor" and enemyState == "source")) then
						table.insert(failures, varData.var.." (scope="..tostring(scope)..", enemyState="..tostring(enemyState)..")")
					end
				end
			end
		end
		assert.is_true(sawWithered, "scan should observe Withered stacks writing to enemyModList")
		assert.are.same({ }, failures)
	end)

	it("classifies minion-state config as actor-scoped, not player-only", function()
		local ConfigScope = require("Modules/ConfigScope")
		assert.are.equal("actor", ConfigScope.forVar("minionsConditionFullLife"))
		assert.are.equal("actor", ConfigScope.forVar("minionsConditionLowLife"))
		assert.are.equal("actor", ConfigScope.forVar("minionsConditionFullEnergyShield"))
		assert.are.equal("actor", ConfigScope.forVar("minionsConditionCreatedRecently"))
		assert.are.equal("actor", ConfigScope.forVar("minionsConditionLeechingEnergyShield"))
		assert.are.equal("actor", ConfigScope.forVar("minionConditionOnProfaneGround"))
		assert.are.equal("actor", ConfigScope.forVar("minionsUsePowerCharges"))
	end)

	it("stores minion Full Life config on the viewed actor", function()
		local configTab = build.configTab
		local configSet = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(configSet)
		configTab:SetViewActor("mercenary")
		configTab:SetConfigValue("minionsConditionFullLife", true)
		assert.is_true(configSet.actors.mercenary.input.minionsConditionFullLife)
		assert.is_not_true(configSet.input.minionsConditionFullLife)
		configTab:SetViewActor("player")
		configTab:SetConfigValue("minionsConditionFullLife", true)
		assert.is_true(configSet.input.minionsConditionFullLife)
		assert.is_true(configSet.actors.mercenary.input.minionsConditionFullLife)
	end)

	it("hides player-only pantheon options when viewing the Mercenary", function()
		local configTab = build.configTab
		configTab:SetConfigValue("pantheonMajorGod", "TheBrineKing")
		configTab:SetConfigValue("pantheonMinorGod", "Gruthkul")
		configTab:SetConfigValue("bandit", "Alira")
		configTab:SetViewActor("player")
		assert.is_true(configTab.varControls.pantheonMajorGod.shown())
		assert.is_true(configTab.varControls.pantheonMinorGod.shown())
		assert.is_true(configTab.varControls.bandit.shown())
		configTab:SetViewActor("mercenary")
		assert.is_false(configTab.varControls.pantheonMajorGod.shown())
		assert.is_false(configTab.varControls.pantheonMinorGod.shown())
		assert.is_false(configTab.varControls.bandit.shown())
		assert.is_false(configTab.varControls.resistancePenalty.shown())
	end)

	it("clears invalid stored item-set ids without changing valid live gear", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local configSet = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(configSet)
		local liveId = itemsTab.activeItemSetId
		configSet.actors.player.itemSetId = 9999
		configTab:ApplyActorItemSets()
		assert.is_nil(configSet.actors.player.itemSetId)
		assert.are.equal(liveId, itemsTab.activeItemSetId)
	end)

	it("keeps Compare on the player config overlay", function()
		local configTab = build.configTab
		local configSet = configTab.configSets[configTab.activeConfigSetId]
		configTab:EnsureActorConfig(configSet)
		configTab:SetViewActor("mercenary")
		configTab:SetConfigValue("usePowerCharges", true)
		assert.is_true(configSet.actors.mercenary.input.usePowerCharges)
		assert.is_not_true(configTab.input.usePowerCharges)
	end)

	it("applies stored item sets after undoing a Config equipped-set change", function()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local originalId = itemsTab.activeItemSetId
		configTab:AddUndoState()
		local altPlayer = itemsTab:NewItemSet()
		table.insert(itemsTab.itemSetOrderList, altPlayer.id)
		configTab.controls.itemSetSelect.selFunc(nil, { id = altPlayer.id })
		assert.are.equal(altPlayer.id, itemsTab.activeItemSetId)
		configTab:Undo()
		assert.are.equal(originalId, itemsTab.activeItemSetId)
		assert.are.equal(originalId, configTab.configSets[configTab.activeConfigSetId].actors.player.itemSetId)
	end)

	local chilledByHitsMod = "Enemies Chilled by your Hits are Shocked"
	local frozenByYouMod = "Enemies permanently take 5% increased Damage for each second they've ever been Frozen by you, up to a maximum of 50%"

	local function enemyShocked(env)
		return env.enemyDB:GetCondition("Shocked") or env.enemyDB:Flag(nil, "Condition:Shocked")
	end

	local function enemyDamageTaken(env)
		return env.enemyDB:Sum("INC", nil, "DamageTaken")
	end

	it("does not let the player's chilled-by-your-hits config trigger the Mercenary's shocked-if-chilled-by-your-hits mod", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.input.conditionEnemyChilledByYourHits = true
		configSet.actors.mercenary.customModsList[1].text = chilledByHitsMod
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_not_true(enemyShocked(env))
		assert.is_true(env.enemyDB:GetCondition("Chilled") or env.enemyDB:Flag(nil, "Condition:Chilled"))
	end)

	it("lets the Mercenary's own chilled-by-your-hits config shock the enemy for both actors", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.input.conditionEnemyChilledByYourHits = true
		configSet.actors.mercenary.customModsList[1].text = chilledByHitsMod
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_true(enemyShocked(env))
	end)

	it("does not let the Mercenary's chilled-by-your-hits config trigger the player's shocked-if-chilled-by-your-hits mod", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.customModsList[1].text = chilledByHitsMod
		configSet.actors.mercenary.input.conditionEnemyChilledByYourHits = true
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_not_true(enemyShocked(env))
	end)

	it("lets the player's own chilled-by-your-hits config shock the enemy for both actors", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.customModsList[1].text = chilledByHitsMod
		configSet.input.conditionEnemyChilledByYourHits = true
		local env = calculate()
		assert.is_true(enemyShocked(env))
	end)

	it("does not let the player's frozen-by-you seconds apply the Mercenary's frozen-by-you damage taken", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.input.multiplierFrozenByYouSeconds = 10
		local baseline = enemyDamageTaken(calculate())
		configSet.actors.mercenary.customModsList[1].text = frozenByYouMod
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.are.equal(baseline, enemyDamageTaken(env))
	end)

	it("applies the Mercenary's frozen-by-you damage taken from the Mercenary's own freeze seconds", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		local baseline = enemyDamageTaken(calculate())
		configSet.actors.mercenary.input.multiplierFrozenByYouSeconds = 10
		configSet.actors.mercenary.customModsList[1].text = frozenByYouMod
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.are.equal(50, enemyDamageTaken(env) - baseline)
	end)

	it("does not let the Mercenary's frozen-by-you seconds apply the player's frozen-by-you damage taken", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.customModsList[1].text = frozenByYouMod
		configSet.actors.mercenary.input.multiplierFrozenByYouSeconds = 10
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.are.equal(0, enemyDamageTaken(env))
	end)

	it("applies the player's frozen-by-you damage taken from the player's own freeze seconds", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		local baseline = enemyDamageTaken(calculate())
		configSet.customModsList[1].text = frozenByYouMod
		configSet.input.multiplierFrozenByYouSeconds = 10
		local env = calculate()
		assert.are.equal(50, enemyDamageTaken(env) - baseline)
	end)

	local ignitedByYouMod = "Enemies Ignited by you take 20% increased Damage"
	local againstIgnitedMod = "20% increased Damage against Ignited Enemies"

	local function innerEnemyMod(line)
		local mods = assert(modLib.parseMod(line))
		for _, mod in ipairs(mods) do
			if mod.name == "EnemyModifier" and mod.value and mod.value.mod then
				return mod.value.mod
			end
		end
		return mods[1]
	end

	it("marks enemies-ignited-by-you as source-owned without redefining Ignited", function()
		local inner = innerEnemyMod(ignitedByYouMod)
		assert.are.equal("Ignited", inner[1].var)
		assert.is_true(inner[1].sourceOwned)
		assert.are.equal("DamageTaken", inner.name)
	end)

	it("marks other by-you ailment tags as source-owned", function()
		for _, line in ipairs({
			"Enemies Shocked by you take 20% increased Damage",
			"Enemies Poisoned by you take 20% increased Damage",
			"Enemies Frozen by you take 20% increased Damage",
			"Enemies Shocked or Frozen by you take 20% increased Damage",
		}) do
			local inner = innerEnemyMod(line)
			assert.is_true(inner[1].sourceOwned, line)
		end
	end)

	it("does not mark against-ignited damage as source-owned", function()
		local mods = assert(modLib.parseMod(againstIgnitedMod))
		local tag = mods[1][1]
		assert.are.equal("ActorCondition", tag.type)
		assert.are.equal("Ignited", tag.var)
		assert.is_not_true(tag.sourceOwned)
	end)

	it("does not let the player's ignited config apply the Mercenary's ignited-by-you damage taken", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.input.conditionEnemyIgnited = true
		local baseline = enemyDamageTaken(calculate())
		configSet.actors.mercenary.customModsList[1].text = ignitedByYouMod
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.are.equal(baseline, enemyDamageTaken(env))
	end)

	it("does not let the player's shocked config apply the Mercenary's shocked-by-you damage taken", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.input.conditionEnemyShocked = true
		local baseline = enemyDamageTaken(calculate())
		configSet.actors.mercenary.customModsList[1].text = "Enemies Shocked by you take 20% increased Damage"
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.are.equal(baseline, enemyDamageTaken(env))
	end)

	it("applies the player's ignited-by-you damage taken from the shared ignited config", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		local baseline = enemyDamageTaken(calculate())
		configSet.customModsList[1].text = ignitedByYouMod
		configSet.input.conditionEnemyIgnited = true
		local env = calculate()
		assert.are.equal(20, enemyDamageTaken(env) - baseline)
	end)

	it("does not let the player's EE hit-element config set the Mercenary overlay", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.input.enemyConditionHitByFireDamage = true
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_true(env.player.enemySourceDB:GetCondition("HitByFireDamage"))
		assert.is_not_true(env.mercenary.enemySourceDB:GetCondition("HitByFireDamage"))
		assert.is_not_true(env.enemyDB:GetCondition("HitByFireDamage") or env.enemyDB:Flag(nil, "Condition:HitByFireDamage"))
	end)

	it("applies the Mercenary's EE hit-element config only to the Mercenary overlay", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.input.enemyConditionHitByFireDamage = true
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_true(env.mercenary.enemySourceDB:GetCondition("HitByFireDamage"))
		assert.is_not_true(env.player.enemySourceDB:GetCondition("HitByFireDamage"))
	end)

	local curseByYouMod = "Enemies you Curse take 20% increased Damage"

	it("applies enemies-you-curse damage taken from an enabled curse without checking cursed", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.customModsList[1].text = curseByYouMod
		local baseline = enemyDamageTaken(calculate())
		assert.is_not_true(configSet.input.conditionEnemyCursed)
		build.skillsTab:PasteSocketGroup("Despair 20/0  1")
		local env = calculate()
		assert.is_true(env.enemy.modDB.conditions.Cursed)
		assert.are.equal(20, enemyDamageTaken(env) - baseline)
	end)

	it("does not let a Mercenary curse activate the player's enemies-you-curse damage taken", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.customModsList[1].text = curseByYouMod
		local baseline = enemyDamageTaken(calculate())
		local profile = build.mercenaryTab.profile
		profile.classId = "ChaosMinionWitch"
		profile.buildId = "ChaosMinionWitchDot"
		profile.mainSkillId = "BaneMercenary"
		profile.skills = {
			{ id = "BaneMercenary", enabled = true, supports = { } },
			{ id = "TemporalChainsMercenary", enabled = true, count = 1, supports = { } },
		}
		build.mercenaryTab:Changed()
		build.mercenaryTab:GetItemSet(true)
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_true(env.enemy.modDB.conditions.Cursed)
		assert.are.equal(baseline, enemyDamageTaken(env))
	end)

	it("applies the Mercenary's enemies-you-curse damage taken from the Mercenary's own curse", function()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		local profile = build.mercenaryTab.profile
		profile.classId = "ChaosMinionWitch"
		profile.buildId = "ChaosMinionWitchDot"
		profile.mainSkillId = "BaneMercenary"
		profile.skills = {
			{ id = "BaneMercenary", enabled = true, supports = { } },
			{ id = "TemporalChainsMercenary", enabled = true, count = 1, supports = { } },
		}
		build.mercenaryTab:Changed()
		build.mercenaryTab:GetItemSet(true)
		local baseline = enemyDamageTaken(calculate())
		configSet.actors.mercenary.customModsList[1].text = curseByYouMod
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_true(env.enemy.modDB.conditions.Cursed)
		assert.are.equal(20, enemyDamageTaken(env) - baseline)
	end)

	it("applies player EE from a calculated fire hit without HitBy config", function()
		allocate("Elemental Equilibrium")
		build.skillsTab:PasteSocketGroup("Fireball 20/0  1")
		local env = calculate()
		assert.is_true(env.player.enemySourceDB:GetCondition("HitByFireDamage"))
		assert.is_not_true(env.player.enemySourceDB:GetCondition("HitByColdDamage"))
		assert.is_not_true(env.mercenary.enemySourceDB:GetCondition("HitByFireDamage"))
		assert.is_true(env.enemyDB:Flag(nil, "Condition:HasColdExposure") or env.enemy.modDB.conditions.HasColdExposure)
		assert.is_true(env.enemyDB:Flag(nil, "Condition:HasLightningExposure") or env.enemy.modDB.conditions.HasLightningExposure)
		assert.is_not_true(env.enemyDB:Flag(nil, "Condition:HasFireExposure") or env.enemy.modDB.conditions.HasFireExposure)
	end)

	it("drives player and Mercenary EE only from each actor's own calculated hit elements", function()
		allocate("Elemental Equilibrium")
		build.skillsTab:PasteSocketGroup("Arc 20/0  1")
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.customModsList[1].text = "Hits that deal Elemental Damage remove Exposure to those Elements and inflict Exposure to other Elements Exposure inflicted this way applies -25% to Resistances"
		local env = calculate()
		assert.is_not_nil(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_true(env.player.enemySourceDB:GetCondition("HitByLightningDamage"))
		assert.is_not_true(env.player.enemySourceDB:GetCondition("HitByFireDamage"))
		assert.is_true(env.mercenary.enemySourceDB:GetCondition("HitByFireDamage"))
		assert.is_not_true(env.mercenary.enemySourceDB:GetCondition("HitByLightningDamage"))
	end)
end)
