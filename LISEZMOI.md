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

## Sur le Workshop

[Advanced Inventory System](https://steamcommunity.com/sharedfiles/filedetails/?id=3845180672) et ses extensions d'équipement (Lua seulement, chacune
demande son addon de playermodels ; l'équipement de cet addon devient des objets que tout playermodel
peut porter) :

| Extension | Objets | Demande |
|---|---|---|
| [WW1 French gear](https://steamcommunity.com/sharedfiles/filedetails/?id=3845180717) | casques Adrian, képi, bonnet, sac, rouleau de couverture, brêlages | playermodels WW1 French soldiers |
| [Vietnam US gear](https://steamcommunity.com/sharedfiles/filedetails/?id=3845180730) | casques M1, chapeau de brousse, sacs, radio PRC-25, brêlages M1956 | Vietnam era US Soldiers |
| [Russian Army gear](https://steamcommunity.com/sharedfiles/filedetails/?id=3845180748) | casque 6B47, porte-plaques | Russian Army | RF Soldier |
| [Civil War gear](https://steamcommunity.com/sharedfiles/filedetails/?id=3845180762) | képis de l'Union et confédéré | Civil War Soldiers |
| [PAVN and Vietcong gear](https://steamcommunity.com/sharedfiles/filedetails/?id=3845180776) | casques coloniaux, porte-chargeurs AK, sac, chapeau de brousse, chapeau conique | RS2: Forces of the East |
| [PMC gear](https://steamcommunity.com/sharedfiles/filedetails/?id=3845180794) | casquettes, casques à lunettes ou visière, masques à gaz, vision nocturne, casque radio, sacs, ceinturons | PMC Pack Redux |
| [Dying Light gear](https://steamcommunity.com/sharedfiles/filedetails/?id=3845686599) | casque de combat, casquette, masque à gaz, demi-masque respiratoire, masques, cagoule, lunettes, harnais et sacoche T.E.A.R. | Dying Light Security forces |
| [Escape From Tarkov PMC gear](https://steamcommunity.com/sharedfiles/filedetails/?id=3845686657) | casques MICH, ULACH, FAST MT et Altyn, casquettes, cagoules, masque à gaz GP-7, casque radio ComTac, lunettes, six gilets, deux sacs | EFT PMC playermodels [Redux] |

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
| `sling_down` | Arme à la grenadière | Back carry | sangle en travers de la poitrine, arme à plat dans le dos : crosse derrière l'omoplate gauche, canon vers le mollet droit | dos |
| `front_hang` | Arme en relâche avant | Front carry / Hang | pendue devant la poitrine | devant |

Une arme longue est toujours portée d'une de ces façons : elle ne peut pas être rangée hors de vue.

Armes : `weapon_smg1`, `weapon_ar2`, `weapon_shotgun`, `weapon_crossbow` (tous les modes) et
`weapon_rpg` (`sling_up`). Par défaut : à la bretelle. (L'arme en bandoulière et l'ancienne arme à
la grenadière en diagonale ont été retirées : une arme enregistrée ainsi prend un autre mode.)

Règles, toutes décidées par le serveur (une demande forgée est refusée) :

- une arme par zone du corps : dos + devant, oui ; deux dans le dos, non ;
- un équipement peut prendre une zone : `ENT.BlocksCarryZones = { back = true }` sur les sacs (la
  base `advinv_base_rucksack` l'a) ; les gilets ont `{ front = false }`, mettre `front = true` sur un
  gilet de combat (chest rig) ;
- un équipement peut aussi prendre des modes (`ENT.BlocksCarryModes`). Sac à dos sur le dos, il ne
  reste que l'arme à la bretelle (la zone de l'arme à la grenadière est prise), et l'arme à la
  bretelle pend à côté du sac, dans l'alignement de l'épaule ; une arme trop large pour cela
  (l'arbalète, `wide = true` dans `AdvInv.CarryWeapons` ou `ENT.CarryWide`) ne se porte qu'en
  relâche avant tant qu'un sac est porté ;
- quand un équipement prend la zone ou le mode d'une arme portée, l'arme passe en relâche avant si
  elle le peut, sinon au premier mode possible parmi `sling_up`, `sling_down`, `front_hang`, puis ses
  autres modes (l'autre arme longue bouge aussi si cela fait de la place) et le joueur est prévenu. Avec `advinv_carry_refuse_gear 1` (serveur),
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
AdvInv.CarryWeapons["mon_lanceur"] = { modes = { "sling_up" }, default = "sling_up" }
```

ou `ENT.CarryModes` / `ENT.CarryDefault` sur l'objet. Une arme sans réglages calculés est placée
par le gabarit du mode, adapté à sa forme ; à régler en jeu (ci-dessous).

Hooks : `CanChangeCarryMode(ply, item, mode)` (renvoyer false pour interdire ; partagé, il grise
aussi le menu s'il est défini côté client) et `OnCarryModeChanged(ply, item, mode, oldMode)`
(serveur). `item` vaut `{ id = ID de l'objet, cat = "PrimaryWep" ou "RocketLauncher", m = mode
actuel }`.

Affichage (client, `lua/advinv/cl_carry.lua`) : les réglages sont rangés par playermodel,
arme et mode (`lua/advinv/cl_carry_data.lua`, ci-dessous). Un gilet porté écarte les armes
de `Config.CarryVestThickness` devant ; dans le dos selon ce que le modèle du gilet a à cet endroit
(mesuré par `tools/vest_back.py` dans `cl_vest_back.lua` : 0 pour un porte-chargeurs, le panneau d'un
porte-plaques ou d'un gilet souple ; `ENT.CarryBackThickness` le fixe pour un objet ; sans mesure, un
blindage compte `Config.CarryVestThickness`, brêlages et ceinturons rien) ; avec un sac, une arme portée à l'épaule (`Config.CarryOverPack`)
est décalée sur le côté jusqu'à dégager la demi-largeur du sac (`Config.CarryBesidePack = false` :
elle passe par-dessus, écartée de son épaisseur). À côté du sac, une arme dont le bas toucherait le sol ou,
accroupi, passerait devant la hanche pend droit depuis l'épaule, son bas ramené en arrière, derrière le corps
(`Config.CarryGroundGap`, `Config.CarryBesideHipFront`, `Config.CarryBesideMaxSwing`) ; debout, rien ne change.
Quand le lance-roquettes et l'arme principale sont tous deux côté dos et
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

## Autres bases d'armes (ARC9, ArcCW, TacRP, TFA, CW 2.0, Sandstorm, M9K...)

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
préréglage), TFA (accessoires choisis), CW 2.0 (accessoires), Sandstorm SWEPs (accessoires et leurs
motifs), ArcCW (accessoires montés), TacRP (accessoires, mode de tir, second pistolet d'une paire).
N'importe quelle base : hooks
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

**Sandstorm SWEPs** (« Sandstorm SWEP Base » du Workshop et ses packs : fusils d'assaut, pistolets,
pistolets de Ready or Not ; `lua/advinv/sv_sandswep.lua`) :

- les accessoires et leurs motifs restent sur l'arme, avec le chargeur qui va avec ;
- la base garde des chargeurs de rechange dans l'arme (pleins à chaque nouvelle arme, la réserve
  versée dedans). Pour l'arme d'un joueur, ils ne montrent que les munitions des boîtes : un
  rechargement prend ses munitions dans les boîtes, un chargeur retiré (autre chargeur monté,
  rechargement interrompu) y remet les siennes. Pas de chargeurs offerts, rien de caché dans l'arme ;
- ses 25 fusils ont leurs positions de port sur chaque playermodel ajusté (à la bretelle, dans le
  dos, devant).

**ArcCW** (Arctic's Customizable Weapons ; essayé avec sa base et le pack Counter-Strike+ ;
`lua/advinv/sv_arccw.lua`, `sh_arccw.lua`) :

- les accessoires montés restent sur l'arme. Celui qui l'équipe les reçoit et la pose d'ArcCW les
  reprend : son inventaire d'accessoires (`arccw_attinv_free 0`) ne gagne ni ne perd rien. Le
  préréglage enregistré du client n'est pas appliqué par-dessus ;
- les munitions qu'ArcCW rend à la réserve (déchargement, chargeur plus petit, lance-grenades retiré)
  vont dans des boîtes de munitions ; le `/drop` de DarkRP ne donne pas de copies des accessoires ;
- ses boîtes de munitions se prennent avec Utiliser (pas en marchant dessus) ; ses grenades sont des
  objets grenades (un type de munitions chacune, le réglage par défaut d'ArcCW) ;
- les 28 armes longues de Counter-Strike+ ont leurs positions de port sur chaque playermodel ajusté.

**TacRP** (Tactical RP Weapons et ses packs : ExoOps, Scavenger's Spoils... ; `lua/advinv/sv_tacrp.lua`,
`sh_tacrp.lua` ; écrit d'après son code, pas encore essayé en jeu) :

- ses armes vont dans l'emplacement que dit leur type (pistolets et pistolets-mitrailleurs compacts dans
  l'emplacement d'arme de poing, fusils, fusils à pompe, mitraillettes et mitrailleuses dans l'emplacement
  principal, le RPG-7, le Stinger, le M202, le M79 et le M320 dans celui des lance-roquettes ; le
  détonateur de C4 dans celui des armes de poing), avec leurs vraies munitions et taille de chargeur
  (TacRP les range ailleurs que dans les champs habituels) ;
- les accessoires, le mode de tir et le second chargeur d'une paire restent avec l'objet ; qui l'équipe
  les reçoit tout de suite, quoi que disent l'inventaire d'accessoires de TacRP, sa règle d'établi ou la
  configuration sauvegardée du client ; décharger donne des boîtes des munitions que ses accessoires
  lui font utiliser ;
- les munitions que TacRP rend (un chargeur retiré par un accessoire), son sac et sa caisse de munitions,
  les remboursements des accessoires de munitions de surplus et le carreau d'un couteau lancé vont dans
  des boîtes de munitions ; ramasser une arme d'une classe déjà tenue ne donne pas de chargeur gratuit ;
- ses grenades (aveuglante, fumigène, gaz, thermite, charge de brèche, grenade de soin) sont des objets
  grenades ; le lancer rapide n'en lance une que s'il y en a une, et une grenade dégoupillée à la mort
  est retirée des objets. Sa grenade à fragmentation utilise les grenades du jeu (objets grenades de
  Half-Life 2) ; les charges de C4 restent des boîtes de munitions ;
- les modèles « à la ceinture » de TacRP ne sont pas dessinés pour les armes que l'inventaire dessine
  sur le corps.
- Laisser `tacrp_infiniteammo`, `tacrp_infinitelaunchers` et `tacrp_infinitegrenades` à 0 (la console
  du serveur prévient) : un chargeur infini se remplit de rien, et l'inventaire garderait ces munitions
  dans ses objets.

**Emplacements des autres packs** (lus dans leur code, comme du texte) : le choix de l'emplacement lit
le type de prise en main sous les noms que lui donnent les bases (CW 2.0 `NormalHoldType`, ArcCW
`HoldtypeActive`, NC SWEPs `RaisedHoldType`, ASTW2 `HoldType_Aim` / `HoldType_Hipfire`) et le type
propre de l'arme quand elle en a un (`SubCatType` : « 1Pistol », « 4Assault Rifle », « 5Sniper
Rifle »... des NC SWEPs et de TacRP ; la `Class` d'ARC9, qui l'emporte sur son emplacement de menu : les
pistolets-mitrailleurs compacts vont dans l'emplacement d'arme de poing, les lance-grenades dans celui
des lance-roquettes). Un RPG-7 qui tire des roquettes PG-7 / OG-7 est un lance-roquettes, quel que soit
le nom de sa munition. Vérifié sur les packs d'armes de la collection Metro /
S.T.A.L.K.E.R. / Fallout (Workshop 2876037581 : ARC9, ArcCW, TFA, ASTW2, Draconic, NC SWEPs, environ
700 armes). Aussi :

- pas des armes d'inventaire (elles restent des armes ordinaires) : les mains et pouvoirs de
  Vortigaunt, les gestes du masque à gaz de Metro et les armes masque à gaz GP-9 / S.T.A.L.K.E.R., le
  bio-masque du Predator, les PDA et la carte du PDA, la trousse de soin de Call of Duty WW2 ;
- les guitares (guitares de S.T.A.L.K.E.R.) se portent dans le dos, la dynamo à main de Metro dans
  l'emplacement d'arme de poing ;
- la nourriture, les boissons et les médicaments d'EFT Supply (Workshop 3845009964) sont des objets de
  l'emplacement d'arme de poing qui gardent leurs utilisations (les 4 d'une trousse AI-2) et ne se
  déchargent jamais : `AdvInv.NoUnload[classe] = true` fait de même pour d'autres armes dont le
  chargeur contient des utilisations.

## Advanced Crafting System

Avec [Advanced Crafting System](https://steamcommunity.com/sharedfiles/filedetails/?id=3017902884)
(ou une copie) installé (`lua/advinv/sh_acs.lua`, `sv_acs.lua`) :

- ses ressources sont un objet de l'inventaire, des **sacs de ressources d'artisanat** (50 par sac,
  3 points chacun) : ils remplissent les poches, le gilet et le sac à dos, vont dans les caisses et
  les coffres, se fouillent, et restent sur le corps à la mort (son propre dépôt à la mort ne
  trouve alors rien à déposer deux fois) ;
- son établi, ses caisses de ressources, son broyeur, les morts qui rapportent des ressources et
  ses commandes d'admin marchent comme avant, sur les sacs portés : un gain remplit les sacs
  entamés, puis de nouveaux, puis le sol (le joueur est prévenu) ; une dépense prend dans les sacs
  les moins pleins d'abord ; un gain pendant que le joueur est mort lui est donné à la réapparition ;
- gardées d'une visite à l'autre : avec un système de personnages, les sacs sont enregistrés avec
  l'inventaire (un solde enregistré avant par l'addon est donné une fois, en sacs) ; sans, ce que le
  joueur porte est écrit dans la sauvegarde de l'addon et rendu en sacs à sa première apparition ;
- ses outils et sa caisse d'objets fabriqués ne deviennent jamais des armes de l'inventaire.

## JMod

Avec [JMod](https://steamcommunity.com/sharedfiles/filedetails/?id=1919689921) installé
(`lua/advinv/sh_jmod.lua`, `sv_jmod.lua`), et les packs d'armures faits pour lui comme
[EFT Equipment Props + JMOD Armor](https://steamcommunity.com/sharedfiles/filedetails/?id=2804625575) :

- **ses armures sont de l'équipement de l'inventaire** : chaque casque, gilet, gilet de combat,
  sac à dos, masque à gaz, masque, lunettes de vision nocturne, lunettes et casque audio de sa liste
  d'armures (305 avec le pack EFT) est un objet, porté dans la case de la partie du corps qu'il
  couvre (casque, gilet, sac à dos, masque à gaz, JVN, radio). JMod protège toujours, l'use et donne
  ses effets (vision nocturne, filtres, audition) ; l'objet garde sa durabilité, ses charges et sa
  couleur quand il est retiré, posé, laissé sur un corps, ramassé ou enregistré. Alt + Utiliser sur
  une armure de JMod la met (ou la range quand la case est prise), Utiliser la ramasse, la fenêtre
  d'armures de JMod la remet dans l'inventaire ; détruit par JMod, l'objet disparaît (ce que tenait
  un gilet ou un sac est gardé). Deux pièces qui couvrent la même partie du corps sont refusées. Sa
  capacité de rangement devient celle de l'objet (x4), son poids ne compte qu'une fois, comme
  encombrement de l'objet. Dessiné par l'inventaire : où JMod le place sur le corps de référence
  (male_07), reporté sur chaque autre playermodel d'après la taille et la place de sa tête (le
  crâne) ou de son torse, mesurées sur son maillage. Les pièces des membres, les combinaisons
  entières, les accessoires de casque, les foulards et les brassards restent ceux de JMod, comme les
  armures mises par du code (l'équipement d'un métier, les commandes d'admin de JMod), perdues à la
  mort comme JMod le fait ;
- **ses ressources sont des objets de l'inventaire** : un genre de sac pour chacune (bois, acier,
  carburant, produits chimiques..., 100 par sac), les mêmes quantités que l'inventaire de ressources
  de JMod : ce que la touche de ramassage, la fabrication ou la fenêtre de JMod ajoutent ou prennent
  change les sacs, et inversement ; elles ne prennent pas de place dans l'inventaire propre de JMod.
  Des ressources gagnées sans place : une caisse JMod à ses pieds. À la mort, elles restent sur le
  corps comme le reste ;
- **ses munitions vont dans des boîtes de munitions** (caisses de munitions, boîtes) ; ses armes
  sont des armes ArcCW, des armes de l'inventaire comme les autres ; ses outils (mains, boîte à
  outils, trousse de soins, seau, désignateur, hache, pioche, pelles) restent des armes ordinaires ;
- son propre inventaire (la touche de ramassage : grenades, objets) reste le sien ; avec ses cadavres
  activés (`JModCorpseStayTime`), le corps de l'inventaire prend leur place et contient ce que le
  cadavre de JMod aurait eu (ouvert avec la touche de ramassage de JMod).

## Addons du Workshop compatibles

Quand le serveur a un de ces addons, ses modèles deviennent des objets de l'inventaire : portés,
rangés, pris sur les corps, enregistrés comme les autres, et ajustés à chacun des 87 playermodels
par défaut. Rien de ces addons n'est livré avec l'inventaire : les installer sur le serveur (et sa
collection du Workshop) ; le serveur fait télécharger à ses joueurs ceux qu'il a
(`advinv_compat_download 1`). Les objets d'un addon absent n'apparaissent nulle part.

| Addon du Workshop | Objets | Menu de spawn |
|---|---|---|
| [Escape From Tarkov - Equipment Megapack (Props)](https://steamcommunity.com/sharedfiles/filedetails/?id=1883492750) | 16 gilets pare-balles, 14 casques, 6 sacs à dos | Inventaire : Escape From Tarkov |
| [Fallout 76 - Backpacks](https://steamcommunity.com/sharedfiles/filedetails/?id=3234192542) | 54 sacs à dos | Inventaire : Fallout 76 |
| [Fallout 3 Custom Backpacks](https://steamcommunity.com/sharedfiles/filedetails/?id=891790188) | 6 sacs à dos | Inventaire : Fallout 3 |
| [FO3 Backpacks](https://steamcommunity.com/sharedfiles/filedetails/?id=315810701) | sac à armature | Inventaire : Fallout 3 |
| [Imperial Helmet Props Star wars](https://steamcommunity.com/sharedfiles/filedetails/?id=943349673) | 8 casques | Inventaire : Star Wars |
| [[AN] Mace Windu's Clone Helmets](https://steamcommunity.com/sharedfiles/filedetails/?id=973353552) | 2 casques | Inventaire : Star Wars |
| [[NGRP] Rebel Pilot Helmet Prop](https://steamcommunity.com/sharedfiles/filedetails/?id=1268434165) | casque de pilote | Inventaire : Star Wars |
| [TF2 Hex - Helmet of Victory](https://steamcommunity.com/sharedfiles/filedetails/?id=242772309) | 9 casques (leurs textures sont celles de Team Fortress 2 : le monter) | Inventaire : TF2 |
| [US & Soviet Tank crew helmets](https://steamcommunity.com/sharedfiles/filedetails/?id=327527107) | 2 casques | Inventaire : militaire |
| [Amnesia « Adrian helmet »](https://steamcommunity.com/sharedfiles/filedetails/?id=3613961508) | casque Adrian | Inventaire : militaire |
| [DayZ Police vest](https://steamcommunity.com/sharedfiles/filedetails/?id=1448797869) | gilet de police | Inventaire : militaire |
| [Petruz PMC Vests](https://steamcommunity.com/sharedfiles/filedetails/?id=3626263716) | 2 porte-chargeurs, 2 porte-plaques | Inventaire : militaire |
| [Tactical Vest H.E.V Replacement](https://steamcommunity.com/sharedfiles/filedetails/?id=3838802156) | gilet tactique | Inventaire : militaire |

Sacs : capacité selon leur taille (40 à 200), sur le dos (pas d'arme longue en travers). Gilets :
blindage et poches ; les porte-chargeurs prennent l'avant. Casques : blindage. ID 1000 à 1999. Les
ajustements sont faits par `tools/fit_compat.py` à partir de `tools/compat_packs.py` (pour ajouter
un addon : voir DEVELOPERS.md).

## Playermodels du Workshop déjà ajustés

En plus des 87 playermodels de Garry's Mod, chaque objet porté (objets fournis et équipement des
addons compatibles) est ajusté à ces playermodels du Workshop, quand le serveur les a (rien d'eux
n'est livré) :

| Addon du Workshop | Playermodels |
|---|---|
| [Rusty's National Guard Redux](https://steamcommunity.com/sharedfiles/filedetails/?id=3037475566) | 15 soldats (9 hommes, 6 femmes) |
| [Vault Dwellers Part 1](https://steamcommunity.com/sharedfiles/filedetails/?id=3612720459) | 4 habitants d'abri |
| [Star Wars Imperial Officers (Imperial Gaming)](https://steamcommunity.com/sharedfiles/filedetails/?id=1133511197) | 9 officiers |
| [[NGRP] Rebel Pilot Variant](https://steamcommunity.com/sharedfiles/filedetails/?id=1268173091) | pilote rebelle |
| [Rogue One Imperial Naval Officers](https://steamcommunity.com/sharedfiles/filedetails/?id=2593940310) | 34 membres d'équipage impériaux (17 hommes, 17 femmes) |
| [[IC] WW1 French army playermodels 1916](https://steamcommunity.com/sharedfiles/filedetails/?id=3433822040) | 6 soldats français (visages : [{PM0V3} Shared Materials](https://steamcommunity.com/sharedfiles/filedetails/?id=1722627125)) |
| [Russian Army \| RF Soldier](https://steamcommunity.com/sharedfiles/filedetails/?id=2764717646) | 5 soldats russes |
| [Civil War Soldiers [Playermodel + Ragdolls]](https://steamcommunity.com/sharedfiles/filedetails/?id=3614216336) | 8 soldats (4 de l'Union, 4 confédérés) |
| [RS2: Forces of the East](https://steamcommunity.com/sharedfiles/filedetails/?id=2944903873) | 4 soldats (2 de l'APVN, 2 Viêt-minh) |
| [PMC Pack Redux (Playermodels & NPCs)](https://steamcommunity.com/sharedfiles/filedetails/?id=1769231405) | 8 soldats de SMP |
| [Dying Light Security forces playermodels and ragdolls](https://steamcommunity.com/sharedfiles/filedetails/?id=3551549411) | 11 membres des forces de sécurité (GRE, police, soldats, T.E.A.R.) |
| [ESCAPE FROM TARKOV - PMC PLAYERMODELS [REDUX]](https://steamcommunity.com/sharedfiles/filedetails/?id=2568198284) | 9 opérateurs (6 USEC, 3 BEAR) |
| [CSS ENHANCED SPECIAL FORCES /// SEB & SWAT /// PLAYERMODEL](https://steamcommunity.com/sharedfiles/filedetails/?id=3387382988) | 2 opérateurs (SEB, SWAT) |
| [Enhanced Citizens v4](https://steamcommunity.com/sharedfiles/filedetails/?id=677125227) | 23 citoyens (hommes et femmes, rebelles et réfugiés) |
| [Collection du Workshop 2876037581](https://steamcommunity.com/sharedfiles/filedetails/?id=2876037581) (Metro, S.T.A.L.K.E.R., Fallout...) | 1 081 playermodels de 78 de ses addons : Metro 2033, Last Light et Exodus, S.T.A.L.K.E.R. (factions d'Anomaly, Clear Sky, S.T.A.L.K.E.R. 2), Fallout (armures assistées, NCR, Légion de César, Confrérie), Gears of War, Army of Two, Escape From Tarkov, The Division... (la liste : `tools/playermodels_workshop.txt`) |

Tout autre playermodel utilise l'ajustement par défaut de chaque objet (fait sur male_07). La liste
des modèles ajustés est `tools/playermodels.txt` (Garry's Mod) et `tools/playermodels_workshop.txt` ;
DEVELOPERS.md explique comment en ajouter.

**Leur équipement appartient à l'inventaire.** Ces playermodels ont des casquettes, casques, gilets ou
sacs à eux, en bodygroups. L'équipement, c'est l'inventaire qui le donne : ces bodygroups ne se
choisissent plus dans un menu ni par un métier (ils reviennent à « aucun ») ; ils n'apparaissent que
quand l'objet correspondant est porté. Un objet qui *est* l'équipement du modèle est montré par le
modèle lui-même, riggé pour ce corps (le casque Adrian sur les soldats français de 14-18) ; tout autre
objet porté prend leur place. Les autres bodygroups (visages, moustaches, grades, écharpes...) restent
au choix du joueur. La table est `AdvInv.ModelGear` (sh_modelgear.lua) ; les serveurs y ajoutent leurs
playermodels (DEVELOPERS.md).

**Leur équipement en objets : les extensions.** Une extension fait de l'équipement d'un addon de
playermodels des objets que tout playermodel peut porter (liens : « Sur le Workshop » plus haut) : *Advanced Inventory System: WW1 French gear*
(les casques Adrian, le képi, le bonnet, le sac, le rouleau de couverture et les brêlages des soldats
français de 14-18) et *Advanced Inventory System: Vietnam US gear* (les casques M1, le chapeau de
brousse, les sacs, la radio PRC-25 et les brêlages des ragdolls Vietnam era US Soldiers, Workshop
146299217 ou sa version corrigée 3627113533), *Russian Army gear* (casque 6B47, gilet porte-plaques),
*Civil War gear* (képis de l'Union et confédéré), *PAVN and Vietcong gear* (casques coloniaux,
porte-chargeurs AK, sac, chapeau de brousse, chapeau conique), *PMC gear* (casquettes, casques à
lunettes ou visière, masques à gaz, vision nocturne, casque audio, sacs, ceinturons), *Dying Light gear*
(casque de combat, casquette, masque à gaz, demi-masque, masques, cagoule, lunettes, harnais et sacoche
T.E.A.R.) et *Escape From Tarkov PMC gear* (casques, casquettes, cagoules, masque à gaz, casque radio,
lunettes, six gilets, deux sacs) et *CSS special forces gear* (casques MICH avec ou sans vision
nocturne, casques radio, lunettes balistiques, un masque à gaz, gilets porte-plaques nus, avec
chargeurs ou en équipement complet, dans l'olive du SEB ou le noir du SWAT). Chacune ne
contient que du Lua et demande cet addon, sur le serveur et chez les joueurs. Sur ses propres playermodels l'objet est montré par leur bodygroup ; sur tout autre,
une copie ajustée à ce corps ; par terre, l'équipement seul.

**Un équipement qu'on ne peut pas enlever.** Quand le couvre-chef, le gilet ou le sac à dos d'un
playermodel fait partie de son maillage (pas de bodygroup), aucun des nôtres ne se porte par-dessus :
impossible de mettre un couvre-chef sur un autre couvre-chef, un gilet sur un autre gilet, un sac à dos
sur un autre sac à dos, et l'inventaire le dit.

- Couvre-chefs : les soldats du Cartel et la Protection civile, les rebelles (leur bonnet) et la
  médecin à la casquette, Odessa, le zombine, les casques et cagoules de Counter-Strike: Source, les
  tenues de sécurité et anti-radiations de Vault-Tec.
- Gilets : les soldats du Cartel, la Protection civile, le zombine, Barney, Eli, les rebelles et les
  médecins, les gilets de Counter-Strike: Source, les brêlages des soldats de Day of Defeat, le gilet
  du pilote rebelle, l'équipe au sol de Rogue One, et les corps blindés de l'équipage de Rogue One et
  de la tenue de sécurité de Vault-Tec (seulement ces choix de bodygroup).
- Sacs à dos : les rebelles et les médecins.
- Les playermodels de la collection (Workshop 2876037581) : armures assistées, exosquelettes,
  combinaisons étanches et créatures ont les quatre intégrés ; gilets pare-balles, porte-chargeurs,
  capuches relevées, casquettes et sacs du maillage sont intégrés là où ils sont ; casques, masques à
  gaz, gilets et sacs en bodygroups s'enlèvent sous les nôtres (chaque modèle examiné :
  `lua/advinv/sh_modelgear.lua`, bloc généré).

Un joueur qui prend un tel playermodel (ou une telle tenue) en portant le nôtre le récupère : dans son
inventaire, ou à ses pieds s'il n'a pas la place ou si l'objet contient quelque chose (un gilet ou un
sac garde son contenu). Un équipement en bodygroup est enlevé sous le nôtre, comme ceux ci-dessus : le
casque des soldats de Day of Defeat, le harnais de la Garde nationale, les bretelles et cartouchières
des soldats de 14-18, les bâtons de l'équipe au sol de Rogue One. La table est `AdvInv.GearBuiltIn`
(sh_modelgear.lua).

## Grenades

Les grenades sont des objets, pas des armes dans un emplacement : une grenade = un objet, rangé et
empilé comme les autres (grenade de HL2, grenades à fragmentation, aveuglantes et fumigènes de
CW 2.0 ; d'autres : `AdvInv.Grenades[classe] = type de munitions`). Clic droit sur une grenade >
**Utiliser** la met en main ; chaque grenade lancée retire un objet, et l'arme part avec la
dernière. Une arme grenade donnée par un autre code (un métier, le menu de spawn, une caisse de
munitions) devient autant d'objets qu'elle a de grenades. Les grenades d'un équipement d'apparition
(celui d'un métier DarkRP, les armes d'apparition de Sandbox avec `sbox_weapons 1`) sont à cet
équipement : reprises à la mort au lieu de rester sur le corps, pas sauvegardées, redonnées à
l'apparition suivante. Les grenades se lâchent depuis l'inventaire (`/drop` de DarkRP et le
lâcher de CW 2.0 ne les prennent pas).

Les consommables d'autres addons qui marchent de la même façon (une arme à tenir, un type de munitions
à elle, une munition par utilisation) sont aussi des objets comme les grenades : les consommables de No
More Room in Hell (Workshop 3297936273 : bandage, trousse de premiers soins, thérapie génique, pilules
Phalanx) et S.T.A.L.K.E.R. 2 Consumables (Workshop 3426614364 : trousses de soin, bandage, antirad,
pilules, nourriture et boissons) ; de même pour les grenades des packs d'armes qui ont une munition à
elles (la grenade de Metro 2033 Weapon, la F1 et la RGD-5 de S.T.A.L.K.E.R. STCoP, la grenade, la mine et
les boulons du pack TFA S.T.A.L.K.E.R.). D'autres (partagé) :
`AdvInv.ConsumableWeapons["classe_arme"] = "type de munitions"` (`lua/advinv/sh_consumables_ext.lua`).

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
verrouiller et lui donner un code (menu contextuel > Verrouiller / déverrouiller, Choisir le code :
4 à 8 chiffres). Les autres doivent entrer le code pour l'ouvrir, à portée. Tous les 3 mauvais codes
sur une caisse, quel que soit le joueur qui les essaie, elle refuse les codes un moment (30 s,
doublé à chaque fois, jusqu'à une heure) et son propriétaire est prévenu. Un véhicule verrouillé
(clés DarkRP, simfphys) n'ouvre son coffre qu'à ses propriétaires.

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

Avec `advinv_death_drop` en dessous de 3, ce qui ne reste pas sur le corps est toujours au joueur
quand il réapparaît. Hooks (serveur) : `AdvInv_DeathDrop(ply)` (renvoyer false : rien ne reste sur
le corps cette fois, le joueur garde tout) et `AdvInv_DeathBody(ply, body)`. Avec un système de personnages, l'inventaire vidé est enregistré tout
de suite : le prochain chargement ne rend pas les objets ; sans système de personnages, l'inventaire
vidé repart de rien à la prochaine apparition.

## Fouiller un joueur

Menu contextuel (C) sur un joueur à portée > **Fouiller**. Au bout de quelques secondes, les deux
joueurs restant proches, celui qui fouille voit l'inventaire de l'autre à droite de l'écran : les
objets illégaux ont un cadre rouge et sont listés dans la discussion. Il peut prendre des objets (les
faire glisser, ou clic droit sur une arme équipée > Prendre) mais ne peut rien mettre sur l'autre.
Le joueur fouillé voit qui le fouille ; s'éloigner, se perdre de vue ou changer de métier annule
ou termine la fouille, et une fouille terminée dure 2 minutes (`AdvInv.Config.SearchViewTime`). Les
règles (métier, hook) sont vérifiées de nouveau pendant toute la fouille.

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
- `/drop` sur une arme de l'inventaire : DarkRP la lâche comme d'habitude, puis son emplacement est
  libéré ; l'arme lâchée garde son chargeur et ses accessoires mais pas de réserve (les boîtes de
  munitions restent dans l'inventaire). Le lâcher à la mort de DarkRP ne lâche jamais une arme de
  l'inventaire (elle reste sur le corps).
- La confiscation du détecteur d'armes retire les armes de l'inventaire de leurs emplacements
  (DarkRP les rend ensuite comme des armes ordinaires). L'arrestation, le changement de métier et le
  retrait par un admin ne prennent rien d'autre : les boîtes restent, et les armes des emplacements
  reviennent au prochain équipement (pas pendant une arrestation).
- `gm_giveswep` (menu de spawn) suit les règles de DarkRP (armes d'admin, arrêté) ; l'arme qu'il
  donne va dans l'inventaire.
- L'inventaire affiche le portefeuille, avec **Déposer de l'argent** (le `/dropmoney` de DarkRP :
  sa limite de tas d'argent, le placement et les journaux).
- **Prison** : DarkRP retire les armes et les munitions d'un joueur arrêté ; son inventaire reste
  (équipement porté, poches, armes gardées dans leurs emplacements avec leur chargeur). Il peut le
  regarder mais pas le modifier, ni rien prendre avec Utiliser, et la police peut le fouiller. À sa
  libération, ses armes reviennent avec leur chargeur.
- **Changer de métier** garde l'inventaire : les armes des emplacements reviennent après
  l'équipement du nouveau métier, avec leur chargeur et leurs accessoires ; les armes du nouveau
  métier sont des armes ordinaires.
- **Isolation des métiers** (RP militaire ou Star Wars, où un métier est un autre personnage) :
  entrer dans un métier isolé ou en sortir oublie l'inventaire, et le nouveau métier commence vide.
  `advinv_job_isolation 1` isole tous les métiers ; sinon `advinv_isolated_jobs "clone,arc"` liste
  les métiers isolés (commandes ou noms, séparés par des virgules). Dans la table
  `DarkRP.createJob` d'un métier, `AdvInvIsolated = true` ou `false` décide pour ce métier quels que
  soient les réglages. Les deux réglages sont dans le menu d'administration. Hook :
  `AdvInv_JobIsolation(ply, oldTeam, newTeam)` (false : garder, true : oublier). Avec un système de
  personnages qui enregistre les inventaires, le laisser désactivé.
- Une arme que le `/drop` de DarkRP refuse (armes du métier avec `dropspawnedweapons` désactivé,
  `DisallowDrop`, `restrictdrop`) ne peut pas non plus quitter son joueur par l'inventaire : ni
  lâchée, ni mise dans une caisse ou sur un corps. Un autre code peut décider avec le hook
  `AdvInv_CanWeaponLeave(ply, class)`.
- Les entités qui ont une limite DarkRP (`max` dans leur entrée F4) restent des entités : les
  prendre dans l'inventaire libérerait une place dans la limite et laisserait l'acheteur en racheter.
- `advinv_darkrp_loadout_to_inventory 1` (désactivé par défaut) : les armes propres au métier (sa
  liste F4) qui ont un emplacement libre deviennent des armes de l'inventaire (visibles sur le corps,
  modes de port). Elles restent au métier : elles partent quand le joueur change de métier ou meurt
  (jamais laissées sur son corps, jamais enregistrées), et le prochain équipement les redonne. Une
  fouille ne peut ni les prendre ni les décharger, et tant qu'elles ne peuvent pas être lâchées
  (`dropspawnedweapons` désactivé) leur propriétaire ne peut pas les décharger non plus : leurs
  munitions restent dedans (ce qu'un accessoire de chargeur en fait sortir devient des boîtes du
  métier, que seule l'arme du métier charge). Quand DarkRP laisse lâcher les armes du métier (`dropspawnedweapons`), celle qui quitte
  le joueur (lâchée, rangée, dans un gilet ou un sac lâché) devient une arme ordinaire, comme dans
  DarkRP.

## Protections

- Les caisses, corps, coffres, fouilles et établis s'utilisent à portée et en vue : pas à travers un
  mur, un sol, une porte fermée ou un mur de props.
- Utiliser et la touche de ramassage respectent la protection des props (CPPI : FPP...) et le
  `canDarkRPUse` de DarkRP ; le hook `AdvInv_CanPickup(ply, ent)` peut en refuser davantage.
- Les munitions qui traînent, quelle que soit leur quantité (un tas DarkRP fusionné...), vont dans
  des boîtes de la taille d'une boîte ; ce qui ne trouve pas de place reste au sol comme une boîte
  avec le reste.
- Chaque action est vérifiée par le serveur ; un joueur mort peut seulement fermer et arrêter une
  fouille. Au plus 15 actions par seconde et par joueur, 255 objets par contenant, 5 vraies armes
  lâchées à la fois.
- Ce qui vient d'être lâché près d'une caisse ou d'un coffre n'y est pas rangé avant une seconde.

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
- **Rareté** (désactivée par défaut : `advinv_rarity 1`, ou le menu d'administration ; 1 commun ...
  5 légendaire) : `ENT.Rarity` sur un objet ou
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
AdvInv.Items = AdvInv.Items or {}
AdvInv.Items["mon_casque"] = true -- le nom de classe est l'identifiant de l'objet
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

L'identifiant d'un objet est son nom de classe : unique quels que soient les addons (mettez-y votre
nom, par ex. `monnom_casque`), et **jamais renommé** une fois en production (la base enregistre les
noms de classe). L'ancien `AdvInv.ClassID["mon_casque"] = 42` marche toujours (DEVELOPERS.md, Item IDs).

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

Seul, l'addon commence l'inventaire vide à la première apparition et après une mort qui a tout
laissé sur le corps ; toute autre apparition (arrestation DarkRP, réapparition par un admin) le
garde. Il n'enregistre rien. Pour enregistrer les
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

La description de la page du Workshop (format Steam, un aperçu court qui renvoie ici pour le
détail) est dans `workshop/description.txt` : la coller dans la page après la publication. Mise à
jour : `gmpublish.exe update -addon "advanced-inventory.gma" -id 3845180672 -changes "..."`.
