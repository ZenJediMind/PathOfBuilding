describe("Mercenary review regressions", function()
	local MercenaryTools = require("Modules/MercenaryTools")

	it("sorts items equipped in Mercenary slots", function()
		newBuild()
		local raw = "Rarity: Normal\nCoral Ring"
		local first = new("Item", raw)
		local second = new("Item", raw)
		first.id, second.id = 99101, 99102
		build.itemsTab.items[first.id] = first
		build.itemsTab.items[second.id] = second
		build.itemsTab.slots[MercenaryTools.itemSlotName("Ring 1")]:SetSelItemId(first.id)
		build.itemsTab.slots[MercenaryTools.itemSlotName("Ring 2")]:SetSelItemId(second.id)
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
		local profile = build.mercenaryTab.profile
		profile.classId = "AurasMinionsTemplar"
		profile.buildId = "AurasMinionsTemplarSpectres"
		profile.foundAreaLevel = 68
		profile.mainSkillId = "SSMHolySpectresMercenary"
		profile.skills = { { id = "SSMHolySpectresMercenary", enabled = true, skillMinionSkill = 1, supports = { } } }
		build.mercenaryTab:Changed()
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
		assert.matches("Missing generated Mercenary skill: nil", table.concat(build.calcsTab.mainEnv.mercenaryCalculationErrors, "\n"))
	end)
end)
