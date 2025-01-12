--[[
HITC - I want to see my hits please!
Just a simple hitbox clarification
Use this to debug weapons, cheats, or find interesting source engine fuck ups
- WholeCream, do as you please.
]]

local convar_reliable = CreateClientConVar( "hitc_reliable", "1", false, true, "Enables/Disables reliable networking", 0, 1 )
local convar_hits = CreateClientConVar( "hitc_hits", "0", false, true, "Enables/Disables hit registration renders", 0, 1 )
local convar_hits_duration = CreateClientConVar( "hitc_hits_duration", "5", false, true, "How long should we render hits", 0, 30 )
local convar_hitbox = CreateClientConVar( "hitc_hitbox", "0", false, true, "Enables/Disables angle renders", 0, 1 )
local convar_hitbox_duration = CreateClientConVar( "hitc_hitbox_duration", "5", false, true, "How long should we render hitbox", 0, 30 )
local convar_reveal = CreateClientConVar( "hitc_reveal", "0", false, true, "Enables/Disables constant hitbox results in field of view", 0, 1 )
local convar_reveal_duration = CreateClientConVar( "hitc_reveal_duration", "0.25", false, true, "How long should we render the revealed hitbox", 0, 30 )

local timescale = GetConVar("host_timescale")

local registry = {}

local function register(attacker, trace, damage)
    if not attacker:IsPlayer() then return end
    if attacker:GetInfoNum( "hitc_hits", 0 ) < 1 then return end
 
    -- find entities in cone
	local in_cone = ents.FindInCone(
        trace.StartPos,
        (trace.HitPos - trace.StartPos):GetNormalized(),
        10000,
        math.cos(math.rad( 15 ))
    )
 
    local to_check = {}
    for i=1, #in_cone do
        local entity = in_cone[i]
        if not entity:IsPlayer() or not entity:IsSolid() or entity:Health() < 1 then continue end
        if entity:GetHitBoxGroupCount() == nil then continue end
        local tr = util.TraceLine({
            start = trace.StartPos,
            endpos = entity:EyePos(),
            filter = {attacker, entity},
            mask = MASK_SHOT
        })
        if tr.Hit then continue end
 
        to_check[#to_check+1] = entity
    end
 
    local entities = {}
    for i=1, #to_check do
        local entity = to_check[i]

        local hitboxes = {}
        for group=0, entity:GetHitBoxGroupCount() - 1 do
            for hitbox=0, entity:GetHitBoxCount(group) - 1 do
                local pos, ang =  entity:GetBonePosition(entity:GetHitBoxBone(hitbox, group))
                local mins, maxs = entity:GetHitBoxBounds(hitbox, group)
                local grouping = entity:GetHitBoxHitGroup(hitbox, 0)

                hitboxes[#hitboxes+1] = {
                    hit = trace.Entity == entity and trace.HitGroup == grouping,
                    position = pos,
                    angle = ang,
                    mins = mins,
                    maxs = maxs
                }
            end
        end

        entities[#entities+1] = {
            index = entity:EntIndex(),
            entity = entity,
            hit = trace.Entity == entity,
            position = entity:GetPos(),
            mins = entity:OBBMins(),
            maxs = entity:OBBMaxs(),
            hitboxes = hitboxes
        }
    end
 
    registry[#registry+1] = {
        client = true,
        time = SysTime(),
        identity = attacker:GetCurrentCommand():CommandNumber(),
        startpos = trace.StartPos,
        endpos = trace.HitPos,
        entities = entities
    }
end

net.Receive("HITC:Register", function()
    if not convar_hits:GetBool() then return end
    local startpos = net.ReadVector()
    local endpos = net.ReadVector()
    local damage = net.ReadInt(31)
    local identity = net.ReadInt(31)

    local entities = {}
    local entity_length = net.ReadUInt(8)
    for i=1, entity_length do
        local index = net.ReadUInt(13)
        local hit = net.ReadBool()
        local position = net.ReadVector()
        local mins = net.ReadVector()
        local maxs = net.ReadVector()

        local hitbox_length = net.ReadUInt(8)
        local hitboxes = {}
        for i=1, hitbox_length do
            local hit = net.ReadBool()
            local position = net.ReadVector()
            local angle = net.ReadAngle()
            local mins = net.ReadVector()
            local maxs = net.ReadVector()

            hitboxes[#hitboxes+1] = {
                hit = hit,
                position = position,
                angle = angle,
                mins = mins,
                maxs = maxs
            }
        end

        entities[#entities+1] = {
            index = index,
            entity = Entity(index),
            hit = hit,
            position = position,
            mins = mins,
            maxs = maxs,
            hitboxes = hitboxes
        }
    end

    local server = {
        time = SysTime(),
        damage = damage,
        identity = identity,
        startpos = startpos,
        endpos = endpos,
        entities = entities
    }

    for i=1, #registry do
        local entry = registry[i]
        if not entry.client then continue end
        if entry.identity ~= identity then continue end
        entry.link = server
        server.link = entry
    end

    registry[#registry+1] = server
end)

local reveal
net.Receive("HITC:Reveal", function()
    if not convar_reveal:GetBool() then return end

    local position = net.ReadVector()
    local mins = net.ReadVector()
    local maxs = net.ReadVector()

    local reveal_length = net.ReadUInt(8)
    local reveales = {}
    for i=1, reveal_length do
        local position = net.ReadVector()
        local angle = net.ReadAngle()
        local mins = net.ReadVector()
        local maxs = net.ReadVector()

        reveales[#reveales+1] = {
            position = position,
            angle = angle,
            mins = mins,
            maxs = maxs
        }
    end

    reveal = {
        time = SysTime(),
        position = position,
        mins = mins,
        maxs = maxs,
        reveales = reveales
    }
end)

local hitbox
net.Receive("HITC:Hitbox", function()
    if not convar_hitbox:GetBool() then return end

    local position = net.ReadVector()
    local mins = net.ReadVector()
    local maxs = net.ReadVector()

    local hitbox_length = net.ReadUInt(8)
    local hitboxes = {}
    for i=1, hitbox_length do
        local position = net.ReadVector()
        local angle = net.ReadAngle()
        local mins = net.ReadVector()
        local maxs = net.ReadVector()

        hitboxes[#hitboxes+1] = {
            position = position,
            angle = angle,
            mins = mins,
            maxs = maxs
        }
    end

    hitbox = {
        time = SysTime(),
        position = position,
        mins = mins,
        maxs = maxs,
        hitboxes = hitboxes
    }
end)

local hit_color = Color(0,255,0)
local hit_client_color = Color(255,0,0)
local color_white = Color(255,255,255)
hook.Add("PostDrawOpaqueRenderables", "HITC:Render", function()
    local t = SysTime()

    if reveal and reveal.time then
        if reveal.time + (convar_reveal_duration:GetFloat() / timescale:GetFloat()) < t then
            reveal = nil
        else
            local reveales = reveal.reveales
            for i=1, #reveales do
                local reveal = reveales[i]
                render.DrawWireframeBox(reveal.position, reveal.angle, reveal.mins, reveal.maxs)
            end

            render.DrawWireframeBox(reveal.position, Angle(), reveal.mins, reveal.maxs)
        end
    end

    if hitbox and hitbox.time then
        if hitbox.time + convar_hitbox_duration:GetFloat() < t then
            hitbox = nil
        else
            local hitboxes = hitbox.hitboxes
            for i=1, #hitboxes do
                local hitbox = hitboxes[i]
                render.DrawWireframeBox(hitbox.position, hitbox.angle, hitbox.mins, hitbox.maxs)
            end

            render.DrawWireframeBox(hitbox.position, Angle(), hitbox.mins, hitbox.maxs)
        end
    end

    local c = 0
    for i=1, #registry do
        local entry = registry[i-c]

        if entry.time + convar_hits_duration:GetFloat() < t then
            table.remove(registry, i-c); c = c + 1;
            continue
        end

        local delta = ((entry.time + convar_hits_duration:GetFloat()) - t) / convar_hits_duration:GetFloat()

        local entities = entry.entities
        local hit = false
        for i=1, #entities do
            local entity = entities[i]

            local hitboxes = entity.hitboxes
            for i=1, #hitboxes do
                local hitbox = hitboxes[i]
                local color = (hitbox.hit and hit_color or nil) or (entry.client and hit_client_color or color_white)
                color = Color(color.r, color.g, color.b, color.a * delta)
                render.DrawWireframeBox(hitbox.position, hitbox.angle, hitbox.mins, hitbox.maxs, color)
            end
            hit = entity.hit
            local color = (entry.client and hit_client_color or nil) or (entity.hit and hit_color or color_white)
            color = Color(color.r, color.g, color.b, color.a * delta)
            render.DrawWireframeBox(entity.position, Angle(), entity.mins, entity.maxs, color)
        end

        if entry.damage then
            -- TODO: add a nice way to show damage values
            local pos = entry.startpos + (entry.endpos - entry.startpos):GetNormalized() * 25
            local angle = ( pos - EyePos() ):GetNormalized():Angle()
            angle = Angle( 0, angle.y, 0 )
            angle:RotateAroundAxis( angle:Up(), -90 )
            angle:RotateAroundAxis( angle:Forward(), 90 )
            local text = "Damage: " .. entry.damage
            cam.Start3D2D( pos, angle, 0.075 )
                local o = surface.GetAlphaMultiplier()
                surface.SetAlphaMultiplier( delta )
                surface.SetDrawColor( 0, 0, 0, 100 )
                surface.DrawRect( -10, -10, 20, 20 )
                surface.SetDrawColor( 255, 255, 255, 255 )
                surface.DrawRect( -1, -10, 1, 20 )
                surface.DrawRect( -10, -1, 20, 1 )
                local offset = 20
                
                if i == #registry then
                    surface.SetFont( "DermaDefault" )
                    local tW, tH = surface.GetTextSize( text )
                    local padX = 5
                    local padY = 5
                    surface.SetDrawColor( 0, 0, 0, 100 )
                    surface.DrawRect( -tW / 2 - padX, offset - padY, tW + padX * 2, tH + padY * 2 )
                    draw.SimpleText( text, "DermaDefault", -tW / 2, offset, color_white )
                end
                
                surface.SetAlphaMultiplier( o )
            cam.End3D2D()
        end

        -- this shows the deviation of client-vs-server positions
        if entry.client and entry.link then
            local reference = entry.link
            for i=1, #entities do
                local client_record = entities[i]
                local server_record

                for i=1, #reference.entities do
                    server_record = reference.entities[i]
                    if server_record.index ~= client_record.index then
                        server_record = nil
                    else
                        break
                    end
                end

                if server_record then
                    local color = Color(255,255,255,255*delta)
                    render.DrawLine(client_record.position + Vector(0,0,client_record.maxs.z) / 2, server_record.position + Vector(0,0,server_record.maxs.z) / 2, color)
                end
            end
        end

        if entry.client then
            if entry.link then
                local reference = entry.link
                local up = ((entry.endpos - entry.startpos):GetNormalized():Angle():Up() + (reference.endpos - reference.startpos):GetNormalized():Angle():Up()) / 2
                local client_reference = up * 2 + entry.startpos + (entry.endpos - entry.startpos):GetNormalized() * 25
                local server_reference = up * 2 + reference.startpos + (reference.endpos - reference.startpos):GetNormalized() * 25
                local deviation = (client_reference - server_reference):Length()
                if deviation > 1 then
                    local color = hit_client_color
                    color = Color(color.r, color.g, color.b, color.a * delta)
                    render.DrawLine(client_reference, server_reference, color)
                    render.DrawLine(entry.startpos, entry.endpos, color)

                    local pos = server_reference + (client_reference - server_reference) / 2
                    local angle = ( pos - EyePos() ):GetNormalized():Angle()
                    angle = Angle( 0, angle.y, 0 )
                    angle:RotateAroundAxis( angle:Up(), -90 )
                    angle:RotateAroundAxis( angle:Forward(), 90 )
                    local text = "Deviation: " .. math.Round(deviation, 2)
                    cam.Start3D2D( pos, angle, 0.075 )
                        local o = surface.GetAlphaMultiplier()
                        surface.SetAlphaMultiplier( delta )
                        surface.SetDrawColor( 0, 0, 0, 100 )
                        surface.DrawRect( -10, -10, 20, 20 )
                        surface.SetDrawColor( 255, 0, 0, 255 )
                        surface.DrawRect( -1, -10, 1, 20 )
                        surface.DrawRect( -10, -1, 20, 1 )
                        local offset = -20
                        
                        if i == #registry-1 then
                            surface.SetFont( "DermaDefault" )
                            local tW, tH = surface.GetTextSize( text )
                            local padX = 5
                            local padY = 5
                            surface.SetDrawColor( 0, 0, 0, 100 )
                            surface.DrawRect( -tW / 2 - padX, offset - padY - tH, tW + padX * 2, tH + padY * 2 )
                            draw.SimpleText( text, "DermaDefault", -tW / 2, offset - tH, hit_client_color )
                        end
                        
                        surface.SetAlphaMultiplier( o )
                    cam.End3D2D()
                end
            else
                local color = hit_client_color
                color = Color(color.r, color.g, color.b, color.a * delta)
                render.DrawLine(entry.startpos, entry.endpos, color)
            end
        else
            local color = hit and hit_color or color_white
            color = Color(color.r, color.g, color.b, color.a * delta)
            render.DrawLine(entry.startpos, entry.endpos, color)
        end
    end
end)

-- x86 didn't seem to have PostEntityFireBullets still...?
-- commented out till homonovus does something about his CSGO weapons
if jit.arch == "x64" then
    hook.Add("PostEntityFireBullets", "HITC:Register", function(attacker, bullet)
        if not IsFirstTimePredicted() then return end
        register(attacker, bullet.Trace)
    end)
else
    local running = false
    hook.Add("EntityFireBullets", "HITC:Register", function(attacker, bullet)
        if running then return end
        if not IsFirstTimePredicted() then return end
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