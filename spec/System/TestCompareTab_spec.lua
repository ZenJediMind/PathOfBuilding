describe("CompareTab", function()
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

	it("imports Mercenary builds and preserves their Calcs skill selection", function()
		local MercenaryTools = require("Modules.MercenaryTools")
		newBuild()
		allocatePermanentHire()
		build.mercenaryTab.profile = {
			classId = "EleBowRanger",
			buildId = "EleBowRangerClones",
			foundAreaLevel = 68,
			mainSkillId = "MirrorArrowMercenary",
			lifeComparison = "AUTO",
			skills = {
				{ id = "MirrorArrowMercenary", enabled = true, includeInFullDPS = true, supports = { } },
				{ id = "IceShotMercenary", enabled = true, includeInFullDPS = false, supports = { } },
			},
		}
		build.mercenaryTab:Changed()
		local mercenaryItemSet = build.mercenaryTab:GetItemSet(true)
		local item = new("Item"):Item("Rarity: Normal\nCrude Bow")
		item.id = 999903
		build.itemsTab.items[item.id] = item
		mercenaryItemSet["Weapon 1"].selItemId = item.id
		build.calcsTab.input.actor = "MERCENARY"
		build.configTab.input.enemyLevel = 83
		build.configTab:BuildModList()
		build.calcsTab:BuildOutput()

		local compareTab = build.compareTab
		assert.is_true(compareTab:ImportBuild(assert(build:SaveDB("mercenary-compare")), "Mercenary"))
		local entry = assert(compareTab:GetActiveCompare())
		compareTab:UpdateSetSelectors(entry)
		assert.is_true(compareTab.controls.cmpMainSkill:IsShown())
		assert.are.equal(2, #compareTab.controls.cmpMainSkill.list)
		compareTab.controls.cmpMainSkill:SetSel(2)
		assert.are.equal("IceShotMercenary", entry.mercenaryTab.profile.mainSkillId)
		entry.mercenaryTab.profile.mainSkillId = "MirrorArrowMercenary"
		entry.mercenaryTab:Changed()
		compareTab.compareViewMode = "CALCS"
		compareTab:RefreshCalcsSkillControls(entry)
		assert.is_true(entry.calcsTab:IsMercenaryActor())
		assert.is_true(compareTab.controls.cmpCalcsMainSkill:IsShown())
		assert.are.equal(2, #compareTab.controls.cmpCalcsMainSkill.list)
		compareTab.controls.cmpCalcsMainSkill:SetSel(2)
		assert.are.equal("IceShotMercenary", entry.mercenaryTab.profile.mainSkillId)
	end)

	it("hides skill detail controls after removing the final comparison", function()
		newBuild()
		local compareTab = build.compareTab
		compareTab.compareEntries = { { label = "Test" } }
		compareTab.activeCompareIndex = 1
		local controls = {
			compareTab.controls.cmpMainSkill,
			compareTab.controls.cmpSkillPart,
			compareTab.controls.cmpStageCount,
			compareTab.controls.cmpMineCount,
			compareTab.controls.cmpMinion,
			compareTab.controls.cmpMinionSkill,
		}
		for _, control in ipairs(controls) do
			control.shown = true
		end

		compareTab:RemoveBuild(1)

		for _, control in ipairs(controls) do
			assert.is_false(control:IsShown())
		end
	end)
	it("reproduces matching-socket gem quality when comparing a build with itself", function()
		newBuild()
		build.itemsTab:CreateDisplayItemFromRaw(
			"Rarity: RARE\nTest Subject\nSage's Robe\nQuality: 0\nSockets: B-B-B\nImplicits: 0\n")
		build.itemsTab:AddDisplayItem()
		build.skillsTab:PasteSocketGroup("Slot: Body Armour\nFireball 20/0  1\n")
		runCallback("OnFrame")
		assert.are.equals(10, build.calcsTab.mainOutput.GemQuality)

		-- doesn't actually save to a file, just encodes as xml
		local entry = new("CompareEntry"):CompareEntry(build:SaveDB("code"), "Self")

		assert.is_true(entry.skillsTab.socketGroupList[1].gemList[1].matchesSocket)
		assert.are.equals(build.calcsTab.mainOutput.GemQuality, entry.calcsTab.mainOutput.GemQuality)
		assert.are.equals(build.calcsTab.mainOutput.CombinedDPS, entry.calcsTab.mainOutput.CombinedDPS)
	end)

	it("copies an item from the visible Mercenary set into the primary Mercenary set", function()
		local MercenaryTools = require("Modules.MercenaryTools")
		newBuild()
		allocatePermanentHire()
		build.mercenaryTab.profile = {
			classId = "EleBowRanger",
			buildId = "EleBowRangerClones",
			foundAreaLevel = 68,
			mainSkillId = "MirrorArrowMercenary",
			lifeComparison = "AUTO",
			skills = { { id = "MirrorArrowMercenary", enabled = true, supports = { } } },
		}
		build.mercenaryTab:Changed()
		local primaryMercenarySet = assert(build.mercenaryTab:GetItemSet(true))
		local item = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		build.itemsTab:AddItem(item, true)
		build.itemsTab:AddItem(quiver, true)
		primaryMercenarySet["Weapon 1"].selItemId = item.id
		primaryMercenarySet["Weapon 2"].selItemId = quiver.id

		build.configTab.input.enemyLevel = 83
		build.configTab:BuildModList()
		build.calcsTab:BuildOutput()
		local compareTab = build.compareTab
		assert.is_true(compareTab:ImportBuild(assert(build:SaveDB("mercenary-copy")), "Mercenary"))
		local entry = assert(compareTab:GetActiveCompare())
		entry.itemsTab:SetViewItemSet(assert(entry.mercenaryTab.itemSetId))
		build.itemsTab:SetViewItemSet(primaryMercenarySet.id)
		build.calcsTab:BuildOutput()
		local _, baseOutput, actorOutputs = build.calcsTab:GetMiscCalculator()
		assert.are.equal(actorOutputs.PLAYER, baseOutput)
		assert.is_truthy(actorOutputs.MERCENARY)

		local playerWeapon = build.itemsTab.activeItemSet["Weapon 1"]
		playerWeapon.selItemId = 0
		compareTab:CopyCompareItemToPrimary("Weapon 1", entry, true)

		local copiedItemId = primaryMercenarySet["Weapon 1"].selItemId
		assert.is_true(copiedItemId > 0)
		assert.are.equal("Crude Bow", build.itemsTab.items[copiedItemId].name)
		assert.are.equal(0, playerWeapon.selItemId)
	end)
end)
