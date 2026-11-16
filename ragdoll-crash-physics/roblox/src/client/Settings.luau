--!nonstrict
-- Client settings store. Every entry here is read by a controller; nothing is decorative.
local Settings = {}
Settings.values = {
	Graphics = "High",          -- Low / Medium / High: particles, shadows on props, label range
	ImpactEffects = true,       -- EffectsController
	StatusText = true,          -- floating dummy labels
	Notifications = true,       -- "Damage Indicators": the bottom damage text bar
	BloodText = true,           -- "Blood": show bleeding / blood % wording
	Weather = "Sunny",          -- EffectsController: client-side sky + lighting preset
	SoundEffects = true,        -- AudioController master SFX switch
	CameraShake = true,         -- CameraController
	MasterVolume = 0.8, SfxVolume = 1, MusicVolume = 0.4, -- AudioController SoundGroups
	ReplayQuality = "High",     -- ReplayController sample rate
	DummyLimit = "Automatic",   -- sent to the server
}
Settings.options = {
	Graphics = { "Low", "Medium", "High" }, Weather = { "Sunny", "Sunset", "Foggy", "Night" }, ReplayQuality = { "Low", "High" }, DummyLimit = { "Automatic", "Low", "High" },
}
local changed = Instance.new("BindableEvent")
Settings.Changed = changed.Event

function Settings.get(key: string)
	return Settings.values[key]
end

function Settings.set(key: string, value)
	if Settings.values[key] ~= value then
		Settings.values[key] = value
		changed:Fire(key, value)
	end
end

return Settings
