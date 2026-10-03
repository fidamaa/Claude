-- Coloque este script em StarterPlayer > StarterPlayerScripts
-- ⚠️ v110: o SetCore falha ("ResetButtonCallback has not been registered")
-- se rodar antes dos CoreScripts — tenta de novo até pegar.
for _ = 1, 20 do
	local ok = pcall(function()
		game:GetService("StarterGui"):SetCore("ResetButtonCallback", false)
	end)
	if ok then break end
	task.wait(0.5)
end