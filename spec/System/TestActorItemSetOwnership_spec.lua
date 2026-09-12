describe("ItemsTab actor item-set ownership", function()
	local MercenaryTest = dofile("../spec/System/MercenaryTestHelpers.lua")
	local selectScionLuminary = MercenaryTest.selectScionLuminary
	local calculateBuild = MercenaryTest.calculateBuild

	local function hireMercenary()
		MercenaryTest.allocatePermanentHire()
		local profile = build.mercenaryTab.profile
		profile.classId = "MeleeAOEMarauder"
		profile.buildId = "MeleeAOEMarauderFireSlam"
		profile.foundAreaLevel = 68
		profile.mainSkillId = "TectonicSlamFireMercenary"
		profile.skills = { { id = "TectonicSlamFireMercenary", enabled = true, supports = { } } }
		build.mercenaryTab:Changed()
	end

	local function addHelmet(raw)
		local item = new("Item"):Item(raw or "Rarity: Normal\nIron Hat")
		build.itemsTab:AddItem(item, true)
		return item
	end

	before_each(function()
		newBuild()
	end)

	it("lets PLAYER and MERCENARY use different generic item sets", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		assert.are_not.equal(playerSetId, mercSet.id)
		assert.are.equal(playerSetId, itemsTab:GetActorItemSetId("PLAYER"))
		assert.are.equal(mercSet.id, itemsTab:GetActorItemSetId("MERCENARY"))
		assert.are.equal(mercSet, itemsTab:GetActorItemSet("MERCENARY"))
	end)

	it("lets PLAYER and MERCENARY share one generic item set", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		assert(itemsTab:SetActorItemSet("MERCENARY", playerSetId, false))
		assert.are.equal(playerSetId, itemsTab:GetActorItemSetId("PLAYER"))
		assert.are.equal(playerSetId, itemsTab:GetActorItemSetId("MERCENARY"))
	end)

	it("viewing MERCENARY equipment does not change PLAYER's equipped set", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		assert(itemsTab:SetViewItemSet(mercSet.id, "MERCENARY"))
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert.are.equal(mercSet.id, itemsTab.viewItemSetId)
		assert.are.equal("MERCENARY", itemsTab.viewComparisonActor)
	end)

	it("editing a mercenary item through the Items UI updates the MERCENARY item set", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		local helm = addHelmet("Rarity: Normal\nLeather Cap")
		assert(itemsTab:SetViewItemSet(mercSet.id, "MERCENARY"))
		itemsTab.slots.Helmet:SetSelItemId(helm.id)
		itemsTab:AddUndoState()
		assert.are.equal(helm.id, itemsTab:GetActorItemSet("MERCENARY").Helmet.selItemId)
		assert.are.equal(0, itemsTab.activeItemSet.Helmet.selItemId)
	end)

	it("editing a player item updates the PLAYER item set", function()
		local itemsTab = build.itemsTab
		local helm = addHelmet()
		itemsTab:SetViewItemSet(itemsTab.activeItemSetId, "PLAYER")
		itemsTab.slots.Helmet:SetSelItemId(helm.id)
		itemsTab:AddUndoState()
		assert.are.equal(helm.id, itemsTab.activeItemSet.Helmet.selItemId)
	end)

	it("Items undo restores item changes and actor item-set assignments", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		itemsTab:ResetUndo()
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		local helm = addHelmet()
		mercSet.Helmet.selItemId = helm.id
		itemsTab:AddUndoState()
		assert(itemsTab:SetActorItemSet("MERCENARY", playerSetId, false))
		itemsTab:AddUndoState()
		itemsTab:Undo()
		assert.are.equal(mercSet.id, itemsTab:GetActorItemSetId("MERCENARY"))
		assert.are.equal(helm.id, itemsTab.itemSets[mercSet.id].Helmet.selItemId)
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
	end)

	it("Mercenary undo restores profile without creating or deleting item sets", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		local setCount = #itemsTab.itemSetOrderList
		build.mercenaryTab:ResetUndo()
		build.mercenaryTab.profile.foundAreaLevel = 80
		build.mercenaryTab:Changed()
		build.mercenaryTab:Undo()
		assert.are.equal(68, build.mercenaryTab.profile.foundAreaLevel)
		assert.are.equal(mercSet.id, itemsTab:GetActorItemSetId("MERCENARY"))
		assert.are.equal(setCount, #itemsTab.itemSetOrderList)
		assert.is_not_nil(itemsTab.itemSets[mercSet.id])
	end)

	it("Config undo and Config Set switches do not alter actor equipment", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local configTab = build.configTab
		local playerSetId = itemsTab.activeItemSetId
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		configTab:ResetUndo()
		configTab.input.usePowerCharges = true
		configTab:AddUndoState()
		local alt = itemsTab:NewItemSet()
		alt.title = "Later Gear"
		table.insert(itemsTab.itemSetOrderList, alt.id)
		assert(itemsTab:SetActiveItemSet(alt.id, false))
		itemsTab:AddUndoState()
		configTab:Undo()
		assert.are.equal(alt.id, itemsTab.activeItemSetId)
		assert.are.equal(mercSet.id, itemsTab:GetActorItemSetId("MERCENARY"))

		local other = configTab:NewConfigSet(nil, "Bossing")
		table.insert(configTab.configSetOrderList, other.id)
		configTab:SetActiveConfigSet(other.id)
		assert.are.equal(alt.id, itemsTab.activeItemSetId)
		assert.are.equal(mercSet.id, itemsTab:GetActorItemSetId("MERCENARY"))
		assert.is_nil(configTab.configSets[configTab.activeConfigSetId].actors.player.itemSetId)
		assert.is_nil(configTab.configSets[configTab.activeConfigSetId].actors.mercenary.itemSetId)
	end)

	it("blocks deletion of a mercenary-referenced item set", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		local extra = itemsTab:NewItemSet()
		table.insert(itemsTab.itemSetOrderList, extra.id)
		local control = new("ItemSetListControl"):ItemSetListControl(nil, {0,0,350,200}, itemsTab)
		assert.is_false(control:CanDeleteItemSet(mercSet.id))
		assert.is_true(itemsTab:IsItemSetReferenced(mercSet.id))
		assert.is_true(control:CanDeleteItemSet(extra.id) or extra.id ~= itemsTab.activeItemSetId)
	end)

	it("save/load round-trips actor assignments from ItemsTab and migrates old Mercenary XML", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		local helm = addHelmet()
		mercSet.Helmet.selItemId = helm.id
		local itemsXml, mercXml = { elem = "Items" }, { elem = "Mercenary" }
		itemsTab:Save(itemsXml)
		build.mercenaryTab:Save(mercXml)
		local found
		for _, node in ipairs(itemsXml) do
			if node.elem == "ActorItemSet" and node.attrib.actor == "MERCENARY" then
				found = tonumber(node.attrib.itemSetId)
			end
		end
		assert.are.equal(mercSet.id, found)
		assert.is_nil(mercXml.attrib.itemSetId)
		assert.is_nil(mercXml.attrib.auxiliaryItemSetId)

		newBuild()
		build.itemsTab:Load(itemsXml, "items.xml")
		build.mercenaryTab:Load(mercXml)
		build.mercenaryTab:PostLoad()
		assert.are.equal(mercSet.id, build.itemsTab:GetActorItemSetId("MERCENARY"))
		assert.are.equal(helm.raw, build.itemsTab.items[build.itemsTab:GetActorItemSet("MERCENARY").Helmet.selItemId].raw)

		newBuild()
		hireMercenary()
		local migrated = build.itemsTab:NewItemSet()
		migrated.title = "Legacy Merc"
		table.insert(build.itemsTab.itemSetOrderList, migrated.id)
		build.mercenaryTab:Load({
			elem = "Mercenary",
			attrib = { activeMercenarySet = "1", itemSetId = tostring(migrated.id) },
			{ elem = "MercenarySet", attrib = { id = "1", itemSetId = tostring(migrated.id), buildId = "MeleeAOEMarauderFireSlam" } },
		})
		build.mercenaryTab:PostLoad()
		assert.are.equal(migrated.id, build.itemsTab:GetActorItemSetId("MERCENARY"))

		local playerHelm = addHelmet("Rarity: Normal\nIron Hat")
		build.itemsTab.activeItemSet.Helmet.selItemId = playerHelm.id
		build.itemsTab:AddUndoState()
		build.itemsTab:Undo()
		assert.are.equal(migrated.id, build.itemsTab:GetActorItemSetId("MERCENARY"))
		assert.are.equal(0, build.itemsTab.activeItemSet.Helmet.selItemId)
	end)

	it("character import updates player items without hijacking mercenary equipment", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		local mercHat = addHelmet("Rarity: Normal\nLeather Cap")
		mercSet.Helmet.selItemId = mercHat.id
		assert(itemsTab:SetViewItemSet(mercSet.id, "MERCENARY"))
		build.importTab:ImportItemsAndSkills({
			level = 12,
			equipment = { { id = "player-helm", name = "", typeLine = "Iron Hat", frameType = 0, inventoryId = "Helm" } },
		}, false, true, true)
		assert.are.equal(mercSet.id, itemsTab:GetActorItemSetId("MERCENARY"))
		assert.are.equal(mercHat.id, itemsTab:GetActorItemSet("MERCENARY").Helmet.selItemId)
		assert.are.equal(itemsTab.activeItemSetId, itemsTab.viewItemSetId)
		assert.are.equal("PLAYER", itemsTab.viewComparisonActor)
		assert.are.equal("Iron Hat", itemsTab.items[itemsTab.activeItemSet.Helmet.selItemId].name)
	end)

	it("selecting a mercenary build does not create an item set", function()
		hireMercenary()
		assert.is_nil(build.itemsTab:GetActorItemSetId("MERCENARY"))
		assert.are.equal(1, #build.itemsTab.itemSetOrderList)
	end)

	it("saves non-PLAYER actor item-set assignments in sorted actor order", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		local extra = itemsTab:NewItemSet()
		extra.title = "Other Actor"
		table.insert(itemsTab.itemSetOrderList, extra.id)
		itemsTab.actorItemSetIds.PLAYER = itemsTab.activeItemSetId
		itemsTab.actorItemSetIds.ZED = extra.id
		itemsTab.actorItemSetIds.MERCENARY = mercSet.id
		local xml = { }
		itemsTab:Save(xml)
		local actors = { }
		for _, node in ipairs(xml) do
			if node.elem == "ActorItemSet" then
				table.insert(actors, node.attrib.actor)
			end
		end
		assert.are.same({ "MERCENARY", "ZED" }, actors)
	end)

	it("assigns the selected item set to an actor from the item-set manager", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local extra = itemsTab:NewItemSet()
		extra.title = "Merc Gear"
		table.insert(itemsTab.itemSetOrderList, extra.id)
		local manager = new("ItemSetListControl"):ItemSetListControl(nil, { 0, 0, 300, 200 }, itemsTab)
		assert.are.equal("MERCENARY", manager:EquipActorList()[2].id)
		manager.selValue = extra.id
		manager.controls.equipActor:SelByValue("MERCENARY", "id")
		manager.controls.equip.onClick()
		assert.are.equal(extra.id, itemsTab:GetActorItemSetId("MERCENARY"))
		assert.are.equal(extra.id, itemsTab.viewItemSetId)
	end)

	it("UndoHandler restore does not receive a second discarded-state argument", function()
		local itemsTab = build.itemsTab
		local seen
		function itemsTab:RestoreUndoState(state, extra)
			seen = extra
			self.activeItemSetId = state.activeItemSetId
			self.activeItemSet = self.itemSets[self.activeItemSetId]
		end
		itemsTab:ResetUndo()
		itemsTab:AddUndoState()
		itemsTab:Undo()
		assert.is_nil(seen)
	end)

	it("hides weapon set II while editing mercenary equipment", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		assert(itemsTab:SetViewItemSet(mercSet.id, "MERCENARY"))
		assert.is_false(itemsTab.controls.weaponSwap2:IsShown())
		assert.is_false(itemsTab:VisibleUsesSecondWeaponSet())
	end)

	it("routes item-set comparison to the actor that owns or is viewing the set", function()
		hireMercenary()
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		local mercSet = itemsTab:EnsureActorItemSet("MERCENARY")
		local hat = addHelmet()

		assert.are.equal("MERCENARY", itemsTab:ComparisonActorForItemSet(mercSet.id))
		assert.are.equal("PLAYER", itemsTab:ComparisonActorForItemSet(playerSetId))
		assert.are.equal("PLAYER", itemsTab:ComparisonActorForItemSet(999))
		assert.are.equal("MERCENARY", itemsTab:ComparisonActorForSlot("Helmet", mercSet.id))
		assert.are.equal("MERCENARY", itemsTab:ComparisonActorForSlot("Mercenary Helmet", playerSetId))

		assert(itemsTab:SetActorItemSet("MERCENARY", playerSetId, false))
		assert(itemsTab:SetViewItemSet(playerSetId, "MERCENARY"))
		assert.are.equal("MERCENARY", itemsTab:ComparisonActorForItemSet(playerSetId))
		assert.are.equal("MERCENARY", itemsTab:ComparisonActorForSlot("Helmet", playerSetId))
		assert(itemsTab:SetViewItemSet(playerSetId, "PLAYER"))
		assert.are.equal("PLAYER", itemsTab:ComparisonActorForItemSet(playerSetId))
		assert.are.equal("PLAYER", itemsTab:ComparisonActorForSlot("Helmet", playerSetId))

		assert(itemsTab:SetActorItemSet("MERCENARY", mercSet.id, false))
		assert(itemsTab:SetViewItemSet(playerSetId, "PLAYER"))
		local override = itemsTab:ItemCalculationOverride("Helmet", hat, mercSet.id)
		assert.are.equal(mercSet.id, override.itemSetId)
		assert.are.equal("MERCENARY", override.comparisonActor)
		assert.are.equal("Helmet", override.repSlotName)
		assert.are.equal(hat, override.repItem)

		assert.are.equal("PLAYER", itemsTab:ComparisonActorForSlot("Jewel 12345", mercSet.id))
		local jewelOverride = itemsTab:ItemCalculationOverride("Jewel 12345", { name = "jewel" }, mercSet.id)
		assert.is_nil(jewelOverride.itemSetId)
		assert.are.equal("PLAYER", jewelOverride.comparisonActor)
	end)
end)
