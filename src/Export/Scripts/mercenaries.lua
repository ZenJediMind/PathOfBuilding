local export = LoadModule("MercenaryExport")
local rowId, rowIds = export.rowId, export.rowIds

local itemClassMap = {
	["Claw"] = "Claw", ["Dagger"] = "Dagger", ["Rune Dagger"] = "Dagger", ["Wand"] = "Wand",
	["One Hand Sword"] = "One Handed Sword", ["Thrusting One Hand Sword"] = "Thrusting One Handed Sword",
	["One Hand Axe"] = "One Handed Axe", ["One Hand Mace"] = "One Handed Mace",
	["Bow"] = "Bow", ["Quiver"] = "Quiver", ["Fishing Rod"] = "Fishing Rod",
	["Staff"] = "Staff", ["Warstaff"] = "Staff", ["Two Hand Sword"] = "Two Handed Sword",
	["Two Hand Axe"] = "Two Handed Axe", ["Two Hand Mace"] = "Two Handed Mace",
	["Shield"] = "Shield", ["Sceptre"] = "Sceptre", ["Unarmed"] = "None",
}

local function weaponType(itemClass)
	if itemClass then
		local itemType = itemClassMap[itemClass.Id]
		assert(itemType, "Unsupported Mercenary item class: "..itemClass.Id)
		return itemType
	end
end

local skillNames = { }
local function exportMonster(variety)
	local template = export.objectTemplate(variety.ObjectType)
	local stats = copyTable(template.stats, true)
	for _, rows in ipairs({ variety.Mods, variety.SpecialMods }) do
		export.appendModStats(rows, stats)
	end
	table.sort(stats, function(a, b)
		if a.id ~= b.id then return a.id < b.id end
		if a.source ~= b.source then return a.source < b.source end
		return a.value < b.value
	end)
	return {
		id = variety.Id,
		name = variety.Name,
		monsterTags = rowIds(variety.Tags),
		movementSpeed = variety.MovementSpeed,
		ailmentThreshold = variety.AilmentThreshold,
		life = variety.LifeMultiplier / 100,
		-- Same monster Energy Shield conversion as the existing minion exporter.
		energyShield = 0.4 * variety.Type.EnergyShield / 100,
		armour = variety.Type.Armour / 100,
		evasion = variety.Type.Evasion / 100,
		fireResist = variety.Type.Resistances.FireMerciless,
		coldResist = variety.Type.Resistances.ColdMerciless,
		lightningResist = variety.Type.Resistances.LightningMerciless,
		chaosResist = variety.Type.Resistances.ChaosMerciless,
		damage = variety.DamageMultiplier / 100,
		damageSpread = variety.Type.DamageSpread / 100,
		attackTime = variety.AttackDuration / 1000,
		attackRange = variety.MaximumAttackRange,
		accuracy = variety.Type.Accuracy / 100,
		baseDamageIgnoresAttackSpeed = variety.Type.BaseDamageIgnoresAttackSpeed,
		lifeScaling = variety.Type.AltLife1 and "AltLife1" or variety.Type.AltLife2 and "AltLife2" or nil,
		weaponType1 = weaponType(variety.MainHandItemClass),
		weaponType2 = weaponType(variety.OffHandItemClass),
		skillIds = export.uniqueSorted(rowIds(export.monsterEffects(variety))),
		stats = stats,
		monsterProperties = template.monsterProperties,
	}
end

local function permanentDamageStat()
	local value
	for passive in dat("PassiveSkills"):Rows() do
		for index, stat in ipairs(passive.Stats) do
			if stat.Id == "permanenet_mercenary_damage_+%_final_and_minion_damage_+%_final_from_luminary" then
				assert(value == nil, "Permanent Mercenary damage stat occurs on multiple passives")
				value = passive["Stat"..index]
			end
		end
	end
	assert(value, "Missing permanent Mercenary damage stat")
	return value
end

local additions = export.objectTemplate("Metadata/Monsters/Mercenaries/MercenaryAdditions")
local mercenaries = {
	baseStats = additions.stats,
	monsterProperties = additions.monsterProperties,
	permanentMercenaryDamageMore = permanentDamageStat(),
	passiveStatLevels = { 24, 68, 84 },
	buffs = { }, actionBuffs = { }, defaultMinions = { }, help = { },
	classes = { }, classOrder = { }, builds = { }, buildOrder = { }, buildsByHash = { },
	skills = { }, supports = { }, minions = { }, summonedMinions = { },
	skillsByHash = { }, supportsByHash = { },
}

for _, id in ipairs({ "MercenaryLoadoutWindowInfoHover", "MercenaryAttributeInfoHover" }) do
	local text = assert(dat("ClientStrings"):GetRow("Id", id), "Missing Mercenary help: "..id).Text
	mercenaries.help[id] = text:gsub("\r\n", "\n"):gsub("\r", "\n")
end

local defaultMinionIds = { }
for line in io.lines("Minions/Minions.txt") do
	local monster, id = line:match("^#monster%s+(%S+)%s+(%S+)")
	if monster then defaultMinionIds[monster] = id end
end

local function exportBuff(row)
	if not row or mercenaries.buffs[row.Id] then return end
	local entry = { }
	for _, key in ipairs({ "Stats", "GrantedFlags" }) do
		entry[key] = export.orderedRowIds(row[key])
	end
	mercenaries.buffs[row.Id] = entry
end

local function addHash(index, hash, id)
	local key = tostring(hash)
	index[key] = index[key] or { }
	table.insert(index[key], id)
end

local supportColors = export.supportColors()
local function exportSupport(row)
	local stats = { }
	assert(#row.Stat == #row.StatValues, "Mercenary support stat/value count mismatch: "..row.Id)
	for index, stat in ipairs(row.Stat) do
		table.insert(stats, { id = stat.Id, value = row.StatValues[index] })
	end
	return {
		id = row.Id, name = row.Name, familyId = rowId(row.SupportFamily),
		hash = row.HASH16, tier = row.Tier, icon = row.GemIcon, stats = stats,
		color = assert(supportColors[row.GemIcon], "Missing Mercenary support color: "..row.Id.." ("..row.GemIcon..")"),
	}
end

for row in dat("MercenarySupports"):Rows() do
	local support = exportSupport(row)
	mercenaries.supports[row.Id] = support
	addHash(mercenaries.supportsByHash, support.hash, row.Id)
end

local function exportSummonedMinion(effect)
	if not effect then return end
	local monster, summon = export.summonedMonster(effect)
	if monster then
		mercenaries.summonedMinions[effect.Id] = { monsterId = monster.Id, buffId = rowId(summon.BuffDefinition) }
		mercenaries.minions[monster.Id] = mercenaries.minions[monster.Id] or exportMonster(monster)
		exportBuff(summon.BuffDefinition)
	end
end

for row in dat("MercenarySkills"):Rows() do
	local id = rowId(row.Id)
	local familyId = rowId(row.SkillFamily)
	mercenaries.skills[id] = {
		id = id, name = row.Name, description = row.Description,
		color = row.Id.Attribute,
		familyId = familyId, hash = row.HASH16, supportCountId = rowId(row.SupportCount),
		possibleSupportIds = rowIds(row.PossibleSupports),
		requiredLevel = row.RequiredLevel, icon = row.HouseSkillIcon,
	}
	skillNames[id] = row.Name
	if row.EncounterGrantedEffect then skillNames[row.EncounterGrantedEffect.Id] = row.Name end
	exportSummonedMinion(row.Id)
	exportSummonedMinion(row.EncounterGrantedEffect)
	addHash(mercenaries.skillsByHash, row.HASH16, id)
end

for _, row in ipairs(export.sortedRows("MercenaryClasses")) do
	mercenaries.classes[row.Id] = {
		id = row.Id, name = row.MonsterVarietyAllied.Name,
		attributeId = rowId(row.Attribute), attributeName = row.Attribute.Name,
		monster = exportMonster(row.MonsterVarietyAllied), buildIds = { }, skillIds = { },
	}
	table.insert(mercenaries.classOrder, row.Id)
end

local function exportPassiveStats(rows)
	local stats = { }
	for _, row in ipairs(rows) do
		table.insert(stats, {
			id = row.Id, statId = row.Stat.Id,
			values = { row.Level24, row.Level68, row.Level84 },
		})
	end
	table.sort(stats, function(a, b) return a.id < b.id end)
	return stats
end

local function exportBuild(row)
	local pools = {
		{ skillIds = rowIds(row.Skill1) },
		{ skillIds = rowIds(row.Skill2), count = row.Skill2Count },
		{ skillIds = rowIds(row.Skill3), count = row.Skill3Count },
	}
	local skills, weapons, itemClasses = { }, { }, { }
	for _, pool in ipairs(pools) do
		for _, id in ipairs(pool.skillIds) do table.insert(skills, id) end
	end
	for _, wieldable in ipairs(row.WeaponTypes) do
		table.insert(weapons, weaponType(wieldable.ItemClasses))
		table.insert(itemClasses, wieldable.ItemClasses.Id)
	end
	return {
		id = row.Id, classId = row.Class.Id, name = row.BuildName, hash = row.HASH16,
		skillPools = pools,
		skillIds = export.uniqueSorted(skills), weaponTypes = export.uniqueSorted(weapons),
		itemClassIds = export.uniqueSorted(itemClasses),
		passiveStats = exportPassiveStats(row.BuildStats),
	}
end

for _, row in ipairs(export.sortedRows("MercenaryBuilds")) do
	local build = exportBuild(row)
	local class = assert(mercenaries.classes[build.classId], "Missing Mercenary class: "..build.classId)
	mercenaries.builds[build.id] = build
	addHash(mercenaries.buildsByHash, build.hash, build.id)
	table.insert(mercenaries.buildOrder, build.id)
	table.insert(class.buildIds, build.id)
	for _, id in ipairs(build.skillIds) do table.insert(class.skillIds, id) end
end

for _, class in pairs(mercenaries.classes) do
	class.skillIds = export.uniqueSorted(class.skillIds)
end
for _, index in ipairs({ mercenaries.buildsByHash, mercenaries.skillsByHash, mercenaries.supportsByHash }) do
	for _, ids in pairs(index) do table.sort(ids) end
end

local skillData = { grantedEffects = { }, statSets = { } }
local baseActiveSkills, baseNames = export.skillBaseIndexes()
local function exportStatSet(statSet)
	if not statSet or skillData.statSets[statSet.Id] then return end
	local entry = export.fields(statSet, "ConstantStatsValues")
	entry.ConstantStats = export.orderedRowIds(statSet.ConstantStats)
	entry.cannotGrantToMinion = export.minionStatFlags(statSet)
	skillData.statSets[statSet.Id] = entry
end

for id, effect in pairsSortByKey(export.skillEffects()) do
	local entry = export.fields(effect, "Id SkillID CooldownNotRecoverDuringActive")
	entry.statSetId = rowId(effect.GrantedEffectStatSets)
	entry.activeSkill = export.fields(effect.ActiveSkill, "DisplayName")
	entry.activeSkill.ActionType = effect.ActiveSkill.ActionType.Name
	local displayName = skillNames[id]
	if not displayName or displayName == "" then displayName = effect.ActiveSkill.DisplayName end
	if displayName == "" then displayName = id end
	entry.baseSkillCandidates = {
		activeSkill = baseActiveSkills[effect.ActiveSkill.Id],
		displayName = baseNames[effect.ActiveSkill.DisplayName] or baseNames[displayName],
	}
	if entry.activeSkill.ActionType == "AddBuffToTarget" then
		local payload, buff = export.buffPayload(effect)
		mercenaries.actionBuffs[effect.SkillID] = payload
		exportBuff(buff)
	end
	local display = export.displayMinion(effect)
	if display then
		local monsterId = display.MonsterVarieties.Id
		entry.displayMinionId = display.Id
		mercenaries.defaultMinions[display.Id] = {
			minionId = assert(defaultMinionIds[monsterId], "Missing shared Mercenary minion: "..monsterId),
		}
	end
	skillData.grantedEffects[id] = entry
	exportStatSet(effect.GrantedEffectStatSets)
end
export.writeData("Mercenaries", mercenaries)
export.writeData("MercenarySkills", skillData)
print(string.format("Mercenary data exported: %d classes, %d builds.", #mercenaries.classOrder, #mercenaries.buildOrder))
