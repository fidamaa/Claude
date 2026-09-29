--[[
	PorteFisico (ModuleScript) — ⚠️ v105
	⚠️ Existe IGUAL em Game/ReplicatedStorage e Lobby/ReplicatedStorage (não
	existe require entre places) — mude os dois juntos.

	PEDIDO: "coloca também limite de altura — pra limitar personagem grandão,
	pra ficar todo mundo no mesmo tamanho. A não ser que você tenha muito
	físico: aí o personagem fica mais parrudo, mais alto e mais largo."

	No R6 o Roblox já ignora a escala do avatar (todo mundo nasce do mesmo
	tamanho) — o "limite" vem de graça. Aqui entra só o PORTE pelo Físico:
	  • Físico até LIMIAR: tamanho padrão (todo mundo igual);
	  • de LIMIAR até 100: cresce aos poucos até ALTURA_MAX de altura (escala
	    do modelo inteiro) e, além disso, LARGURA_MAX de tronco (mais largo e
	    mais fundo — ombros e quadris acompanham).
	Idempotente: pode chamar de novo (respawn, Físico mudou) que ele desfaz o
	porte anterior antes de aplicar o novo.

	As posições de descanso das juntas ficam no atributo "C0Pos" de cada
	Motor6D — o AnimadorProcedural lê dali (senão ele reescreveria a junta na
	posição antiga, de antes do porte, e o braço ficaria solto do corpo).
]]

local Porte = {}

Porte.LIMIAR = 70        -- Físico a partir do qual o corpo começa a crescer
Porte.ALTURA_MAX = 1.08  -- escala de altura no Físico 100
Porte.LARGURA_MAX = 1.22 -- largura/profundidade EXTRA do tronco no Físico 100
Porte.QUADRIL_SEGUE = 0.5 -- quanto os quadris abrem junto com o tronco (0..1)

function Porte.Fatores(fisico)
	local f = math.clamp(((tonumber(fisico) or 50) - Porte.LIMIAR) / (100 - Porte.LIMIAR), 0, 1)
	return 1 + (Porte.ALTURA_MAX - 1) * f, 1 + (Porte.LARGURA_MAX - 1) * f
end

local JUNTAS_OMBRO = { "Right Shoulder", "Left Shoulder" }
local JUNTAS_QUADRIL = { "Right Hip", "Left Hip" }

local function escalarX(motor, k)
	if not motor or not motor:IsA("Motor6D") or k == 1 then return end
	local p = motor.C0.Position
	motor.C0 = CFrame.new(p.X * k, p.Y, p.Z) * motor.C0.Rotation
end

-- aplica (k > 1) ou desfaz (1/k) a largura extra
local function largura(character, k)
	local torso = character:FindFirstChild("Torso")
	if not torso or k == 1 then return end
	torso.Size = Vector3.new(torso.Size.X * k, torso.Size.Y, torso.Size.Z * k)
	for _, nome in ipairs(JUNTAS_OMBRO) do escalarX(torso:FindFirstChild(nome), k) end
	local kq = 1 + (k - 1) * Porte.QUADRIL_SEGUE
	if k < 1 then kq = 1 / (1 + (1 / k - 1) * Porte.QUADRIL_SEGUE) end
	for _, nome in ipairs(JUNTAS_QUADRIL) do escalarX(torso:FindFirstChild(nome), kq) end
end

local function gravarPosicoes(character)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") then d:SetAttribute("C0Pos", d.C0.Position) end
	end
end

-- Só no SERVIDOR (tamanho e juntas replicam pra todo mundo).
function Porte.Aplicar(character, fisico)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then return end
	local altura, larg = Porte.Fatores(fisico)

	-- desfaz a largura aplicada antes (o ScaleTo escala o que estiver lá)
	local anterior = character:GetAttribute("PorteLargura") or 1
	if anterior ~= 1 then largura(character, 1 / anterior) end

	pcall(function()
		if math.abs(character:GetScale() - altura) > 1e-3 then
			character:ScaleTo(altura)
		end
	end)

	largura(character, larg)
	character:SetAttribute("PorteLargura", larg)
	character:SetAttribute("PorteAltura", altura)
	gravarPosicoes(character)
end

return Porte
