describe("Calcs source-skill flag visibility", function()
	local function skillSelectRow(label)
		for _, section in ipairs(build.calcsTab.sectionList) do
			if section.id == "SkillSelect" then
				for _, row in ipairs(section.subSection[1].data) do
					if row.label == label then return row end
				end
			end
		end
	end

	local function selectScionLuminary()
		for classId, class in pairs(build.spec.tree.classes) do
			if class.name == "Scion" then build.spec:SelectClass(classId) break end
		end
		for ascendClassId, ascendClass in pairs(build.spec.curClass.classes) do
			if ascendClass.name == "Luminary" then build.spec:SelectAscendClass(ascendClassId) break end
		end
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

	local function configureMercenary(classId, buildId, skillId)
		local profile = build.mercenaryTab.profile
		profile.classId = classId
		profile.buildId = buildId
		profile.foundAreaLevel = 68
		profile.mainSkillId = skillId
		profile.lifeComparison = "AUTO"
		profile.skills = { { id = skillId, enabled = true, includeInFullDPS = false, count = 1, supports = { } } }
		local MercenaryTools = require("Modules.MercenaryTools")
		local itemSet = build.mercenaryTab:GetItemSet(true)
		local mace = new("Item"):Item("Rarity: Normal\nDriftwood Club")
		local shield = new("Item"):Item("Rarity: Normal\nTwig Spirit Shield")
		build.itemsTab:AddItem(mace, true)
		build.itemsTab:AddItem(shield, true)
		itemSet["Weapon 1"].selItemId = mace.id
		itemSet["Weapon 2"].selItemId = shield.id
		build.mercenaryTab:Changed()
		build.configTab.input.enemyLevel = 83
		build.configTab:BuildModList()
		build.spec.modFlag = true
		build.buildFlag = true
		runCallback("OnFrame")
		runCallback("OnFrame")
	end

	before_each(function()
		newBuild()
	end)

	it("uses playerFlag for Skill Part, Skill Stages, and Active Mines", function()
		for _, case in ipairs({
			{ label = "Skill Part", flag = "multiPart" },
			{ label = "Skill Stages", flag = "multiStage" },
			{ label = "Active Mines", flag = "mine" },
		}) do
			local row = assert(skillSelectRow(case.label), case.label)
			assert.are.equal(case.flag, row.playerFlag, case.label)
			assert.is_nil(row.flag, case.label)
		end
	end)

	it("keeps PLAYER multipart visibility on the player skill", function()
		build.skillsTab:PasteSocketGroup("Arc 20/0  1")
		runCallback("OnFrame")
		build.calcsTab.input.actor = "PLAYER"
		assert.is_true(not build.calcsTab:CheckFlag(skillSelectRow("Skill Part")))
		build.calcsTab.calcsEnv.player.mainSkill.skillFlags.multiPart = true
		assert.is_true(build.calcsTab:CheckFlag(skillSelectRow("Skill Part")))
	end)

	it("follows the player source skill for PLAYER_MINION multipart, stages, and mines", function()
		build.skillsTab:PasteSocketGroup("Summon Raging Spirit 20/0  1")
		runCallback("OnFrame")
		local env = assert(build.calcsTab.calcsEnv)
		assert.is_table(env.minion)
		local playerFlags = env.player.mainSkill.skillFlags
		local minionFlags = env.minion.mainSkill.skillFlags
		playerFlags.multiPart = true
		playerFlags.multiStage = true
		playerFlags.mine = true
		minionFlags.multiPart = nil
		minionFlags.multiStage = nil
		minionFlags.mine = nil
		build.calcsTab.input.actor = "PLAYER_MINION"
		assert.is_true(build.calcsTab:CheckFlag(skillSelectRow("Skill Part")))
		assert.is_true(build.calcsTab:CheckFlag(skillSelectRow("Skill Stages")))
		assert.is_true(build.calcsTab:CheckFlag(skillSelectRow("Active Mines")))
		playerFlags.multiPart = nil
		playerFlags.multiStage = nil
		playerFlags.mine = nil
		assert.is_true(not build.calcsTab:CheckFlag(skillSelectRow("Skill Part")))
		assert.is_true(not build.calcsTab:CheckFlag(skillSelectRow("Skill Stages")))
		assert.is_true(not build.calcsTab:CheckFlag(skillSelectRow("Active Mines")))
	end)

	it("follows the Mercenary source skill for MERCENARY and MERCENARY_MINION", function()
		selectScionLuminary()
		allocate("Noble Blood")
		configureMercenary("AurasMinionsTemplar", "AurasMinionsTemplarSmite", "SSMHolySpectresMercenary")
		local env = assert(build.calcsTab.calcsEnv)
		assert.is_table(env.mercenary)
		assert.is_table(env.mercenaryMinion)
		local playerFlags = env.player.mainSkill.skillFlags
		local mercenaryFlags = env.mercenary.mainSkill.skillFlags
		local minionFlags = env.mercenaryMinion.mainSkill.skillFlags
		playerFlags.multiPart = nil
		playerFlags.multiStage = nil
		playerFlags.mine = nil
		mercenaryFlags.multiPart = true
		mercenaryFlags.multiStage = true
		mercenaryFlags.mine = true
		minionFlags.multiPart = nil
		minionFlags.multiStage = nil
		minionFlags.mine = nil
		for _, actor in ipairs({ "MERCENARY", "MERCENARY_MINION" }) do
			build.calcsTab.input.actor = actor
			assert.is_true(build.calcsTab:CheckFlag(skillSelectRow("Skill Part")), actor)
			assert.is_true(build.calcsTab:CheckFlag(skillSelectRow("Skill Stages")), actor)
			assert.is_true(build.calcsTab:CheckFlag(skillSelectRow("Active Mines")), actor)
		end
		mercenaryFlags.multiPart = nil
		mercenaryFlags.multiStage = nil
		mercenaryFlags.mine = nil
		build.calcsTab.input.actor = "MERCENARY_MINION"
		assert.is_true(not build.calcsTab:CheckFlag(skillSelectRow("Skill Part")))
	end)
end)
