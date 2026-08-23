-- Path of Building
--
-- Module: Config Scope
-- Classifies Configuration options as shared (encounter), actor, or player-only.
-- Enemy writes are further classified as encounter state or source-owned ("by you") state.
--
local ConfigScope = { }

local PLAYER_VARS = {
	resistancePenalty = true,
	bandit = true,
	pantheonMajorGod = true,
	pantheonMinorGod = true,
	ignoreItemDisablers = true,
	ignoreJewelLimits = true,
}

-- Enemy conditions/multipliers whose wording establishes source ownership.
-- Each actor evaluates these against its own overlay; resulting encounter effects
-- (Shock, Exposure, increased damage taken, ...) are published to shared enemy state.
local SOURCE_OWNED_ENEMY_VARS = {
	ChilledByYou = true,
	ChilledByYourHits = true,
	FrozenByYou = true,
	ChilledByYouSeconds = true,
	FrozenByYouSeconds = true,
	BetweenYouAndLinkedTarget = true,
	NearLinkedTarget = true,
	ChampionIntimidate = true,
	HigherLifePercentThanPlayer = true,
	HitByFireDamage = true,
	HitByColdDamage = true,
	HitByLightningDamage = true,
}

-- Actor flags that only apply while that actor's hits have chilled the enemy.
-- These mods do not tag ChilledByYourHits themselves, so usage must be implied
-- for Config visibility and overlay gating.
local CHILL_BY_HITS_EFFECT_FLAGS = {
	ChillEffectIncDamageTaken = true,
	ChillEffectIncColdDamageTaken = true,
	ChillEffectLessDamageDealt = true,
}

local scopeByVar = { }
local enemyStateByVar = { }
local indexed = false

local function isSourceOwnedName(name)
	return name and SOURCE_OWNED_ENEMY_VARS[name] or false
end

local function anySourceOwned(value)
	if type(value) == "table" then
		for _, name in ipairs(value) do
			if isSourceOwnedName(name) then
				return true
			end
		end
		return false
	end
	return isSourceOwnedName(value)
end

function ConfigScope.isSourceOwnedEnemyVar(var)
	return isSourceOwnedName(var)
end

function ConfigScope.isSourceOwnedEnemyMod(mod)
	if not mod or not mod.name then
		return false
	end
	local var = mod.name:match("^Condition:(.+)$") or mod.name:match("^Multiplier:(.+)$")
	return var and isSourceOwnedName(var)
end

function ConfigScope.isSourceOwnedEnemyTag(tag)
	if not tag then
		return false
	end
	if tag.sourceOwned then
		return tag.type == "Condition" or tag.type == "Multiplier" or tag.type == "MultiplierThreshold" or tag.type == "ActorCondition"
	end
	if tag.type ~= "Condition" and tag.type ~= "Multiplier" and tag.type ~= "MultiplierThreshold" and tag.type ~= "ActorCondition" then
		return false
	end
	return anySourceOwned(tag.var or tag.varList)
end

function ConfigScope.impliesChilledByYourHits(modName)
	return modName and CHILL_BY_HITS_EFFECT_FLAGS[modName] or false
end

local VALID_ENEMY_STATE = {
	source = true,
	encounter = true,
}

local VALID_SCOPE = {
	shared = true,
	actor = true,
	player = true,
}

local function inferEnemyState(varData)
	if varData.enemyState then
		if not VALID_ENEMY_STATE[varData.enemyState] then
			error("ConfigScope: invalid enemyState '"..tostring(varData.enemyState).."' for "..tostring(varData.var))
		end
		return varData.enemyState
	end
	if anySourceOwned(varData.ifEnemyCond) or anySourceOwned(varData.ifEnemyMult) then
		return "source"
	end
	return "encounter"
end

local function inferScope(varData, sectionScope)
	-- Source-owned enemy predicates are per-actor even if a section default is shared.
	if inferEnemyState(varData) == "source" then
		return "actor"
	end
	if varData.scope then
		if not VALID_SCOPE[varData.scope] then
			error("ConfigScope: invalid scope '"..tostring(varData.scope).."' for "..tostring(varData.var))
		end
		return varData.scope
	end
	local var = varData.var or ""
	if var:match("^playerCursed") then
		return "actor"
	end
	-- Minion-state options (minionsCondition*, minionsUse*, ifMinionCond) describe the
	-- viewed actor's minions, including Mercenary minions, so they stay actor-scoped.
	if PLAYER_VARS[var] or var:match("^overrideEmpty") then
		return "player"
	end
	if varData.ifEnemyCond or varData.ifEnemyMult or varData.ifEnemyStat
		or var:match("^enemy") or var:match("^conditionEnemy")
		or var:match("^MapPrefix") or var:match("^MapSuffix")
		or var:match("^multiplierMap") or var == "multiplierSextant" or var == "PvpScaling"
		or var:match("OnEnemy") or var == "ShockStacks" or var == "ScorchStacks"
	then
		return "shared"
	end
	return sectionScope or "actor"
end

function ConfigScope.index(varList)
	scopeByVar = { }
	enemyStateByVar = { }
	local sectionScope = "actor"
	for _, varData in ipairs(varList or { }) do
		if varData.section then
			if not varData.scope then
				error("ConfigScope: section '"..tostring(varData.section).."' needs explicit scope")
			elseif not VALID_SCOPE[varData.scope] then
				error("ConfigScope: invalid scope '"..tostring(varData.scope).."' for section "..tostring(varData.section))
			end
			sectionScope = varData.scope
		end
		if varData.var then
			local enemyState = inferEnemyState(varData)
			local scope = inferScope(varData, sectionScope)
			scopeByVar[varData.var] = scope
			enemyStateByVar[varData.var] = enemyState
			varData.resolvedScope = scope
			varData.resolvedEnemyState = enemyState
		end
	end
	indexed = true
end

function ConfigScope.forVar(var)
	if not var then
		return "actor"
	end
	return scopeByVar[var] or "actor"
end

function ConfigScope.forVarData(varData)
	if varData and varData.resolvedScope then
		return varData.resolvedScope
	end
	if varData and varData.var then
		return ConfigScope.forVar(varData.var)
	end
	return "actor"
end

function ConfigScope.enemyStateForVar(var)
	if not var then
		return "encounter"
	end
	return enemyStateByVar[var] or "encounter"
end

function ConfigScope.enemyStateForVarData(varData)
	if varData and varData.resolvedEnemyState then
		return varData.resolvedEnemyState
	end
	if varData and varData.var then
		return ConfigScope.enemyStateForVar(varData.var)
	end
	return "encounter"
end

function ConfigScope.isIndexed()
	return indexed
end

return ConfigScope
