--[[
	Cosmeticos (ModuleScript) — ⚠️ v110
	LOCAL: ReplicatedStorage (IGUAL nos dois places: Game e Lobby — Roblox não
	tem require entre places; mexeu num, copie pro outro)

	PEDIDO: "inclua todos os cosméticos... a aba de seleção pra escolher qual
	cosmético você quer — a moldura, você clica nela, expande uma tela e decide;
	uma cor ou outra, um título ou outro; cor no chat, e coloque tudo possível;
	o nome personalizado dos slots dentro do jogo; comemoração com animação pra
	cada uma; pelo menos 15 de cada: 15 comemorações, 15 emotes, 15 molduras,
	15 títulos..." + "cutscenes de Flow (Blue Lock) na loja pra escolher o flow;
	cada flow dá um buff diferente".

	Fonte ÚNICA de:
	  • os itens de cada categoria (a Loja do Lobby monta o catálogo daqui — ver
	    LobbyConfig.SHOP.Items; os Ids ANTIGOS da loja foram mantidos, quem já
	    comprou continua com o item);
	  • as poses dos Emotes e das Comemorações (mesmo formato das ações do
	    AnimacoesProcedurais — o Game registra como ações do animador; o Lobby
	    toca com o reprodutor simples do EmotesLobby);
	  • a placa de nome (nome do slot + título + tag + cor + moldura), montada
	    igual nos dois places;
	  • os FLOWS: buff de atributos e o tema visual da cutscene de cada um.

	Slots (= chave em playerData.EquippedCosmetics):
	  Frame, Title, Tag, NameColor, ChatColor, Emote, Celebration, Aura,
	  GoalEffect, Flow
]]

local C = {}

local V = Vector3.new
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

-- ============================================================
-- PREÇO POR RARIDADE
-- ============================================================
C.PRECO = { Common = 400, Rare = 800, Epic = 1300, Legendary = 2000, Mythic = 3200 }

-- ============================================================
-- MOLDURAS (borda da placa de nome e do cartão do personagem)
-- Cor1 -> Cor2 é o degradê da borda; Gira = o degradê gira devagar.
-- ============================================================
C.Frame = {
	{ Id = "Frame_Madeira", Nome = "Madeira", Raridade = "Common", Cor1 = rgb(150, 105, 60), Cor2 = rgb(95, 60, 30), Espessura = 2 },
	{ Id = "Frame_Bronze", Nome = "Bronze", Raridade = "Common", Cor1 = rgb(215, 140, 80), Cor2 = rgb(140, 80, 40), Espessura = 2 },
	{ Id = "Frame_Prata", Nome = "Prata", Raridade = "Common", Cor1 = rgb(235, 240, 250), Cor2 = rgb(140, 150, 165), Espessura = 2 },
	{ Id = "Frame_Gold", Nome = "Ouro", Raridade = "Rare", Cor1 = rgb(255, 225, 110), Cor2 = rgb(200, 140, 30), Espessura = 3 },
	{ Id = "Frame_Rubi", Nome = "Rubi", Raridade = "Rare", Cor1 = rgb(255, 90, 110), Cor2 = rgb(150, 10, 40), Espessura = 3 },
	{ Id = "Frame_Esmeralda", Nome = "Esmeralda", Raridade = "Rare", Cor1 = rgb(90, 240, 150), Cor2 = rgb(10, 120, 70), Espessura = 3 },
	{ Id = "Frame_Safira", Nome = "Safira", Raridade = "Rare", Cor1 = rgb(110, 170, 255), Cor2 = rgb(20, 60, 170), Espessura = 3 },
	{ Id = "Frame_Ametista", Nome = "Ametista", Raridade = "Epic", Cor1 = rgb(210, 140, 255), Cor2 = rgb(100, 30, 170), Espessura = 3 },
	{ Id = "Frame_Obsidiana", Nome = "Obsidiana", Raridade = "Epic", Cor1 = rgb(110, 90, 140), Cor2 = rgb(15, 10, 25), Espessura = 3 },
	{ Id = "Frame_Diamond", Nome = "Diamante", Raridade = "Epic", Cor1 = rgb(220, 250, 255), Cor2 = rgb(110, 210, 255), Espessura = 3, Gira = true },
	{ Id = "Frame_Fogo", Nome = "Fogo", Raridade = "Epic", Cor1 = rgb(255, 220, 90), Cor2 = rgb(230, 60, 20), Espessura = 3, Gira = true },
	{ Id = "Frame_Gelo", Nome = "Gelo", Raridade = "Legendary", Cor1 = rgb(240, 255, 255), Cor2 = rgb(90, 190, 255), Espessura = 4, Gira = true },
	{ Id = "Frame_ArcoIris", Nome = "Arco-íris", Raridade = "Legendary", Cor1 = rgb(255, 80, 120), Cor2 = rgb(80, 200, 255), Espessura = 4, Gira = true, ArcoIris = true },
	{ Id = "Frame_Galaxia", Nome = "Galáxia", Raridade = "Mythic", Cor1 = rgb(160, 90, 255), Cor2 = rgb(30, 180, 255), Espessura = 4, Gira = true },
	{ Id = "Frame_Lenda", Nome = "Lendária", Raridade = "Mythic", Cor1 = rgb(255, 245, 190), Cor2 = rgb(255, 150, 40), Espessura = 4, Gira = true },
}

-- ============================================================
-- TÍTULOS (linha pequena acima do nome)
-- ============================================================
C.Title = {
	{ Id = "Title_Novato", Nome = "Novato Promissor", Raridade = "Common", Cor = rgb(200, 220, 235) },
	{ Id = "Title_Capitao", Nome = "Capitão", Raridade = "Common", Cor = rgb(255, 215, 100) },
	{ Id = "Title_Artilheiro", Nome = "Artilheiro Nato", Raridade = "Common", Cor = rgb(255, 140, 90) },
	{ Id = "Title_Muralha", Nome = "A Muralha", Raridade = "Rare", Cor = rgb(170, 190, 210) },
	{ Id = "Title_Mago", Nome = "Mago do Drible", Raridade = "Rare", Cor = rgb(190, 140, 255) },
	{ Id = "Title_Maestro", Nome = "Maestro", Raridade = "Rare", Cor = rgb(120, 220, 200) },
	{ Id = "Title_Guardiao", Nome = "Guardião do Gol", Raridade = "Rare", Cor = rgb(120, 180, 255) },
	{ Id = "Title_Egoista", Nome = "O Egoísta", Raridade = "Epic", Cor = rgb(90, 160, 255) },
	{ Id = "Title_Rei", Nome = "Rei da Área", Raridade = "Epic", Cor = rgb(255, 200, 60) },
	{ Id = "Title_Monstro", Nome = "Monstro", Raridade = "Epic", Cor = rgb(255, 230, 80) },
	{ Id = "Title_Prodigio", Nome = "Prodígio", Raridade = "Legendary", Cor = rgb(255, 110, 140) },
	{ Id = "Title_Imperador", Nome = "Imperador", Raridade = "Legendary", Cor = rgb(110, 140, 255) },
	{ Id = "Title_Cacador", Nome = "Caçador de Gols", Raridade = "Legendary", Cor = rgb(255, 90, 60) },
	{ Id = "Title_Escolhido", Nome = "O Escolhido", Raridade = "Mythic", Cor = rgb(255, 245, 200) },
	{ Id = "Title_LendaViva", Nome = "Lenda Viva", Raridade = "Mythic", Cor = rgb(255, 170, 60) },
}

-- ============================================================
-- TAGS (etiqueta ao lado do nome)
-- ============================================================
C.Tag = {
	{ Id = "Tag_Artilheiro", Nome = "ARTILHEIRO", Raridade = "Rare", Cor = rgb(255, 140, 80) },
	{ Id = "Tag_Muralha", Nome = "MURALHA", Raridade = "Rare", Cor = rgb(170, 190, 210) },
	{ Id = "Tag_Lenda", Nome = "LENDA", Raridade = "Legendary", Cor = rgb(255, 200, 60) },
	{ Id = "Tag_10", Nome = "10", Raridade = "Common", Cor = rgb(255, 255, 255) },
	{ Id = "Tag_Craque", Nome = "CRAQUE", Raridade = "Common", Cor = rgb(120, 230, 140) },
	{ Id = "Tag_Veloz", Nome = "VELOZ", Raridade = "Common", Cor = rgb(255, 150, 60) },
	{ Id = "Tag_Capitao", Nome = "C", Raridade = "Common", Cor = rgb(255, 215, 100) },
	{ Id = "Tag_MVP", Nome = "MVP", Raridade = "Rare", Cor = rgb(255, 225, 90) },
	{ Id = "Tag_Ace", Nome = "ACE", Raridade = "Rare", Cor = rgb(90, 200, 255) },
	{ Id = "Tag_Ego", Nome = "EGO", Raridade = "Epic", Cor = rgb(80, 150, 255) },
	{ Id = "Tag_Flow", Nome = "FLOW", Raridade = "Epic", Cor = rgb(140, 255, 220) },
	{ Id = "Tag_Hissatsu", Nome = "HISSATSU", Raridade = "Epic", Cor = rgb(255, 90, 120) },
	{ Id = "Tag_Rei", Nome = "REI", Raridade = "Legendary", Cor = rgb(255, 200, 60) },
	{ Id = "Tag_Fantasma", Nome = "FANTASMA", Raridade = "Legendary", Cor = rgb(190, 180, 255) },
	{ Id = "Tag_Deus", Nome = "DEUS DO GOL", Raridade = "Mythic", Cor = rgb(255, 245, 190) },
}

-- ============================================================
-- COR DO NOME (placa de nome) — Cor2 = degradê
-- ============================================================
C.NameColor = {
	{ Id = "NameColor_Gold", Nome = "Dourado", Raridade = "Rare", Cor = rgb(255, 210, 80) },
	{ Id = "NameColor_Red", Nome = "Vermelho", Raridade = "Common", Cor = rgb(255, 90, 90) },
	{ Id = "NameColor_Cyan", Nome = "Azul Neon", Raridade = "Common", Cor = rgb(90, 230, 255) },
	{ Id = "NameColor_Verde", Nome = "Verde", Raridade = "Common", Cor = rgb(110, 235, 130) },
	{ Id = "NameColor_Roxo", Nome = "Roxo", Raridade = "Common", Cor = rgb(190, 130, 255) },
	{ Id = "NameColor_Rosa", Nome = "Rosa", Raridade = "Common", Cor = rgb(255, 130, 200) },
	{ Id = "NameColor_Laranja", Nome = "Laranja", Raridade = "Common", Cor = rgb(255, 160, 70) },
	{ Id = "NameColor_Prata", Nome = "Prata", Raridade = "Rare", Cor = rgb(220, 228, 240) },
	{ Id = "NameColor_Esmeralda", Nome = "Esmeralda", Raridade = "Rare", Cor = rgb(60, 220, 150) },
	{ Id = "NameColor_Carmesim", Nome = "Carmesim", Raridade = "Rare", Cor = rgb(220, 30, 70) },
	{ Id = "NameColor_Fogo", Nome = "Fogo", Raridade = "Epic", Cor = rgb(255, 220, 90), Cor2 = rgb(255, 70, 30) },
	{ Id = "NameColor_Gelo", Nome = "Gelo", Raridade = "Epic", Cor = rgb(240, 255, 255), Cor2 = rgb(90, 190, 255) },
	{ Id = "NameColor_Veneno", Nome = "Veneno", Raridade = "Epic", Cor = rgb(200, 255, 120), Cor2 = rgb(120, 60, 200) },
	{ Id = "NameColor_Galaxia", Nome = "Galáxia", Raridade = "Legendary", Cor = rgb(200, 140, 255), Cor2 = rgb(60, 190, 255) },
	{ Id = "NameColor_ArcoIris", Nome = "Arco-íris", Raridade = "Mythic", Cor = rgb(255, 90, 110), Cor2 = rgb(90, 200, 255), ArcoIris = true },
}

-- ============================================================
-- COR NO CHAT (nome no chat)
-- ============================================================
C.ChatColor = {
	{ Id = "ChatColor_Custom", Nome = "Azul Claro", Raridade = "Common", Cor = rgb(140, 200, 255) },
	{ Id = "ChatColor_Branco", Nome = "Branco", Raridade = "Common", Cor = rgb(255, 255, 255) },
	{ Id = "ChatColor_Vermelho", Nome = "Vermelho", Raridade = "Common", Cor = rgb(255, 100, 100) },
	{ Id = "ChatColor_Verde", Nome = "Verde", Raridade = "Common", Cor = rgb(110, 235, 130) },
	{ Id = "ChatColor_Amarelo", Nome = "Amarelo", Raridade = "Common", Cor = rgb(255, 230, 90) },
	{ Id = "ChatColor_Laranja", Nome = "Laranja", Raridade = "Common", Cor = rgb(255, 160, 70) },
	{ Id = "ChatColor_Rosa", Nome = "Rosa", Raridade = "Rare", Cor = rgb(255, 130, 200) },
	{ Id = "ChatColor_Roxo", Nome = "Roxo", Raridade = "Rare", Cor = rgb(190, 130, 255) },
	{ Id = "ChatColor_Ciano", Nome = "Ciano", Raridade = "Rare", Cor = rgb(90, 240, 240) },
	{ Id = "ChatColor_Dourado", Nome = "Dourado", Raridade = "Rare", Cor = rgb(255, 205, 70) },
	{ Id = "ChatColor_Esmeralda", Nome = "Esmeralda", Raridade = "Epic", Cor = rgb(60, 220, 150) },
	{ Id = "ChatColor_Carmesim", Nome = "Carmesim", Raridade = "Epic", Cor = rgb(230, 40, 80) },
	{ Id = "ChatColor_Lavanda", Nome = "Lavanda", Raridade = "Epic", Cor = rgb(200, 180, 255) },
	{ Id = "ChatColor_Neon", Nome = "Verde Neon", Raridade = "Legendary", Cor = rgb(160, 255, 90) },
	{ Id = "ChatColor_Solar", Nome = "Solar", Raridade = "Mythic", Cor = rgb(255, 180, 40) },
}

-- ============================================================
-- AURAS (partículas em volta do corpo — sutis, não atrapalham o jogo)
-- ============================================================
C.Aura = {
	{ Id = "Aura_Gold", Nome = "Dourada", Raridade = "Rare", Cor = rgb(255, 210, 80) },
	{ Id = "Aura_Blue", Nome = "Azul", Raridade = "Common", Cor = rgb(90, 160, 255) },
	{ Id = "Aura_Red", Nome = "Vermelha", Raridade = "Common", Cor = rgb(255, 80, 80) },
	{ Id = "Aura_Verde", Nome = "Verde", Raridade = "Common", Cor = rgb(90, 230, 120) },
	{ Id = "Aura_Roxa", Nome = "Roxa", Raridade = "Common", Cor = rgb(180, 110, 255) },
	{ Id = "Aura_Rosa", Nome = "Rosa", Raridade = "Rare", Cor = rgb(255, 130, 200) },
	{ Id = "Aura_Branca", Nome = "Branca", Raridade = "Rare", Cor = rgb(245, 250, 255) },
	{ Id = "Aura_Fogo", Nome = "Chamas", Raridade = "Epic", Cor = rgb(255, 130, 40), Estilo = "Fogo" },
	{ Id = "Aura_Gelo", Nome = "Gelo", Raridade = "Epic", Cor = rgb(170, 230, 255), Estilo = "Gelo" },
	{ Id = "Aura_Raio", Nome = "Raios", Raridade = "Epic", Cor = rgb(255, 240, 120), Estilo = "Raio" },
	{ Id = "Aura_Sombra", Nome = "Sombra", Raridade = "Legendary", Cor = rgb(60, 30, 90), Estilo = "Sombra" },
	{ Id = "Aura_Petalas", Nome = "Pétalas", Raridade = "Legendary", Cor = rgb(255, 150, 190), Estilo = "Petalas" },
	{ Id = "Aura_Estrelas", Nome = "Estrelas", Raridade = "Legendary", Cor = rgb(255, 250, 200), Estilo = "Estrelas" },
	{ Id = "Aura_ArcoIris", Nome = "Arco-íris", Raridade = "Mythic", Cor = rgb(255, 120, 200), Estilo = "ArcoIris" },
	{ Id = "Aura_Galaxia", Nome = "Galáxia", Raridade = "Mythic", Cor = rgb(150, 100, 255), Estilo = "Galaxia" },
}

-- ============================================================
-- EFEITO DE GOL (explode no gol quando VOCÊ marca)
-- ============================================================
C.GoalEffect = {
	{ Id = "GoalEffect_Fireworks", Nome = "Fogos de Artifício", Raridade = "Rare", Cor = rgb(255, 200, 80), Estilo = "Fogos" },
	{ Id = "GoalEffect_Confetti", Nome = "Confete", Raridade = "Common", Cor = rgb(255, 120, 200), Estilo = "Confete" },
	{ Id = "GoalEffect_Flash", Nome = "Flash Colorido", Raridade = "Common", Cor = rgb(120, 220, 255), Estilo = "Flash" },
	{ Id = "GoalEffect_Estrelas", Nome = "Chuva de Estrelas", Raridade = "Rare", Cor = rgb(255, 245, 190), Estilo = "Estrelas" },
	{ Id = "GoalEffect_Fogo", Nome = "Explosão de Fogo", Raridade = "Rare", Cor = rgb(255, 120, 40), Estilo = "Fogo" },
	{ Id = "GoalEffect_Raio", Nome = "Relâmpago", Raridade = "Epic", Cor = rgb(255, 240, 120), Estilo = "Raio" },
	{ Id = "GoalEffect_Petalas", Nome = "Pétalas", Raridade = "Common", Cor = rgb(255, 150, 190), Estilo = "Petalas" },
	{ Id = "GoalEffect_Bolhas", Nome = "Bolhas", Raridade = "Common", Cor = rgb(150, 220, 255), Estilo = "Bolhas" },
	{ Id = "GoalEffect_Neve", Nome = "Nevasca", Raridade = "Rare", Cor = rgb(240, 250, 255), Estilo = "Neve" },
	{ Id = "GoalEffect_Moedas", Nome = "Chuva de Moedas", Raridade = "Epic", Cor = rgb(255, 210, 60), Estilo = "Moedas" },
	{ Id = "GoalEffect_Coracoes", Nome = "Corações", Raridade = "Epic", Cor = rgb(255, 90, 130), Estilo = "Coracoes" },
	{ Id = "GoalEffect_Onda", Nome = "Onda de Energia", Raridade = "Legendary", Cor = rgb(120, 255, 210), Estilo = "Onda" },
	{ Id = "GoalEffect_Aurora", Nome = "Aurora", Raridade = "Legendary", Cor = rgb(120, 255, 180), Estilo = "Aurora" },
	{ Id = "GoalEffect_BuracoNegro", Nome = "Buraco Negro", Raridade = "Mythic", Cor = rgb(140, 70, 255), Estilo = "BuracoNegro" },
	{ Id = "GoalEffect_Supernova", Nome = "Supernova", Raridade = "Mythic", Cor = rgb(255, 230, 150), Estilo = "Supernova" },
}

-- ============================================================
-- EMOTES e COMEMORAÇÕES — poses no formato do AnimacoesProcedurais:
-- quadros { tempo, { Junta = V(rx, ry, rz), RootPos = V(...) } }, graus.
-- Convenção: ombro/quadril rx+ = pra FRENTE, rz+ abre (direito +, esquerdo -);
-- Root rx+ = inclina pra TRÁS; Neck rx+ = olha pra cima. R6: o quadril só desce
-- com o tronco tombado >45° (ver r6-pose-agachar). Giro inteiro: quadro 0 e,
-- 0.1ms depois, ±360 (mesma orientação) e volta a 0 girando.
-- Loop = { ini, fim } repete o trecho enquanto durar.
-- ============================================================
local BRACO_ALTO_D = { RShoulder = V(170, 0, 15), RElbow = V(10, 0, 0) }
local function juntar(...)
	local r = {}
	for _, t in ipairs({ ... }) do for k, v in pairs(t) do r[k] = v end end
	return r
end

C.Emote = {
	{ Id = "Emote_Dance", Nome = "Dança da Vitória", Raridade = "Common", Duracao = 3, Loop = { 0.2, 1.4 }, Quadros = {
		{ 0.0, {} },
		{ 0.2, { Root = V(0, 12, 6), RShoulder = V(150, 0, 30), LShoulder = V(40, 0, -40), RHip = V(10, 0, 10), LKnee = V(-20, 0, 0) } },
		{ 0.5, { Root = V(0, -12, -6), LShoulder = V(150, 0, -30), RShoulder = V(40, 0, 40), LHip = V(10, 0, -10), RKnee = V(-20, 0, 0) } },
		{ 0.8, { Root = V(0, 12, 6), RShoulder = V(150, 0, 30), LShoulder = V(40, 0, -40), RHip = V(10, 0, 10), LKnee = V(-20, 0, 0) } },
		{ 1.1, { Root = V(0, -12, -6), LShoulder = V(150, 0, -30), RShoulder = V(40, 0, 40), LHip = V(10, 0, -10), RKnee = V(-20, 0, 0) } },
		{ 1.4, { Root = V(0, 12, 6), RShoulder = V(150, 0, 30), LShoulder = V(40, 0, -40), RHip = V(10, 0, 10), LKnee = V(-20, 0, 0) } },
		{ 3.0, {} },
	} },
	{ Id = "Emote_Jump", Nome = "Salto de Comemoração", Raridade = "Common", Duracao = 1.4, Quadros = {
		{ 0.0, {} },
		{ 0.25, { Root = V(-10, 0, 0), RHip = V(40, 0, 6), LHip = V(40, 0, -6), RKnee = V(-60, 0, 0), LKnee = V(-60, 0, 0), RShoulder = V(-30, 0, 20), LShoulder = V(-30, 0, -20) } },
		{ 0.55, { Root = V(6, 0, 0), Neck = V(25, 0, 0), RShoulder = V(175, 0, 10), RElbow = V(20, 0, 0), LShoulder = V(20, 0, -40), RootPos = V(0, 3, 0), LKnee = V(-50, 0, 0), LHip = V(30, 0, 0) } },
		{ 0.85, { Neck = V(15, 0, 0), RShoulder = V(170, 0, 10), LShoulder = V(10, 0, -30), RootPos = V(0, 0.5, 0) } },
		{ 1.4, {} },
	} },
	{ Id = "Emote_Bow", Nome = "Reverência", Raridade = "Common", Duracao = 2, Quadros = {
		{ 0.0, {} },
		{ 0.5, { Root = V(-45, 0, 0), Neck = V(-10, 0, 0), RShoulder = V(60, 0, -40), RElbow = V(90, 0, 0), LShoulder = V(-30, 0, -20), RHip = V(40, 0, 0), LHip = V(40, 0, 0) } },
		{ 1.4, { Root = V(-45, 0, 0), Neck = V(-10, 0, 0), RShoulder = V(60, 0, -40), RElbow = V(90, 0, 0), LShoulder = V(-30, 0, -20), RHip = V(40, 0, 0), LHip = V(40, 0, 0) } },
		{ 2.0, {} },
	} },
	{ Id = "Emote_Aceno", Nome = "Aceno", Raridade = "Common", Duracao = 2.2, Loop = { 0.3, 1.1 }, Quadros = {
		{ 0.0, {} },
		{ 0.3, { RShoulder = V(150, 0, 60), RElbow = V(20, 0, 0), Neck = V(5, 10, 0) } },
		{ 0.5, { RShoulder = V(150, 0, 30), RElbow = V(20, 0, 0), Neck = V(5, 10, 0) } },
		{ 0.7, { RShoulder = V(150, 0, 60), RElbow = V(20, 0, 0), Neck = V(5, 10, 0) } },
		{ 0.9, { RShoulder = V(150, 0, 30), RElbow = V(20, 0, 0), Neck = V(5, 10, 0) } },
		{ 1.1, { RShoulder = V(150, 0, 60), RElbow = V(20, 0, 0), Neck = V(5, 10, 0) } },
		{ 2.2, {} },
	} },
	{ Id = "Emote_Joinha", Nome = "Joinha", Raridade = "Common", Duracao = 1.8, Quadros = {
		{ 0.0, {} },
		{ 0.3, { RShoulder = V(90, 0, 10), RElbow = V(40, 0, 0), Neck = V(0, -10, 0), Root = V(0, 10, 0) } },
		{ 1.4, { RShoulder = V(95, 0, 10), RElbow = V(40, 0, 0), Neck = V(0, -10, 0), Root = V(0, 10, 0) } },
		{ 1.8, {} },
	} },
	{ Id = "Emote_Palmas", Nome = "Palmas", Raridade = "Common", Duracao = 2.4, Loop = { 0.2, 0.6 }, Quadros = {
		{ 0.0, {} },
		{ 0.2, { RShoulder = V(80, 0, 25), LShoulder = V(80, 0, -25), RElbow = V(40, 0, 0), LElbow = V(40, 0, 0) } },
		{ 0.4, { RShoulder = V(80, 0, -8), LShoulder = V(80, 0, 8), RElbow = V(40, 0, 0), LElbow = V(40, 0, 0) } },
		{ 0.6, { RShoulder = V(80, 0, 25), LShoulder = V(80, 0, -25), RElbow = V(40, 0, 0), LElbow = V(40, 0, 0) } },
		{ 2.4, {} },
	} },
	{ Id = "Emote_Continencia", Nome = "Continência", Raridade = "Rare", Duracao = 2, Quadros = {
		{ 0.0, {} },
		{ 0.35, { RShoulder = V(110, 0, 70), RElbow = V(120, 0, 0), Neck = V(5, 0, 0), Root = V(4, 0, 0) } },
		{ 1.6, { RShoulder = V(110, 0, 70), RElbow = V(120, 0, 0), Neck = V(5, 0, 0), Root = V(4, 0, 0) } },
		{ 2.0, {} },
	} },
	{ Id = "Emote_Forca", Nome = "Mostra a Força", Raridade = "Rare", Duracao = 2, Quadros = {
		{ 0.0, {} },
		{ 0.4, { RShoulder = V(0, 0, 90), LShoulder = V(0, 0, -90), RElbow = V(110, 0, 0), LElbow = V(110, 0, 0), Root = V(-5, 0, 0), RHip = V(0, 0, 12), LHip = V(0, 0, -12) } },
		{ 1.0, { RShoulder = V(10, 0, 95), LShoulder = V(10, 0, -95), RElbow = V(120, 0, 0), LElbow = V(120, 0, 0), Root = V(-8, 0, 0), RHip = V(0, 0, 12), LHip = V(0, 0, -12) } },
		{ 1.6, { RShoulder = V(0, 0, 90), LShoulder = V(0, 0, -90), RElbow = V(110, 0, 0), LElbow = V(110, 0, 0), Root = V(-5, 0, 0), RHip = V(0, 0, 12), LHip = V(0, 0, -12) } },
		{ 2.0, {} },
	} },
	{ Id = "Emote_Pensativo", Nome = "Pensativo", Raridade = "Rare", Duracao = 2.4, Quadros = {
		{ 0.0, {} },
		{ 0.4, { RShoulder = V(110, 0, -20), RElbow = V(130, 0, 0), LShoulder = V(40, 0, -10), LElbow = V(90, 0, 0), Neck = V(-10, 15, 0), Root = V(0, 0, 4) } },
		{ 2.0, { RShoulder = V(112, 0, -20), RElbow = V(130, 0, 0), LShoulder = V(40, 0, -10), LElbow = V(90, 0, 0), Neck = V(-12, 20, 0), Root = V(0, 0, 4) } },
		{ 2.4, {} },
	} },
	{ Id = "Emote_Risada", Nome = "Risada", Raridade = "Rare", Duracao = 2.2, Loop = { 0.3, 0.7 }, Quadros = {
		{ 0.0, {} },
		{ 0.3, { Root = V(14, 0, 0), Neck = V(25, 0, 0), RShoulder = V(40, 0, -20), LShoulder = V(40, 0, 20), RElbow = V(80, 0, 0), LElbow = V(80, 0, 0) } },
		{ 0.5, { Root = V(10, 0, 0), Neck = V(18, 0, 0), RShoulder = V(45, 0, -20), LShoulder = V(45, 0, 20), RElbow = V(85, 0, 0), LElbow = V(85, 0, 0) } },
		{ 0.7, { Root = V(14, 0, 0), Neck = V(25, 0, 0), RShoulder = V(40, 0, -20), LShoulder = V(40, 0, 20), RElbow = V(80, 0, 0), LElbow = V(80, 0, 0) } },
		{ 2.2, {} },
	} },
	{ Id = "Emote_ApontaCeu", Nome = "Aponta pro Céu", Raridade = "Rare", Duracao = 2, Quadros = {
		{ 0.0, {} },
		{ 0.35, juntar(BRACO_ALTO_D, { Neck = V(35, 0, 0), Root = V(6, 0, 0), LShoulder = V(0, 0, -20) }) },
		{ 1.6, juntar(BRACO_ALTO_D, { Neck = V(40, 0, 0), Root = V(8, 0, 0), LShoulder = V(0, 0, -20) }) },
		{ 2.0, {} },
	} },
	{ Id = "Emote_Cruzados", Nome = "Braços Cruzados", Raridade = "Epic", Duracao = 2.6, Quadros = {
		{ 0.0, {} },
		{ 0.35, { RShoulder = V(70, 0, -45), LShoulder = V(70, 0, 45), RElbow = V(110, 0, 0), LElbow = V(110, 0, 0), Neck = V(10, -15, 0), Root = V(3, 0, 0), RHip = V(0, 0, 8), LHip = V(0, 0, -8) } },
		{ 2.2, { RShoulder = V(70, 0, -45), LShoulder = V(70, 0, 45), RElbow = V(110, 0, 0), LElbow = V(110, 0, 0), Neck = V(12, -15, 0), Root = V(3, 0, 0), RHip = V(0, 0, 8), LHip = V(0, 0, -8) } },
		{ 2.6, {} },
	} },
	{ Id = "Emote_Guitarra", Nome = "Guitarra Imaginária", Raridade = "Epic", Duracao = 3, Loop = { 0.3, 0.9 }, Quadros = {
		{ 0.0, {} },
		{ 0.3, { Root = V(-12, 0, -6), Neck = V(-20, 0, 0), LShoulder = V(60, 0, -60), LElbow = V(20, 0, 0), RShoulder = V(40, 0, -10), RElbow = V(90, 0, 0), RHip = V(20, 0, 15), RKnee = V(-30, 0, 0) } },
		{ 0.6, { Root = V(-12, 0, -6), Neck = V(-25, 0, 0), LShoulder = V(60, 0, -60), LElbow = V(20, 0, 0), RShoulder = V(20, 0, -10), RElbow = V(70, 0, 0), RHip = V(20, 0, 15), RKnee = V(-30, 0, 0) } },
		{ 0.9, { Root = V(-12, 0, -6), Neck = V(-20, 0, 0), LShoulder = V(60, 0, -60), LElbow = V(20, 0, 0), RShoulder = V(40, 0, -10), RElbow = V(90, 0, 0), RHip = V(20, 0, 15), RKnee = V(-30, 0, 0) } },
		{ 3.0, {} },
	} },
	{ Id = "Emote_Robo", Nome = "Dança do Robô", Raridade = "Epic", Duracao = 3.2, Loop = { 0.2, 1.8 }, Quadros = {
		{ 0.0, {} },
		{ 0.2, { RShoulder = V(90, 0, 0), RElbow = V(90, 0, 0), LShoulder = V(0, 0, -10), Root = V(0, 20, 0) } },
		{ 0.6, { RShoulder = V(90, 0, 0), RElbow = V(90, 0, 0), LShoulder = V(0, 0, -10), Root = V(0, 20, 0) } },
		{ 0.65, { LShoulder = V(90, 0, 0), LElbow = V(90, 0, 0), RShoulder = V(0, 0, 10), Root = V(0, -20, 0) } },
		{ 1.1, { LShoulder = V(90, 0, 0), LElbow = V(90, 0, 0), RShoulder = V(0, 0, 10), Root = V(0, -20, 0) } },
		{ 1.15, { RShoulder = V(0, 0, 90), LShoulder = V(0, 0, -90), Neck = V(0, 30, 0) } },
		{ 1.75, { RShoulder = V(0, 0, 90), LShoulder = V(0, 0, -90), Neck = V(0, -30, 0) } },
		{ 1.8, { RShoulder = V(90, 0, 0), RElbow = V(90, 0, 0), LShoulder = V(0, 0, -10), Root = V(0, 20, 0) } },
		{ 3.2, {} },
	} },
	{ Id = "Emote_Ego", Nome = "Pose do Ego", Raridade = "Legendary", Duracao = 2.6, Quadros = {
		{ 0.0, {} },
		-- a pose do egoísta: mão na frente do rosto, olho por entre os dedos
		{ 0.4, { RShoulder = V(125, 0, -30), RElbow = V(115, 0, 0), LShoulder = V(-10, 0, -15), Neck = V(-12, -10, 0), Root = V(-6, -15, 0), RHip = V(5, 0, 10), LHip = V(-5, 0, -8) } },
		{ 2.2, { RShoulder = V(127, 0, -30), RElbow = V(117, 0, 0), LShoulder = V(-10, 0, -15), Neck = V(-14, -10, 0), Root = V(-6, -15, 0), RHip = V(5, 0, 10), LHip = V(-5, 0, -8) } },
		{ 2.6, {} },
	} },
}

-- Comemoração de gol (tocada no autor do gol, ver MatchController)
C.Celebration = {
	{ Id = "Cel_Punho", Nome = "Punho no Ar", Raridade = "Common", Duracao = 3, Quadros = {
		{ 0.0, {} },
		{ 0.3, { Root = V(8, 0, 0), Neck = V(30, 0, 0), RShoulder = V(175, 0, 10), RElbow = V(15, 0, 0), LShoulder = V(-20, 0, -30), LElbow = V(60, 0, 0) } },
		{ 0.6, { Root = V(10, 0, 0), Neck = V(35, 0, 0), RShoulder = V(165, 0, 10), RElbow = V(60, 0, 0), LShoulder = V(-20, 0, -30), LElbow = V(60, 0, 0) } },
		{ 0.9, { Root = V(8, 0, 0), Neck = V(30, 0, 0), RShoulder = V(175, 0, 10), RElbow = V(15, 0, 0), LShoulder = V(-20, 0, -30), LElbow = V(60, 0, 0) } },
		{ 2.6, { Root = V(8, 0, 0), Neck = V(30, 0, 0), RShoulder = V(175, 0, 10), RElbow = V(15, 0, 0), LShoulder = V(-20, 0, -30) } },
		{ 3.0, {} },
	} },
	{ Id = "Cel_Aviao", Nome = "Aviãozinho", Raridade = "Common", Duracao = 3, Quadros = {
		{ 0.0, {} },
		{ 0.4, { Root = V(-15, 0, -25), RShoulder = V(0, 0, 95), LShoulder = V(0, 0, -95), Neck = V(10, 0, 10), RHip = V(-10, 0, 0) } },
		{ 1.4, { Root = V(-15, 0, 25), RShoulder = V(0, 0, 95), LShoulder = V(0, 0, -95), Neck = V(10, 0, -10), LHip = V(-10, 0, 0) } },
		{ 2.4, { Root = V(-15, 0, -25), RShoulder = V(0, 0, 95), LShoulder = V(0, 0, -95), Neck = V(10, 0, 10), RHip = V(-10, 0, 0) } },
		{ 3.0, {} },
	} },
	{ Id = "Cel_Joelhos", Nome = "Deslize de Joelhos", Raridade = "Rare", Duracao = 3, Quadros = {
		{ 0.0, {} },
		-- tombado pra trás >45° pro quadril descer no R6: joelhos "no chão", braços abertos
		{ 0.35, { Root = V(55, 0, 0), Neck = V(-15, 0, 0), RHip = V(-20, 0, 8), LHip = V(-20, 0, -8), RKnee = V(-100, 0, 0), LKnee = V(-100, 0, 0),
			RShoulder = V(150, 0, 60), LShoulder = V(150, 0, -60), RootPos = V(0, -1.4, 0) } },
		{ 2.4, { Root = V(55, 0, 0), Neck = V(-5, 0, 0), RHip = V(-20, 0, 8), LHip = V(-20, 0, -8), RKnee = V(-100, 0, 0), LKnee = V(-100, 0, 0),
			RShoulder = V(160, 0, 55), LShoulder = V(160, 0, -55), RootPos = V(0, -1.4, 0) } },
		{ 3.0, {} },
	} },
	{ Id = "Cel_Siu", Nome = "Salto Giratório", Raridade = "Epic", Duracao = 2.4, Quadros = {
		{ 0.0, {} },
		{ 0.25, { Root = V(-10, 0, 0), RHip = V(40, 0, 6), LHip = V(40, 0, -6), RKnee = V(-60, 0, 0), LKnee = V(-60, 0, 0), RShoulder = V(-20, 0, 20), LShoulder = V(-20, 0, -20) } },
		{ 0.2501, { Root = V(-10, -180, 0), RHip = V(40, 0, 6), LHip = V(40, 0, -6), RKnee = V(-60, 0, 0), LKnee = V(-60, 0, 0), RShoulder = V(-20, 0, 20), LShoulder = V(-20, 0, -20) } },
		-- sobe girando meia volta e cai de braços abertos pra baixo (a pose clássica)
		{ 0.65, { Root = V(0, -60, 0), RShoulder = V(20, 0, 40), LShoulder = V(20, 0, -40), RootPos = V(0, 3.2, 0), RHip = V(10, 0, 15), LHip = V(10, 0, -15) } },
		{ 0.95, { Root = V(10, 0, 0), Neck = V(25, 0, 0), RShoulder = V(-20, 0, 70), LShoulder = V(-20, 0, -70), RHip = V(0, 0, 18), LHip = V(0, 0, -18), RootPos = V(0, 0, 0) } },
		{ 2.0, { Root = V(12, 0, 0), Neck = V(30, 0, 0), RShoulder = V(-25, 0, 72), LShoulder = V(-25, 0, -72), RHip = V(0, 0, 18), LHip = V(0, 0, -18) } },
		{ 2.4, {} },
	} },
	{ Id = "Cel_Ninar", Nome = "Nina o Bebê", Raridade = "Common", Duracao = 3, Loop = { 0.3, 1.1 }, Quadros = {
		{ 0.0, {} },
		{ 0.3, { RShoulder = V(70, 0, -30), LShoulder = V(70, 0, 30), RElbow = V(80, 0, 0), LElbow = V(80, 0, 0), Root = V(0, 12, 0) } },
		{ 0.7, { RShoulder = V(70, 0, -30), LShoulder = V(70, 0, 30), RElbow = V(80, 0, 0), LElbow = V(80, 0, 0), Root = V(0, -12, 0) } },
		{ 1.1, { RShoulder = V(70, 0, -30), LShoulder = V(70, 0, 30), RElbow = V(80, 0, 0), LElbow = V(80, 0, 0), Root = V(0, 12, 0) } },
		{ 3.0, {} },
	} },
	{ Id = "Cel_Coracao", Nome = "Coração", Raridade = "Rare", Duracao = 2.6, Quadros = {
		{ 0.0, {} },
		{ 0.4, { RShoulder = V(150, 0, -15), LShoulder = V(150, 0, 15), RElbow = V(70, 0, 0), LElbow = V(70, 0, 0), Neck = V(20, 0, 0) } },
		{ 2.2, { RShoulder = V(152, 0, -15), LShoulder = V(152, 0, 15), RElbow = V(72, 0, 0), LElbow = V(72, 0, 0), Neck = V(22, 0, 0) } },
		{ 2.6, {} },
	} },
	{ Id = "Cel_Mortal", Nome = "Mortal", Raridade = "Legendary", Duracao = 2, Quadros = {
		{ 0.0, {} },
		{ 0.2, { Root = V(-10, 0, 0), RHip = V(45, 0, 6), LHip = V(45, 0, -6), RKnee = V(-70, 0, 0), LKnee = V(-70, 0, 0), RShoulder = V(-30, 0, 20), LShoulder = V(-30, 0, -20) } },
		{ 0.2001, { Root = V(-370, 0, 0), RHip = V(45, 0, 6), LHip = V(45, 0, -6), RKnee = V(-70, 0, 0), LKnee = V(-70, 0, 0), RShoulder = V(-30, 0, 20), LShoulder = V(-30, 0, -20) } },
		-- mortal pra trás (grupado), cai de pé com os braços pro alto
		{ 0.55, { Root = V(-190, 0, 0), RHip = V(100, 0, 0), LHip = V(100, 0, 0), RKnee = V(-110, 0, 0), LKnee = V(-110, 0, 0), RShoulder = V(60, 0, 20), LShoulder = V(60, 0, -20), RootPos = V(0, 3.4, 0) } },
		{ 0.9, { Root = V(0, 0, 0), RShoulder = V(170, 0, 30), LShoulder = V(170, 0, -30), RootPos = V(0, 0.3, 0) } },
		{ 1.7, { Root = V(6, 0, 0), Neck = V(25, 0, 0), RShoulder = V(170, 0, 30), LShoulder = V(170, 0, -30) } },
		{ 2.0, {} },
	} },
	{ Id = "Cel_Calma", Nome = "Pede Calma", Raridade = "Common", Duracao = 2.6, Loop = { 0.3, 0.9 }, Quadros = {
		{ 0.0, {} },
		{ 0.3, { RShoulder = V(50, 0, 30), LShoulder = V(50, 0, -30), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0), Neck = V(-5, 0, 0) } },
		{ 0.6, { RShoulder = V(30, 0, 30), LShoulder = V(30, 0, -30), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0), Neck = V(-5, 0, 0) } },
		{ 0.9, { RShoulder = V(50, 0, 30), LShoulder = V(50, 0, -30), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0), Neck = V(-5, 0, 0) } },
		{ 2.6, {} },
	} },
	{ Id = "Cel_Telefone", Nome = "Telefone", Raridade = "Common", Duracao = 2.6, Quadros = {
		{ 0.0, {} },
		{ 0.35, { RShoulder = V(130, 0, 50), RElbow = V(140, 0, 0), Neck = V(0, 0, -10), Root = V(0, 0, 6), LShoulder = V(10, 0, -25) } },
		{ 2.2, { RShoulder = V(130, 0, 50), RElbow = V(140, 0, 0), Neck = V(0, 0, -14), Root = V(0, 0, 6), LShoulder = V(10, 0, -25) } },
		{ 2.6, {} },
	} },
	{ Id = "Cel_Arqueiro", Nome = "Arqueiro", Raridade = "Epic", Duracao = 2.8, Quadros = {
		{ 0.0, {} },
		-- estica o arco (braço esquerdo esticado, direito puxando a corda) e solta
		{ 0.5, { Root = V(0, 60, 0), Neck = V(0, -55, 0), LShoulder = V(90, 0, -80), LElbow = V(0, 0, 0), RShoulder = V(90, 0, -60), RElbow = V(130, 0, 0), RHip = V(0, 0, 15), LHip = V(0, 0, -15) } },
		{ 1.4, { Root = V(0, 60, 0), Neck = V(0, -55, 0), LShoulder = V(92, 0, -80), LElbow = V(0, 0, 0), RShoulder = V(80, 0, -30), RElbow = V(150, 0, 0), RHip = V(0, 0, 15), LHip = V(0, 0, -15) } },
		{ 1.6, { Root = V(0, 60, 0), Neck = V(0, -55, 0), LShoulder = V(92, 0, -80), LElbow = V(0, 0, 0), RShoulder = V(20, 0, 60), RElbow = V(10, 0, 0), RHip = V(0, 0, 15), LHip = V(0, 0, -15) } },
		{ 2.4, { Root = V(0, 60, 0), Neck = V(0, -55, 0), LShoulder = V(90, 0, -80), RShoulder = V(20, 0, 60), RHip = V(0, 0, 15), LHip = V(0, 0, -15) } },
		{ 2.8, {} },
	} },
	{ Id = "Cel_Escudo", Nome = "Beija o Escudo", Raridade = "Rare", Duracao = 2.8, Quadros = {
		{ 0.0, {} },
		{ 0.4, { RShoulder = V(80, 0, -50), RElbow = V(120, 0, 0), Neck = V(-25, 0, 0), Root = V(-6, 0, 0) } },
		{ 1.2, { RShoulder = V(80, 0, -50), RElbow = V(120, 0, 0), Neck = V(-25, 0, 0), Root = V(-6, 0, 0) } },
		{ 1.7, { RShoulder = V(170, 0, 20), RElbow = V(10, 0, 0), LShoulder = V(170, 0, -20), Neck = V(40, 0, 0), Root = V(8, 0, 0) } },
		{ 2.4, { RShoulder = V(170, 0, 20), LShoulder = V(170, 0, -20), Neck = V(40, 0, 0), Root = V(8, 0, 0) } },
		{ 2.8, {} },
	} },
	{ Id = "Cel_Dab", Nome = "Dab", Raridade = "Common", Duracao = 2.2, Quadros = {
		{ 0.0, {} },
		{ 0.25, { RShoulder = V(120, 0, 70), RElbow = V(0, 0, 0), LShoulder = V(100, 0, 30), LElbow = V(120, 0, 0), Neck = V(-30, -40, 0), Root = V(-8, 0, 0) } },
		{ 1.8, { RShoulder = V(122, 0, 70), LShoulder = V(100, 0, 30), LElbow = V(120, 0, 0), Neck = V(-32, -40, 0), Root = V(-8, 0, 0) } },
		{ 2.2, {} },
	} },
	{ Id = "Cel_Rei", Nome = "Grito do Rei", Raridade = "Legendary", Duracao = 3, Quadros = {
		{ 0.0, {} },
		-- o "rei" (Barou): braços abertos pra trás, peito pra frente, cabeça pro céu
		{ 0.4, { Root = V(18, 0, 0), Neck = V(45, 0, 0), RShoulder = V(-40, 0, 80), LShoulder = V(-40, 0, -80), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0), RHip = V(0, 0, 15), LHip = V(0, 0, -15) } },
		{ 2.6, { Root = V(20, 0, 0), Neck = V(50, 0, 0), RShoulder = V(-45, 0, 85), LShoulder = V(-45, 0, -85), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0), RHip = V(0, 0, 15), LHip = V(0, 0, -15) } },
		{ 3.0, {} },
	} },
	{ Id = "Cel_Silencio", Nome = "Silêncio", Raridade = "Epic", Duracao = 2.8, Quadros = {
		{ 0.0, {} },
		{ 0.35, { RShoulder = V(110, 0, -25), RElbow = V(140, 0, 0), Neck = V(-5, 0, 0), Root = V(-4, 0, 0) } },
		{ 2.4, { RShoulder = V(112, 0, -25), RElbow = V(140, 0, 0), Neck = V(-5, 0, 0), Root = V(-4, 0, 0) } },
		{ 2.8, {} },
	} },
	{ Id = "Cel_Dancinha", Nome = "Dancinha", Raridade = "Rare", Duracao = 3.2, Loop = { 0.2, 1.0 }, Quadros = {
		{ 0.0, {} },
		{ 0.2, { Root = V(0, 0, 10), RShoulder = V(60, 0, 40), LShoulder = V(60, 0, -40), RElbow = V(90, 0, 0), LElbow = V(90, 0, 0), RHip = V(15, 0, 10) } },
		{ 0.6, { Root = V(0, 0, -10), RShoulder = V(60, 0, 40), LShoulder = V(60, 0, -40), RElbow = V(90, 0, 0), LElbow = V(90, 0, 0), LHip = V(15, 0, -10) } },
		{ 1.0, { Root = V(0, 0, 10), RShoulder = V(60, 0, 40), LShoulder = V(60, 0, -40), RElbow = V(90, 0, 0), LElbow = V(90, 0, 0), RHip = V(15, 0, 10) } },
		{ 3.2, {} },
	} },
}

-- ============================================================
-- FLOWS (Blue Lock) — PEDIDO: "cutscenes de flow igual as dos animes (o flow
-- do Isagi, do Bachira...), na loja pra escolher o flow; cada flow dá um buff
-- diferente". O medidor de Flow continua o mesmo (passes/roubos/gols, ver
-- InstinctController); o que muda é o QUE o Flow faz e a cena ao ativar.
--   Atributos = pontos somados (0-100) enquanto o Flow dura (e tirados no fim)
--   Velocidade = multiplicador de velocidade enquanto dura
--   (o desvio aleatório de mira está desligado no jogo — Config.DESVIO_ALEATORIO_LIGADO —
--   então precisão = Técnica, que é o que pesa no passe e no QTE)
--   Tema = cores e o motivo visual da cena (FlowCutsceneClient)
-- ============================================================
C.Flow = {
	{ Id = "Flow_Isagi", Nome = "Flow do Isagi", Raridade = "Common", Personagem = "Isagi Yoichi",
		Descricao = "Metavisão: o campo vira um quebra-cabeça — Técnica e Chute sobem.",
		Atributos = { Kick = 12, Technique = 18 },
		Tema = { Cor = rgb(90, 160, 255), Cor2 = rgb(220, 240, 255), Motivo = "Pecas" },
		-- ⚠️ v120b — PEDIDO: "uma soundtrack boa: a música do Flow de cada um (playlist do
		-- Blue Lock); o Isagi usa a Puzzle" + "a fala do Sung Jin-Woo (Solo Leveling, 0:30) e os
		-- efeitos sonoros". UM áudio só, já mixado e sincronizado com a cena (39s: Puzzle com a
		-- batida na pisada 9,55s, o grito do Jin-Woo na levantada, efeitos em cada momento) em
		-- _upload/Flow_Isagi_Cena.mp3 (gerado por .claude/skills/flow-cutscene/mixar_cena_isagi.py)
		-- — falta subir e colar o ID.
		Musica = { Id = "rbxassetid://138043913660792", Volume = 1.3, Duracao = 39 } }, -- (v126c: Duracao = segundos do áudio: o Flow acaba junto com a música) -- (v120f: "aumenta o som inteiro", era 0.6)
	{ Id = "Flow_Bachira", Nome = "Flow do Bachira", Raridade = "Rare", Personagem = "Bachira Meguru",
		Descricao = "O monstro dentro dele: drible muito maior e mais velocidade com a bola.",
		Atributos = { DribbleSkill = 25 }, Velocidade = 1.08,
		Tema = { Cor = rgb(255, 215, 70), Cor2 = rgb(40, 20, 10), Motivo = "Monstro" } },
	{ Id = "Flow_Nagi", Nome = "Flow do Nagi", Raridade = "Rare", Personagem = "Nagi Seishiro",
		Descricao = "Domínio perfeito: controle total da bola e chute limpo.",
		Atributos = { DribbleSkill = 12, Kick = 12, Technique = 12 },
		Tema = { Cor = rgb(235, 240, 255), Cor2 = rgb(150, 170, 200), Motivo = "Penas" } },
	{ Id = "Flow_Chigiri", Nome = "Flow do Chigiri", Raridade = "Rare", Personagem = "Chigiri Hyoma",
		Descricao = "A pantera: explosão de velocidade.",
		Atributos = { Speed = 25 }, Velocidade = 1.12,
		Tema = { Cor = rgb(255, 80, 110), Cor2 = rgb(255, 200, 210), Motivo = "Petalas" } },
	{ Id = "Flow_Kunigami", Nome = "Flow do Kunigami", Raridade = "Epic", Personagem = "Kunigami Rensuke",
		Descricao = "O herói: corpo de aço e chute de canhota pesado.",
		Atributos = { Physical = 25, Kick = 10 },
		Tema = { Cor = rgb(255, 150, 40), Cor2 = rgb(255, 230, 150), Motivo = "Chamas" } },
	{ Id = "Flow_Reo", Nome = "Flow do Reo", Raridade = "Epic", Personagem = "Mikage Reo",
		Descricao = "O camaleão: copia tudo — todos os atributos sobem um pouco.",
		Atributos = { Kick = 8, DribbleSkill = 8, Speed = 8, Physical = 8, Technique = 8 },
		Tema = { Cor = rgb(180, 110, 255), Cor2 = rgb(240, 220, 255), Motivo = "Espelhos" } },
	{ Id = "Flow_Aiku", Nome = "Flow do Aiku", Raridade = "Epic", Personagem = "Aiku Oliver",
		Descricao = "O fantasma da defesa: corpo e velocidade pra roubar a bola.",
		Atributos = { Physical = 18, Speed = 12 },
		Tema = { Cor = rgb(170, 180, 210), Cor2 = rgb(60, 60, 90), Motivo = "Fantasma" } },
	{ Id = "Flow_Barou", Nome = "Flow do Barou", Raridade = "Legendary", Personagem = "Barou Shoei",
		Descricao = "O rei: chute devastador e corpo que ninguém tira da bola.",
		Atributos = { Kick = 25, Physical = 15 },
		Tema = { Cor = rgb(255, 205, 60), Cor2 = rgb(30, 20, 10), Motivo = "Coroa" } },
	{ Id = "Flow_Shidou", Nome = "Flow do Shidou", Raridade = "Legendary", Personagem = "Shidou Ryusei",
		Descricao = "Big Bang Drive: ativar o Flow é CHUTAR — com a bola NO AR em cima de você, ele salta e dá a bicicleta pra onde você mira. Chute e Velocidade sobem.",
		Atributos = { Kick = 20, Speed = 10 },
		Tema = { Cor = rgb(255, 110, 190), Cor2 = rgb(255, 240, 120), Motivo = "Explosao" },
		-- ⚠️ v125 — PEDIDO: "nem a música e nem o áudio de nada foi incluído... eu vou colocar".
		-- _upload/Flow_Shidou_Cena.mp3 (39s): falas do vídeo (demucs) nos tempos da cena —
		-- "Big Bang Drive" em 8.9s — + a trilha com a explosão caindo no chute (10.4s).
		-- Se mudar FS.ImpactTime, remixar o áudio (a explosão é presa nesse tempo).
		Musica = { Id = "rbxassetid://134592522690900", Volume = 1.2, Duracao = 39 } }, -- (v125b: sem a fala com palavrão; o 92767227847282 ficou restrito)
	{ Id = "Flow_Sae", Nome = "Flow do Sae", Raridade = "Legendary", Personagem = "Itoshi Sae",
		Descricao = "O prodígio: Técnica altíssima — passe e chute de outro nível.",
		Atributos = { Technique = 28, Kick = 12 },
		Tema = { Cor = rgb(220, 40, 70), Cor2 = rgb(255, 200, 210), Motivo = "Rosas" } },
	{ Id = "Flow_Rin", Nome = "Flow do Rin", Raridade = "Mythic", Personagem = "Itoshi Rin",
		Descricao = "O destruidor: chute, velocidade e técnica sobem juntos.",
		Atributos = { Kick = 22, Speed = 12, Technique = 10 }, Velocidade = 1.06,
		Tema = { Cor = rgb(20, 190, 170), Cor2 = rgb(10, 30, 40), Motivo = "Agua" } },
	{ Id = "Flow_Kaiser", Nome = "Flow do Kaiser", Raridade = "Mythic", Personagem = "Michael Kaiser",
		Descricao = "O imperador: o chute mais rápido do mundo e explosão de velocidade.",
		Atributos = { Kick = 20, Speed = 18 }, Velocidade = 1.1,
		Tema = { Cor = rgb(70, 110, 255), Cor2 = rgb(200, 220, 255), Motivo = "RosaAzul" } },
}

-- ============================================================
-- CONSULTAS
-- ============================================================
-- ⚠️ v117 — PEDIDO: "Unifique os Emotes e Comemorações". Agora é UMA categoria só
-- ("Emote"): as 15 comemorações de gol viraram emotes comuns (os Ids "Cel_*" foram
-- mantidos, quem já comprou continua com o item) e os emotes cadastrados em
-- EmotesCustom entram na mesma lista. Quem usa é uma RODA de 6 casas (tecla G): a
-- casa 1 também é a comemoração tocada no gol.
-- ⚠️ v119 — PEDIDO: "remova completamente a aura... remova a cor no chat. Mantenha
-- só a cor do nome, a tag, a moldura, o título, os emotes" (+ efeito de gol e Flow).
-- As listas C.Aura / C.ChatColor continuam aqui só como registro, mas FORA das
-- categorias: não entram na loja/armário, C.Item() não acha esses Ids e
-- C.Equipado(player, "Aura"/"ChatColor") devolve nil (quem tinha equipado perde o
-- efeito; nada quebra).
C.CATEGORIAS = { "Frame", "Title", "Tag", "NameColor", "Emote", "GoalEffect", "Flow" }
C.NOME_CATEGORIA = {
	Frame = "Moldura", Title = "Título", Tag = "Tag", NameColor = "Cor do Nome", ChatColor = "Cor no Chat",
	Emote = "Emotes", Aura = "Aura", GoalEffect = "Efeito de Gol", Flow = "Flow",
}
C.RODA_TAMANHO = 6
-- o Flow do Isagi é de graça (todo mundo começa com ele)
C.GRATIS = { Flow_Isagi = true }

-- comemorações de gol entram na lista única de emotes
for _, it in ipairs(C.Celebration) do
	it.Comemoracao = true
	table.insert(C.Emote, it)
end
C.Celebration = nil

-- emotes cadastrados à mão (ver EmotesCustom.luau: nome + id da animação)
do
	local ok, lista = pcall(function()
		local m = script.Parent:FindFirstChild("EmotesCustom")
		return m and require(m) or nil
	end)
	if ok and typeof(lista) == "table" then
		local usados = {}
		for _, e in ipairs(lista) do
			if typeof(e) == "table" and typeof(e.Nome) == "string" and e.Nome ~= "" and e.AnimacaoId ~= nil then
				local limpo = e.Nome:gsub("[^%w]", "")
				local id = "EmoteCustom_" .. (limpo ~= "" and limpo or tostring(#C.Emote))
				if usados[id] then
					warn("[Cosmeticos] EmotesCustom: nome repetido '" .. e.Nome .. "' — ignorado")
				else
					usados[id] = true
					local animId = tostring(e.AnimacaoId)
					if animId:match("^%d+$") then animId = "rbxassetid://" .. animId end
					table.insert(C.Emote, {
						Id = id, Nome = e.Nome, Raridade = C.PRECO[e.Raridade] and e.Raridade or "Common",
						Duracao = tonumber(e.Duracao) or 4, AnimacaoId = animId, Loop = e.Loop == true,
						Custo = tonumber(e.Preco), Custom = true,
						Descricao = e.Descricao or (e.Autor and ("Por " .. e.Autor)) or nil,
					})
					if e.Gratis == true then C.GRATIS[id] = true end
				end
			end
		end
	elseif not ok then
		warn("[Cosmeticos] EmotesCustom com erro: " .. tostring(lista))
	end
end

local porId = {}
for _, cat in ipairs(C.CATEGORIAS) do
	for _, item in ipairs(C[cat]) do
		item.Slot = cat
		porId[item.Id] = item
	end
end
function C.Item(id) return id and porId[id] or nil end
function C.Preco(item)
	if not item then return 0 end
	if C.GRATIS[item.Id] then return 0 end
	return item.Custo or C.PRECO[item.Raridade] or 500
end

-- atributos do Player (os dois places): "Cosm_<Slot>" = Id equipado
function C.Atributo(slot) return "Cosm_" .. slot end
function C.Equipado(player, slot)
	return C.Item(player:GetAttribute(C.Atributo(slot)))
end
-- casa i (1..RODA_TAMANHO) da roda de emotes: guardada como "Cosm_EmoteSlot<i>"
function C.CasaDaRoda(player, i)
	return C.Item(player:GetAttribute("Cosm_EmoteSlot" .. i))
end

-- ============================================================
-- PLACA DE NOME (os dois places): nome do slot + título + tag + cor + moldura
-- ============================================================
local function degradeArcoIris()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 80, 110)), ColorSequenceKeypoint.new(0.25, rgb(255, 210, 80)),
		ColorSequenceKeypoint.new(0.5, rgb(90, 230, 130)), ColorSequenceKeypoint.new(0.75, rgb(80, 180, 255)),
		ColorSequenceKeypoint.new(1, rgb(200, 110, 255)),
	})
end

-- dados = { Nome, Titulo (item), Tag (item), CorNome (item), Moldura (item), CorTime (Color3|nil) }
function C.MontarPlaca(dados)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlacaCosmeticos"
	billboard.Size = UDim2.fromOffset(220, 62)
	billboard.StudsOffset = Vector3.new(0, 3.1, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 110
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false

	local fundo = Instance.new("Frame")
	fundo.Name = "Fundo"
	fundo.AnchorPoint = Vector2.new(0.5, 1)
	fundo.Position = UDim2.fromScale(0.5, 1)
	fundo.Size = UDim2.new(0, 0, 0, 30)
	fundo.AutomaticSize = Enum.AutomaticSize.X
	fundo.BackgroundColor3 = rgb(16, 20, 30)
	fundo.BackgroundTransparency = 0.25
	fundo.BorderSizePixel = 0
	fundo.Parent = billboard
	local canto = Instance.new("UICorner")
	canto.CornerRadius = UDim.new(0, 8)
	canto.Parent = fundo
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = fundo
	local linha = Instance.new("UIListLayout")
	linha.FillDirection = Enum.FillDirection.Horizontal
	linha.VerticalAlignment = Enum.VerticalAlignment.Center
	linha.HorizontalAlignment = Enum.HorizontalAlignment.Center
	linha.Padding = UDim.new(0, 6)
	linha.Parent = fundo

	-- MOLDURA (borda em degradê)
	local moldura = dados.Moldura
	local borda = Instance.new("UIStroke")
	borda.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	borda.Thickness = moldura and moldura.Espessura or 1
	borda.Color = moldura and Color3.new(1, 1, 1) or (dados.CorTime or rgb(70, 80, 100))
	borda.Parent = fundo
	if moldura then
		local grad = Instance.new("UIGradient")
		grad.Color = moldura.ArcoIris and degradeArcoIris() or ColorSequence.new(moldura.Cor1, moldura.Cor2)
		grad.Rotation = 45
		grad.Parent = borda
		if moldura.Gira then grad:SetAttribute("Gira", true) end
	end

	-- TAG
	if dados.Tag then
		local tag = Instance.new("TextLabel")
		tag.Name = "Tag"
		tag.LayoutOrder = 1
		tag.AutomaticSize = Enum.AutomaticSize.X
		tag.Size = UDim2.new(0, 0, 0, 18)
		tag.BackgroundColor3 = dados.Tag.Cor
		tag.BackgroundTransparency = 0.1
		tag.Font = Enum.Font.GothamBlack
		tag.TextSize = 11
		tag.TextColor3 = rgb(15, 15, 20)
		tag.Text = dados.Tag.Nome
		tag.Parent = fundo
		local c2 = Instance.new("UICorner")
		c2.CornerRadius = UDim.new(0, 4)
		c2.Parent = tag
		local p2 = Instance.new("UIPadding")
		p2.PaddingLeft = UDim.new(0, 5)
		p2.PaddingRight = UDim.new(0, 5)
		p2.Parent = tag
	end

	-- NOME (cor / degradê)
	local nome = Instance.new("TextLabel")
	nome.Name = "Nome"
	nome.LayoutOrder = 2
	nome.AutomaticSize = Enum.AutomaticSize.X
	nome.Size = UDim2.new(0, 0, 1, 0)
	nome.BackgroundTransparency = 1
	nome.Font = Enum.Font.GothamBold
	nome.TextSize = 17
	nome.Text = dados.Nome or "Jogador"
	nome.TextStrokeTransparency = 0.4
	local corNome = dados.CorNome
	if corNome and (corNome.Cor2 or corNome.ArcoIris) then
		nome.TextColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Color = corNome.ArcoIris and degradeArcoIris() or ColorSequence.new(corNome.Cor, corNome.Cor2)
		g.Parent = nome
	else
		nome.TextColor3 = corNome and corNome.Cor or Color3.new(1, 1, 1)
	end
	nome.Parent = fundo

	-- TÍTULO (em cima)
	if dados.Titulo then
		local titulo = Instance.new("TextLabel")
		titulo.Name = "Titulo"
		titulo.AnchorPoint = Vector2.new(0.5, 1)
		titulo.Position = UDim2.new(0.5, 0, 1, -32)
		titulo.Size = UDim2.new(1, 0, 0, 16)
		titulo.BackgroundTransparency = 1
		titulo.Font = Enum.Font.GothamBold
		titulo.TextSize = 13
		titulo.TextColor3 = dados.Titulo.Cor
		titulo.TextStrokeTransparency = 0.35
		titulo.Text = dados.Titulo.Nome
		titulo.Parent = billboard
	end
	return billboard
end

-- lê os atributos "Cosm_*" do jogador e monta os dados da placa
function C.DadosDaPlaca(player, nome, corTime)
	return {
		Nome = nome,
		Titulo = C.Equipado(player, "Title"),
		Tag = C.Equipado(player, "Tag"),
		CorNome = C.Equipado(player, "NameColor"),
		Moldura = C.Equipado(player, "Frame"),
		CorTime = corTime,
	}
end

return C
