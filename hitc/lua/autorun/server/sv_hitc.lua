--[[
HITC - I want to see my hits please!
Just a simple hitbox clarification
Use this to debug weapons, cheats, or find interesting source engine fuck ups
- WholeCream, do as you please.
]]

util.AddNetworkString("HITC:Register")
util.AddNetworkString("HITC:Reveal")
util.AddNetworkString("HITC:Hitbox")

local function hitbox_network(target)
    net.WriteVector(target:GetPos())
    net.WriteVector(target:OBBMins())
    net.WriteVector(target:OBBMaxs())
    
    local hitboxes = {}
    for group=0, target:GetHitBoxGroupCount() - 1 do
        for hitbox=0, target:GetHitBoxCount(group) - 1 do
            local pos, ang =  target:GetBonePosition(target:GetHitBoxBone(hitbox, group))
            local mins, maxs = target:GetHitBoxBounds(hitbox, group)
    
            hitboxes[#hitboxes+1] = {
                position = pos,
                angle = ang,
                mins = mins,
                maxs = maxs
            }
        end
    end
    
    net.WriteUInt(#hitboxes, 8)
    
    for i=1, #hitboxes do
        local hitbox = hitboxes[i]
        net.WriteVector(hitbox.position)
        net.WriteAngle(hitbox.angle)
        net.WriteVector(hitbox.mins)
        net.WriteVector(hitbox.maxs)
    end

    return hitboxes
end

local function register(attacker, trace, damage)
    if not attacker:IsPlayer() then return end
    if attacker:GetInfoNum( "hitc_hits", 0 ) < 1 then return end
 
    net.Start("HITC:Register", not (attacker:GetInfoNum( "hitc_reliable", 0 ) < 1))
 
    -- write raycast result
    net.WriteVector(trace.StartPos)
    net.WriteVector(trace.HitPos)
    net.WriteUInt(damage or 0, 31) -- TODO: Review source sdk if this can be reduced
    net.WriteUInt(attacker.HITC_COMMAND or 0, 31) -- TODO: Same as above
 
    -- find entities in cone
    local in_cone = ents.FindInCone(
        trace.StartPos,
        (trace.HitPos - trace.StartPos):GetNormalized(),
        10000,
        math.cos(math.rad( 15 ))
    )
 
    local entities = {}
    for i=1, #in_cone do
        local entity = in_cone[i]
        if entity == attacker or not entity:IsPlayer() or not entity:IsSolid() or entity:Health() < 1 then continue end
        if entity:GetHitBoxGroupCount() == nil then continue end
        local tr = util.TraceLine({
            start = trace.StartPos,
            endpos = entity:EyePos(),
            filter = {attacker, entity},
            mask = MASK_SHOT
        })
        if tr.Hit then continue end
 
        entities[#entities+1] = entity
    end
 
    net.WriteUInt(#entities, 8)
 
    for i=1, #entities do
        local entity = entities[i]
        net.WriteUInt(entity:EntIndex(), 13)
        net.WriteBool(trace.Entity == entity)
        net.WriteVector(entity:GetPos())
        net.WriteVector(entity:OBBMins())
        net.WriteVector(entity:OBBMaxs())
        
        local hitboxes = {}
        for group=0, entity:GetHitBoxGroupCount() - 1 do
            for hitbox=0, entity:GetHitBoxCount(group) - 1 do
                local pos, ang =  entity:GetBonePosition(entity:GetHitBoxBone(hitbox, group))
                local mins, maxs = entity:GetHitBoxBounds(hitbox, group)
        
                hitboxes[#hitboxes+1] = {
                    hit = trace.Entity == entity and trace.HitGroup == group,
                    position = pos,
                    angle = ang,
                    mins = mins,
                    maxs = maxs
                }
            end
        end
        
        net.WriteUInt(#hitboxes, 8)
        
        for i=1, #hitboxes do
            local hitbox = hitboxes[i]
            net.WriteBool(hitbox.hit)
            net.WriteVector(hitbox.position)
            net.WriteAngle(hitbox.angle)
            net.WriteVector(hitbox.mins)
            net.WriteVector(hitbox.maxs)
        end
    end
 
    net.Send(attacker)
end

local next_tick = 0
hook.Add("Tick", "HITC:Hitbox", function()
    local t = CurTime()
    if next_tick + 1/16 > t then -- TODO: make server-cvar for changing this rate...
        return
    end
    next_tick = CurTime()

    local players = player.GetHumans()
    for i=1, #players do
        local player = players[i]

        if player:GetInfoNum( "hitc_reveal", 0 ) > 0 then
            local player = players[i]
            local in_cone = ents.FindInCone(
                player:EyePos(),
                player:EyeAngles():Forward(),
                1000,
                math.cos(math.rad( 15 ))
            )

            local closest, closest_dist = nil, math.huge
            for i=1, #in_cone do
                local entity = in_cone[i]
                if entity == attacker or not entity:IsPlayer() or not entity:IsSolid() or entity:Health() < 1 then continue end
                if entity:GetHitBoxGroupCount() == nil then continue end
                local dist = entity:GetPos():DistToSqr(player:GetPos())
                if closest_dist > dist then
                    closest = entity
                    closest_dist = dist
                end
            end
    
            if closest then
                net.Start("HITC:Reveal", not (player:GetInfoNum( "hitc_reliable", 0 ) < 1))
                hitbox_network(closest)
                net.Send(player)
            end
        end

        if player:GetInfoNum( "hitc_hitbox", 0 ) > 0 then
            net.Start("HITC:Hitbox", not (player:GetInfoNum( "hitc_reliable", 0 ) < 1))
            hitbox_network(player)
            net.Send(player)
        end
    end
end)

hook.Add("StartCommand", "HITC:Track", function(invoker, cmd)
    invoker.HITC_COMMAND = cmd:CommandNumber()
    -- ^ source engine being cool
end)

-- x86 didn't seem to have PostEntityFireBullets still...?
if jit.arch == "x64" then
    hook.Add("PostEntityFireBullets", "HITC:Register", function(attacker, bullet)
        register(attacker, bullet.Trace, bullet.Damage)
    end)
else
    local running = false
    hook.Add("EntityFireBullets", "HITC:Register", function(attacker, bullet)
        if running then return end
        local original = bullet.Callback
        bullet.Callback = function(attacker, tr, cdmg)
            register(attacker, tr, cdmg:GetDamage())
            if original then
                return original(attacker, tr, cdmg)
            end
        end
        running = true
        -- TODO: continuation of hook events
        hook.Run("EntityFireBullets", attacker, bullet)
        running = false
        return true
    end)
end