--[[
	QTESystem - Sistema de Quick Time Events
	LocalScript em StarterPlayer > StarterPlayerScripts
	
	✅ Sistema de inputs configurável
	✅ Feedback visual e sonoro
	✅ Cálculo de performance
	✅ Animações suaves
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Módulos
-- ⚠️ v110: este QTE é do sistema ANTIGO de Hissatsu (antes do Pulso/Instinto)
-- e o módulo HissatsuData não existe mais — dava erro vermelho em todo
-- carregamento do Lobby. Agora só sai quieto. (Pode apagar este LocalScript
-- no Studio: nada no Lobby usa ele.)
local pastaModulos = ReplicatedStorage:FindFirstChild("Modules")
local moduloHissatsu = pastaModulos and pastaModulos:FindFirstChild("HissatsuData")
if not moduloHissatsu then return end
local HissatsuData = require(moduloHissatsu)

-- ========================================
-- CONFIGURAÇÃO
-- ========================================
local QTESystem = {
	Active = false,
	CurrentSequence = {},
	CurrentIndex = 1,
	SuccessCount = 0,
	TotalTime = 0,
	ElapsedTime = 0,
	HitWindow = 0.5,
	Callback = nil,

	-- UI
	GUI = nil,
	KeyFrames = {},
	ProgressBar = nil,
	PerformanceLabel = nil
}

-- ========================================
-- CRIAR UI DO QTE
-- ========================================
function QTESystem:CreateUI()
	-- Criar ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "QTESystem"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Container principal
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0.6, 0, 0.25, 0)
	mainFrame.Position = UDim2.new(0.5, 0, 0.75, 0)
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	mainFrame.BackgroundTransparency = 0.3
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	-- Corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 15)
	corner.Parent = keyFrame

	-- Stroke (borda)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 100, 150)
	stroke.Thickness = 3
	stroke.Transparency = 0.5
	stroke.Parent = keyFrame

	-- Texto da tecla
	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.Size = UDim2.new(1, 0, 1, 0)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Text = key:upper()
	keyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	keyLabel.TextSize = 36
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextStrokeTransparency = 0.5
	keyLabel.Parent = keyFrame

	-- Indicador de status
	local statusIndicator = Instance.new("Frame")
	statusIndicator.Name = "StatusIndicator"
	statusIndicator.Size = UDim2.new(0, 15, 0, 15)
	statusIndicator.Position = UDim2.new(1, -10, 0, 10)
	statusIndicator.AnchorPoint = Vector2.new(1, 0)
	statusIndicator.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	statusIndicator.BorderSizePixel = 0
	statusIndicator.Visible = false
	statusIndicator.Parent = keyFrame

	local indicatorCorner = Instance.new("UICorner")
	indicatorCorner.CornerRadius = UDim.new(1, 0)
	indicatorCorner.Parent = statusIndicator

	return keyFrame
end

-- ========================================
-- INICIAR QTE
-- ========================================
function QTESystem:Start(hissatsuID, playerAura, callback)
	if self.Active then
		warn("⚠️ QTE já está ativo!")
		return
	end

	local hissatsu = HissatsuData:GetHissatsu(hissatsuID)
	if not hissatsu then
		warn("❌ Hissatsu não encontrada:", hissatsuID)
		return
	end

	print(string.format("🎯 Iniciando QTE para %s", hissatsu.Name))

	-- Resetar estado
	self.Active = true
	self.CurrentSequence = hissatsu.QTE.Sequence
	self.CurrentIndex = 1
	self.SuccessCount = 0
	self.HitWindow = hissatsu.QTE.HitWindow
	self.Callback = callback
	self.TotalTime = HissatsuData:CalculateQTEDuration(hissatsuID, playerAura)
	self.ElapsedTime = 0

	-- Criar UI se não existir
	if not self.GUI then
		self:CreateUI()
	end

	-- Limpar teclas antigas
	for _, child in ipairs(self.KeysContainer:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	self.KeyFrames = {}

	-- Criar frames de teclas
	for i, key in ipairs(self.CurrentSequence) do
		local keyFrame = self:CreateKeyFrame(key)
		keyFrame.Parent = self.KeysContainer
		table.insert(self.KeyFrames, keyFrame)
	end

	-- Destacar primeira tecla
	self:HighlightCurrentKey()

	-- Mostrar UI
	self.GUI.Enabled = true
	self:UpdatePerformanceLabel()

	-- Iniciar countdown
	self:StartCountdown()
end

-- ========================================
-- DESTACAR TECLA ATUAL
-- ========================================
function QTESystem:HighlightCurrentKey()
	for i, frame in ipairs(self.KeyFrames) do
		local stroke = frame:FindFirstChildOfClass("UIStroke")

		if i == self.CurrentIndex then
			-- Tecla atual: destaque
			frame.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
			stroke.Color = Color3.fromRGB(255, 215, 0)
			stroke.Thickness = 4
			stroke.Transparency = 0

			-- Animação de pulse
			self:PulseAnimation(frame)
		elseif i < self.CurrentIndex then
			-- Teclas já pressionadas: manter status
			-- (já foi marcado como sucesso/erro)
		else
			-- Teclas futuras: escurecidas
			frame.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
			stroke.Color = Color3.fromRGB(100, 100, 150)
			stroke.Thickness = 3
			stroke.Transparency = 0.5
		end
	end
end

-- ========================================
-- PROCESSAR INPUT
-- ========================================
function QTESystem:ProcessInput(input)
	if not self.Active then return end

	local expectedKey = self.CurrentSequence[self.CurrentIndex]
	local pressedKey = input.KeyCode.Name:upper()

	-- Verificar se é a tecla correta
	if pressedKey == expectedKey:upper() then
		self:OnCorrectInput()
	else
		self:OnWrongInput()
	end
end

-- ========================================
-- INPUT CORRETO
-- ========================================
function QTESystem:OnCorrectInput()
	self.SuccessCount = self.SuccessCount + 1

	local currentFrame = self.KeyFrames[self.CurrentIndex]
	local statusIndicator = currentFrame:FindFirstChild("StatusIndicator")

	-- Feedback visual
	currentFrame.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	local stroke = currentFrame:FindFirstChildOfClass("UIStroke")
	stroke.Color = Color3.fromRGB(100, 255, 100)

	if statusIndicator then
		statusIndicator.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		statusIndicator.Visible = true
	end

	-- Som de sucesso (opcional)
	self:PlaySound("Success")

	-- Próxima tecla
	self.CurrentIndex = self.CurrentIndex + 1
	self:UpdatePerformanceLabel()

	if self.CurrentIndex > #self.CurrentSequence then
		-- Sequência completa!
		self:Complete()
	else
		self:HighlightCurrentKey()
	end
end

-- ========================================
-- INPUT ERRADO
-- ========================================
function QTESystem:OnWrongInput()
	local currentFrame = self.KeyFrames[self.CurrentIndex]
	local statusIndicator = currentFrame:FindFirstChild("StatusIndicator")

	-- Feedback visual
	currentFrame.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	local stroke = currentFrame:FindFirstChildOfClass("UIStroke")
	stroke.Color = Color3.fromRGB(255, 100, 100)

	if statusIndicator then
		statusIndicator.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		statusIndicator.Visible = true
	end

	-- Som de erro (opcional)
	self:PlaySound("Fail")

	-- Shake animation
	self:ShakeAnimation(currentFrame)

	-- Próxima tecla (QTE continua mesmo com erro)
	self.CurrentIndex = self.CurrentIndex + 1
	self:UpdatePerformanceLabel()

	if self.CurrentIndex > #self.CurrentSequence then
		self:Complete()
	else
		task.wait(0.2)
		self:HighlightCurrentKey()
	end
end

-- ========================================
-- COUNTDOWN DE TEMPO
-- ========================================
function QTESystem:StartCountdown()
	local connection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not self.Active then
			connection:Disconnect()
			return
		end

		self.ElapsedTime = self.ElapsedTime + deltaTime
		local remaining = 1 - (self.ElapsedTime / self.TotalTime)

		-- Atualizar barra de progresso
		self.ProgressBar.Size = UDim2.new(remaining, 0, 1, 0)

		-- Mudar cor conforme tempo
		if remaining > 0.5 then
			self.ProgressBar.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
		elseif remaining > 0.25 then
			self.ProgressBar.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
		else
			self.ProgressBar.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
		end

		-- Timeout
		if self.ElapsedTime >= self.TotalTime then
			self:Timeout()
		end
	end)
end

-- ========================================
-- TIMEOUT (TEMPO ESGOTADO)
-- ========================================
function QTESystem:Timeout()
	print("⏱️ QTE Timeout!")

	-- Marcar teclas restantes como erro
	for i = self.CurrentIndex, #self.KeyFrames do
		local frame = self.KeyFrames[i]
		frame.BackgroundColor3 = Color3.fromRGB(100, 50, 50)

		local statusIndicator = frame:FindFirstChild("StatusIndicator")
		if statusIndicator then
			statusIndicator.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			statusIndicator.Visible = true
		end
	end

	task.wait(0.5)
	self:Complete()
end

-- ========================================
-- COMPLETAR QTE
-- ========================================
function QTESystem:Complete()
	self.Active = false

	local totalKeys = #self.CurrentSequence
	local successRate = self.SuccessCount / totalKeys

	-- Determinar performance
	local performance
	if successRate >= 1.0 then
		performance = "PERFECT"
	elseif successRate >= 0.8 then
		performance = "GOOD"
	elseif successRate >= 0.5 then
		performance = "OKAY"
	else
		performance = "POOR"
	end

	print(string.format("✅ QTE Completo: %s (%d/%d)", performance, self.SuccessCount, totalKeys))

	-- Mostrar resultado final
	self:ShowResult(performance, successRate)

	-- Callback com resultados
	if self.Callback then
		self.Callback({
			Success = self.SuccessCount,
			Total = totalKeys,
			SuccessRate = successRate,
			Performance = performance
		})
	end

	-- Fechar UI
	task.wait(1.5)
	if self.GUI then
		self.GUI.Enabled = false
	end
end

-- ========================================
-- MOSTRAR RESULTADO
-- ========================================
function QTESystem:ShowResult(performance, rate)
	local mainFrame = self.GUI.MainFrame

	-- Criar label de resultado
	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "ResultLabel"
	resultLabel.Size = UDim2.new(1, 0, 0.5, 0)
	resultLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	resultLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Text = performance
	resultLabel.TextSize = 60
	resultLabel.Font = Enum.Font.GothamBold
	resultLabel.TextStrokeTransparency = 0.5
	resultLabel.ZIndex = 10
	resultLabel.TextTransparency = 1
	resultLabel.Parent = mainFrame

	-- Cores por performance
	if performance == "PERFECT" then
		resultLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	elseif performance == "GOOD" then
		resultLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	elseif performance == "OKAY" then
		resultLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	else
		resultLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	end

	-- Animação de fade in
	local tween = TweenService:Create(
		resultLabel,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{TextTransparency = 0}
	)
	tween:Play()

	-- Animação de scale
	resultLabel.Size = UDim2.new(0.5, 0, 0.3, 0)
	local scaleTween = TweenService:Create(
		resultLabel,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.new(1, 0, 0.5, 0)}
	)
	scaleTween:Play()
end

-- ========================================
-- ATUALIZAR LABEL DE PERFORMANCE
-- ========================================
function QTESystem:UpdatePerformanceLabel()
	local completed = self.CurrentIndex - 1
	local total = #self.CurrentSequence

	self.PerformanceLabel.Text = string.format("%d/%d acertos", self.SuccessCount, completed)
end

-- ========================================
-- ANIMAÇÕES
-- ========================================
function QTESystem:PulseAnimation(frame)
	local originalSize = frame.Size

	local tween = TweenService:Create(
		frame,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
		{Size = originalSize * 1.1}
	)

	tween:Play()

	task.delay(1, function()
		tween:Cancel()
		frame.Size = originalSize
	end)
end

function QTESystem:ShakeAnimation(frame)
	local originalPos = frame.Position

	for i = 1, 5 do
		frame.Position = originalPos + UDim2.new(0, math.random(-5, 5), 0, math.random(-5, 5))
		task.wait(0.05)
	end

	frame.Position = originalPos
end

-- ========================================
-- SOM (PLACEHOLDER)
-- ========================================
function QTESystem:PlaySound(soundType)
	-- TODO: Implementar sons
	-- local sound = Instance.new("Sound")
	-- sound.SoundId = soundType == "Success" and "rbxassetid://..." or "rbxassetid://..."
	-- sound.Parent = workspace
	-- sound:Play()
end

-- ========================================
-- CONECTAR INPUTS
-- ========================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		QTESystem:ProcessInput(input)
	end
end)

-- ========================================
-- FUNÇÃO GLOBAL PARA TESTAR
-- ========================================
_G.TestQTE = function(hissatsuID)
	QTESystem:Start(hissatsuID or "shot_pocket_001", 50, function(result)
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print("🎯 RESULTADO DO QTE:")
		print(string.format("   Acertos: %d/%d", result.Success, result.Total))
		print(string.format("   Taxa: %.1f%%", result.SuccessRate * 100))
		print(string.format("   Performance: %s", result.Performance))
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	end)
end

print("✅ QTESystem carregado!")
print("   Use _G.TestQTE('hissatsu_id') para testar")

-- ⚠️ v68 — ARQUIVO ESTAVA CORROMPIDO E NÃO COMPILAVA.
-- A linha final era `return QTESystemner")`, ou seja, `return QTESystem`
-- grudado no meio de um `Instance.new("UICorner")`. Depois dela vinham ~89
-- linhas de uma VERSÃO ANTIGA deste mesmo script, emendadas por engano:
-- elas referenciavam `mainFrame`, que não existe naquele escopo, e o
-- fragmento terminava cortado no meio de uma função.
--
-- Com isso o script INTEIRO não carregava (erro de sintaxe), então o
-- QTESystem nunca chegou a existir no lobby. O trecho órfão foi removido;
-- o script completo é tudo que vem acima desta linha.
return QTESystem
