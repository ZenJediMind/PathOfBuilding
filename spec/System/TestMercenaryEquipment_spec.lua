describe("Mercenary equipment validation", function()
	local MercenaryTools = require("Modules/MercenaryTools")
	local tab, itemSet, mercenaryItemSet
	local function selectScionLuminary()
		for classId, class in pairs(build.spec.tree.classes) do
			if class.name == "Scion" then build.spec:SelectClass(classId) break end
		end
		for ascendClassId, ascendClass in pairs(build.spec.curClass.classes) do
			if ascendClass.name == "Luminary" then build.spec:SelectAscendClass(ascendClassId) break end
		end
	end

	local function item(fields)
		local value = {
			id = 9001,
			type = "Body Armour",
			rarity = "RARE",
			requirements = { level = 0, str = 0, dex = 0, int = 0 },
			grantedSkills = { },
		}
		for key, fieldValue in pairs(fields or { }) do value[key] = fieldValue end
		return value
	end

	local function selectBuild(buildId, foundAreaLevel)
		tab.profile.buildId = buildId
		tab.profile.foundAreaLevel = foundAreaLevel or 68
		tab:Changed()
		mercenaryItemSet = tab:GetItemSet(true)
	end

	local function showMercenaryEquipment()
		mercenaryItemSet = tab:GetItemSet(true)
		build.itemsTab:SetViewItemSet(mercenaryItemSet.id)
		return mercenaryItemSet
	end

	local function validateEquippedItem(equippedItem, slotName, mercenarySet)
		return MercenaryTools.validateEquippedItem(equippedItem, slotName, {
			profile = tab.profile,
			mercenaryData = tab.data,
			itemSet = mercenarySet or mercenaryItemSet,
			playerItemSet = itemSet,
			items = build.itemsTab.items,
			playerHasFlag = function(flagName) return tab:PlayerFlag(flagName) end,
		})
	end

	local function allocatePassive(name)
		local node = build.spec.tree.ascendancyMap[name]
		if not node then
			for _, candidate in pairs(build.spec.nodes) do
				if candidate.name == name then node = candidate break end
			end
		end
		node = assert(node, name)
		node = build.spec.nodes[node.id] or node
		node.alloc = true
		build.spec.allocNodes[node.id] = node
		-- A Mercenary's equipment permissions are modifiers, so they only reach the tab
		-- once a calculation has rebuilt the modifier database.
		build.spec.modFlag = true
		build.buildFlag = true
		runCallback("OnFrame")
	end

	before_each(function()
		newBuild()
		selectScionLuminary()
		tab = build.mercenaryTab
		itemSet = build.itemsTab.activeItemSet
		mercenaryItemSet = nil
	end)

	it("views Mercenary gear in the same item slots as the player", function()
		local itemsTab = build.itemsTab
		local equipmentSlots = { "Weapon 1", "Weapon 2", "Helmet", "Body Armour", "Gloves", "Boots", "Amulet", "Ring 1", "Ring 2", "Belt" }
		local flaskSlots = { "Flask 1", "Flask 2", "Flask 3", "Flask 4", "Flask 5" }
		selectBuild("MeleeAOEMarauderFireSlam")
		showMercenaryEquipment()
		assert.is_nil(itemsTab.slots["Mercenary Helmet"])
		for _, slotName in ipairs(equipmentSlots) do
			assert.is_true(itemsTab.slots[slotName]:IsShown(), slotName)
		end
		for _, slotName in ipairs(flaskSlots) do
			assert.is_true(itemsTab.slots[slotName]:IsShown(), slotName)
		end
	end)

	it("keeps player passive tree and socket controls anchored to player equipment", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local specSelect = itemsTab.controls.specSelect
		assert.are.equal(itemsTab.slots["Flask 5"], specSelect.anchor.other)
		assert.is_true(specSelect:IsShown())
		local firstSocket
		for _, socket in pairs(itemsTab.sockets) do
			if socket.anchor.other == specSelect then
				firstSocket = socket
				break
			end
		end
		assert.is_not_nil(firstSocket)
		assert.are.equal("^7View item set:", itemsTab.controls.setLabel.label)
	end)

	it("views dedicated Mercenary equipment without displacing player equipment", function()
		local itemsTab = build.itemsTab
		selectBuild("MeleeAOEMarauderFireSlam")
		local mercSet = showMercenaryEquipment()
		local secondSet = itemsTab:NewItemSet()
		table.insert(itemsTab.itemSetOrderList, secondSet.id)
		for id = 9001, 9004 do
			itemsTab.items[id] = item({ id = id, name = "Helmet "..id, type = "Helmet", base = { type = "Helmet" } })
		end
		itemSet.Helmet.selItemId = 9001
		mercSet["Helmet"].selItemId = 9002
		secondSet.Helmet.selItemId = 9003

		itemsTab:SetActiveItemSet(secondSet.id)
		itemsTab:SetViewItemSet(secondSet.id)
		assert.are.equal(9003, itemsTab.slots.Helmet.selItemId)
		assert.are.equal(9002, mercSet["Helmet"].selItemId)
		itemsTab:SetActiveItemSet(itemSet.id)
		assert.are.equal(9001, itemsTab.slots.Helmet.selItemId)
		itemsTab:SetViewItemSet(mercSet.id)
		assert.are.equal(9002, itemsTab.slots["Helmet"].selItemId)
		assert.are.equal(itemSet.id, itemsTab.activeItemSetId)
	end)

	it("edits the visible Mercenary set from shared slot controls", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local mercSet = showMercenaryEquipment()
		local playerHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local mercHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		itemsTab:AddItem(playerHelmet, true)
		itemsTab:AddItem(mercHelmet, true)
		itemsTab.activeItemSet.Helmet.selItemId = playerHelmet.id
		mercSet.Helmet.selItemId = mercHelmet.id
		itemsTab:PopulateSlots()
		itemsTab.slots.Helmet:SetSelItemId(0, itemsTab:GetVisibleItemSet())
		assert.are.equal(playerHelmet.id, itemsTab.activeItemSet.Helmet.selItemId)
		assert.are.equal(0, mercSet.Helmet.selItemId)
	end)

	it("wears any existing item set and rejects missing IDs", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local mercSet = showMercenaryEquipment()
		local playerSetId = itemsTab.activeItemSetId
		assert(itemsTab:SetActiveItemSet(mercSet.id))
		assert.are.equal(mercSet.id, itemsTab.activeItemSetId)
		assert.are.equal(mercSet.id, itemsTab.viewItemSetId)
		assert(itemsTab:SetActiveItemSet(playerSetId))
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert.is_true(not itemsTab:SetActiveItemSet(99999))
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert.is_true(not itemsTab:SetViewItemSet(99999))
		assert.are.equal(playerSetId, itemsTab.viewItemSetId)
	end)

	it("refreshes player item slots only once when switching the active player set", function()
		local itemsTab = build.itemsTab
		local secondSet = itemsTab:NewItemSet()
		table.insert(itemsTab.itemSetOrderList, secondSet.id)
		local populateCount = 0
		local originalPopulate = itemsTab.PopulateSlots
		itemsTab.PopulateSlots = function(tab)
			populateCount = populateCount + 1
			return originalPopulate(tab)
		end
		assert(itemsTab:SetActiveItemSet(secondSet.id))
		itemsTab.PopulateSlots = originalPopulate
		assert.are.equal(1, populateCount)
		assert.are.equal(secondSet.id, itemsTab.activeItemSetId)
		assert.are.equal(secondSet.id, itemsTab.viewItemSetId)
	end)

	it("numbers active Mercenary Abyssal sockets sequentially", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local helmet = item({ id = 9022, name = "Abyssal Helmet", type = "Helmet", base = { type = "Helmet" }, abyssalSocketCount = 1 })
		local belt = item({ id = 9023, name = "Abyssal Belt", type = "Belt", base = { type = "Belt" }, abyssalSocketCount = 1 })
		itemsTab.items[helmet.id] = helmet
		itemsTab.items[belt.id] = belt
		mercenaryItemSet["Helmet"].selItemId = helmet.id
		mercenaryItemSet["Belt"].selItemId = belt.id
		itemsTab:SetViewItemSet(mercenaryItemSet.id)
		assert.are.equal("Abyssal #1", itemsTab.slots["Helmet Abyssal Socket 1"].label)
		assert.are.equal("Abyssal #1", itemsTab.slots["Belt Abyssal Socket 1"].label)
	end)

	it("creates a new item set from Manage and can assign it to the Mercenary", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		local manager = new("ItemSetListControl"):ItemSetListControl(nil, {0, 0, 350, 200}, itemsTab)
		assert.is_table(tab.controls.itemSetManage)
		assert.is_table(manager.controls.copy)
		assert.is_table(manager.controls.delete)
		assert.is_table(manager.controls.new)

		local originalOpenPopup = main.OpenPopup
		local originalClosePopup = main.ClosePopup
		local popup
		main.OpenPopup = function(_, _, _, _, controls) popup = controls end
		main.ClosePopup = function() end
		local ok, err = pcall(function()
			manager.controls.new.onClick()
			popup.edit.buf = "Alternate Equipment"
			popup.save.onClick()
		end)
		main.OpenPopup = originalOpenPopup
		main.ClosePopup = originalClosePopup
		assert.is_true(ok, err)

		local newSetId
		for _, itemSetId in ipairs(itemsTab.itemSetOrderList) do
			if itemsTab.itemSets[itemSetId].title == "Alternate Equipment" then
				newSetId = itemSetId
				break
			end
		end
		assert.is_not_nil(newSetId)
		manager:OnSelClick(isValueInArray(manager.list, newSetId), newSetId, true)
		assert.are.equal(newSetId, itemsTab.viewItemSetId)
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert(tab:SetItemSet(newSetId))
		assert.are.equal(newSetId, tab.itemSetId)
		assert.are.equal(newSetId, itemsTab.viewItemSetId)
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)
		assert.matches("%(Visible%)", manager:GetRowValue(1, isValueInArray(manager.list, newSetId), newSetId))
	end)

	it("views Animate Guardian and Mercenary gear alongside the active player set", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local guardianSet = itemsTab:NewItemSet()
		guardianSet.title = "Animate Guardian"
		table.insert(itemsTab.itemSetOrderList, guardianSet.id)
		local mercSet = showMercenaryEquipment()
		local playerHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local guardianHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local mercHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		itemsTab:AddItem(playerHelmet, true)
		itemsTab:AddItem(guardianHelmet, true)
		itemsTab:AddItem(mercHelmet, true)
		itemSet.Helmet.selItemId = playerHelmet.id
		guardianSet.Helmet.selItemId = guardianHelmet.id
		mercSet["Helmet"].selItemId = mercHelmet.id

		itemsTab:SetViewItemSet(guardianSet.id)
		assert.are.equal(guardianHelmet.id, itemsTab.slots.Helmet.selItemId)
		assert.are.equal(itemSet.id, itemsTab.activeItemSetId)
		itemsTab:SetViewItemSet(mercSet.id)
		assert.are.equal(mercHelmet.id, itemsTab.slots["Helmet"].selItemId)
		assert.are.equal(itemSet.id, itemsTab.activeItemSetId)
		itemsTab:SetViewItemSet(itemSet.id)
		assert.are.equal(playerHelmet.id, itemsTab.slots.Helmet.selItemId)
	end)

	it("persists Mercenary equipment in an owned item set", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local mercSet = showMercenaryEquipment()
		build.itemsTab.items[9001] = item({ id = 9001, name = "Mercenary Helmet", type = "Helmet", base = { type = "Helmet" } })
		mercSet["Helmet"].selItemId = 9001
		local itemsXml = { }
		build.itemsTab:Save(itemsXml)
		local savedItemId
		local savedOwner
		for _, node in ipairs(itemsXml) do
			if node.elem == "ItemSet" and tonumber(node.attrib.id) == mercSet.id then
				savedOwner = node.attrib.owner
				for _, slot in ipairs(node) do
					if slot.attrib and slot.attrib.name == "Helmet" then savedItemId = slot.attrib.itemId end
				end
			end
		end
		assert.are.equal("9001", savedItemId)
		assert.is_nil(savedOwner)
		assert.is_nil(itemsXml.attrib.viewItemSet)
		for _, node in ipairs(itemsXml) do
			if node.elem == "ItemSet" and tonumber(node.attrib.id) == itemSet.id then
				assert.is_nil(node.attrib.owner)
			end
		end
		local mercenaryXml = { }
		tab:Save(mercenaryXml)
		assert.are.equal(tostring(mercSet.id), mercenaryXml.attrib.itemSetId)
	end)

	it("does not overwrite generic slots when loading mixed Mercenary keys", function()
		local itemsTab = build.itemsTab
		itemsTab.items[9001] = { id = 9001, name = "Kept Helmet", type = "Helmet", base = { type = "Helmet" }, rarity = "NORMAL" }
		itemsTab.items[9100] = { id = 9100, name = "Prefixed Helmet", type = "Helmet", base = { type = "Helmet" }, rarity = "NORMAL" }
		itemsTab:Load({
			attrib = { activeItemSet = "7", useSecondWeaponSet = "false" },
			{
				elem = "ItemSet",
				attrib = { id = "7", title = "Legacy Active", useSecondWeaponSet = "false" },
				{ elem = "Slot", attrib = { name = "Helmet", itemId = "9001" } },
				{ elem = "Slot", attrib = { name = "Mercenary Helmet", itemId = "9100" } },
			},
		})
		assert.are.equal(9001, itemsTab.itemSets[7].Helmet.selItemId)
		assert.is_nil(itemsTab.itemSets[7]["Mercenary Helmet"])
		assert.is_nil(itemsTab.itemSets[7].owner)
	end)

	it("selects the Mercenary equipment item set from the Mercenary tab", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local activePlayerSetId = itemsTab.activeItemSetId
		tab:GetItemSet(true)
		local secondSet = itemsTab:NewItemSet()
		secondSet.title = "Alternate Mercenary Equipment"
		table.insert(itemsTab.itemSetOrderList, secondSet.id)
		tab:RefreshControls()

		local secondSetIndex
		for index, value in ipairs(tab.controls.itemSetSelect.list) do
			if value.id == secondSet.id then secondSetIndex = index break end
		end
		assert.is_not_nil(secondSetIndex)
		tab.controls.itemSetSelect:SetSel(secondSetIndex)
		assert.are.equal(secondSet.id, tab.itemSetId)
		assert.are.equal(secondSet.id, itemsTab.viewItemSetId)
		assert.are.equal(activePlayerSetId, itemsTab.activeItemSetId)

		local saved = { }
		tab:Save(saved)
		assert.are.equal(tostring(secondSet.id), saved.attrib.itemSetId)
	end)

	it("finds a dedicated Mercenary set before profile selection", function()
		local mercSet = tab:EnsureItemSet()
		assert.are.equal(mercSet, tab:GetItemSet(true))
	end)

	it("does not replace an invalid explicit Mercenary item set", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local validSet = tab:GetItemSet(false)
		assert.is_table(validSet)
		tab.itemSetId = 99999
		assert.is_nil(tab:GetItemSet(false))
		assert.is_nil(tab:GetItemSet(true))
		assert.is_nil(tab:EnsureItemSet())
		assert.are.equal(99999, tab.itemSetId)
		tab:PostLoad()
		assert.are.equal(99999, tab.itemSetId)
		assert.is_nil(tab:GetItemSet(false))
		assert.are.equal(validSet, build.itemsTab.itemSets[validSet.id])
	end)

	it("keeps a set named Animate Guardian as a normal item set", function()
		local playerSet = build.itemsTab:NewItemSet()
		playerSet.title = "Animate Guardian"
		table.insert(build.itemsTab.itemSetOrderList, playerSet.id)
		local itemsXml = { }
		build.itemsTab:Save(itemsXml)
		build.itemsTab:Load(itemsXml)
		assert.are.equal("Animate Guardian", build.itemsTab.itemSets[playerSet.id].title)
		assert.is_nil(build.itemsTab.itemSets[playerSet.id].owner)
	end)

	it("round-trips the visible actor set without changing the active player set", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local mercSet = showMercenaryEquipment()
		local playerHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local mercHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		itemsTab:AddItem(playerHelmet, true)
		itemsTab:AddItem(mercHelmet, true)
		itemsTab.activeItemSet.Helmet.selItemId = playerHelmet.id
		mercSet["Helmet"].selItemId = mercHelmet.id
		local activePlayerSetId = itemsTab.activeItemSetId
		local itemsXml, mercenaryXml = { }, { }
		itemsTab:Save(itemsXml)
		tab:Save(mercenaryXml)
		itemsTab:Load(itemsXml)
		tab:Load(mercenaryXml)
		assert.are.equal(activePlayerSetId, itemsTab.activeItemSetId)
		assert.are.equal(activePlayerSetId, itemsTab.viewItemSetId)
		assert.is_nil(itemsXml.attrib.viewItemSet)
		for _, node in ipairs(itemsXml) do
			if node.elem == "ItemSet" and tonumber(node.attrib.id) == activePlayerSetId then
				assert.is_nil(node.attrib.owner)
			end
		end
		assert.are.equal(playerHelmet.id, itemsTab.itemSets[activePlayerSetId].Helmet.selItemId)
		assert.are.equal(mercHelmet.id, tab:GetItemSet(true)["Helmet"].selItemId)
	end)

	it("ignores ItemSet owner attributes on load", function()
		local itemsTab = build.itemsTab
		itemsTab:Load({
			attrib = { activeItemSet = "1", useSecondWeaponSet = "false" },
			{
				elem = "ItemSet",
				attrib = { id = "1", owner = "Player", title = "Branch Owner", useSecondWeaponSet = "false" },
			},
		})
		assert.are.equal("Branch Owner", itemsTab.itemSets[1].title)
		assert.is_nil(itemsTab.itemSets[1].owner)
	end)

	it("restores undo view state without substituting another item set", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local mercSet = showMercenaryEquipment()
		local playerSetId = itemsTab.activeItemSetId
		assert(itemsTab:SetViewItemSet(playerSetId))
		local state = itemsTab:CreateUndoState()
		assert(itemsTab:SetViewItemSet(mercSet.id))
		itemsTab:RestoreUndoState(state)
		assert.are.equal(playerSetId, itemsTab.viewItemSetId)
		assert.are.equal(playerSetId, itemsTab.activeItemSetId)

		state.viewItemSetId = nil
		itemsTab:RestoreUndoState(state)
		assert.are.equal(playerSetId, itemsTab.viewItemSetId)
		assert.are.equal(playerSetId, itemsTab.viewItemSet.id)
	end)

	it("formats validity rows for TextListControl", function()
		tab:RefreshErrors()
		assert.is_true(#tab.errors > 0)
		for _, row in ipairs(tab.errors) do
			assert.are.equal(16, row.height)
		end
	end)

	it("applies single, dual, and triple attribute armour rules", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		assert.is_true(validateEquippedItem(item({ requirements = { str = 100, dex = 100 } }), "Body Armour"))
		assert.is_false(validateEquippedItem(item({ requirements = { dex = 100 } }), "Body Armour"))
		assert.is_false(validateEquippedItem(item({ requirements = { str = 1, dex = 1, int = 1 } }), "Body Armour"))

		selectBuild("AurasMinionsTemplarStaff")
		assert.is_true(validateEquippedItem(item({ requirements = { str = 100, int = 100 } }), "Body Armour"))
		assert.is_false(validateEquippedItem(item({ requirements = { str = 100, dex = 1 } }), "Body Armour"))

		selectBuild("MiscScionPhysDot")
		assert.is_true(validateEquippedItem(item({ requirements = { str = 1, dex = 1, int = 1 } }), "Body Armour"))
	end)

	it("enforces the exact 70 percent found-area level boundary", function()
		selectBuild("MeleeAOEMarauderFireSlam", 47)
		assert.is_false(validateEquippedItem(item({ requirements = { level = 68, str = 1 } }), "Body Armour"))
		tab.profile.foundAreaLevel = 48
		assert.is_true(validateEquippedItem(item({ requirements = { level = 68, str = 1 } }), "Body Armour"))
	end)

	it("requires Legendary slot passives and always rejects unique body armour", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		assert.is_false(validateEquippedItem(item({ rarity = "UNIQUE" }), "Body Armour"))
		local helmet = item({ type = "Helmet", rarity = "UNIQUE", requirements = { str = 1 } })
		assert.is_false(validateEquippedItem(helmet, "Helmet"))
		allocatePassive("Legendary Helmets")
		assert.is_true(validateEquippedItem(helmet, "Helmet"))
	end)

	it("applies every Legendary slot permission", function()
		selectBuild("MeleeStrikesMarauderFire")
		local cases = {
			{ "Helmet", "Helmet", "Legendary Helmets", { str = 1 } },
			{ "Gloves", "Gloves", "Legendary Gloves", { str = 1 } },
			{ "Boots", "Boots", "Legendary Boots", { str = 1 } },
			{ "Amulet", "Amulet", "Legendary Amulets" },
			{ "Ring 1", "Ring", "Legendary Rings" },
			{ "Ring 2", "Ring", "Legendary Rings" },
			{ "Belt", "Belt", "Legendary Belts" },
			{ "Weapon 1", "One Handed Sword", "Legendary Arms" },
			{ "Weapon 2", "One Handed Sword", "Legendary Arms" },
		}
		local allocated = { }
		for index, case in ipairs(cases) do
			local unique = item({ id = 9100 + index, type = case[2], rarity = "UNIQUE", requirements = case[4] or { } })
			if not allocated[case[3]] then
				assert.is_false(validateEquippedItem(unique, case[1]))
				allocatePassive(case[3])
				allocated[case[3]] = true
			end
			assert.is_true(validateEquippedItem(unique, case[1]))
		end
	end)

	it("uses exported main-hand, optional off-hand, shield, and quiver rules", function()
		selectBuild("TrapsMinesShadowLightning")
		assert.is_true(validateEquippedItem(item({ type = "Dagger" }), "Weapon 1"))
		assert.is_false(validateEquippedItem(item({ type = "Shield" }), "Weapon 2"))

		selectBuild("MeleeStrikesMarauderFire")
		assert.is_true(validateEquippedItem(item({ type = "Shield" }), "Weapon 2"))
		assert.is_true(validateEquippedItem(item({ type = "One Handed Sword" }), "Weapon 2"))

		selectBuild("AurasMinionsTemplarSmite")
		assert.is_true(validateEquippedItem(item({ type = "Shield" }), "Weapon 2"))
		assert.is_false(validateEquippedItem(item({ type = "Sceptre" }), "Weapon 2"))

		selectBuild("NonEleBowRangerPhys")
		assert.is_true(validateEquippedItem(item({ type = "Bow" }), "Weapon 1"))
		assert.is_true(validateEquippedItem(item({ type = "Quiver" }), "Weapon 2"))
	end)

	it("rejects shared physical item ids", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local shared = item({ type = "Helmet", requirements = { str = 1 } })
		itemSet["Helmet"].selItemId = shared.id
		assert.is_false(validateEquippedItem(shared, "Helmet"))
	end)

	it("accepts items that grant skills or triggers", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local grantedAura = item({ type = "Helmet", id = 9002, requirements = { str = 1 }, grantedSkills = { { skillId = "Anger" } } })
		assert.is_true(validateEquippedItem(grantedAura, "Helmet"))
	end)

	it("detaches Mercenary equipment on reset without deleting the item set", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local mercSet = showMercenaryEquipment()
		build.itemsTab.items[9001] = item({ id = 9001, name = "Mercenary Helmet", type = "Helmet", base = { type = "Helmet" } })
		mercSet["Helmet"].selItemId = 9001
		tab:Reset()
		assert.is_nil(tab.itemSetId)
		assert.are.equal(build.itemsTab.activeItemSetId, build.itemsTab.viewItemSetId)
		assert.are.equal(mercSet, build.itemsTab.itemSets[mercSet.id])
		assert.are.equal(9001, mercSet["Helmet"].selItemId)
	end)

	it("protects the referenced Mercenary set in the item-set manager", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local mercSet = showMercenaryEquipment()
		local manager = new("ItemSetListControl"):ItemSetListControl(nil, { 0, 0, 300, 200 }, build.itemsTab)
		manager.selValue = mercSet.id
		manager.selIndex = isValueInArray(manager.list, mercSet.id)
		assert.is_true(manager.controls.copy.enabled())
		assert.is_false(manager.controls.delete.enabled())
		assert.are.equal("ItemList", manager:GetDragValue(manager.selIndex, mercSet.id))
	end)

	it("keeps a player set active when deleting the adjacent actor set", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local activePlayerSetId = itemsTab.activeItemSetId
		local actorSet = itemsTab:NewItemSet()
		actorSet.title = "Animate Guardian"
		local secondPlayerSet = itemsTab:NewItemSet()
		itemsTab.itemSetOrderList = { actorSet.id, activePlayerSetId, secondPlayerSet.id }
		local manager = new("ItemSetListControl"):ItemSetListControl(nil, { 0, 0, 300, 200 }, itemsTab)
		local originalOpenConfirmPopup = main.OpenConfirmPopup
		main.OpenConfirmPopup = function(_, _, _, _, onConfirm)
			onConfirm()
		end
		local ok, errorMessage = pcall(function()
			manager:OnSelDelete(isValueInArray(manager.list, activePlayerSetId), activePlayerSetId)
		end)
		main.OpenConfirmPopup = originalOpenConfirmPopup
		assert.is_true(ok, errorMessage)
		assert.are.equal(secondPlayerSet.id, itemsTab.activeItemSetId)
		assert.are.equal(secondPlayerSet, itemsTab.activeItemSet)
	end)

	it("does not delete the last remaining item set", function()
		local itemsTab = build.itemsTab
		local extraSet = itemsTab:NewItemSet()
		itemsTab.itemSetOrderList = { itemsTab.activeItemSetId, extraSet.id }
		local manager = new("ItemSetListControl"):ItemSetListControl(nil, { 0, 0, 300, 200 }, itemsTab)
		manager.selValue = extraSet.id
		assert.is_true(manager.controls.delete.enabled())
		table.remove(itemsTab.itemSetOrderList, 2)
		manager.selValue = itemsTab.activeItemSetId
		assert.is_false(manager.controls.delete.enabled())
	end)

	it("shares the dragged set's equipped items, not the currently visible slots", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local playerSet = itemsTab.activeItemSet
		local mercSet = showMercenaryEquipment()
		local playerItem = new("Item"):Item("Rarity: Normal\nIron Hat")
		local mercItem = new("Item"):Item("Rarity: Normal\nLeather Cap")
		itemsTab:AddItem(playerItem, true)
		itemsTab:AddItem(mercItem, true)
		playerSet.Helmet.selItemId = playerItem.id
		mercSet.Helmet.selItemId = mercItem.id
		itemsTab:PopulateSlots()

		local sharedList = new("SharedItemSetListControl"):SharedItemSetListControl(nil, { 0, 0, 300, 200 }, itemsTab)
		local sharedSetCount = #sharedList.list
		sharedList:ReceiveDrag("ItemList", playerSet)

		assert.are.equal(sharedSetCount + 1, #sharedList.list)
		local sharedSet = sharedList.list[#sharedList.list]
		assert.are.equal(playerItem.name, sharedSet.slots.Helmet.name)
	end)

	it("imports copied Warrant text into the active loadout", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local mercSet = showMercenaryEquipment()
		local mercenaryHelmet = "Helmet"
		mercSet[mercenaryHelmet].selItemId = 9001
		local warrantText = [[
Item Class: Map Fragments
Rarity: Normal
Mercenary Warrant
--------
Thalia, the Exquisite
--------
Build: Kineticist
Mercenary Level: 83
--------
Elemental Weakness
Greater Curse Effect (Tier: 3)
Faster Casting (Tier: 2)
--------
Right click this item to view Mercenary details.
--------
Note: ~b/o 1 mirror
]]
		tab.controls.importWarrant:Click()
		local popup = main.popups[1]
		assert.are.equal("Import Mercenary Warrant", popup.title)
		popup.controls.edit:SetText(warrantText)
		popup.controls.import:Click()
		assert.are_not.equal(popup, main.popups[1])
		assert.are.equal("Kineticist", tab.data.builds[tab.profile.buildId].name)
		assert.are.equal(83, tab.profile.foundAreaLevel)
		assert.are.equal("Elemental Weakness", tab.data.skills[tab.profile.mainSkillId].name)
		assert.is_true(tab.profile.importedWarrant)
		assert.are.equal(9001, mercSet[mercenaryHelmet].selItemId)
		local xml = { }
		tab:Save(xml)
		assert.are.equal("true", xml[1].attrib.importedWarrant)
		tab:Reset()
		tab:Load(xml)
		assert.is_true(tab.profile.importedWarrant)
		assert.are.equal("Kineticist", tab.data.builds[tab.profile.buildId].name)
	end)

	it("preserves invalid equipped items for diagnostics", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local mercSet = showMercenaryEquipment()
		local invalidHelmet = item({ id = 9015, name = "Invalid Mercenary Helmet", type = "Helmet", base = { type = "Helmet" }, requirements = { int = 1 } })
		build.itemsTab.items[invalidHelmet.id] = invalidHelmet
		build.itemsTab.slots["Helmet"]:SetSelItemId(invalidHelmet.id, build.itemsTab:GetVisibleItemSet())
		build.itemsTab:PopulateSlots()
		assert.are.equal(invalidHelmet.id, mercSet["Helmet"].selItemId)
		assert.matches("Helmet: armour attribute alignment", table.concat(tab:GetErrors(), "\n"))
	end)

	it("offers base-compatible warning items with normal item colors", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		showMercenaryEquipment()
		local invalidHelmet = item({ id = 9018, name = "Selectable Invalid Helmet", type = "Helmet", base = { type = "Helmet" }, requirements = { int = 1 } })
		build.itemsTab.items[invalidHelmet.id] = invalidHelmet
		build.itemsTab:PopulateSlots()
		local helmetSlot = build.itemsTab.slots["Helmet"]
		local candidateIndex
		for index, itemId in ipairs(helmetSlot.items) do
			if itemId == invalidHelmet.id then candidateIndex = index break end
		end
		assert.is_number(candidateIndex)
		assert.matches(colorCodes[invalidHelmet.rarity], helmetSlot.list[candidateIndex], nil, true)
		helmetSlot:SetSelItemId(invalidHelmet.id, build.itemsTab:GetVisibleItemSet())
		build.itemsTab:PopulateSlots()
		assert.are.equal(invalidHelmet.id, helmetSlot.selItemId)
		assert.matches("Helmet: armour attribute alignment", table.concat(tab:GetErrors(), "\n"))
	end)

	it("allows Abyss jewels only in sockets on supported equipment", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local mercSet = showMercenaryEquipment()
		local jewel = item({ id = 9016, name = "Mercenary Abyss Jewel", type = "Jewel", base = { type = "Jewel", subType = "Abyss" }, requirements = { level = 1 } })
		assert.is_false(validateEquippedItem(jewel, "Helmet Abyssal Socket 1"))
		local helmet = item({ id = 9017, name = "Mercenary Abyss Helmet", type = "Helmet", base = { type = "Helmet" }, requirements = { str = 1 }, abyssalSocketCount = 1 })
		build.itemsTab.items[helmet.id] = helmet
		mercSet["Helmet"].selItemId = helmet.id
		assert.is_true(validateEquippedItem(jewel, "Helmet Abyssal Socket 1", mercSet))
		assert.is_false(tab:IsSlotSupported("Jewel 12345"))
	end)

	it("allows Unique Abyss jewels in sockets without equipment permissions", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local mercSet = showMercenaryEquipment()
		local uniqueJewel = item({ id = 9024, name = "Mercenary Unique Abyss Jewel", type = "Jewel", base = { type = "Jewel", subType = "Abyss" }, rarity = "UNIQUE", requirements = { level = 1 } })
		build.itemsTab.items[uniqueJewel.id] = uniqueJewel
		local cases = {
			{ type = "Body Armour", slotName = "Body Armour" },
			{ type = "Helmet", slotName = "Helmet" },
		}
		for index, case in ipairs(cases) do
			local parent = item({ id = 9024 + index, name = "Mercenary Abyss "..case.type, type = case.type, base = { type = case.type }, requirements = { str = 1 }, abyssalSocketCount = 1 })
			build.itemsTab.items[parent.id] = parent
			mercSet[case.slotName].selItemId = parent.id
			assert.is_true(validateEquippedItem(uniqueJewel, case.slotName.." Abyssal Socket 1", mercSet))
		end
	end)

	it("bounds Full DPS count edits in the Mercenary UI", function()
		tab.profile.skills[1] = { id = "InfernalBlowMercenary", enabled = true, supports = { } }
		tab.controls.skillCount.changeFunc("200")
		assert.are.equal(99, tab.profile.skills[1].count)
		tab.controls.skillCount.changeFunc("0")
		assert.are.equal(1, tab.profile.skills[1].count)
	end)

	it("reuses player gem sort options and persists Mercenary preferences", function()
		local skillOptions = require("Modules/SkillOptions")
		assert.are.same(skillOptions.sortGemTypeList, tab.controls.sortGemsByDPSFieldControl.list)
		local xml = { }
		tab.sortGemsByDPS = false
		tab.sortGemsByDPSField = "TotalDPS"
		tab:Save(xml)
		assert.are.equal("false", xml.attrib.sortGemsByDPS)
		assert.are.equal("TotalDPS", xml.attrib.sortGemsByDPSField)
	end)

	it("keeps unlimited Mercenary loadouts independent while sharing equipment", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local mercSet = showMercenaryEquipment()
		local sharedHelmet = "Helmet"
		mercSet[sharedHelmet].selItemId = 9019
		tab.profile.buildId = "MeleeAOEMarauderFireSlam"
		tab.profile.skills = { { id = "InfernalBlowMercenary", enabled = true, supports = { } } }
		tab.profile.mainSkillId = "InfernalBlowMercenary"
		tab.profile.title = "First"
		tab:RefreshControls()

		local firstId = tab.activeMercenarySetId
		for index = 1, 16 do
			local set = tab:NewMercenarySet()
			set.title = "Loadout "..index
			table.insert(tab.mercenarySetOrderList, set.id)
		end
		assert.are.equal(17, #tab.mercenarySetOrderList)
		local manager = new("MercenarySetListControl"):MercenarySetListControl(nil, {0, 0, 350, 200}, tab)
		assert.is_table(manager.controls.copy)
		assert.is_table(manager.controls.delete)

		local secondId = tab.mercenarySetOrderList[2]
		tab:RefreshControls()
		tab.controls.setSelect:SetSel(2)
		assert.are.equal(secondId, tab.activeMercenarySetId)
		tab.profile.buildId = "TrapsMinesShadowLightning"
		tab.profile.foundAreaLevel = 80
		tab.profile.skills = { { id = "LightningTrapMercenary", enabled = true, supports = { } } }
		tab.profile.mainSkillId = "LightningTrapMercenary"
		tab:RefreshControls()
		assert.are.equal(9019, mercSet[sharedHelmet].selItemId)

		tab.controls.setSelect:SetSel(1)
		assert.are.equal("MeleeAOEMarauderFireSlam", tab.profile.buildId)
		assert.are.equal("InfernalBlowMercenary", tab.profile.mainSkillId)
		assert.are.equal(9019, mercSet[sharedHelmet].selItemId)

		local xml = { }
		tab:Save(xml)
		assert.are.equal("1", xml.attrib.activeMercenarySet)
		local savedSetCount = 0
		for _, child in ipairs(xml) do
			if child.elem == "MercenarySet" then savedSetCount = savedSetCount + 1 end
		end
		assert.are.equal(17, savedSetCount)

		tab:Load(xml)
		assert.are.equal(17, #tab.mercenarySetOrderList)
		assert.are.equal(firstId, tab.activeMercenarySetId)
		assert.are.equal("InfernalBlowMercenary", tab.profile.mainSkillId)
		assert.are.equal(9019, mercSet[sharedHelmet].selItemId)
	end)

	it("matches the player skill tip sizing without exposing Calcs state in row text", function()
		tab.profile.skills[1] = { id = "ConsecratedPathMercenary", enabled = true, supports = { } }
		tab.profile.mainSkillId = "ConsecratedPathMercenary"
		tab:RefreshControls()
		local row = tab.controls.skillList:GetRowValue(1, 1, tab.profile.skills[1])
		assert.are.equal(14, tab.controls.skillTip.height)
		assert.is_nil(row:find("(Calcs)", 1, true))
	end)

	it("shows player-style stat tooltips for Mercenary skills and supports", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		tab:SetSkill(1, "ConsecratedPathMercenary")
		local expectedSkillColor = data.skillColorMap[build.data.skills.ConsecratedPathMercenary.color]
		local skillRow = tab.controls.skillList:GetRowValue(1, 1, tab.profile.skills[1])
		assert.are.equal(expectedSkillColor, skillRow:sub(1, #expectedSkillColor))
		local skillOption
		for _, option in ipairs(tab.controls.skill.list) do
			if option.id == "ConsecratedPathMercenary" then skillOption = option break end
		end
		assert(skillOption)
		assert.are.equal(expectedSkillColor, skillOption.label:sub(1, #expectedSkillColor))
		local tooltip = new("Tooltip"):Tooltip()
		local function tooltipText()
			local lines = { }
			for _, line in ipairs(tooltip.lines) do if line.text then table.insert(lines, line.text) end end
			return table.concat(lines, "\n")
		end

		tab.controls.skillList:AddValueTooltip(tooltip, 1, tab.profile.skills[1])
		local skillTooltipText = tooltipText()
		assert.matches("Consecrated Path", skillTooltipText)
		assert.matches("Level:", skillTooltipText)
		assert.matches("Slams the ground", skillTooltipText)

		tooltip:Clear(true)
		tab.controls.skill.tooltipFunc(tooltip, "HOVER", 1, { id = "ConsecratedPathMercenary" })
		assert.matches("Consecrated Path", tooltipText())

		tooltip:Clear(true)
		local support = assert(tab.supportControls[1].list[2])
		tab.supportControls[1].tooltipFunc(tooltip, "HOVER", 2, support)
		local supportTooltipText = tooltipText()
		assert.is_true(supportTooltipText:find(tab.data.supports[support.id].name, 1, true) ~= nil)
		assert.is_true(supportTooltipText:find("Mercenary Support, Tier ", 1, true) ~= nil)
		assert.matches("Supported Skills gain", supportTooltipText)
	end)

	it("uses the Mercenary effective level in skill tooltips", function()
		selectBuild("TrapsMinesShadowLightning", 80)
		build.configTab.enemyLevel = 60
		tab:SetSkill(1, "LightningTrapMercenary")
		local tooltip = new("Tooltip"):Tooltip()
		tab.controls.skillList:AddValueTooltip(tooltip, 1, tab.profile.skills[1])
		local displayedLevel
		for _, line in ipairs(tooltip.lines) do
			displayedLevel = displayedLevel or line.text and line.text:match("Level: %^7(%d+)")
		end
		local actorLevel = MercenaryTools.effectiveLevel(80, 60)
		assert.are.equal(MercenaryTools.skillLevel(build.data.skills.LightningTrapMercenary, actorLevel), tonumber(displayedLevel))
	end)

	it("sorts Mercenary supports by the selected DPS output", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		tab:SetSkill(1, "ConsecratedPathMercenary")
		local selected = tab.profile.skills[1]
		local preferredId = tab.supportControls[1].list[2].id
		local originalCalculator = build.calcsTab.GetMiscCalculator
		local ok, err = pcall(function()
			build.calcsTab.GetMiscCalculator = function()
				return function()
					local supportId = selected.supports[1] and selected.supports[1].id
					local dps = supportId == preferredId and 100 or 10
					return { CombinedDPS = dps, FullDPS = dps }
				end
			end
			tab.sortGemsByDPS = true
			tab.sortGemsByDPSField = "CombinedDPS"
			tab:QueueSupportSort(1)
			while tab.supportSortCoroutine do tab:ProcessSupportSort() end
			assert.are.equal(preferredId, tab.supportControls[1].list[1].id)
			assert.is_nil(selected.supports[1])
		end)
		build.calcsTab.GetMiscCalculator = originalCalculator
		assert.is_true(ok, err)
	end)

	it("keeps support selections contiguous", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		assert(tab:SetSkill(1, "ConsecratedPathMercenary"))
		local supportId = assert(tab.data.skills.ConsecratedPathMercenary.possibleSupportIds[1])
		assert(tab:SetSupport(5, supportId))
		assert.are.equal(1, #tab.profile.skills[1].supports)
		assert.are.equal(supportId, tab.profile.skills[1].supports[1].id)
	end)

	it("edits the selected skill group and its supports through the UI", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		tab:RefreshControls()
		tab.controls.skillList.controls.new.onClick()
		assert.are.equal(1, #tab.profile.skills)
		local skillEntry
		for _, candidate in ipairs(tab.controls.skill.list) do
			if candidate.id and #(tab.data.skills[candidate.id].possibleSupportIds or { }) > 0 then skillEntry = candidate break end
		end
		assert(skillEntry)
		tab.controls.skill.selFunc(2, skillEntry)
		assert.are.equal(skillEntry.id, tab.profile.skills[1].id)
		local supportEntry = assert(tab.supportControls[1].list[2])
		tab.supportControls[1].selFunc(2, supportEntry)
		assert.are.equal(supportEntry.id, tab.profile.skills[1].supports[1].id)
		tab.supportControls[1].selFunc(1, tab.supportControls[1].list[1])
		assert.are.equal(0, #tab.profile.skills[1].supports)
	end)

	it("registers Ice Shot support pickers with the Mercenary control host", function()
		selectBuild("EleBowRangerClones")
		assert(tab:SetSkill(1, "IceShotMercenary"))
		assert.is_true(#tab.supportControls[1].list > 1)
		for index = 1, 5 do
			assert.are.equal(tab.supportControls[index], tab.controls["support"..index])
			assert.is_true(tab.supportControls[index]:IsShown())
		end
		assert.is_nil(tab.controls.skillLink)
	end)

	it("does not mutate support slots beyond capacity and keeps persisted extras", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		assert(tab:SetSkill(1, "ConsecratedPathMercenary"))
		assert.is_true(tab.supportControls[3].shown)
		assert.is_true(not tab.supportControls[4].shown)
		local supportId = tab.data.skills.ConsecratedPathMercenary.possibleSupportIds[1]
		local support = tab.data.supports[supportId]
		for index = 1, 4 do tab.profile.skills[1].supports[index] = { id = supportId, tier = support.variant } end
		tab:RefreshControls()
		assert.are.equal(4, #tab.profile.skills[1].supports)
		assert.matches("has more than 3 supports", table.concat(tab:GetErrors(), "\n"))
		local otherId = tab.data.skills.ConsecratedPathMercenary.possibleSupportIds[4]
		assert.is_nil(select(1, tab:SetSupport(4, otherId)))
		assert.are.equal(4, #tab.profile.skills[1].supports)
		assert.are.equal(supportId, tab.profile.skills[1].supports[4].id)
	end)

	it("shows clean Mercenary class and build labels", function()
		tab.profile.classId = "AurasMinionsTemplar"
		tab:RefreshControls()
		for _, entry in ipairs(tab.controls.class.list) do
			assert.not_matches("%[DNT%]", entry.label)
		end
		local labels = { }
		for _, entry in ipairs(tab.controls.build.list) do labels[entry.id] = entry.label end
		assert.are.equal("Warpriest", labels.AurasMinionsTemplarSmite)
		assert.are.equal("Infamous Warpriest", labels.AurasMinionsTemplarSmiteNoble)
	end)

	it("does not add a zero-capacity data skill through New", function()
		tab.profile.classId = "Crit1HShadow"
		tab.profile.buildId = "Crit1HShadowSpectral"
		tab:RefreshControls()
		assert.is_true(not tab.controls.skillList.controls.new.enabled())
		tab.controls.skillList.controls.new.onClick()
		assert.are.equal(0, #tab.profile.skills)
	end)

	it("does not create more than six skills through New", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		tab:RefreshControls()
		for _ = 1, 7 do tab.controls.skillList.controls.new.onClick() end
		assert.are.equal(6, #tab.profile.skills)
		assert.is_true(not tab.controls.skillList.controls.new.enabled())
	end)

	it("keeps a malformed XML fixture for diagnosis and blocks calculation", function()
		local skillIds = { }
		for _, skillId in ipairs(tab.data.builds.MeleeAOEMarauderFireSlam.skillIds) do
			table.insert(skillIds, skillId)
			if #skillIds == 7 then break end
		end
		local setNode = {
			elem = "MercenarySet",
			attrib = {
				id = "1",
				buildId = "MeleeAOEMarauderFireSlam",
				foundAreaLevel = "68",
				mainSkillId = skillIds[1],
			},
		}
		for _, skillId in ipairs(skillIds) do
			table.insert(setNode, { elem = "Skill", attrib = { id = skillId, enabled = "true" } })
		end
		local mercenaryXml = { attrib = { }, setNode }
		tab:Load(mercenaryXml)
		assert.are.equal(7, #tab.profile.skills)
		for index, skillId in ipairs(skillIds) do
			assert.are.equal(skillId, tab.profile.skills[index].id)
		end

		local mercSet = tab:GetItemSet(true)
		local uniqueBody = new("Item"):Item("Rarity: Unique\nIllegal Unique Body\nPlate Vest")
		build.itemsTab:AddItem(uniqueBody, true)
		mercSet["Body Armour"].selItemId = uniqueBody.id

		local itemsXml, savedMercenary = { }, { }
		build.itemsTab:Save(itemsXml)
		tab:Save(savedMercenary)
		newBuild()
		selectScionLuminary()
		tab = build.mercenaryTab
		build.itemsTab:Load(itemsXml)
		tab:Load(savedMercenary)
		tab:PostLoad()

		assert.are.equal(7, #tab.profile.skills)
		for index, skillId in ipairs(skillIds) do
			assert.are.equal(skillId, tab.profile.skills[index].id)
		end
		assert.are.equal(uniqueBody.id, tab:GetItemSet(true)["Body Armour"].selItemId)
		local errors = table.concat(tab:GetErrors(), "\n")
		assert.matches("cannot have more than 6", errors)
		assert.matches("Body Armour", errors)
		assert.is_true(not tab.controls.skillList.controls.new.enabled())
		tab:AddSkill()
		assert.are.equal(7, #tab.profile.skills)

		build.configTab.input.enemyLevel = 83
		build.configTab:BuildModList()
		build.spec.modFlag = true
		build.buildFlag = true
		runCallback("OnFrame")
		runCallback("OnFrame")
		assert.is_nil(build.calcsTab.mainEnv.mercenary)
		assert.matches("cannot have more than 6", table.concat(build.calcsTab.mainEnv.mercenaryCalculationErrors or { }, "\n"))
	end)

	it("rejects duplicate and pool-invalid skill edits without mutating", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		assert(tab:SetSkill(1, "InfernalCryMercenary"))
		assert.is_nil(select(1, tab:SetSkill(2, "InfernalCryMercenary")))
		assert.are.equal(1, #tab.profile.skills)
		assert(tab:SetSkill(2, "FissureSlamMercenary"))
		assert.is_nil(select(1, tab:SetSkill(3, "TectonicSlamFireMercenary")))
		assert.are.equal(2, #tab.profile.skills)
		assert.are.equal("FissureSlamMercenary", tab.profile.skills[2].id)
	end)

	it("keeps the selected Calcs skill consistent with skill-row edits", function()
		assert.is_nil(tab.controls.skillMain)
		assert.is_nil(tab.controls.skillMainLabel)
		selectBuild("MeleeAOEMarauderFireSlam")
		assert(tab:SetSkill(1, "InfernalCryMercenary"))
		assert.are.equal("InfernalCryMercenary", tab.profile.mainSkillId)
		assert(tab:SetSkill(1, "FissureSlamMercenary"))
		assert.are.equal("FissureSlamMercenary", tab.profile.mainSkillId)
		assert(tab:SetSkill(1, nil))
		assert.is_nil(tab.profile.mainSkillId)
	end)

	it("does not allocate a Mercenary item set when changing a support", function()
		tab.profile.buildId = "MeleeAOEMarauderFireSlam"
		tab.profile.classId = "MeleeAOEMarauder"
		tab.profile.skills = { { id = "FissureSlamMercenary", enabled = true, supports = { } } }
		tab.profile.mainSkillId = "FissureSlamMercenary"
		local before = #build.itemsTab.itemSetOrderList
		assert(tab:SetSupport(1, "FistOfWarHigh"))
		assert.are.equal(before, #build.itemsTab.itemSetOrderList)
		assert.are.equal("FistOfWarHigh", tab.profile.skills[1].supports[1].id)
	end)

	it("restores support selections when preview comparison fails", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		assert(tab:SetSkill(1, "FissureSlamMercenary"))
		local skill = tab.profile.skills[1]
		skill.supports = { { id = "AddedFireHigh", tier = 3 } }
		local original = copyTable(skill.supports, true)
		local originalGet = build.calcsTab.GetMiscCalculator
		build.calcsTab.GetMiscCalculator = function() error("preview boom") end
		local support = assert(tab.data.supports.FistOfWarHigh)
		assert.has_error(function()
			tab:AddSupportTooltip(new("Tooltip"):Tooltip(), support, 1, true)
		end)
		build.calcsTab.GetMiscCalculator = originalGet
		assert.same(original, skill.supports)
	end)

	it("surfaces support-sort failures without caching them", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		assert(tab:SetSkill(1, "FissureSlamMercenary"))
		tab.sortGemsByDPS = true
		tab:RefreshSupportLists()
		local originalGet = build.calcsTab.GetMiscCalculator
		build.calcsTab.GetMiscCalculator = function() error("sort boom") end
		tab:QueueSupportSort(1)
		assert.has_error(function()
			tab:ProcessSupportSort()
		end)
		build.calcsTab.GetMiscCalculator = originalGet
		assert.is_nil(tab.supportSortCache[1])
		assert.is_nil(tab.supportSortCoroutine)
	end)

	it("does not rerun full validation on idle error refresh", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local calls = 0
		local original = tab.GetErrors
		tab.GetErrors = function(self)
			calls = calls + 1
			return original(self)
		end
		tab:RefreshErrors()
		local afterRefresh = calls
		tab:RefreshErrorsIfNeeded()
		assert.are.equal(afterRefresh, calls)
		tab.errorsDirty = true
		tab:RefreshErrorsIfNeeded()
		assert.are.equal(afterRefresh + 1, calls)
		tab.GetErrors = original
	end)

	it("compares a shared active item set as Mercenary when opened from Edit Equipment", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		assert(tab:SetItemSet(playerSetId, false))
		tab.controls.editEquipment.onClick()
		assert.are.equal("ITEMS", build.viewMode)
		assert.are.equal(playerSetId, itemsTab.viewItemSetId)
		assert.are.equal("MERCENARY", MercenaryTools.comparisonActorForItemSet(playerSetId, itemsTab))
		assert.are.equal("MERCENARY", itemsTab:ItemCalculationOverride("Helmet", item()).comparisonActor)
	end)

	it("compares a shared active item set as the player when opened from Items", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		assert(tab:SetItemSet(playerSetId, false))
		tab.controls.editEquipment.onClick()
		assert.are.equal("MERCENARY", MercenaryTools.comparisonActorForItemSet(playerSetId, itemsTab))
		assert(itemsTab:SetViewItemSet(playerSetId))
		assert.are.equal("PLAYER", MercenaryTools.comparisonActorForItemSet(playerSetId, itemsTab))
		assert.are.equal("PLAYER", itemsTab:ItemCalculationOverride("Helmet", item()).comparisonActor)
	end)

	it("compares a distinct Mercenary item set as Mercenary", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local itemsTab = build.itemsTab
		local mercSet = itemsTab:NewItemSet()
		mercSet.title = "Mercenary Equipment"
		table.insert(itemsTab.itemSetOrderList, mercSet.id)
		assert(tab:SetItemSet(mercSet.id, false))
		assert(itemsTab:SetViewItemSet(mercSet.id))
		assert.are_not.equal(itemsTab.activeItemSetId, mercSet.id)
		assert.are.equal("MERCENARY", MercenaryTools.comparisonActorForItemSet(mercSet.id, itemsTab))
		assert.are.equal("MERCENARY", itemsTab:ItemCalculationOverride("Helmet", item()).comparisonActor)
	end)
end)
