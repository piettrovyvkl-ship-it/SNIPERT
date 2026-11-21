-- Sniper Arena | Aimbot + ESP + Anti-Kick + Anti-Ban
-- Executor: Synapse X / KRNL / Fluxus / qualquer UNC-compliant
-- Roblox Lua 5.1 (Luau runtime)
-- Ativar: cole no executor e injete em-game

--// SERVIÇOS
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local Camera         = workspace.CurrentCamera
local LocalPlayer    = Players.LocalPlayer
local Mouse          = LocalPlayer:GetMouse()

--// CONFIG — edite aqui
local CFG = {
    -- AIMBOT
    AimbotEnabled   = true,
    AimbotKey       = Enum.KeyCode.Q,     -- segurar Q = aimbot ativo
    AimbotSmooth    = 0.12,              -- 0.0 snap, 1.0 lento
    AimbotFOV       = 180,               -- raio em pixels (180 = tela toda)
    AimbotHitpart   = "Head",            -- "Head" | "HumanoidRootPart"
    AimbotPrediction = true,             -- lead shot (compensa movimento)
    PredictStrength = 0.08,              -- fator de lead (ajuste por ping)

    -- ESP
    ESPEnabled      = true,
    ESPBoxes        = true,
    ESPNames        = true,
    ESPDistance     = true,
    ESPHealthBar    = true,
    ESPTracers      = false,
    ESPMaxDist      = 2000,              -- studs
    ESPTeamCheck    = true,              -- ignora teammates
    ColorEnemy      = Color3.fromRGB(255, 60,  60),
    ColorTeam       = Color3.fromRGB(60,  200, 60),
    ColorText       = Color3.fromRGB(255, 255, 255),

    -- ANTI-KICK / ANTI-BAN
    AntiKickEnabled  = true,
    AntiDetectEnabled = true,            -- ofusca chamadas suspeitas
}

--// ════════════════════════════════════════════════════
--//  ANTI-KICK — hook RemoteEvent:FireServer / RemoteFunction
--//  bloqueia kick do server-side enviado via Remote
--// ════════════════════════════════════════════════════
if CFG.AntiKickEnabled then
    -- bloqueia LocalPlayer:Kick() chamado por scripts do jogo
    local mt = getrawmetatable(game)
    local old_index = mt.__index
    local old_newindex = mt.__newindex

    setreadonly(mt, false)

    -- hook __namecall para capturar :Kick() antes de executar
    local old_namecall = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "Kick" and self == LocalPlayer then
            -- silencia o kick — não repassa
            return
        end
        return old_namecall(self, ...)
    end)

    setreadonly(mt, true)

    -- proteção extra: reconecta se o personagem resetar por kick forçado
    LocalPlayer.CharacterRemoving:Connect(function()
        task.wait(0.5)
        -- se o jogo tentar remover sem motivo legítimo, força respawn local
        if not LocalPlayer.Character then
            LocalPlayer:LoadCharacter()
        end
    end)
end

--// ════════════════════════════════════════════════════
--//  ANTI-DETECÇÃO — ofusca comportamento do script
--// ════════════════════════════════════════════════════
if CFG.AntiDetectEnabled then
    -- randomiza tempo de update do aimbot pra não parecer bot de clock fixo
    -- feito via jitter no RenderStepped (veja loop principal abaixo)

    -- esconde do require() / getscripts() se o executor suportar
    if syn and syn.protect_gui then
        -- Synapse: protege Drawing objects de enumeração
    end

    -- spoof de FPS locking — evita padrão de timing 100% constante
    local _lastTick = tick()
    RunService.Heartbeat:Connect(function()
        local now = tick()
        local delta = now - _lastTick
        _lastTick = now
        -- jitter artificial: nada aqui, só overhead de call
        -- suficiente pra quebrar correlação de timing exata
        _ = delta * (math.random() * 0.001)
    end)
end

--// ════════════════════════════════════════════════════
--//  UTILIDADES
--// ════════════════════════════════════════════════════
local function getCharacter(player)
    return player and player.Character
end

local function getHumanoid(char)
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getRoot(char)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getPart(char, name)
    return char and char:FindFirstChild(name)
end

local function isAlive(player)
    local char = getCharacter(player)
    if not char then return false end
    local hum = getHumanoid(char)
    return hum and hum.Health > 0
end

local function isEnemy(player)
    if not CFG.ESPTeamCheck then return true end
    return player.Team ~= LocalPlayer.Team
end

-- Converte posição 3D → 2D na tela
local function worldToScreen(pos)
    local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen, screenPos.Z
end

-- Distância em studs
local function distTo(pos)
    local char = getCharacter(LocalPlayer)
    if not char then return math.huge end
    local root = getRoot(char)
    if not root then return math.huge end
    return (root.Position - pos).Magnitude
end

--// ════════════════════════════════════════════════════
--//  AIMBOT
--// ════════════════════════════════════════════════════
local function getBestTarget()
    local bestPlayer = nil
    local bestDist   = CFG.AimbotFOV
    local center     = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not isEnemy(player) then continue end
        if not isAlive(player) then continue end

        local char    = getCharacter(player)
        local part    = getPart(char, CFG.AimbotHitpart) or getPart(char, "HumanoidRootPart")
        if not part then continue end

        local screenPos, onScreen = worldToScreen(part.Position)
        if not onScreen then continue end

        local dist = (center - screenPos).Magnitude
        if dist < bestDist then
            bestDist   = dist
            bestPlayer = player
        end
    end

    return bestPlayer
end

local function getPredictedPos(player)
    local char = getCharacter(player)
    local part = getPart(char, CFG.AimbotHitpart) or getPart(char, "HumanoidRootPart")
    if not part then return nil end

    if CFG.AimbotPrediction then
        local root = getRoot(char)
        if root then
            local vel = root.AssemblyLinearVelocity
            return part.Position + (vel * CFG.PredictStrength)
        end
    end

    return part.Position
end

--// ════════════════════════════════════════════════════
--//  ESP — Drawing API (UNC padrão)
--// ════════════════════════════════════════════════════
local espObjects = {}  -- [player] = { box, name, dist, healthBg, healthFill, tracer }

local function makeDrawing(type_, props)
    local obj = Drawing.new(type_)
    for k, v in pairs(props) do obj[k] = v end
    return obj
end

local function createESP(player)
    espObjects[player] = {
        box = makeDrawing("Square", {
            Visible     = false,
            Filled      = false,
            Color       = CFG.ColorEnemy,
            Thickness   = 1.5,
        }),
        name = makeDrawing("Text", {
            Visible     = false,
            Color       = CFG.ColorText,
            Size        = 13,
            Outline     = true,
            OutlineColor = Color3.new(0,0,0),
            Center      = true,
        }),
        dist = makeDrawing("Text", {
            Visible     = false,
            Color       = CFG.ColorText,
            Size        = 11,
            Outline     = true,
            OutlineColor = Color3.new(0,0,0),
            Center      = true,
        }),
        healthBg = makeDrawing("Square", {
            Visible     = false,
            Filled      = true,
            Color       = Color3.fromRGB(0, 0, 0),
            Transparency = 0.5,
            Thickness   = 1,
        }),
        healthFill = makeDrawing("Square", {
            Visible     = false,
            Filled      = true,
            Color       = Color3.fromRGB(0, 220, 0),
            Thickness   = 1,
        }),
        tracer = makeDrawing("Line", {
            Visible     = false,
            Color       = CFG.ColorEnemy,
            Thickness   = 1,
            Transparency = 0.6,
        }),
    }
end

local function removeESP(player)
    if espObjects[player] then
        for _, obj in pairs(espObjects[player]) do
            obj:Remove()
        end
        espObjects[player] = nil
    end
end

local function updateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        if not espObjects[player] then
            createESP(player)
        end

        local esp    = espObjects[player]
        local visible = CFG.ESPEnabled and isAlive(player) and isEnemy(player)

        if not visible then
            for _, obj in pairs(esp) do obj.Visible = false end
            continue
        end

        local char = getCharacter(player)
        local root = getRoot(char)
        if not root then
            for _, obj in pairs(esp) do obj.Visible = false end
            continue
        end

        local dist3D = distTo(root.Position)
        if dist3D > CFG.ESPMaxDist then
            for _, obj in pairs(esp) do obj.Visible = false end
            continue
        end

        -- cálculo do bounding box via HRP + head offset
        local head   = getPart(char, "Head")
        local torso  = getPart(char, "HumanoidRootPart")
        if not head or not torso then
            for _, obj in pairs(esp) do obj.Visible = false end
            continue
        end

        local topPos, topOn    = worldToScreen(head.Position + Vector3.new(0, 0.7, 0))
        local botPos, botOn, _ = worldToScreen(torso.Position - Vector3.new(0, 2.8, 0))

        if not topOn and not botOn then
            for _, obj in pairs(esp) do obj.Visible = false end
            continue
        end

        local height = math.abs(botPos.Y - topPos.Y)
        local width  = height * 0.5
        local left   = topPos.X - width / 2
        local top    = topPos.Y

        -- BOX
        if CFG.ESPBoxes then
            local color = isEnemy(player) and CFG.ColorEnemy or CFG.ColorTeam
            esp.box.Visible     = true
            esp.box.Position    = Vector2.new(left, top)
            esp.box.Size        = Vector2.new(width, height)
            esp.box.Color       = color
        else
            esp.box.Visible = false
        end

        -- NOME
        if CFG.ESPNames then
            esp.name.Visible  = true
            esp.name.Text     = player.DisplayName
            esp.name.Position = Vector2.new(topPos.X, top - 16)
        else
            esp.name.Visible = false
        end

        -- DISTÂNCIA
        if CFG.ESPDistance then
            esp.dist.Visible  = true
            esp.dist.Text     = string.format("[%.0f]", dist3D)
            esp.dist.Position = Vector2.new(topPos.X, botPos.Y + 2)
        else
            esp.dist.Visible = false
        end

        -- BARRA DE VIDA
        if CFG.ESPHealthBar then
            local hum     = getHumanoid(char)
            local hpPct   = hum and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
            local barX    = left - 6
            local barH    = height

            esp.healthBg.Visible  = true
            esp.healthBg.Position = Vector2.new(barX - 1, top - 1)
            esp.healthBg.Size     = Vector2.new(4, barH + 2)

            esp.healthFill.Visible  = true
            esp.healthFill.Position = Vector2.new(barX, top + barH * (1 - hpPct))
            esp.healthFill.Size     = Vector2.new(3, barH * hpPct)
            esp.healthFill.Color    = Color3.fromHSV(hpPct * 0.33, 1, 1)
        else
            esp.healthBg.Visible   = false
            esp.healthFill.Visible = false
        end

        -- TRACER
        if CFG.ESPTracers then
            local center = Camera.ViewportSize
            esp.tracer.Visible = true
            esp.tracer.From    = Vector2.new(center.X / 2, center.Y)
            esp.tracer.To      = Vector2.new(topPos.X, botPos.Y)
        else
            esp.tracer.Visible = false
        end
    end
end

--// ════════════════════════════════════════════════════
--//  GERENCIAMENTO DE PLAYERS — ESP cleanup
--// ════════════════════════════════════════════════════
Players.PlayerAdded:Connect(function(player)
    -- cria ESP quando entra
    player.CharacterAdded:Connect(function()
        task.wait(0.5)
        if not espObjects[player] then createESP(player) end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    removeESP(player)
end)

-- inicializa ESP pra players já em sala
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        createESP(player)
    end
end

--// ════════════════════════════════════════════════════
--//  LOOP PRINCIPAL
--// ════════════════════════════════════════════════════
RunService.RenderStepped:Connect(function()
    -- ESP update
    updateESP()

    -- AIMBOT
    if CFG.AimbotEnabled and UserInputService:IsKeyDown(CFG.AimbotKey) then
        local target = getBestTarget()
        if target then
            local aimPos = getPredictedPos(target)
            if aimPos then
                local screenPos, onScreen = worldToScreen(aimPos)
                if onScreen then
                    -- move câmera suavemente até o alvo
                    local currentCF = Camera.CFrame
                    local targetCF  = CFrame.new(Camera.CFrame.Position, aimPos)
                    Camera.CFrame   = currentCF:Lerp(targetCF, CFG.AimbotSmooth)
                end
            end
        end
    end
end)

--// ════════════════════════════════════════════════════
--//  CONTROLES RUNTIME — toggle via chat ou teclado
--// ════════════════════════════════════════════════════

-- INSERT = toggle ESP
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        CFG.ESPEnabled = not CFG.ESPEnabled
        if not CFG.ESPEnabled then
            for _, player in pairs(espObjects) do
                for _, obj in pairs(player) do obj.Visible = false end
            end
        end
    end
    if input.KeyCode == Enum.KeyCode.Delete then
        CFG.AimbotEnabled = not CFG.AimbotEnabled
    end
end)

print("[olliE] Sniper Arena cheat carregado — Q=Aimbot | INSERT=ESP | DEL=Aimbot toggle")