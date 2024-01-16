﻿AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "EZ Solar Panel"
ENT.Author = "Jackarunda, AdventureBoots"
ENT.Category = "JMod - EZ Machines"
ENT.Information = ""
ENT.Spawnable = true
ENT.Base = "ent_jack_gmod_ezmachine_base"
ENT.Model = "models/jmod/machines/Scaffolding_smol.mdl"
ENT.Mass = 100
--
ENT.JModPreferredCarryAngles = Angle(90, 0, 0)
--
ENT.StaticPerfSpecs = {
	MaxDurability = 75,
	MaxElectricity = 0
}
ENT.DynamicPerfSpecs = {
	ChargeSpeed = 1
}
ENT.PowerProducer = true

function ENT:CustomSetupDataTables()
	self:NetworkVar("Float", 1, "Progress")
	self:NetworkVar("Float", 2, "Visibility")
end

local STATE_BROKEN, STATE_OFF,  STATE_ON = -1, 0, 1

if(SERVER)then
	function ENT:CustomInit()
		self.EZupgradable = true
		self:TurnOn()
		self:SetProgress(0)
		self.NextUse = 0
		self.PowerSLI = 0 -- Power Since Last Interaction
		self.MaxPowerSLI = 500
		local mapName = game.GetMap()
	end

	function ENT:SetupWire()
		if not(istable(WireLib)) then return end
		self.Inputs = WireLib.CreateInputs(self, {"ToggleState [NORMAL]", "OnOff [NORMAL]"}, {"Toggles the machine on or off with an input > 0", "1 turns on, 0 turns off"})
		---
		local WireOutputs = {"State [NORMAL]", "Grade [NORMAL]", "Visibility [NORMAL]", "Progress [NORMAL]"}
		local WireOutputDesc = {"The state of the machine \n-1 is broken \n0 is off \n1 is on", "The machine grade", "Solar panel light visibility", "Machine's progress"}
		for _, typ in ipairs(self.EZconsumes) do
			if typ == JMod.EZ_RESOURCE_TYPES.BASICPARTS then typ = "Durability" end
			local ResourceName = string.Replace(typ, " ", "")
			local ResourceDesc = "Amount of "..ResourceName.." left"
			--
			local OutResourceName = string.gsub(ResourceName, "^%l", string.upper).." [NORMAL]"
			table.insert(WireOutputs, OutResourceName)
			table.insert(WireOutputDesc, ResourceDesc)
		end
		self.Outputs = WireLib.CreateOutputs(self, WireOutputs, WireOutputDesc)
	end

	function ENT:UpdateWireOutputs()
		if istable(WireLib) then
			WireLib.TriggerOutput(self, "State", self:GetState())
			WireLib.TriggerOutput(self, "Grade", self:GetGrade())
			WireLib.TriggerOutput(self, "Progress", self:GetProgress())
			WireLib.TriggerOutput(self, "Visibility", self:GetVisibility())
			for _, typ in ipairs(self.EZconsumes) do
				if typ == JMod.EZ_RESOURCE_TYPES.BASICPARTS then
					WireLib.TriggerOutput(self, "Durability", self.Durability)
				end
			end
		end
	end

	function ENT:Use(activator)
		if self.NextUse > CurTime() then return end
		local State=self:GetState()
		local OldOwner=self.EZowner
		local alt = activator:KeyDown(JMod.Config.General.AltFunctionKey)
		JMod.SetEZowner(self,activator)
		JMod.Colorify(self)
		if(IsValid(self.EZowner) and (OldOwner ~= self.EZowner))then
			JMod.Colorify(self)
		end
		if(State==STATE_BROKEN)then
			JMod.Hint(activator,"destroyed",self)
		return
		elseif(State==STATE_OFF)then
			self:TurnOn()
		elseif(State==STATE_ON)then
			if(alt)then
				self:ProduceResource()
				return
			end
			self:TurnOff()
		end
	end

	function ENT:TurnOn()
		if self:GetState() > STATE_OFF then return end
		if (self:CheckSky() > 0) then
			self:EmitSound("buttons/button1.wav", 60, 80)
			self:SetState(STATE_ON)
			self.NextUse = CurTime() + 1
		else
			self:EmitSound("buttons/button2.wav", 60, 100)
		end
		self.PowerSLI = 0 
	end

	function ENT:TurnOff()
		if (self:GetState() <= 0) then return end
		self:EmitSound("buttons/button18.wav", 60, 80)
		self:ProduceResource()
		self:SetState(STATE_OFF)
		self.NextUse = CurTime() + 1
		self.PowerSLI = 0 
	end

	function ENT:SpawnEffect(pos)
		local effectdata=EffectData()
		effectdata:SetOrigin(pos)
		effectdata:SetNormal((VectorRand()+Vector(0,0,1)):GetNormalized())
		effectdata:SetMagnitude(math.Rand(5,10))
		effectdata:SetScale(math.Rand(.5,1.5))
		effectdata:SetRadius(math.Rand(2,4))
		util.Effect("Sparks", effectdata)
		self:EmitSound("items/suitchargeok1.wav", 80, 120)
	end

	function ENT:ProduceResource()
		local SelfPos, Up, Forward, Right = self:GetPos(), self:GetUp(), self:GetForward(), self:GetRight()
		local amt = math.Clamp(math.floor(self:GetProgress()), 0, 100)

		if amt <= 0 then return end

		local pos = SelfPos + Forward*15 - Up*50 - Right*2
		JMod.MachineSpawnResource(self, JMod.EZ_RESOURCE_TYPES.POWER, amt, self:WorldToLocal(pos), Angle(-90, 0, 0), Up*-300, true, 200)
		self:SetProgress(math.Clamp(self:GetProgress() - amt, 0, 100))
		self:EmitSound("items/suitchargeok1.wav", 80, 120)
		--self:SpawnEffect(pos)

		self.PowerSLI = math.Clamp(self.PowerSLI + amt, 0, self.MaxPowerSLI)
		
		if self.PowerSLI >= self.MaxPowerSLI then
			self:TurnOff()
		end
	end

	function ENT:CheckSky()
		local SkyMod,MapName=1,string.lower(game.GetMap())
		for k,mods in pairs(JMod.MapSolarPowerModifiers)do
			local keywords,mult=mods[1],mods[2]
			for _,word in pairs(keywords)do
				if(string.find(MapName,word))then SkyMod=mult break end
			end
		end
		local HitAmount, StartPos = 0, self:GetPos()
		for i = 1, 10 do
			for j = 1, 10 do
				local Dir = self:LocalToWorldAngles(Angle(260 - j*8, -10 + i*2, 0)):Forward()
				local Tr = util.TraceLine({start = StartPos, endpos = StartPos + Dir * 9e9, filter = {self}, mask = MASK_SOLID})
				if (Tr.HitSky) then
					HitAmount = HitAmount + 0.01
				end
			end
		end
		return HitAmount*SkyMod
	end

	function ENT:GetLightAlignment()
		local LightEnt=ents.FindByClass("light_environment")[1]
		local SunEnt=ents.FindByClass("env_sun")[1]
		if(IsValid(LightEnt))then
			-- we can only get yaw, sadly, because Gaben
			local SunVec=-(LightEnt:GetAngles()):Forward()
			local OurFacingVec=self:GetUp()
			local AngleDifference=-math.deg(math.asin(SunVec:Dot(OurFacingVec)))
			-- negative 90 means we're facing directly into the sun
			-- positive 90 means we're facing directly away from it
			return 1-(AngleDifference+90)/180
		elseif(IsValid(SunEnt))then
			local Ang=SunEnt:GetAngles()
			Ang.p=0
			Ang.r=0
			local SunVec=(Ang):Forward()
			local OurFacingVec=self:GetUp()
			local AngleDifference=-math.deg(math.asin(SunVec:Dot(OurFacingVec)))
			return (AngleDifference+90)/180
		end
		if(StormFox)then
			local Minutes = StormFox.GetTime()
			local Frac = Minutes / 1440
			Frac = (math.sin(Frac * math.pi * 2 - math.pi / 2) + 0.1)
			return math.Clamp(Frac, 0, 1)
		end
		-- if the map has no light and no sun, then uh... uhhhhhhhh
		return .5
	end

	function ENT:Think()
		local State = self:GetState()

		self:UpdateWireOutputs()
		
		if(State == STATE_ON)then
			if (self:WaterLevel() > 0) then self:TurnOff() return end
			local weatherMult = 1
			if(StormFox)then 
				if (StormFox.IsNight())then 
					weatherMult = 0 
				else
					local weather = StormFox.GetWeather()
					if (weather == "Fog") or (weather == "Cloudy")then weatherMult = 0.3 
					elseif (weather == "Rainin'") or (weather =="Sleet") or (weather =="Snowin'") or (weather =="Sandstorm")then weatherMult = 0.1 
					elseif (weather == "Lava Eruption") or (weather =="Radioactive")then weatherMult = 0 
					else weatherMult = 1 end
				end
			end

			local AlignmentFactor = self:GetLightAlignment()
			self:SetVisibility(self:CheckSky() * weatherMult * AlignmentFactor)
			local vis = self:GetVisibility()
			local grade = self:GetGrade()

			if vis <= 0 or self:WaterLevel() >= 2 then
				JMod.Hint(JMod.GetEZowner(self), "solar panel no sun")
			elseif self:GetProgress() < 100 then
				local rate = math.Round(1 * JMod.EZ_GRADE_BUFFS[grade] ^ 2 * vis, 2)
				self:SetProgress(self:GetProgress() + rate)
			end

			if self:GetProgress() >= 100 then
				self:ProduceResource()
			end

			self:NextThink(CurTime() + 5)

			return true
		end
	end

	function ENT:OnPostEntityPaste(ply, ent, createdEntities)
		local Time = CurTime()
		ent.NextUse = Time + math.Rand(0, 3)
	end

elseif CLIENT then
	function ENT:CustomInit()
		self.SolarCellModel = JMod.MakeModel(self, "models/hunter/plates/plate3x5.mdl", "models/mat_jack_gmod_solarcells", .5)
		self.PanelBackModel = JMod.MakeModel(self, "models/hunter/plates/plate3x5.mdl", "models/props_pipes/pipeset_metal02", .5)
		self.ChargerModel = JMod.MakeModel(self, "models/props_lab/powerbox01a.mdl", nil, .5)
		self:DrawShadow(true)
	end
	
	function ENT:Draw()
		local SelfPos,SelfAng,State=self:GetPos(),self:GetAngles(),self:GetState()
		local Up,Right,Forward=SelfAng:Up(),SelfAng:Right(),SelfAng:Forward()
		local Grade = self:GetGrade()
		---
		local BasePos=SelfPos
		local Obscured=util.TraceLine({start=EyePos(),endpos=BasePos,filter={LocalPlayer(),self},mask=MASK_OPAQUE}).Hit
		local Closeness=LocalPlayer():GetFOV()*(EyePos():Distance(SelfPos))
		local DetailDraw=Closeness<120000 -- cutoff point is 400 units when the fov is 90 degrees
		local PanelDraw = true
		---
		if((not(DetailDraw))and(Obscured))then return end -- if player is far and sentry is obscured, draw nothing
		if(Obscured)then DetailDraw=false end -- if obscured, at least disable details
		if(State==STATE_BROKEN)then DetailDraw=false PanelDraw=false end -- look incomplete to indicate damage, save on gpu comp too
		---
		self:DrawModel()
		---
		local BoxAng=SelfAng:GetCopy()
		BoxAng:RotateAroundAxis(Right, 90)
		BoxAng:RotateAroundAxis(Forward, 180)
		JMod.RenderModel(self.ChargerModel,BasePos-Up*25+Forward*6-Right*6,BoxAng,Vector(1.8,1.8,1.2), nil, JMod.EZ_GRADE_MATS[Grade])
		local PanelAng=SelfAng:GetCopy()
		PanelAng:RotateAroundAxis(Right, 60)
		if(PanelDraw)then
			JMod.RenderModel(self.SolarCellModel,BasePos-Forward+Right*.5,PanelAng)
		end

		if DetailDraw then
			JMod.RenderModel(self.PanelBackModel, BasePos - Forward * 0.6 + Right * .5, PanelAng, Vector(1.01, 1.01, 1))

			if Closeness < 20000 and State == STATE_ON then
				local DisplayAng = SelfAng:GetCopy()
				DisplayAng:RotateAroundAxis(DisplayAng:Right(), 0)
				DisplayAng:RotateAroundAxis(DisplayAng:Up(), -90)
				DisplayAng:RotateAroundAxis(DisplayAng:Forward(), 180)
				local Opacity = math.random(50, 150)
				local ElecFrac = self:GetProgress() / 100
				local VisFrac = self:GetVisibility()
				local R, G, B = JMod.GoodBadColor(ElecFrac)
				local VR, VG, VB = JMod.GoodBadColor(VisFrac)
				cam.Start3D2D(SelfPos - Up * 35 - Forward * 20 - Right * 30, DisplayAng, .1)
				surface.SetDrawColor(10,10,10,Opacity+50)
				surface.DrawRect(390,80,128,128)
				JMod.StandardRankDisplay(Grade,452,148,118,Opacity+50)
				draw.SimpleTextOutlined("PROGRESS", "JMod-Display", 150, 30, Color(255, 255, 255, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				draw.SimpleTextOutlined(tostring(math.Round(ElecFrac * 100)) .. "%", "JMod-Display", 150, 60, Color(R, G, B, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				draw.SimpleTextOutlined("EFFICIENCY", "JMod-Display", 350, 30, Color(255, 255, 255, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				draw.SimpleTextOutlined(tostring(math.Round(VisFrac * 100)) .. "%", "JMod-Display", 350, 60, Color(VR, VG, VB, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				cam.End3D2D()
			end
		end
	end
	language.Add("ent_jack_gmod_ezsolargenerator", "EZ Solar Panel")
end
