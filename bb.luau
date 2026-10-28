local runService = game:GetService("RunService")
local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
local camera = workspace.CurrentCamera
local container = Instance.new("Folder", gethui and gethui() or game:GetService("CoreGui"))
local floor, round = math.floor, math.round
local clear, unpack, find = table.clear, table.unpack, table.find

local wtvp = camera.WorldToViewportPoint
local isA = workspace.IsA
local findFirstChild = workspace.FindFirstChild
local getChildren = workspace.GetChildren
local toOrientation = CFrame.identity.ToOrientation
local pointToObjectSpace = CFrame.identity.PointToObjectSpace
local lerpColor = Color3.new().Lerp
local min2, max2, lerp2 = Vector2.zero.Min, Vector2.zero.Max, Vector2.zero.Lerp
local min3, max3 = Vector3.zero.Min, Vector3.zero.Max

local HEALTH_BAR_OFFSET = Vector2.new(5, 0)
local HEALTH_TEXT_OFFSET = Vector2.new(3, 0)
local HEALTH_BAR_OUTLINE_OFFSET = Vector2.new(0, 1)
local NAME_OFFSET = Vector2.new(0, 2)
local DISTANCE_OFFSET = Vector2.new(0, 2)
local CHASING_OFFSET = Vector2.new(0, 2)
local viewportSize = camera.ViewportSize

local VERTICES = {
    Vector3.new(-1,-1,-1), Vector3.new(-1,1,-1), Vector3.new(-1,1,1), Vector3.new(-1,-1,1),
    Vector3.new(1,-1,-1),  Vector3.new(1,1,-1),  Vector3.new(1,1,1),  Vector3.new(1,-1,1),
}

local BODY_PARTS = {
    Head=true, Chest=true, Abdomen=true, Hips=true, Neck=true,
    LeftArm=true, RightArm=true, LeftForearm=true, RightForearm=true,
    LeftHand=true, RightHand=true, LeftForeleg=true, RightForeleg=true,
    LeftLeg=true, RightLeg=true, LeftFoot=true, RightFoot=true,
}

local function getLocalCharacter()
    local chars = workspace:FindFirstChild("Characters")
    if not chars then return nil end
    for _, v in ipairs(chars:GetChildren()) do
        local body = v:FindFirstChild("Body")
        local head = body and body:FindFirstChild("Head")
        if head and (head.Position - camera.CFrame.Position).Magnitude < 5 then
            return v
        end
    end
end

local cachedLocalChar = getLocalCharacter()
runService.Heartbeat:Connect(function()
    local d = getLocalCharacter()
    if d then cachedLocalChar = d end
end)

-- NameGui billboard teamcheck
local function onTeam(character)
    if not character or typeof(character) ~= "Instance" then return false end
    local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return false end
    for _, v in ipairs(pg:GetChildren()) do
        if v.Name == "NameGui" and v.Adornee then
            if v.Adornee:IsDescendantOf(character) then
                return true
            end
        end
    end
    return false
end

local function getBoundingBox(parts)
    local mn, mx
    for i = 1, #parts do
        local p = parts[i]
        local cf, sz = p.CFrame, p.Size
        mn = min3(mn or cf.Position, (cf - sz*0.5).Position)
        mx = max3(mx or cf.Position, (cf + sz*0.5).Position)
    end
    local center = (mn + mx)*0.5
    return CFrame.new(center, Vector3.new(center.X, center.Y, mx.Z)), mx - mn
end

local function worldToScreen(world)
    local s, ok = wtvp(camera, world)
    return Vector2.new(s.X, s.Y), ok, s.Z
end

local function calculateCorners(cf, sz)
    local cs = {}
    for i = 1, #VERTICES do cs[i] = worldToScreen((cf + sz*0.5*VERTICES[i]).Position) end
    local mn = min2(viewportSize, unpack(cs))
    local mx = max2(Vector2.zero, unpack(cs))
    return {
        corners = cs,
        topLeft = Vector2.new(floor(mn.X), floor(mn.Y)),
        topRight = Vector2.new(floor(mx.X), floor(mn.Y)),
        bottomLeft = Vector2.new(floor(mn.X), floor(mx.Y)),
        bottomRight = Vector2.new(floor(mx.X), floor(mx.Y)),
    }
end

local function rotateVector(v, r)
    local c, s = math.cos(r), math.sin(r)
    return Vector2.new(c*v.X - s*v.Y, s*v.X + c*v.Y)
end

-- ============================================================
-- ESP object
-- ============================================================
local EspObject = {}
EspObject.__index = EspObject

function EspObject.new(player, interface)
    local self = setmetatable({}, EspObject)
    self.player = player
    self.interface = interface
    self.charCache = {}
    self.childCount = 0
    self.bin = {}
    self:Construct()
    return self
end

function EspObject:create(class, props)
    local d = Drawing.new(class)
    for k, v in next, props do d[k] = v end
    self.bin[#self.bin+1] = d
    return d
end

function EspObject:Construct()
    self.drawings = {
        box3d = {{self:create("Line",{Thickness=1,Visible=false}),self:create("Line",{Thickness=1,Visible=false}),self:create("Line",{Thickness=1,Visible=false})},
                 {self:create("Line",{Thickness=1,Visible=false}),self:create("Line",{Thickness=1,Visible=false}),self:create("Line",{Thickness=1,Visible=false})},
                 {self:create("Line",{Thickness=1,Visible=false}),self:create("Line",{Thickness=1,Visible=false}),self:create("Line",{Thickness=1,Visible=false})},
                 {self:create("Line",{Thickness=1,Visible=false}),self:create("Line",{Thickness=1,Visible=false}),self:create("Line",{Thickness=1,Visible=false})}},
        visible = {
            tracerOutline=self:create("Line",{Thickness=3,Visible=false}),
            tracer=self:create("Line",{Thickness=1,Visible=false}),
            boxFill=self:create("Square",{Filled=true,Visible=false}),
            boxOutline=self:create("Square",{Thickness=3,Visible=false}),
            box=self:create("Square",{Thickness=1,Visible=false}),
            healthBarOutline=self:create("Line",{Thickness=3,Visible=false}),
            healthBar=self:create("Line",{Thickness=1,Visible=false}),
            healthText=self:create("Text",{Center=true,Visible=false}),
            name=self:create("Text",{Text=self.player.DisplayName or self.player.Name,Center=true,Visible=false}),
            distance=self:create("Text",{Center=true,Visible=false}),
            weapon=self:create("Text",{Center=true,Visible=false}),
            isChasing=self:create("Text",{Text="chase",Center=true,Visible=false}),
        },
        hidden = {
            arrowOutline=self:create("Triangle",{Thickness=3,Visible=false}),
            arrow=self:create("Triangle",{Filled=true,Visible=false}),
        }
    }
    self.renderConnection = runService.Heartbeat:Connect(function(dt) self:Update(); self:Render() end)
end

function EspObject:Destruct()
    self.renderConnection:Disconnect()
    for _, d in next, self.bin do d:Remove() end
    clear(self)
end

function EspObject:Update()
    local i = self.interface
    self.options = i.teamSettings[i.isFriendly(self.player) and "friendly" or "enemy"]
    self.character = i.getCharacter(self.player)
    self.health, self.maxHealth = i.getHealth(self.character)
    self.weapon = i.getWeapon(self.player)
    self.enabled = self.options.enabled and self.character and not
        (#i.whitelist > 0 and not find(i.whitelist, self.player.UserId))

    local body = self.enabled and findFirstChild(self.character, "Body")
    local head = body and findFirstChild(body, "Head")
    if not head then self.enabled = false return end

    if self.character == cachedLocalChar then self.enabled = false return end
    if (head.Position - camera.CFrame.Position).Magnitude < 4 then self.enabled = false return end

    local _, onScreen, depth = worldToScreen(head.Position)
    self.onScreen = onScreen
    self.distance = depth
    if i.sharedSettings.limitDistance and depth > i.sharedSettings.maxDistance then self.onScreen = false end

    if self.onScreen then
        local children = getChildren(body)
        if not self.charCache[1] or self.childCount ~= #children then
            clear(self.charCache)
            for _, p in ipairs(children) do
                if isA(p, "BasePart") and BODY_PARTS[p.Name] then self.charCache[#self.charCache+1] = p end
            end
            self.childCount = #children
        end
        self.corners = calculateCorners(getBoundingBox(self.charCache))
    elseif self.options.offScreenArrow then
        local _, yaw, roll = toOrientation(camera.CFrame)
        local flat = CFrame.Angles(0, yaw, roll) + camera.CFrame.Position
        local os = pointToObjectSpace(flat, head.Position)
        local angle = math.atan2(os.Z, os.X)
        self.direction = Vector2.new(math.cos(angle), math.sin(angle))
    end
end

function EspObject:Render()
    local on, en = self.onScreen or false, self.enabled or false
    local v, h, b3, i = self.drawings.visible, self.drawings.hidden, self.drawings.box3d, self.interface
    local o, c = self.options, self.corners

    v.box.Visible = en and on and o.box
    v.boxOutline.Visible = v.box.Visible and o.boxOutline
    if v.box.Visible then
        v.box.Position = c.topLeft
        v.box.Size = c.bottomRight - c.topLeft
        v.box.Color = o.boxColor[1]
        v.box.Transparency = o.boxColor[2]
        v.boxOutline.Position = v.box.Position
        v.boxOutline.Size = v.box.Size
        v.boxOutline.Color = o.boxOutlineColor[1]
        v.boxOutline.Transparency = o.boxOutlineColor[2]
    end

    v.boxFill.Visible = en and on and o.boxFill
    if v.boxFill.Visible then
        v.boxFill.Position = c.topLeft
        v.boxFill.Size = c.bottomRight - c.topLeft
        v.boxFill.Color = o.boxFillColor[1]
        v.boxFill.Transparency = o.boxFillColor[2]
    end

    v.healthBar.Visible = en and on and o.healthBar
    v.healthBarOutline.Visible = v.healthBar.Visible and o.healthBarOutline
    if v.healthBar.Visible then
        local bf = c.topLeft - HEALTH_BAR_OFFSET
        local bt = c.bottomLeft - HEALTH_BAR_OFFSET
        v.healthBar.To = bt
        v.healthBar.From = lerp2(bt, bf, self.health/self.maxHealth)
        v.healthBar.Color = lerpColor(o.dyingColor, o.healthyColor, self.health/self.maxHealth)
        v.healthBarOutline.To = bt + HEALTH_BAR_OUTLINE_OFFSET
        v.healthBarOutline.From = bf - HEALTH_BAR_OUTLINE_OFFSET
        v.healthBarOutline.Color = o.healthBarOutlineColor[1]
        v.healthBarOutline.Transparency = o.healthBarOutlineColor[2]
    end

    v.healthText.Visible = en and on and o.healthText
    if v.healthText.Visible then
        local bf = c.topLeft - HEALTH_BAR_OFFSET
        local bt = c.bottomLeft - HEALTH_BAR_OFFSET
        v.healthText.Text = round(self.health) .. "hp"
        v.healthText.Size = i.sharedSettings.textSize
        v.healthText.Font = i.sharedSettings.textFont
        v.healthText.Color = o.healthTextColor[1]
        v.healthText.Transparency = o.healthTextColor[2]
        v.healthText.Outline = o.healthTextOutline
        v.healthText.OutlineColor = o.healthTextOutlineColor
        v.healthText.Position = lerp2(bt, bf, self.health/self.maxHealth) - v.healthText.TextBounds*0.5 - HEALTH_TEXT_OFFSET
    end

    v.name.Visible = en and on and o.name
    if v.name.Visible then
        v.name.Size = i.sharedSettings.textSize
        v.name.Font = i.sharedSettings.textFont
        v.name.Color = o.nameColor[1]
        v.name.Transparency = o.nameColor[2]
        v.name.Outline = o.nameOutline
        v.name.OutlineColor = o.nameOutlineColor
        v.name.Position = (c.topLeft + c.topRight)*0.5 - Vector2.yAxis*v.name.TextBounds.Y - NAME_OFFSET
    end

    v.distance.Visible = en and on and self.distance and o.distance
    if v.distance.Visible then
        v.distance.Text = round(self.distance) .. " studs"
        v.distance.Size = i.sharedSettings.textSize
        v.distance.Font = i.sharedSettings.textFont
        v.distance.Color = o.distanceColor[1]
        v.distance.Transparency = o.distanceColor[2]
        v.distance.Outline = o.distanceOutline
        v.distance.OutlineColor = o.distanceOutlineColor
        v.distance.Position = (c.bottomLeft + c.bottomRight)*0.5 + DISTANCE_OFFSET
    end

    v.weapon.Visible = en and on and o.weapon
    if v.weapon.Visible then
        v.weapon.Text = self.weapon
        v.weapon.Size = i.sharedSettings.textSize
        v.weapon.Font = i.sharedSettings.textFont
        v.weapon.Color = o.weaponColor[1]
        v.weapon.Transparency = o.weaponColor[2]
        v.weapon.Outline = o.weaponOutline
        v.weapon.OutlineColor = o.weaponOutlineColor
        v.weapon.Position = (c.bottomLeft + c.bottomRight)*0.5 +
            (v.distance.Visible and DISTANCE_OFFSET + Vector2.yAxis*v.distance.TextBounds.Y or Vector2.zero)
    end

    v.tracer.Visible = en and on and o.tracer
    v.tracerOutline.Visible = v.tracer.Visible and o.tracerOutline
    if v.tracer.Visible then
        v.tracer.Color = o.tracerColor[1]
        v.tracer.Transparency = o.tracerColor[2]
        v.tracer.To = (c.bottomLeft + c.bottomRight)*0.5
        v.tracer.From = o.tracerOrigin == "Middle" and viewportSize*0.5 or
                        o.tracerOrigin == "Top" and viewportSize*Vector2.new(0.5,0) or
                        viewportSize*Vector2.new(0.5,1)
        v.tracerOutline.Color = o.tracerOutlineColor[1]
        v.tracerOutline.Transparency = o.tracerOutlineColor[2]
        v.tracerOutline.To = v.tracer.To
        v.tracerOutline.From = v.tracer.From
    end

    h.arrow.Visible = en and (not on) and o.offScreenArrow
    h.arrowOutline.Visible = h.arrow.Visible and o.offScreenArrowOutline
    if h.arrow.Visible then
        h.arrow.PointA = min2(max2(viewportSize*0.5 + self.direction*o.offScreenArrowRadius, Vector2.one*25), viewportSize - Vector2.one*25)
        h.arrow.PointB = h.arrow.PointA - rotateVector(self.direction, 0.45)*o.offScreenArrowSize
        h.arrow.PointC = h.arrow.PointA - rotateVector(self.direction, -0.45)*o.offScreenArrowSize
        h.arrow.Color = o.offScreenArrowColor[1]
        h.arrow.Transparency = o.offScreenArrowColor[2]
        h.arrowOutline.PointA = h.arrow.PointA
        h.arrowOutline.PointB = h.arrow.PointB
        h.arrowOutline.PointC = h.arrow.PointC
        h.arrowOutline.Color = o.offScreenArrowOutlineColor[1]
        h.arrowOutline.Transparency = o.offScreenArrowOutlineColor[2]
    end

    local b3on = en and on and o.box3d
    for i1 = 1, #b3 do
        local face = b3[i1]
        for i2 = 1, #face do
            face[i2].Visible = b3on
            face[i2].Color = o.box3dColor[1]
            face[i2].Transparency = o.box3dColor[2]
        end
        if b3on then
            face[1].From = c.corners[i1]
            face[1].To = c.corners[i1 == 4 and 1 or i1+1]
            face[2].From = c.corners[i1 == 4 and 1 or i1+1]
            face[2].To = c.corners[i1 == 4 and 5 or i1+5]
            face[3].From = c.corners[i1 == 4 and 5 or i1+5]
            face[3].To = c.corners[i1 == 4 and 8 or i1+4]
        end
    end
end

-- ============================================================
-- Cham object — the fix
-- ============================================================
local ChamObject = {}
ChamObject.__index = ChamObject

function ChamObject.new(player, interface)
    local self = setmetatable({}, ChamObject)
    self.player = player
    self.interface = interface
    self.highlight = Instance.new("Highlight", container)
    self._tick = 0
    self.updateConnection = runService.Heartbeat:Connect(function() self:Update() end)
    return self
end

function ChamObject:Destruct()
    self.updateConnection:Disconnect()
    self.highlight:Destroy()
end

-- Priority order for Adornee — nested Model (Body) wins over outer Model
-- because Roblox silently fails to render Highlight when Adornee is a Model
-- whose only BaseParts are nested inside ANOTHER Model. Preferring Body
-- guarantees Roblox finds the visible MeshParts.
local function resolveAdornee(char)
    if not char then return nil, "no-char" end

    -- PRIORITY 1: Body — this is where the visible MeshParts actually live
    local body = char:FindFirstChild("Body")
    if body then
        if body:IsA("Model") then
            return body, "body-model"
        end
        if body:IsA("BasePart") then
            return body, "body-part"
        end
    end

    -- PRIORITY 2: char itself (Model or BasePart, no nested structure)
    if char:IsA("Model") or char:IsA("BasePart") then
        return char, "char-model"
    end

    -- Fallback: walk up from any descendant BasePart to find a Model ancestor
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            local p = d
            while p and p ~= char do
                if p:IsA("Model") then return p, "ancestor-model" end
                p = p.Parent
            end
        end
    end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then return d, "part-fallback" end
    end
    return nil, "no-adornee"
end

-- True if the Body has any parts that will actually render. Highlight can't
-- render on fully-transparent parts, so if all of them are Transparency=1
-- there's no point spending a highlight slot on them.
local function hasVisibleParts(body)
    if not body then return false end
    if body:IsA("BasePart") then return body.Transparency < 1 end
    for _, d in ipairs(body:GetDescendants()) do
        if d:IsA("BasePart") and d.Transparency < 1 then
            return true
        end
    end
    return false
end

function ChamObject:Update()
    local i = self.interface
    local char = i.getCharacter(self.player)
    local o = i.teamSettings[i.isFriendly(self.player) and "friendly" or "enemy"]
    local en = o.enabled and char ~= nil
        and not (#i.whitelist > 0 and not find(i.whitelist, self.player.UserId))
    if char == cachedLocalChar then en = false end

    local adornee, mode = nil, "disabled"
    if en then adornee, mode = resolveAdornee(char) end

    -- Skip if the target is currently invisible (dead, downed, etc.) — the
    -- highlight won't render anyway and it saves the render slot.
    local visible = adornee ~= nil and (
        adornee:IsA("BasePart") and adornee.Transparency < 1
        or adornee:IsA("Model") and hasVisibleParts(adornee)
    )
    local wantChams = en and o.chams and adornee ~= nil and visible
    self.lastMode = mode

    -- Roblox loses Adornee bind over time (known bug). Force re-set the
    -- Adornee reference every ~2 seconds so it re-acquires the parts list.
    self._tick = (self._tick or 0) + 1
    local forceRebind = (self._tick % 120) == 0

    self.highlight.Enabled = wantChams
    if wantChams then
        self.highlight.DepthMode =
            o.chamsVisibleOnly and Enum.HighlightDepthMode.Occluded
            or Enum.HighlightDepthMode.AlwaysOnTop
        if forceRebind or self.highlight.Adornee ~= adornee then
            -- null out first so Roblox definitely rebuilds the parts list
            self.highlight.Adornee = nil
            self.highlight.Adornee = adornee
        end
        self.highlight.FillColor           = o.chamsFillColor[1]
        self.highlight.FillTransparency    = o.chamsFillColor[2]
        self.highlight.OutlineColor        = o.chamsOutlineColor[1]
        self.highlight.OutlineTransparency = o.chamsOutlineColor[2]
    end
end

-- ============================================================
-- Interface
-- ============================================================
local EspInterface = {
    _hasLoaded = false,
    _objectCache = {},
    whitelist = {},
    sharedSettings = { textSize = 13, textFont = 2, limitDistance = false, maxDistance = 150 },
    teamSettings = {
        enemy = {
            enabled=false, box=false, boxColor={Color3.new(1,0,0),1},
            boxOutline=true, boxOutlineColor={Color3.new(),1},
            boxFill=false, boxFillColor={Color3.new(1,0,0),0.5},
            healthBar=false, healthyColor=Color3.new(0,1,0), dyingColor=Color3.new(1,0,0),
            healthBarOutline=true, healthBarOutlineColor={Color3.new(),0.5},
            healthText=false, healthTextColor={Color3.new(1,1,1),1},
            healthTextOutline=true, healthTextOutlineColor=Color3.new(),
            box3d=false, box3dColor={Color3.new(1,0,0),1},
            name=false, nameColor={Color3.new(1,1,1),1}, nameOutline=true, nameOutlineColor=Color3.new(),
            weapon=false, weaponColor={Color3.new(1,1,1),1}, weaponOutline=true, weaponOutlineColor=Color3.new(),
            distance=false, distanceColor={Color3.new(1,1,1),1}, distanceOutline=true, distanceOutlineColor=Color3.new(),
            isChasing=false, isChasingColor={Color3.new(1,1,1),1}, isChasingOutline=true, isChasingOutlineColor=Color3.new(),
            tracer=false, tracerOrigin="Bottom", tracerColor={Color3.new(1,0,0),1},
            tracerOutline=true, tracerOutlineColor={Color3.new(),1},
            offScreenArrow=false, offScreenArrowColor={Color3.new(1,1,1),1},
            offScreenArrowSize=15, offScreenArrowRadius=150,
            offScreenArrowOutline=true, offScreenArrowOutlineColor={Color3.new(),1},
            chams=false, chamsVisibleOnly=false,
            chamsFillColor={Color3.new(0.2,0.2,0.2),0.5}, chamsOutlineColor={Color3.new(1,0,0),0},
        },
        friendly = {
            enabled=false, box=false, boxColor={Color3.new(0,1,0),1},
            boxOutline=true, boxOutlineColor={Color3.new(),1},
            boxFill=false, boxFillColor={Color3.new(0,1,0),0.5},
            healthBar=false, healthyColor=Color3.new(0,1,0), dyingColor=Color3.new(1,0,0),
            healthBarOutline=true, healthBarOutlineColor={Color3.new(),0.5},
            healthText=false, healthTextColor={Color3.new(1,1,1),1},
            healthTextOutline=true, healthTextOutlineColor=Color3.new(),
            box3d=false, box3dColor={Color3.new(0,1,0),1},
            name=false, nameColor={Color3.new(1,1,1),1}, nameOutline=true, nameOutlineColor=Color3.new(),
            weapon=false, weaponColor={Color3.new(1,1,1),1}, weaponOutline=true, weaponOutlineColor=Color3.new(),
            distance=false, distanceColor={Color3.new(1,1,1),1}, distanceOutline=true, distanceOutlineColor=Color3.new(),
            tracer=false, tracerOrigin="Bottom", tracerColor={Color3.new(0,1,0),1},
            tracerOutline=true, tracerOutlineColor={Color3.new(),1},
            offScreenArrow=false, offScreenArrowColor={Color3.new(1,1,1),1},
            offScreenArrowSize=15, offScreenArrowRadius=150,
            offScreenArrowOutline=true, offScreenArrowOutlineColor={Color3.new(),1},
            chams=false, chamsVisibleOnly=false,
            chamsFillColor={Color3.new(0.2,0.2,0.2),0.5}, chamsOutlineColor={Color3.new(0,1,0),0},
        },
    },
}

function EspInterface.isFriendly(player)
    local character = type(player) == "table" and player._character or player
    if not character or typeof(character) ~= "Instance" then return false end
    if character == cachedLocalChar then return true end
    return onTeam(character)
end

function EspInterface.getCharacter(player)
    return type(player) == "table" and player._character or player
end

function EspInterface.getHealth(character)
    if typeof(character) ~= "Instance" then return 100, 100 end
    local h = character:FindFirstChild("Health")
    if h and h:IsA("NumberValue") then
        local mx = h:FindFirstChild("MaxHealth")
        return h.Value, (mx and mx:IsA("NumberValue") and mx.Value) or 100
    end
    return 100, 100
end

function EspInterface.getWeapon(player)
    local char = type(player) == "table" and player._character or player
    if typeof(char) ~= "Instance" then return "Unknown" end
    local bp = char:FindFirstChild("Backpack")
    if not bp then return "Unknown" end
    local eq = bp:FindFirstChild("Equipped")
    if eq and eq:IsA("ObjectValue") and eq.Value then return eq.Value.Name end
    for _, slot in ipairs({"Primary","Secondary","Melee","Throwable"}) do
        local s = bp:FindFirstChild(slot)
        if s and s:IsA("ObjectValue") and s.Value then return s.Value.Name end
    end
    return "None"
end

function EspInterface.Load()
    assert(not EspInterface._hasLoaded, "already loaded")
    local folder = workspace:FindFirstChild("Characters") or workspace:WaitForChild("Characters", 30)
    if not folder then warn("[ESP] no Characters folder") return end

    local function create(char)
        if char == getLocalCharacter() then return end
        if EspInterface._objectCache[char] then return end
        local playerLike = {
            Name = char.Name, DisplayName = char.Name,
            UserId = char.Name, _character = char,
        }
        EspInterface._objectCache[char] = {
            EspObject.new(playerLike, EspInterface),
            ChamObject.new(playerLike, EspInterface),
        }
    end

    local function remove(char)
        local o = EspInterface._objectCache[char]
        if o then
            for i = 1, #o do o[i]:Destruct() end
            EspInterface._objectCache[char] = nil
        end
    end

    for _, c in ipairs(folder:GetChildren()) do create(c) end
    EspInterface._characterAdded = folder.ChildAdded:Connect(create)
    EspInterface._characterRemoving = folder.ChildRemoved:Connect(remove)
    EspInterface._hasLoaded = true
end

function EspInterface.Unload()
    assert(EspInterface._hasLoaded, "not loaded")
    for _, o in next, EspInterface._objectCache do
        for i = 1, #o do o[i]:Destruct() end
    end
    EspInterface._characterAdded:Disconnect()
    EspInterface._characterRemoving:Disconnect()
    EspInterface._hasLoaded = false
end


function EspInterface.RefreshChams()
    for _, objs in pairs(EspInterface._objectCache) do
        local cham = objs[2]
        if cham and cham.highlight then
            cham.highlight.Adornee = nil
            cham._tick = 0
        end
    end
    print("[chams] rebind forced on all highlights")
end

function EspInterface.DebugChams()
    local friendlyCount, enemyCount = 0, 0
    local friendlyChams, enemyChams, enemyMissing = 0, 0, 0
    print("[chams] === per-character ===")
    for char, objs in pairs(EspInterface._objectCache) do
        local isFriend = EspInterface.isFriendly(char)
        if isFriend then friendlyCount = friendlyCount + 1 else enemyCount = enemyCount + 1 end
        local cham = objs[2]
        local body = char:FindFirstChild("Body")
        local adornee, mode = resolveAdornee(char)
        local visible = adornee ~= nil and (
            adornee:IsA("BasePart") and adornee.Transparency < 1
            or adornee:IsA("Model") and hasVisibleParts(adornee))
        local hlState = cham and cham.highlight and tostring(cham.highlight.Enabled) or "?"
        if isFriend then
            if hlState == "true" then friendlyChams = friendlyChams + 1 end
        else
            if hlState == "true" then enemyChams = enemyChams + 1 else enemyMissing = enemyMissing + 1 end
        end
        print(string.format("  %s %-8s | body=%s | resolved=%s(%s) | visible=%s | hl.Enabled=%s",
            (isFriend and "[F]" or "[E]"),
            char.Name:sub(1, 8),
            body and body.ClassName or "nil",
            adornee and (adornee.ClassName .. ":" .. adornee.Name:sub(1,8)) or "nil",
            mode,
            tostring(visible),
            hlState))
    end
    print(string.format("[chams] buckets: %d friendly (chams=%d), %d enemy (chams=%d, missing=%d)",
        friendlyCount, friendlyChams, enemyCount, enemyChams, enemyMissing))
    local function countHL(root)
        local c = 0
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("Highlight") and d.Enabled then c = c + 1 end
        end
        return c
    end
    print(string.format("[chams] active Highlights: ours=%d workspace=%d lighting=%d TOTAL=%d (cap ~31)",
        countHL(container), countHL(workspace), countHL(game:GetService("Lighting")),
        countHL(container) + countHL(workspace) + countHL(game:GetService("Lighting"))))
end

return EspInterface
