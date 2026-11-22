-- Tenue (treillis, combinaison...) : se porte dans l'emplacement « Tenue » et fixe la capacité
-- des poches (contenant « Uniform »). Sans tenue, les poches ont AdvInv.Config.DefaultUniformLoad.
-- La tenue ne change pas l'apparence du joueur.
ENT.Type = "anim"
ENT.Base = "advinv_base_gear"
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = false

ENT.AdvInvCategory = "Uniform"
ENT.PrintName = AdvInv.T("Uniform", "Tenue")
-- Modèle par défaut (jeu de base) : chaque objet définit son ENT.Model.
ENT.Model = "models/props_junk/cardboard_box004a.mdl"
ENT.MaxLoad = 40
ENT.Mass = 30
