# Advanced Inventory System

Inventaire façon Arma 3 pour Garry's Mod : tenue, gilet, sac à dos, casque, LVN, masque à gaz,
radio (casque audio) et trois emplacements d'armes. Les contenants n'ont pas de nombre de places
mais une **capacité** : chaque objet a un **encombrement**, deux chargeurs de pistolet ne prennent
pas la place de deux chargeurs tambours (voir « Encombrement et capacité »). L'équipement porté est
affiché sur le joueur. On ouvre l'inventaire avec la touche `I` (modifiable dans
Options > Advanced Inventory > Inventaire).

Code source, signalements et guide du développeur (`DEVELOPERS.md`, en anglais, pour rendre un
addon compatible avec l'inventaire) : https://github.com/milou2764/gmod-inventory

Aucune dépendance obligatoire. Si ULX/ULib est installé, l'équipement des joueurs
invisibles est caché. Si simfphys est installé, les véhicules servent de coffre.

(English documentation: `README.md`.)

## Langue

Anglais par défaut ; français, allemand, espagnol et russe disponibles. Le serveur choisit pour tout le monde, dans le
`server.cfg` :

```
advinv_language en    // anglais
advinv_language fr    // français
```

Les noms des objets sont lus au chargement de l'addon : après un changement de langue, relancer
la carte. Tous les textes sont dans `lua/advinv/sh_lang.lua` ; pour ajouter une langue,
ajouter une table à `AdvInv.Lang` (les clés manquantes reprennent l'anglais).

## Encombrement et capacité

Comme la « masse » d'Arma 3, l'encombrement est un nombre de points sans unité :

- chaque objet déclare `ENT.Mass` (encombrement), chaque contenant `ENT.MaxLoad` (capacité) ;
- un contenant accepte un objet tant que la somme des encombrements ne dépasse pas sa capacité ;
- contenants du joueur : la **tenue** (poches), le **gilet** (s'il a des poches) et le **sac** ;
  la caisse et le coffre d'un véhicule ont un contenant « Stockage ».

| | Valeurs par défaut |
|---|---|
| Tenue | 40 sans objet « tenue » (`AdvInv.Config.DefaultUniformLoad`), sinon `ENT.MaxLoad` de la tenue |
| Caisse / véhicule | 1000 / 500 (`Config.CrateLoad`, `Config.VehicleLoad`) |
| Munitions | boîte 9 mm 4, .357 3, SMG 8, fusil à pompe 10, AR2 10, roquette 60 ; boîtes de 100 cartouches : 9×19 12, 5,56 20, 7,62 25, 12,7 50 |
| Armes | pistolet 20, .357 25, SMG 40, fusil à pompe 70, AR2 80, arbalète 80, lance-roquettes 120 |
| Équipement | casque 40, gilet 80, sac 30, LVN 20, masque 15 à 20, casque audio 10 |

Un objet sans `ENT.Mass` reçoit une valeur selon sa classe de base (munitions 8, casque 40,
gilet 80, sac 30, arme principale 80...). Un sac ou un gilet d'un autre addon qui ne déclare que
l'ancien `ENT.Capacity` (nombre de places) reçoit 16 points par place.

**Dans l'inventaire (touche I)** : chaque contenant a sa barre « utilisé / capacité » ; on clique
sur un contenant pour voir son contenu. On glisse un objet vers un contenant ou son onglet (ranger),
vers un emplacement d'équipement (équiper), ou hors des panneaux (déposer au sol). Clic droit :
équiper, ranger dans..., déposer. Double-clic : équiper. Touche Utiliser sur un objet au sol :
l'équiper si son emplacement est libre, sinon le ranger (tenue, puis gilet, puis sac).

**Règles** : un sac ou un gilet posé au sol garde son contenu et le rend quand on le remet ;
on ne range pas un sac ou un gilet plein dans un autre contenant (le vider ou le poser au sol) ;
on n'enlève pas une tenue si les poches débordent sans elle. Le serveur vérifie chaque action
(distance, capacité, propriétaire) : un joueur ne peut toucher qu'à son inventaire et aux caisses
ou véhicules à portée.

**Munitions** : la réserve d'une arme est le total des boîtes rangées dans la tenue, le gilet et
le sac ; recharger vide les boîtes (les moins pleines d'abord), une boîte vide disparaît. Une boîte
ramassée complète d'abord les boîtes entamées du même type. Pour une boîte, `ENT.Capacity` reste le
nombre de munitions qu'elle contient au maximum.

**Piles** : les objets identiques d'un contenant (même objet, mêmes munitions, même blindage)
forment une seule case avec leur nombre. Glisser déplace un objet ; le clic droit ajoute « Tout
ranger dans... » et « Tout déposer » (le serveur s'arrête quand il n'y a plus de place).

## Armes

Les armes équipées qui ne sont pas en main sont affichées sur le corps : les armes longues selon
leur mode de port (ci-dessous), l'arme de poing dans un étui sur la cuisse droite. C'est le côté le
plus mince de l'arme qui repose sur le corps : une arbalète est à plat sur ses branches. Elles sont
cachées quand l'arme est en main, quand le joueur est mort ou dans un véhicule, et dans votre propre
vue à la première personne. Dans l'inventaire, les armes sont dessinées de profil, à l'horizontale, à la
taille de leur case ; les armes longues prennent deux cases dans un contenant.

La forme exacte de chaque arme est mesurée sur son maillage la première fois qu'elle est affichée :
n'importe quel modèle d'arme convient. Réglages (client, `lua/advinv/cl_weapons.lua`) :
`Config.WeaponMounts` (os, point de la surface du corps et angles de l'arme pour chaque
emplacement), `Config.ShowMountedWeapons` (false pour couper), `Config.VestBackThickness`,
`Config.WeaponMountGap`.

## Modes de port

Chaque arme longue se porte d'une de ces façons, choisie dans l'inventaire : clic droit sur l'arme
équipée, **Mode de port**. Tout le monde le voit sur le playermodel.

| Mode | Français | Anglais | Où | Zone du corps |
|---|---|---|---|---|
| `sling_up` | Arme à la bretelle | Sling arms | à l'épaule droite, canon en haut | épaule |
| `sling_down` | Arme à la bretelle, canon en bas | Muzzle-down carry | à l'épaule droite, canon en bas | épaule |
| `cross_body` | Arme en bandoulière | Cross-body carry | sangle en travers du torse, arme sur la hanche gauche | côté |
| `back_carry` | Arme à la grenadière | Back carry | en diagonale dans le dos | dos |
| `front_hang` | Arme en relâche avant | Front carry / Hang | pendue devant la poitrine | devant |

Une arme longue est toujours portée d'une de ces façons : elle ne peut pas être rangée hors de vue.

Armes : `weapon_smg1`, `weapon_ar2`, `weapon_shotgun`, `weapon_crossbow` (tous les modes) et
`weapon_rpg` (`back_carry`, `sling_up`). Par défaut : à la bretelle, à la grenadière pour le
lance-roquettes.

Règles, toutes décidées par le serveur (une demande forgée est refusée) :

- une arme par zone du corps : dos + devant, oui ; deux dans le dos, non ;
- un équipement peut prendre une zone : `ENT.BlocksCarryZones = { back = true }` sur les sacs (la
  base `advinv_base_rucksack` l'a) ; les gilets ont `{ front = false }`, mettre `front = true` sur un
  gilet de combat (chest rig) ;
- quand un équipement prend la zone d'une arme portée, l'arme passe au premier mode possible parmi
  `sling_up`, `cross_body`, `front_hang`, puis ses autres modes (l'autre arme longue bouge aussi si
  cela fait de la place) et le joueur est prévenu. Avec `advinv_carry_refuse_gear 1` (serveur),
  c'est l'équipement qui est refusé ;
- un équipement ou une arme qui ne laisserait aucun mode possible à une arme longue est refusé
  (« Plus de place pour porter : RPG ») ;
- vérifié à nouveau à l'apparition, au chargement de l'inventaire, à chaque changement
  d'équipement et à chaque ramassage. Quand deux armes veulent la même zone, celle qui y est déjà
  la garde ;
- le mode est enregistré avec l'objet arme : il le suit dans un contenant, au sol et retour.

Les modes impossibles sont grisés dans le menu, avec la raison (« Impossible avec un sac à dos
équipé »).

Autres armes (données dans `lua/advinv/sh_carry.lua`, partagé) :

```lua
AdvInv.CarryWeapons["mon_fusil"] = { default = "sling_up" }   -- tous les modes
AdvInv.CarryWeapons["mon_lanceur"] = { modes = { "back_carry" }, default = "back_carry" }
```

ou `ENT.CarryModes` / `ENT.CarryDefault` sur l'objet. Une arme sans réglages calculés est placée
par le gabarit du mode, adapté à sa forme ; à régler en jeu (ci-dessous).

Hooks : `CanChangeCarryMode(ply, item, mode)` (renvoyer false pour interdire ; partagé, il grise
aussi le menu s'il est défini côté client) et `OnCarryModeChanged(ply, item, mode, oldMode)`
(serveur). `item` vaut `{ id = ID de l'objet, cat = "PrimaryWep" ou "RocketLauncher", m = mode
actuel }`.

Affichage (client, `lua/advinv/cl_carry.lua`) : les réglages sont rangés par playermodel,
arme et mode (`lua/advinv/cl_carry_data.lua`, ci-dessous). Un gilet porté écarte les armes
de `Config.CarryVestThickness`, un sac fait passer les modes d'épaule par-dessus
(`Config.CarryOverPack`). Quand le lance-roquettes et l'arme principale sont tous deux côté dos et
se croisent, l'un passe sur l'autre. Un playermodel sans l'os d'un mode n'affiche pas cette arme.
Les modèles sont supprimés à la mort, à la déconnexion et au rechargement du Lua.

### Réglages de chaque playermodel de base

`tools/fit_carry.py` place chaque arme dans chaque mode sur les 87 playermodels du jeu de base
(`tools/playermodels.txt`, tirés de `player_manager`) : le mode donne la direction et le côté du
corps, puis l'arme est descendue sur le corps jusqu'à ce que son corps principal le touche, sans y
entrer (bras exclus, ils bougent). Les petites pièces qui dépassent sur le côté, comme celle de
l'AR2, peuvent s'enfoncer : les compter tiendrait toute l'arme à distance du corps. Les playermodels
aux mêmes proportions partagent un jeu de réglages (`AdvInv.CarryAliases`, 49 jeux) : un modèle rejoint un jeu seulement si ce jeu lui va sans
traverser le corps et à moins d'une unité de son propre réglage. Un playermodel d'un autre addon
utilise le jeu `default` (male_07).

```
cd tools
python fit_carry.py                          # réécrit lua/advinv/cl_carry_data.lua
python carry_sheets.py dossier               # une image par arme et par mode : tous les playermodels
python carry_sheets.py dossier --one models/player/alyx.mdl     # tous les modes, 4 vues
python carry_sheets.py dossier --pairs models/player/alyx.mdl   # lance-roquettes + arme principale
```

### Commandes de développement (client)

- `advinv_carry_tune` : une visionneuse avec votre playermodel, votre arme longue et son mode (ou
  tout autre choix) : curseurs pour l'os, la position et les angles. Le changement se voit tout de
  suite, dans la visionneuse et dans le monde, sur tous les playermodels du jeu de réglages.
  **Print** écrit les valeurs dans la console, **Save** écrit toutes les valeurs réglées dans
  `garrysmod/data/advinv_carry_tuned.json` (rechargé la fois suivante). Pour les livrer, copier ce
  fichier en `tools/carry_overrides.json` et lancer `python fit_carry.py`.
- `advinv_carry_cycle` : la même visionneuse qui passe par chaque playermodel de base x arme x mode
  (1 914 vues ; précédent / suivant, par modèle, ou Auto avec un délai), avec une deuxième arme si
  voulu, et un choix d'animation (repos, marche, course, pistolet en main...).

## Quantités et objets au sol

- Faire glisser une pile déplace un objet ; **Maj + glisser** déplace toute la pile. Clic droit sur
  une pile > **Ranger une quantité dans** / **Déposer une quantité...** pour choisir combien.
- Clic droit sur une boîte de munitions > **Diviser la boîte...** : les munitions choisies vont dans
  une nouvelle boîte.
- Les objets identiques déposés ensemble forment une seule pile au sol, et un objet déposé sur une
  pile identique la rejoint. Prendre une pile en prend autant qu'il y a de place ; le reste reste.
- Regarder un objet au sol affiche son nom, combien il y en a, ses munitions, son encombrement et la
  touche pour le prendre (le corps d'un joueur mort : son nom et la touche pour le fouiller). Les
  joueurs qui veulent plus d'immersion désactivent ce texte : Options > Advanced Inventory >
  Inventaire : plus, ou le réglage client `advinv_hover_text 0`.
- Les objets posés au sol par l'inventaire (lâchés, échangés, l'arme d'un joueur mort...)
  disparaissent après `advinv_ground_item_time` secondes (serveur, 600 par défaut, 0 : jamais ;
  aussi dans le menu d'administration). Ramassés ou rangés, ils ne comptent plus ; ajouter à une
  pile relance son temps. L'objet d'un point de butin reste jusqu'à ce qu'on le prenne. Les corps
  ont leur propre temps (`advinv_death_loot_time`).

## Armes et objets qui traînent

Les armes posées dans le monde (lâchées, apparues par le menu, placées par la carte) se prennent
avec la touche Utiliser, plus en marchant dessus : dans leur emplacement s'il est libre, sinon
dans la tenue, le gilet ou le sac. Une arme qui a son objet enregistré devient cet objet (`weapon_ar2` ->
l'objet AR2) ; toute autre arme devient un objet « arme générique » qui garde sa classe, ses
munitions et, pour une arme longue, reçoit tous les modes de port. Les armes données par le code
(armes de métier, `ply:Give`) ne sont pas touchées, et une arme donnée depuis le menu de spawn va
directement dans l'inventaire.

La trousse de soins, la fiole de soins et la batterie de combinaison de HL2 se prennent aussi avec
Utiliser (les toucher ne les utilise plus), et les munitions HL2 deviennent la boîte de munitions
correspondante.

```
advinv_pickup_weapons 1      // armes qui traînent : prises avec Utiliser dans l'inventaire
advinv_pickup_any_weapon 1   // armes sans objet enregistré : objets génériques
advinv_pickup_entities 1     // entités de la liste et munitions HL2 : prises avec Utiliser
```

Listes que d'autres addons peuvent compléter (partagé, `lua/advinv/sh_generic.lua`) :

```lua
AdvInv.PickupWhitelist["ma_trousse"] = { name = "Trousse", model = "models/...", mass = 6 }
AdvInv.WeaponBlacklist["mon_outil"] = true            -- jamais transformé en objet
AdvInv.PickupConvert["mon_entite_munitions"] = "advinv_ammo_ar2"  -- devient cet objet enregistré
AdvInv.WeaponCategory["mon_fusil"] = "PrimaryWep"     -- force l'emplacement d'une arme
```

L'emplacement d'une arme sans objet enregistré est deviné d'après son emplacement dans le menu et sa
prise en main (pistolets, armes de mêlée et grenades : arme de poing ; RPG : lance-roquettes ; le
reste : arme principale) ; `SWEP.AdvInvCategory` et `SWEP.AdvInvMass` sur l'arme le remplacent. Le
physgun, le toolgun, l'appareil photo, les mains et les outils de DarkRP sont exclus.

## Autres bases d'armes (ARC9, TFA, CW 2.0, M9K...)

Les armes de n'importe quelle base deviennent des armes génériques (voir plus haut). Leurs
munitions :

- Chaque type de munitions sans objet munitions enregistré reçoit une **boîte de munitions générique**
  (30 munitions, encombrement 8) : elle se range, alimente la réserve et se vide en rechargeant
  comme les boîtes HL2, et reçoit les munitions d'une arme déchargée. Par type :
  `AdvInv.AmmoBoxSize[type]`, `AmmoBoxMass[type]`, `AmmoBoxModel[type]`. Menu
  d'administration > Objets : donner une boîte de n'importe quel type.
- Les entités de munitions des autres bases se prennent avec Utiliser dans l'inventaire quand elles
  indiquent leur type et leur quantité (`ENT.AmmoType` et `ENT.AmmoCount` / `AmmoAmount` / `Amount`).

Accessoires : une arme garde ses données en plus à travers l'inventaire (retirée, rangée, déposée,
rééquipée, enregistrée). Intégré, sans essai sur toutes les versions de ces bases : ARC9 (code de
préréglage), TFA (accessoires choisis), CW 2.0 (accessoires). N'importe quelle base : hooks
(serveur) `AdvInv_WeaponData(wep)` -> une chaîne, et `AdvInv_ApplyWeaponData(wep, data)`
-> true une fois fait. Les armes aux données différentes ne s'empilent pas.

**CW 2.0** (essayé avec la base du Workshop, « Chuck's Weaponry 2.0 », et ses 15 armes) :

- les fusils vont dans l'emplacement principal (encombrement 80, tous les modes de port), les
  pistolets et les grenades dans l'emplacement de l'arme de poing (encombrement 20) ; l'emplacement
  vient de l'emplacement de menu et de la tenue de l'arme (`AdvInv.WeaponCategory[classe]` pour le
  changer) ;
- les accessoires restent sur l'arme (retirée, rangée, déposée, prise sur un corps, enregistrée).
  Celui qui l'équipe reçoit ses accessoires, comme CW 2.0 le fait pour ses propres armes lâchées ;
- `cw_dropweapon` sur une arme de l'inventaire la lâche à la façon de l'inventaire (hors de son
  emplacement, accessoires gardés) ; les armes lâchées par CW 2.0 se prennent avec Utiliser dans
  l'inventaire ;
- les munitions des trousses et caisses de munitions de CW 2.0 vont dans des boîtes de munitions
  génériques de leur calibre.

## Utiliser des objets, décharger les armes

Clic droit sur un objet de son inventaire > **Utiliser** (ou double-clic) : la trousse de soins
(+25 de vie), la fiole de soins (+10) et la batterie de combinaison (+15 de blindage) de HL2 sont
consommées ; rien ne se passe si vous n'en avez pas besoin. Clic droit sur une arme (rangée ou
équipée) > **Décharger** : les munitions de son chargeur retournent dans des boîtes de munitions,
les boîtes entamées d'abord, puis de nouvelles boîtes (au sol s'il n'y a plus de place).

Autres objets utilisables (partagé) :

```lua
AdvInv.Consumables["ma_ration"] = { health = 15, armor = 0, sound = "items/smallmedkit1.wav" }
ENT.Consumable = { health = 40 }                       -- sur un objet enregistré
function ENT:OnUseItem(ply, item) ... return true end  -- n'importe quel effet ; true = consommé
```

Hook (serveur) : `AdvInv_UseItem(ply, item)`, renvoyer false pour interdire. Une arme se
décharge quand ses munitions ont un objet boîte de munitions.

## Stockage : permanent, partagé, personnel, banques, verrous, butin

Admins : menu contextuel (C) sur une caisse > **Réglages du stockage** :

- **Permanent** : la caisse est enregistrée avec la carte, contenu compris, et revient à chaque
  démarrage (et après un nettoyage de la carte). Les joueurs ne peuvent ni la déplacer ni la
  supprimer.
- **Personnel** : chaque joueur y a son propre contenu (par personnage avec un système de
  personnages).
- **Nom partagé** : les caisses de même nom partagent un seul contenu, n'importe où sur la carte.
- **Capacité** : sa propre capacité (0 : `Config.CrateLoad`).
- **Table de butin** : une fois vidée, la caisse est remplie à nouveau d'objets au hasard après le
  délai (minutes).

**Banques** (`advinv_bank`, menu de spawn, admins) : toutes les banques ouvrent le même stockage
personnel du joueur (capacité `Config.BankLoad`, 300), conservé entre les sessions.

**Verrous** : le joueur qui a fait apparaître ou acheté une caisse, et les admins, peuvent la
verrouiller et lui donner un code (menu contextuel > Verrouiller / déverrouiller, Choisir le code).
Les autres doivent entrer le code pour l'ouvrir.

**Points de butin** (menu d'administration > Points de butin) : des points invisibles où un objet
au hasard d'une table de butin apparaît, et réapparaît quelques secondes après avoir été pris. En
ajouter un là où l'on regarde, puis clic droit dans la liste pour y aller, le modifier ou le
supprimer ; les points sont affichés tant que l'onglet est ouvert.

Tables de butin (partagé) : `supplies`, `medical`, `weapons` sont fournies ; ajouter les siennes :

```lua
AdvInv.LootTables["armurerie"] = { rolls = { 1, 2 }, items = {
    { item = "advinv_ammo_ar2", weight = 5 },          -- un objet enregistré
    { weapon = "weapon_crowbar", weight = 2 },        -- n'importe quelle arme
    { entity = "item_healthkit", weight = 3, count = { 1, 2 } },  -- une entité de la liste
} }
```

Enregistré dans SQLite (tables créées si absentes, jamais supprimées) : `advinv_storage` (stockages
permanents, réglages et contenu) et `advinv_stores` (stockages partagés et personnels, banques).

## Mort

Le corps d'un joueur mort garde ce qu'il portait : son ragdoll reste là où il est tombé, avec son
équipement (casque, gilet, sac...), ses armes portées sur lui, ses poches, son gilet et son sac
toujours pleins. L'arme qu'il tenait en main tombe au sol à côté de lui.

N'importe qui à portée ouvre le corps avec la touche Utiliser : son inventaire s'affiche à côté du
sien. Les objets équipés se prennent par double-clic ou clic droit > Prendre (dans son emplacement
s'il est libre, sinon dans ses contenants) : ils quittent le corps, un casque pris n'est donc plus
sur sa tête. Les poches, le gilet et le sac se vident en faisant glisser, comme une caisse.
Réglages du serveur :

```
advinv_death_drop 3          // laissé sur le corps : 0 rien (le joueur garde tout), 1 le contenu de
                             // la tenue/du gilet/du sac, 2 la même chose et les armes, 3 tout
advinv_death_loot_time 300   // secondes avant que le corps disparaisse (0 : jamais)
advinv_death_body_max 20     // corps au plus, le plus ancien part en premier
advinv_death_loot_name 1     // le nom du mort est affiché sur son corps
```

Hooks (serveur) : `AdvInv_DeathDrop(ply)` (renvoyer false : rien ne reste sur le corps cette fois) et
`AdvInv_DeathBody(ply, body)`. Avec un système de personnages, l'inventaire vidé est enregistré tout
de suite : le prochain chargement ne rend pas les objets ; sans système de personnages, l'inventaire
est remis à zéro à chaque apparition.

## Fouiller un joueur

Menu contextuel (C) sur un joueur à portée > **Fouiller**. Au bout de quelques secondes, les deux
joueurs restant proches, celui qui fouille voit l'inventaire de l'autre à droite de l'écran : les
objets illégaux ont un cadre rouge et sont listés dans la discussion. Il peut prendre des objets (les
faire glisser, ou clic droit sur une arme équipée > Prendre) mais ne peut rien mettre sur l'autre.
Le joueur fouillé voit qui le fouille ; s'éloigner annule ou termine la fouille.

```
advinv_search_mode 1    // 0 personne (sauf les admins), 1 métiers autorisés, 2 tout le monde
advinv_search_time 5    // secondes que dure une fouille
advinv_search_take 1    // celui qui fouille peut prendre (confisquer) des objets
```

Métiers autorisés (mode 1) : les métiers de police de DarkRP, et les noms d'équipe de
`AdvInv.Config.SearchTeams` ; sans l'un ni l'autre (pas de DarkRP, liste vide), tout le monde
peut fouiller. Objets illégaux : `ENT.Illegal = true` sur un objet enregistré, ou
`AdvInv.IllegalItems[classe] = true` pour n'importe quelle classe. Hooks :
`CanSearchInventory(searcher, target)` (partagé, false pour interdire, true pour autoriser),
`AdvInv_Searched(searcher, target, illegalNames)` et
`AdvInv_Confiscated(searcher, target, item)` (serveur).

## DarkRP

- Ce qui est acheté depuis le menu F4 (entités, armes, munitions) va directement dans l'inventaire
  s'il y a la place (`advinv_darkrp_buy_to_inventory 1`). Les cargaisons restent telles quelles ; les
  armes qu'elles donnent, comme toute arme DarkRP qui traîne, se prennent avec Utiliser (chargeur
  plein), une à la fois.
- Les munitions DarkRP qui traînent deviennent des boîtes de munitions.
- `/drop` sur une arme de l'inventaire : DarkRP la lâche comme d'habitude et son emplacement est
  libéré. Le lâcher à la mort de DarkRP ne lâche jamais une arme de l'inventaire (elle reste sur le
  corps).
- L'inventaire affiche le portefeuille, avec **Déposer de l'argent**.
- `advinv_darkrp_loadout_to_inventory 1` (désactivé par défaut) : les armes du métier qui ont un
  emplacement libre deviennent des armes de l'inventaire (sur le corps, modes de port, lâchées à la
  mort). Avec le lâcher à la mort, chaque réapparition en redonne de nouvelles à lâcher : à
  réfléchir avant de l'activer.

## Administration

Les admins ouvrent le menu d'administration avec la commande console `advinv_admin`, ou par un clic
droit sur un joueur dans le menu contextuel (C) > **Inventaire (admin)**.

- **Joueurs** : voir l'inventaire d'un joueur à côté du sien, de n'importe où sur la carte : faire
  glisser des objets entre les deux, clic droit sur un objet > Supprimer, clic droit sur un objet
  équipé > Prendre ou Supprimer. **Vider l'inventaire** supprime tout ce que le joueur porte et
  transporte.
- **Objets** : donner n'importe quel objet, ou n'importe quelle arme par sa classe, à un joueur
  (boîtes pleines, armes chargées, équipement au blindage maximal).
- **Réglages** : tous les réglages serveur de l'addon (variables console `advinv_*`), appliqués tout
  de suite.

Qui est admin : le privilège CAMI `Advanced Inventory System - Admin` (les superadmins par défaut ; ULX, SAM,
FAdmin... peuvent le donner à d'autres groupes). Sans CAMI : les superadmins. Le serveur vérifie
chaque demande, note chaque action dans sa console et appelle le hook
`AdvInv_AdminAction(admin, action, target, text)`.

## Divers

- **Infobulles** : encombrement, emplacement, rareté, munitions et chargeur, type de munitions,
  modes de port, blindage, capacité, ce que l'utilisation donne, et « Illégal ».
- **Rareté** (1 commun ... 5 légendaire) : `ENT.Rarity` sur un objet ou
  `AdvInv.ItemRarity[classe] = 3` pour n'importe quelle classe ; le cadre de l'objet prend sa
  couleur.
- **Blindage par partie du corps** : tout objet porté avec `ENT.Armor` protège les parties qu'il
  couvre, s'use sous les coups et laisse passer plus de dégâts en s'usant. Parties :
  `ENT.ArmorHitgroups` sur l'objet, sinon selon l'emplacement (`AdvInv.ArmorZones` : casque
  tête, gilet poitrine et ventre, tenue corps, bras et jambes, masque à gaz tête).
- **Thèmes** : Options > Advanced Inventory > Inventaire : plus > Couleurs (sombre, clair, militaire), ou le
  réglage client `advinv_theme`.
- **Langues** : `advinv_language en / fr / de / es / ru` (allemand, espagnol et russe dans
  `lua/advinv/sh_lang_more.lua` ; les noms d'objets y restent en anglais ; corrections
  bienvenues).
- **Ouvrir** : la touche I, les commandes de discussion `!inventory`, `/inventory`, `!inv`, `/inv`,
  ou l'outil Inventaire (`advinv_inventory_tool` : clic gauche ouvre, clic droit prend l'objet regardé).
- **Touche de ramassage** : Options > Advanced Inventory > Inventaire : plus (aucune par défaut : la touche
  Utiliser).
- **Fabrication** (désactivée par défaut : `advinv_craft 1` sur le serveur, ou le menu
  d'administration) : le bouton Fabrication de l'inventaire, ou un établi (`advinv_workbench`,
  admins) : les recettes prennent leurs ingrédients dans la tenue, le gilet et le sac. Deux exemples sont
  fournis (trousse de soins avec 2 fioles ; munitions .357 avec 3 boîtes de pistolet, à un établi).
  Ajouter les siennes (partagé) :

```lua
AdvInv.AddRecipe({
    id = "bandage", name = { en = "Bandage", fr = "Bandage" },
    needs = { { item = "advinv_tissu", count = 2 } },     -- item / entity / weapon / ammo
    gives = { entity = "item_healthvial" },
    bench = false, time = 2,
})
```

  Hooks (serveur) : `AdvInv_CanCraft(ply, recipe)` (false pour interdire),
  `AdvInv_Crafted(ply, recipe)`.
- **Wiremod** (s'il est installé) : les caisses ont les sorties Load, Capacity, Items et Viewers.

## Option : la charge ralentit le joueur

Désactivée par défaut. Dans le `server.cfg` :

```
advinv_load_slowdown 1        // active l'option
advinv_load_free 300          // charge sans effet (points)
advinv_load_max 1000          // charge où le ralentissement est maximal
advinv_load_min_speed 0.55    // vitesse restante à cette charge (fraction)
```

La charge est l'encombrement de tout ce que porte le joueur (contenu des contenants et objets
équipés) ; elle s'affiche dans l'inventaire, avec la vitesse quand l'option est active.

## Tenue

L'emplacement « Tenue » reçoit un objet basé sur `advinv_base_uniform` ; son `ENT.MaxLoad` fixe la
capacité des poches. Sans tenue, les poches valent `Config.DefaultUniformLoad`. La tenue ne change
pas l'apparence du joueur.

```lua
ENT.Base = "advinv_base_uniform"
ENT.PrintName = "Treillis F2"
ENT.Spawnable = true
ENT.Model = "models/props_junk/cardboard_box004a.mdl"
ENT.MaxLoad = 60 -- capacité des poches
ENT.Mass = 30    -- encombrement quand elle est rangée
```

## Contenu

- `lua/autorun/advinv_loader.lua` : chargement de l'addon
- `lua/advinv/` : logique (registre d'objets, sauvegarde SQLite, interface,
  affichage de l'équipement, éditeur de placement, langues)
- `lua/entities/advinv_base_*` : classes de base des objets
  (`advinv_base_helmet`, `advinv_base_vest`, `advinv_base_pocketvest`, `advinv_base_rucksack`,
  `advinv_base_wep`, `advinv_base_ammobox`, `advinv_base_gear`)
- `lua/entities/advinv_*` : objets fournis, faits avec des modèles du jeu de base
- `lua/entities/advinv_crate.lua` : caisse de stockage (capacité 1000, contenu non sauvegardé)

L'addon ne contient que du Lua : modèles, icônes et sons viennent tous de Garry's Mod.

## Objets fournis

Menu de spawn (Entités) : « Inventaire : équipement », « Inventaire : armes », « Inventaire :
munitions » et « Inventaire : mobilier » (caisses, casier de banque, établi) ; l'outil Inventaire
est dans Armes > « Inventaire ». Les objets sans icône propre montrent leur modèle, comme les
props. Ils n'utilisent que des modèles installés avec Garry's Mod.
ID réservés : 100 à 127.

| Objet | Emplacement | Modèle | Affichage |
|---|---|---|---|
| `advinv_cp_mask` | masque à gaz | `models/barneyhelmet_faceplate.mdl` | os + décalage |
| `advinv_top_hat` | casque | `models/player/items/humans/top_hat.mdl` | bonemerge |
| `advinv_graduation_cap` | casque | `models/player/items/humans/graduation_cap.mdl` | bonemerge |
| `advinv_barney_helmet` | casque | `models/barneyhelmet.mdl` | os + décalage |
| `advinv_bucket` | casque | `models/props_junk/metalbucket01a.mdl` | os + décalage |
| `advinv_jetpack` | sac | `models/thrusters/jetpack.mdl` | os + décalage |
| `advinv_suitcase` | sac | `models/props_c17/suitcase001a.mdl` | os + décalage |

Armes HL2 et leurs munitions :

| Arme | Emplacement | Munition | Objet de munitions |
|---|---|---|---|
| `advinv_hl2_pistol` (`weapon_pistol`) | arme secondaire | `Pistol` | `advinv_ammo_pistol` (20) |
| `advinv_hl2_357` (`weapon_357`) | arme secondaire | `357` | `advinv_ammo_357` (6) |
| `advinv_hl2_smg1` (`weapon_smg1`) | arme principale | `SMG1`, `SMG1_Grenade` | `advinv_ammo_smg1` (45), `advinv_ammo_smg1_grenade` (1) |
| `advinv_hl2_ar2` (`weapon_ar2`) | arme principale | `AR2`, `AR2AltFire` | `advinv_ammo_ar2` (20), `advinv_ammo_ar2_altfire` (1) |
| `advinv_hl2_shotgun` (`weapon_shotgun`) | arme principale | `Buckshot` | `advinv_ammo_buckshot` (20) |
| `advinv_hl2_crossbow` (`weapon_crossbow`) | arme principale | `XBowBolt` | `advinv_ammo_crossbow` (6) |
| `advinv_hl2_rpg` (`weapon_rpg`) | lance-roquettes | `RPG_Round` | `advinv_ammo_rpg` (1) |

Icônes du menu de spawn : les armes et munitions réutilisent celles de Garry's Mod
(`ENT.IconOverride = "entities/weapon_smg1.png"`) ; les objets sans icône (équipement, caisses)
montrent leur modèle, comme les props (l'addon ne livre aucun matériau).

Les munitions de réserve sont les objets de munitions rangés dans l'inventaire :
recharger consomme ces objets. Une arme sans chargeur (`ENT.ClipSize = -1`, comme le
lance-roquettes) est donnée sans munitions.

## Créer un objet

Un objet est une entité qui hérite d'une classe de base, plus un ID unique. Son nom se donne dans
chaque langue avec `AdvInv.T(anglais, français)`, ou en simple texte.

**N'importe quel prop** : on le fixe sur un os du playermodel avec `ENT.Attach`.

```lua
-- lua/entities/mon_casque.lua
AddCSLuaFile()
ENT.Base = "advinv_base_helmet"
ENT.PrintName = AdvInv.T("Heavy helmet", "Casque lourd")
ENT.Spawnable = true
ENT.Model = "models/mon_addon/casque.mdl"
ENT.Armor = 150
ENT.Attach = {
    bone = "ValveBiped.Bip01_Head1",
    pos = Vector(1.5, 0.4, -1.5),
    ang = Angle(90, 10, 0),
    scale = 1,
}

-- n'importe où dans un fichier partagé (lua/autorun/...) :
AdvInv = AdvInv or {}
AdvInv.ClassID = AdvInv.ClassID or {}
AdvInv.ClassID["mon_casque"] = 42
```

**Modèle riggé sur le squelette ValveBiped** : ne pas mettre d'`ENT.Attach`,
l'objet est affiché en bonemerge et se plie avec le corps (gilets, sacs à bretelles).

Deux playermodels au même squelette n'ont pas la même carrure (poitrine plus en avant,
épaules plus hautes...). Un objet riggé ajusté sur `models/player/group01/male_07.mdl`
peut déclarer `ENT.BodyFit` pour être décalé selon le playermodel qui le porte :

```lua
ENT.BodyFit = "vest" -- centré sur le torse, bretelles posées sur les épaules
ENT.BodyFit = "back" -- collé au dos
```

Le décalage suit l'os Spine4 du joueur (l'objet continue à se plier avec le corps). Les
mesures des 87 playermodels fournis avec Garry's Mod sont dans
`lua/advinv/cl_bodyfit_data.lua` ; un playermodel absent de la table garde le
placement d'origine. Un addon peut ajouter les siens :
`AdvInv.BodyFit.models["models/x.mdl"] = { avant, dos, épaule }`, mesurés avec
`tools/bodyfit.py` (voir l'en-tête du script).

Pour trouver les valeurs de `ENT.Attach`, ouvrir l'éditeur avec la console :

```
advinv_attach_editor                  -- casque de Barney par défaut
advinv_attach_editor mon_casque       -- reprend le modèle et les réglages d'un objet
advinv_attach_editor models/x/y.mdl   -- n'importe quel modèle
```

Régler l'os, le décalage, la rotation et la taille sur l'aperçu, puis « Copier le
code » et coller le bloc dans le fichier de l'objet.

Si le modèle n'a pas de collision (`.phy`), l'objet posé au sol reçoit une boîte de
collision autour du modèle ; `ENT.PhysBox = { Vector(...), Vector(...) }` permet de la
définir à la main.

Règles des ID : entre 2 et 127, uniques, et **jamais modifiés** une fois en
production (ils sont enregistrés en base).

Champs utiles selon la base : `Mass` (encombrement, tous les objets), `MaxLoad` (capacité d'un
sac, d'un gilet à poches ou d'une tenue), `Armor` (casque,
gilet), `NVGsHolder` (casque pouvant porter des LVN), `AdvInvCategory` (`Rucksack` pour
un sac, `Gasmask` pour un masque, `Radio` pour un casque audio), et pour les armes `WeaponClass`, `Ammo`, `Rounds`,
`ClipSize` avec `AdvInvCategory` = `PrimaryWep`, `SecondaryWep` ou `RocketLauncher`.

## Ajusté à chaque playermodel

Chaque objet porté et les emplacements des armes sont adaptés à chacun des 87 playermodels fournis
avec Garry's Mod (`tools/playermodels.txt`) : les casques reposent sur cette tête, les chapeaux et
le seau grandissent là où une tête, des cheveux ou un casque dépasseraient, les sacs se posent sur
ce dos, les armes sur ce dos et cette cuisse. Les valeurs sont dans
`lua/advinv/cl_fits_data.lua`, produit par `tools/fit_items.py` (règles dans son en-tête) ;
un playermodel absent (modèle personnalisé) utilise l'`ENT.Attach` de l'objet et
`Config.WeaponMounts`. Après avoir modifié un objet ou ajouté un playermodel à la liste :

```
cd tools
python fit_items.py                 # réécrit lua/advinv/cl_fits_data.lua
python fit_sheets.py dossier        # une image par objet : l'objet sur chaque playermodel
```

## Vérifier les objets portés sans lancer le jeu

`tools/mount_check.py` (non inclus dans le `.gma`) pose chaque objet porté de `lua/entities` sur
des playermodels comme le fait le jeu (FollowBone avec `ENT.Attach`, bonemerge sans), dans leur
pose de référence, et les dessine de face, de gauche et de dos, sans lancer Garry's Mod. Corps par
défaut : Dr Isaac Kleiner et male_07 ; on peut donner n'importe quel playermodel du jeu.

```
cd tools
python mount_check.py dossier_de_sortie [models/player/alyx.mdl ...]
```

`tools/weapon_check.py` fait de même pour les armes : icônes de l'inventaire et armes sur le corps
(avec et sans sac). Les modèles d'armes sont posés dans la première image de leur séquence de repos
(`tools/anim0.py`), comme le jeu les dessine : canon selon +X, dessus selon +Z.

Les objets sont dessinés dans leur pose de repos (première image de leur séquence de repos) : beaucoup de modèles sont enregistrés tournés et ne prennent leur vraie orientation que par elle (sauf les props statiques). Dans la pose de référence, un corps ValveBiped regarde vers -Y ; dans l'os de la tête, X pointe
vers le haut, Y vers l'arrière et Z vers la droite (utile pour écrire `ENT.Attach` à la main).

## Sauvegarde et intégration à un système de personnages

Seul, l'addon remet l'inventaire à zéro à chaque apparition et n'enregistre rien. Pour enregistrer les
inventaires (par joueur, par personnage...), indiquer à qui appartient l'inventaire porté et appeler
Load / Save :

```lua
-- serveur
hook.Add("AdvInv_ShouldAutoInit", "MonRP", function() return false end) -- pas de remise à zéro
hook.Add("AdvInv_OwnerID", "MonRP", function(ply) return idDuPersonnage(ply) end)

AdvInv.Load(ply, owner)      -- quand le joueur prend le personnage (les objets équipés sont donnés)
AdvInv.Save(ply, owner)      -- à la déconnexion / à l'arrêt du serveur
AdvInv.Record(owner)         -- les données enregistrées sans joueur (aperçus...)
AdvInv.RecordSlot(record, "Helmet") -- l'objet d'un emplacement enregistré
AdvInv.DeleteRecord(owner)   -- un personnage supprimé
AdvInv.GiveWeapons(ply)      -- redonne les armes des emplacements qui manquent (après un StripWeapons)
AdvInv.SetDefaults(ply)      -- inventaire de départ vide
AdvInv.Clear(ply)            -- tout vider
```

Un propriétaire est une chaîne ou un nombre quelconque (un SteamID64, un ID de personnage...). Côté
client : `AdvInv_CanOpen(ply)` (renvoyer false pour empêcher l'ouverture) et
`AdvInv_PanelCreated(panel, target)`.

Les données sont dans la table SQLite `advinv_inventory` (`sv.db`), une ligne par propriétaire, en
JSON : `{"v":3,"s":{emplacement: objet},"c":{contenant: [objets]}}`, chaque objet sous la forme
`[id, munitions, blindage, mode de port, classe, données en plus]`. Les colonnes de la table ne
changent jamais.

## Publication

```
gmad.exe create -folder "addons/advanced-inventory" -out "advanced-inventory.gma"
gmpublish.exe create -addon "advanced-inventory.gma" -icon "icone_512x512.jpg"
```

La description de la page du Workshop (format Steam, toutes les fonctionnalités, lien vers GitHub)
est dans `workshop/description.txt` : la coller dans la page après la publication.
