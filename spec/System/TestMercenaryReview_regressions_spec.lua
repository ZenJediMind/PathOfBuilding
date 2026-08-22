describe("Mercenary review regressions", function()
	local MercenaryTools = require("Modules/MercenaryTools")

	local function allocatePermanentHire()
		for classId, class in pairs(build.spec.tree.classes) do
			if class.name == "Scion" then build.spec:SelectClass(classId) break end
		end
		for ascendClassId, ascendClass in pairs(build.spec.curClass.classes) do
			if ascendClass.name == "Luminary" then build.spec:SelectAscendClass(ascendClassId) break end
		end
		local node
		for _, candidate in pairs(build.spec.nodes) do
			if candidate.name == "Noble Blood" and (not node or candidate.id < node.id) then node = candidate end
		end
		node = assert(node or build.spec.tree.ascendancyMap["noble blood"], "Noble Blood")
		node = build.spec.nodes[node.id] or node
		if node.path then
			build.spec:AllocNode(node)
		else
			node.alloc = true
			build.spec.allocNodes[node.id] = node
		end
	end

	it("sorts items equipped in Mercenary slots", function()
		newBuild()
		build.mercenaryTab.profile.buildId = "MeleeAOEMarauderFireSlam"
		build.mercenaryTab:Changed()
		local mercenaryItemSet = build.mercenaryTab:GetItemSet(true)
		build.itemsTab:SetViewItemSet(mercenaryItemSet.id)
		local raw = "Rarity: Normal\nCoral Ring"
		local first = new("Item"):Item(raw)
		local second = new("Item"):Item(raw)
		first.id, second.id = 99101, 99102
		build.itemsTab.items[first.id] = first
		build.itemsTab.items[second.id] = second
		build.itemsTab.slots["Ring 1"]:SetSelItemId(first.id, build.itemsTab:GetVisibleItemSet())
		build.itemsTab.slots["Ring 2"]:SetSelItemId(second.id, build.itemsTab:GetVisibleItemSet())
		local equippedSlot = assert(build.itemsTab:GetEquippedSlotForItem(first))
		assert.are.equal("Ring 1", equippedSlot.slotName)
		assert.are.equal("Ring 1", build.itemsTab:GetComparisonSlotNameForItem(first))
		local unequipped = new("Item"):Item("Rarity: Normal\nIron Hat")
		assert.are.equal("Helmet", build.itemsTab:GetComparisonSlotNameForItem(unequipped))
		build.itemsTab.itemOrderList = { first.id, second.id }

		local ok, err = pcall(function() build.itemsTab:SortItemList() end)
		assert.is_true(ok, err)
		assert.are.same({ first.id, second.id }, build.itemsTab.itemOrderList)
	end)

	it("round-trips the Calcs-specific Mercenary minion skill", function()
		newBuild()
		local profile = build.mercenaryTab.profile
		profile.classId = "EleBowRanger"
		profile.buildId = "EleBowRangerClones"
		profile.foundAreaLevel = 68
		profile.mainSkillId = "MirrorArrowMercenary"
		profile.skills = { {
			id = "MirrorArrowMercenary",
			enabled = true,
			skillMinionSkill = 1,
			skillMinionSkillCalcs = 2,
			supports = { },
		} }

		local saved = { elem = "Mercenary", attrib = { } }
		build.mercenaryTab:Save(saved)
		assert.are.equal("2", saved[1][1].attrib.skillMinionSkillCalcs)

		build.mercenaryTab:Reset()
		build.mercenaryTab:Load(saved)
		local loaded = build.mercenaryTab.profile.skills[1]
		assert.are.equal(1, loaded.skillMinionSkill)
		assert.are.equal(2, loaded.skillMinionSkillCalcs)
	end)

	it("keeps Compare Mercenary controls stateful and context-specific", function()
		newBuild()
		allocatePermanentHire()
		local profile = build.mercenaryTab.profile
		profile.classId = "AurasMinionsTemplar"
		profile.buildId = "AurasMinionsTemplarSmite"
		profile.foundAreaLevel = 68
		profile.mainSkillId = "SSMHolySpectresMercenary"
		profile.skills = { { id = "SSMHolySpectresMercenary", enabled = true, skillMinionSkill = 1, supports = { } } }
		build.mercenaryTab:Changed()
		local itemSet = build.mercenaryTab:GetItemSet(true)
		local mace = new("Item"):Item("Rarity: Normal\nDriftwood Club")
		local shield = new("Item"):Item("Rarity: Normal\nTwig Spirit Shield")
		build.itemsTab:AddItem(mace, true)
		build.itemsTab:AddItem(shield, true)
		itemSet["Weapon 1"].selItemId = mace.id
		itemSet["Weapon 2"].selItemId = shield.id
		build.calcsTab.input.actor = "MERCENARY"
		build.configTab:BuildModList()
		build.calcsTab:BuildOutput()

		local compareTab = build.compareTab
		assert.is_true(compareTab:ImportBuild(assert(build:SaveDB("mercenary-review")), "Mercenary"))
		local entry = assert(compareTab:GetActiveCompare())
		local skill = entry.mercenaryTab.profile.skills[1]
		skill.skillMinionSkill = 1
		skill.skillMinionSkillCalcs = 2
		entry.calcsTab.input.actor = "MERCENARY"
		entry.mercenaryTab:Changed()
		entry.configTab:BuildModList()
		entry.calcsTab:BuildOutput()

		compareTab:UpdateSetSelectors(entry)
		assert.is_false(compareTab.controls.cmpSocketGroup.enabled)
		assert.are.equal(1, compareTab.controls.cmpMinionSkill.selIndex)

		compareTab:RefreshCalcsSkillControls(entry)
		assert.are.equal(2, compareTab.controls.cmpCalcsMinionSkill.selIndex)

		entry.calcsTab.input.actor = "PLAYER"
		compareTab:UpdateSetSelectors(entry)
		assert.is_true(compareTab.controls.cmpSocketGroup.enabled)
	end)

	it("handles missing Mercenary skill and support IDs without crashing", function()
		local profile = {
			buildId = "AurasMinionsTemplarSpectres",
			foundAreaLevel = 68,
			mainSkillId = "SSMHolySpectresMercenary",
			skills = { {
				id = "SSMHolySpectresMercenary",
				enabled = true,
				supports = { { tier = 3 } },
			} },
		}
		local ok, errors = pcall(MercenaryTools.validateProfile, profile, data.mercenaries)
		assert.is_true(ok)
		assert.matches("Invalid support", table.concat(errors, "\n"))

		newBuild()
		local runtimeProfile = build.mercenaryTab.profile
		runtimeProfile.classId = "AurasMinionsTemplar"
		runtimeProfile.buildId = "AurasMinionsTemplarSpectres"
		runtimeProfile.foundAreaLevel = 68
		runtimeProfile.mainSkillId = "SSMHolySpectresMercenary"
		runtimeProfile.skills = { { enabled = true, supports = { } } }
		build.mercenaryTab:Changed()
		build.configTab:BuildModList()
		local calculated, calculationError = pcall(function() build.calcsTab:BuildOutput() end)
		assert.is_true(calculated, calculationError)
		assert.matches("Invalid skill for selected build", table.concat(build.calcsTab.mainEnv.mercenaryCalculationErrors, "\n"))
	end)

	it("does not change the player's main skill when swapping weapons on a viewed inactive set", function()
		newBuild()
		local itemsTab = build.itemsTab
		build.skillsTab:PasteSocketGroup("Slot: Weapon 1\nHeavy Strike 20/0  1\n")
		build.skillsTab:PasteSocketGroup("Slot: Weapon 1 Swap\nCleave 20/0  1\n")
		build.mainSocketGroup = 1
		local inactiveSet = itemsTab:NewItemSet()
		inactiveSet.title = "Inactive"
		table.insert(itemsTab.itemSetOrderList, inactiveSet.id)
		assert(itemsTab:SetViewItemSet(inactiveSet.id))
		assert.is_not_true(inactiveSet.useSecondWeaponSet)

		itemsTab.controls.weaponSwap2.onClick()

		assert.is_true(inactiveSet.useSecondWeaponSet)
		assert.is_not_true(itemsTab.activeItemSet.useSecondWeaponSet)
		assert.are.equal(1, build.mainSocketGroup)
	end)

	it("still migrates the main skill when the player swaps weapons on the active set", function()
		newBuild()
		local itemsTab = build.itemsTab
		build.skillsTab:PasteSocketGroup("Slot: Weapon 1\nHeavy Strike 20/0  1\n")
		build.skillsTab:PasteSocketGroup("Slot: Weapon 1 Swap\nCleave 20/0  1\n")
		build.mainSocketGroup = 1
		assert.are.equal(itemsTab.activeItemSetId, itemsTab.viewItemSetId)

		itemsTab.controls.weaponSwap2.onClick()

		assert.is_true(itemsTab.activeItemSet.useSecondWeaponSet)
		assert.are.equal(2, build.mainSocketGroup)
	end)

	it("treats actively equipped items as equipped rather than merely used in a set", function()
		newBuild()
		local itemsTab = build.itemsTab
		local equipped = new("Item"):Item("Rarity: Normal\nIron Hat")
		local other = new("Item"):Item("Rarity: Normal\nLeather Cap")
		itemsTab:AddItem(equipped, true)
		itemsTab:AddItem(other, true)
		itemsTab.activeItemSet.Helmet.selItemId = equipped.id
		local mapping = itemsTab:NewItemSet()
		mapping.title = "Mapping"
		table.insert(itemsTab.itemSetOrderList, mapping.id)
		mapping.Helmet.selItemId = other.id
		itemsTab:PopulateSlots()

		local equippedSlot, equippedSet = itemsTab:GetEquippedSlotForItem(equipped)
		assert.are.equal("Helmet", equippedSlot.slotName)
		assert.is_nil(equippedSet)
		local otherSlot, otherSet = itemsTab:GetEquippedSlotForItem(other)
		assert.are.equal("Helmet", otherSlot.slotName)
		assert.are.equal(mapping, otherSet)

		mapping.Helmet.selItemId = equipped.id
		local duplicateSlot, duplicateSet = itemsTab:GetEquippedSlotForItem(equipped)
		assert.are.equal(equippedSlot, duplicateSlot)
		assert.is_nil(duplicateSet)

		assert(itemsTab:SetViewItemSet(mapping.id))
		local viewedSlot, viewedSet = itemsTab:GetEquippedSlotForItem(equipped)
		assert.is_nil(viewedSet)
		assert.are.equal(equippedSlot, viewedSlot)

		mapping.Helmet.selItemId = other.id
		local equippedRow = itemsTab.controls.itemList:GetRowValue(1, 1, equipped.id)
		local otherRow = itemsTab.controls.itemList:GetRowValue(1, 1, other.id)
		assert.does_not_match("Used in", equippedRow)
		assert.matches("Used in 'Mapping'", otherRow)

		mapping["Weapon 1"].selItemId = equipped.id
		local crossSlot, crossSet = itemsTab:GetEquippedSlotForItem(equipped)
		assert.are.equal("Helmet", crossSlot.slotName)
		assert.is_nil(crossSet)
	end)
end)
