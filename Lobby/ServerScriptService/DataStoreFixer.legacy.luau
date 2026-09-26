--[[
	DataStoreFixer - Correção de Erros HTTP 500

	Testa se o DataStore está acessível (útil no Studio, onde API
	Services pode estar desabilitado). Antes imprimia um guia gigante
	de diagnóstico (~120 linhas) TODA vez que o servidor iniciava,
	mesmo quando estava tudo certo — reduzido pra 1 linha quando OK, e
	só mostra o passo a passo de como habilitar quando realmente falha.
]]

local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

if RunService:IsStudio() then
	local success, result = pcall(function()
		local testStore = DataStoreService:GetDataStore("ConnectionTest")
		testStore:GetAsync("test")
		return true
	end)

	if success then
		print("✅ DataStoreFixer: API Services habilitado, DataStore acessível.")
	else
		warn("❌ DataStoreFixer: DataStore inacessível (" .. tostring(result) .. "). Habilite em Home > Game Settings > Security > 'Enable Studio Access to API Services', depois reinicie o Studio.")
	end
else
	print("✅ DataStoreFixer: ambiente de produção, DataStore real em uso.")
end
