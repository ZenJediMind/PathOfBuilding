describe("Generic item sets for player, Animate Guardian, and Mercenary", function()
	local MercenaryTools = require("Modules/MercenaryTools")

	local function selectScionLuminary()
		for classId, class in pairs(build.spec.tree.classes) do
			if class.name == "Scion" then build.spec:SelectClass(classId) break end
		end
		for ascendClassId, ascendClass in pairs(build.spec.curClass.classes) do
			if ascendClass.name == "Luminary" then build.spec:SelectAscendClass(ascendClassId) break end
		end
	end

	local function findGuardianGem()
		for _, socketGroup in ipairs(build.skillsTab.socketGroupList) do
			for _, gem in ipairs(socketGroup.gemList) do
				local name = gem.nameSpec or (gem.gemData and gem.gemData.name) or (gem.grantedEffect and gem.grantedEffect.name)
				if name == "Animate Guardian" then
					return gem
				end
			end
		end
	end

	local function findCanonicalGuardianItemSet()
		local itemsTab = build.itemsTab
		for _, itemSetId in ipairs(itemsTab.itemSetOrderList) do
			local itemSet = itemsTab.itemSets[itemSetId]
			if itemSet.title == "Animate Guardian" and itemSet.id ~= itemsTab.activeItemSetId then
				return itemSet
			end
		end
	end

	local function makeImportItem(typeLine, inventoryId, itemId)
		return {
			id = itemId or "guardian-helm-1",
			frameType = 0,
			name = "",
			typeLine = typeLine,
			inventoryId = inventoryId,
			ilvl = 10,
			properties = {},
			sockets = {},
			socketedItems = {},
		}
	end

	before_each(function()
		newBuild()
	end)

	it("makes the Items dropdown view a set without wearing it", function()
		local itemsTab = build.itemsTab
		local secondSet = itemsTab:NewItemSet()
		secondSet.title = "Alternate"
		table.insert(itemsTab.itemSetOrderList, secondSet.id)
		local playerHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local otherHelmet = new("Item"):Item("Rarity: Normal\nLeather Cap")
		itemsTab:AddItem(playerHelmet, true)
		itemsTab:AddItem(otherHelmet, true)
		local playerSetId = itemsTab.activeItemSetId
		itemsTab.activeItemSet.Helmet.selItemId = playerHelmet.id
		secondSet.Helmet.selItemId = otherHelmet.id
		itemsTab:PopulateSlots()

		itemsTab.controls.setSelect.selIndex = 2
		itemsTab.controls.setSelect.selFunc(2, secondSet.title)

		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert.are.equal(secondSet.id, itemsTab.viewItemSetId)
		assert.are.equal(otherHelmet.id, itemsTab.slots.Helmet.selItemId)
		assert.are.equal(playerSetId, build.configTab.configSets[build.configTab.activeConfigSetId].actors.player.itemSetId)
	end)

	it("can view another set without changing the player's worn set", function()
		local itemsTab = build.itemsTab
		local secondSet = itemsTab:NewItemSet()
		table.insert(itemsTab.itemSetOrderList, secondSet.id)
		local playerHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local otherHelmet = new("Item"):Item("Rarity: Normal\nLeather Cap")
		itemsTab:AddItem(playerHelmet, true)
		itemsTab:AddItem(otherHelmet, true)
		local playerSetId = itemsTab.activeItemSetId
		itemsTab.activeItemSet.Helmet.selItemId = playerHelmet.id
		secondSet.Helmet.selItemId = otherHelmet.id

		assert(itemsTab:SetViewItemSet(secondSet.id))
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert.are.equal(secondSet.id, itemsTab.viewItemSetId)
		assert.are.equal(otherHelmet.id, itemsTab.slots.Helmet.selItemId)
	end)

	it("keeps the Items dropdown on the viewed set", function()
		local itemsTab = build.itemsTab
		local secondSet = itemsTab:NewItemSet()
		secondSet.title = "Inspected"
		table.insert(itemsTab.itemSetOrderList, secondSet.id)
		assert(itemsTab:SetViewItemSet(secondSet.id))
		assert.are_not.equal(itemsTab.activeItemSetId, itemsTab.viewItemSetId)

		itemsTab:Draw({ x = 0, y = 0, width = 1920, height = 1080 }, { })

		assert.are.equal(2, itemsTab.controls.setSelect.selIndex)
		assert.are.equal(secondSet.id, itemsTab.viewItemSetId)
		assert.are.equal(itemsTab.itemSetOrderList[1], itemsTab.activeItemSetId)
	end)

	it("passes the visible set into item tooltip comparisons", function()
		selectScionLuminary()
		build.mercenaryTab.profile.buildId = "MeleeAOEMarauderFireSlam"
		build.mercenaryTab:Changed()
		local itemsTab = build.itemsTab
		local mercSet = assert(build.mercenaryTab:GetItemSet(true))
		local hoverHelmet = new("Item"):Item("Rarity: Normal\nLeather Cap")
		itemsTab:AddItem(hoverHelmet, true)
		assert(itemsTab:SetViewItemSet(mercSet.id))

		local calcsTab = build.calcsTab
		local originalGetMiscCalculator = calcsTab.GetMiscCalculator
		local captured
		calcsTab.GetMiscCalculator = function(self)
			local calcFunc, calcBase, actorOutputs = originalGetMiscCalculator(self)
			return function(override, useFullDPS)
				captured = override
				return calcFunc(override, useFullDPS)
			end, calcBase, actorOutputs
		end
		local ok, err = pcall(function()
			local tooltip = new("Tooltip"):Tooltip()
			itemsTab:AddItemTooltip(tooltip, hoverHelmet)
			assert.is_not_nil(captured)
			assert.are.equal(mercSet.id, captured.itemSetId)
			assert.are.equal("MERCENARY", captured.comparisonActor)
			assert.are.equal("Helmet", captured.repSlotName)
			assert.are.equal(hoverHelmet, captured.repItem)
		end)
		calcsTab.GetMiscCalculator = originalGetMiscCalculator
		assert(ok, err)
	end)

	it("keeps an equipped two-hand and offhand pair while inspecting a set", function()
		selectScionLuminary()
		build.mercenaryTab.profile.buildId = "MeleeAOEMarauderFireSlam"
		build.mercenaryTab:Changed()
		local itemsTab = build.itemsTab
		local mercSet = assert(build.mercenaryTab:GetItemSet(true))
		local staff = new("Item"):Item("Rarity: Normal\nGnarled Branch")
		local shield = new("Item"):Item("Rarity: Normal\nGoathide Buckler")
		itemsTab:AddItem(staff, true)
		itemsTab:AddItem(shield, true)
		mercSet["Weapon 1"].selItemId = staff.id
		mercSet["Weapon 2"].selItemId = shield.id
		assert(itemsTab:SetViewItemSet(mercSet.id))
		itemsTab:PopulateSlots()

		assert.are.equal(staff.id, mercSet["Weapon 1"].selItemId)
		assert.are.equal(shield.id, mercSet["Weapon 2"].selItemId)
		local weapon2 = itemsTab.slots["Weapon 2"]
		assert.are.equal(shield.id, weapon2.selItemId)
		local listed
		for index, itemId in ipairs(weapon2.items) do
			if itemId == shield.id then
				listed = weapon2.list[index]
				break
			end
		end
		assert.is_not_nil(listed)
		assert.matches(colorCodes.NEGATIVE, listed, nil, true)
	end)

	it("clears an invalid offhand when the player's worn set selects a two-hander", function()
		local itemsTab = build.itemsTab
		local wand = new("Item"):Item("Rarity: Normal\nDriftwood Wand")
		local shield = new("Item"):Item("Rarity: Normal\nGoathide Buckler")
		local staff = new("Item"):Item("Rarity: Normal\nGnarled Branch")
		itemsTab:AddItem(wand, true)
		itemsTab:AddItem(shield, true)
		itemsTab:AddItem(staff, true)
		itemsTab.activeItemSet["Weapon 1"].selItemId = wand.id
		itemsTab.activeItemSet["Weapon 2"].selItemId = shield.id
		itemsTab:PopulateSlots()
		assert.are.equal(itemsTab.activeItemSetId, itemsTab.viewItemSetId)

		itemsTab.slots["Weapon 1"]:SetSelItemId(staff.id, itemsTab:GetVisibleItemSet())
		itemsTab:PopulateSlots()

		assert.are.equal(0, itemsTab.activeItemSet["Weapon 2"].selItemId)
		assert.are.equal(0, itemsTab.slots["Weapon 2"].selItemId)
	end)

	it("lets Mercenary and Animate Guardian use any item set", function()
		selectScionLuminary()
		local itemsTab = build.itemsTab
		local playerSet = itemsTab.activeItemSet
		build.mercenaryTab.profile.buildId = "MeleeAOEMarauderFireSlam"
		build.mercenaryTab:Changed()
		assert(build.mercenaryTab:SetItemSet(playerSet.id))
		assert.are.equal(playerSet.id, build.mercenaryTab.itemSetId)
		assert.are.equal(playerSet, build.mercenaryTab:GetItemSet(false))

		build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1")
		local gem = assert(findGuardianGem())
		gem.skillMinionItemSet = playerSet.id
		gem.skillMinionItemSetCalcs = playerSet.id
		assert.are.equal(playerSet.id, gem.skillMinionItemSet)
	end)

	it("reimports Animate Guardian gear into the gem's referenced set", function()
		local itemsTab = build.itemsTab
		local guardianSet = itemsTab:NewItemSet()
		guardianSet.title = "Animate Guardian"
		table.insert(itemsTab.itemSetOrderList, guardianSet.id)
		local oldHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		itemsTab:AddItem(oldHelmet, true)
		guardianSet.Helmet.selItemId = oldHelmet.id
		build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1")
		runCallback("OnFrame")
		local gem = assert(findGuardianGem())
		gem.skillMinionItemSet = guardianSet.id
		gem.skillMinionItemSetCalcs = guardianSet.id
		local setCountBefore = #itemsTab.itemSetOrderList

		build.importTab:ImportItemsAndSkills({
			level = 12,
			equipment = {
				makeImportItem("Driftwood Wand", "Weapon", "player-weapon-1"),
			},
			guardian = {
				makeImportItem("Leather Cap", "Helm", "fresh-guardian-helm"),
			},
		}, false, true, true)

		assert.are.equal(setCountBefore, #itemsTab.itemSetOrderList)
		local importedHelmet = itemsTab.items[guardianSet.Helmet.selItemId]
		assert.is_not_nil(importedHelmet)
		assert.are.equal("fresh-guardian-helm", importedHelmet.uniqueID)
		assert.are_not.equal(oldHelmet.id, guardianSet.Helmet.selItemId)
	end)

	it("does not import Animate Guardian gear onto the player's worn set", function()
		local itemsTab = build.itemsTab
		local playerHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		itemsTab:AddItem(playerHelmet, true)
		itemsTab.activeItemSet.Helmet.selItemId = playerHelmet.id
		build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1")
		runCallback("OnFrame")
		local gem = assert(findGuardianGem())
		gem.skillMinionItemSet = itemsTab.activeItemSetId
		gem.skillMinionItemSetCalcs = itemsTab.activeItemSetId
		local setCountBefore = #itemsTab.itemSetOrderList

		build.importTab:ImportItemsAndSkills({
			level = 12,
			equipment = {
				makeImportItem("Driftwood Wand", "Weapon", "player-weapon-1"),
			},
			guardian = {
				makeImportItem("Leather Cap", "Helm", "fresh-guardian-helm"),
			},
		}, false, false, true)

		assert.are.equal(playerHelmet.id, itemsTab.activeItemSet.Helmet.selItemId)
		gem = assert(findGuardianGem())
		assert.are.equal(itemsTab.activeItemSetId, gem.skillMinionItemSet)
		assert.are.equal(itemsTab.activeItemSetId, gem.skillMinionItemSetCalcs)
		local guardianSet = assert(findCanonicalGuardianItemSet())
		assert.are_not.equal(itemsTab.activeItemSetId, guardianSet.id)
		local importedHelmet = itemsTab.items[guardianSet.Helmet.selItemId]
		assert.is_not_nil(importedHelmet)
		assert.are.equal("fresh-guardian-helm", importedHelmet.uniqueID)
		local setCountAfterFirst = #itemsTab.itemSetOrderList
		assert.is_true(setCountAfterFirst > setCountBefore)

		build.importTab:ImportItemsAndSkills({
			level = 12,
			equipment = {
				makeImportItem("Driftwood Wand", "Weapon", "player-weapon-2"),
			},
			guardian = {
				makeImportItem("Leather Cap", "Helm", "second-guardian-helm"),
			},
		}, false, false, true)

		assert.are.equal(setCountAfterFirst, #itemsTab.itemSetOrderList)
		assert.are.equal(playerHelmet.id, itemsTab.activeItemSet.Helmet.selItemId)
		gem = assert(findGuardianGem())
		assert.are.equal(itemsTab.activeItemSetId, gem.skillMinionItemSet)
		assert.are.equal(itemsTab.activeItemSetId, gem.skillMinionItemSetCalcs)
		assert.are.equal(guardianSet.id, findCanonicalGuardianItemSet().id)
		assert.are.equal("second-guardian-helm", itemsTab.items[guardianSet.Helmet.selItemId].uniqueID)
	end)

	it("preserves custom Animate Guardian item-set references on reimport", function()
		local itemsTab = build.itemsTab
		local bossSet = itemsTab:NewItemSet()
		bossSet.title = "Boss AG"
		table.insert(itemsTab.itemSetOrderList, bossSet.id)
		local calcsSet = itemsTab:NewItemSet()
		calcsSet.title = "Calcs AG"
		table.insert(itemsTab.itemSetOrderList, calcsSet.id)
		local bossHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local calcsHelmet = new("Item"):Item("Rarity: Normal\nLeather Cap")
		itemsTab:AddItem(bossHelmet, true)
		itemsTab:AddItem(calcsHelmet, true)
		bossSet.Helmet.selItemId = bossHelmet.id
		calcsSet.Helmet.selItemId = calcsHelmet.id
		build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1")
		runCallback("OnFrame")
		local gem = assert(findGuardianGem())
		gem.skillMinionItemSet = bossSet.id
		gem.skillMinionItemSetCalcs = calcsSet.id

		build.importTab:ImportItemsAndSkills({
			level = 12,
			equipment = {
				makeImportItem("Driftwood Wand", "Weapon", "player-weapon-1"),
			},
			guardian = {
				makeImportItem("Leather Cap", "Helm", "fresh-guardian-helm"),
			},
		}, false, false, true)

		gem = assert(findGuardianGem())
		assert.are.equal(bossSet.id, gem.skillMinionItemSet)
		assert.are.equal(calcsSet.id, gem.skillMinionItemSetCalcs)
		assert.are.equal(bossHelmet.id, bossSet.Helmet.selItemId)
		assert.are.equal(calcsHelmet.id, calcsSet.Helmet.selItemId)
		local guardianSet = assert(findCanonicalGuardianItemSet())
		assert.are_not.equal(bossSet.id, guardianSet.id)
		assert.are_not.equal(calcsSet.id, guardianSet.id)
		assert.are.equal("fresh-guardian-helm", itemsTab.items[guardianSet.Helmet.selItemId].uniqueID)
	end)

	it("recognizes an allocated passive jewel socket as equipped", function()
		local spec = build.spec
		local socketNode
		for _, node in pairs(spec.nodes) do
			if node.type == "Socket" then
				socketNode = node
				break
			end
		end
		socketNode = assert(socketNode)
		socketNode.alloc = true
		spec.allocNodes[socketNode.id] = socketNode
		build.itemsTab:UpdateSockets()
		local jewel = new("Item"):Item("Rarity: RARE\nPlain Spark\nCrimson Jewel\nImplicits: 0\n")
		build.itemsTab:AddItem(jewel, true)
		build.itemsTab.sockets[socketNode.id]:SetSelItemId(jewel.id)
		build.itemsTab:PopulateSlots()

		local equippedSlot, equippedSet = build.itemsTab:GetEquippedSlotForItem(jewel)
		assert.are.equal(build.itemsTab.sockets[socketNode.id], equippedSlot)
		assert.is_nil(equippedSet)
		assert.are.equal("Jewel "..socketNode.id, build.itemsTab:GetComparisonSlotNameForItem(jewel))
	end)

	it("loads Mercenary-prefixed slots into generic slots and ignores owner", function()
		local itemsTab = build.itemsTab
		itemsTab.items[9001] = { id = 9001, name = "Legacy Merc Helmet", type = "Helmet", base = { type = "Helmet" }, rarity = "NORMAL" }
		itemsTab.items[9002] = { id = 9002, name = "Legacy AG Helmet", type = "Helmet", base = { type = "Helmet" }, rarity = "NORMAL" }
		itemsTab:Load({
			attrib = { activeItemSet = "1", useSecondWeaponSet = "false" },
			{
				elem = "ItemSet",
				attrib = { id = "1", owner = "Mercenary", title = "Legacy Merc", useSecondWeaponSet = "false" },
				{ elem = "Slot", attrib = { name = MercenaryTools.itemSlotName("Helmet"), itemId = "9001" } },
			},
			{
				elem = "ItemSet",
				attrib = { id = "2", owner = "Animate Guardian", title = "Legacy AG", useSecondWeaponSet = "false" },
				{ elem = "Slot", attrib = { name = "Helmet", itemId = "9002" } },
			},
		})
		assert.is_nil(itemsTab.itemSets[1].owner)
		assert.is_nil(itemsTab.itemSets[2].owner)
		assert.are.equal(9001, itemsTab.itemSets[1].Helmet.selItemId)
		assert.is_nil(itemsTab.itemSets[1][MercenaryTools.itemSlotName("Helmet")])
		assert.are.equal(9002, itemsTab.itemSets[2].Helmet.selItemId)
	end)

	it("does not overwrite existing generic slots when migrating mixed Mercenary keys", function()
		local itemsTab = build.itemsTab
		itemsTab.items[9001] = { id = 9001, name = "Kept Helmet", type = "Helmet", base = { type = "Helmet" }, rarity = "NORMAL" }
		itemsTab.items[9100] = { id = 9100, name = "Prefixed Helmet", type = "Helmet", base = { type = "Helmet" }, rarity = "NORMAL" }
		itemsTab:Load({
			attrib = { activeItemSet = "7", useSecondWeaponSet = "false" },
			{
				elem = "ItemSet",
				attrib = { id = "7", title = "Legacy Active", useSecondWeaponSet = "false" },
				{ elem = "Slot", attrib = { name = "Helmet", itemId = "9001" } },
				{ elem = "Slot", attrib = { name = MercenaryTools.itemSlotName("Helmet"), itemId = "9100" } },
			},
		})
		assert.are.equal(9001, itemsTab.itemSets[7].Helmet.selItemId)
		assert.is_nil(itemsTab.itemSets[7][MercenaryTools.itemSlotName("Helmet")])
	end)

	it("does not write owner on save", function()
		selectScionLuminary()
		build.mercenaryTab.profile.buildId = "MeleeAOEMarauderFireSlam"
		build.mercenaryTab:Changed()
		local mercSet = build.mercenaryTab:GetItemSet(true)
		local xml = { }
		build.itemsTab:Save(xml)
		for _, node in ipairs(xml) do
			if node.elem == "ItemSet" then
				assert.is_nil(node.attrib.owner)
			end
		end
		assert.is_not_nil(mercSet)
	end)

	it("allows Mercenary to wear items from a shared player item set", function()
		selectScionLuminary()
		local itemsTab = build.itemsTab
		build.mercenaryTab.profile.buildId = "MeleeAOEMarauderFireSlam"
		build.mercenaryTab:Changed()
		local helmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		itemsTab:AddItem(helmet, true)
		itemsTab.activeItemSet.Helmet.selItemId = helmet.id
		assert(build.mercenaryTab:SetItemSet(itemsTab.activeItemSetId))
		local valid, reason = MercenaryTools.validateEquippedItem(helmet, "Helmet", {
			profile = build.mercenaryTab.profile,
			mercenaryData = build.mercenaryTab.data,
			itemSet = itemsTab.activeItemSet,
			playerItemSet = itemsTab.activeItemSet,
			items = itemsTab.items,
			playerHasFlag = function() return true end,
		})
		assert.is_true(valid, reason)
	end)
end)
