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
end)
