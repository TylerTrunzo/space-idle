# Settings: war toggle, difficulty, hardcore

## What the owner wants **[Owner]**

- A **war toggle** in settings, so war can or can't happen to you.
- A **difficulty** choice: a slider or menu selections.
- Settings can be **changed anytime**.
- A **hardcore mode**: the world is persistent, keeps going offline, and you can be wrecked.
- Even in hardcore, you **always keep a home planet**.

## War toggle **[Claude, owner liked]**

- **"Factions can declare war on me": on or off.**
  - **On:** spec §8 as written. Aggressive factions can threaten you, and diplomacy can calm them at a cost.
  - **Off:** grudges top out at hostile (closed lanes, no deals). No faction declares war on you.
  - **Either way, you can still declare war yourself.** The toggle only covers wars against you.
- **Pirates stay in both modes.** They're not a faction. Difficulty sets their strength.
- **Switching war off mid-war** ends the war with a ceasefire at your next check-in.

## Difficulty **[Claude, owner liked]**

Presets that open into sliders:

```
Difficulty        [Relaxed] [Standard] [Hard] [Custom]
 Faction aggression     ▮▮▮▯▯
 Faction expansion      ▮▮▮▯▯
 Pirate strength        ▮▮▯▯▯
 Grudge memory          ▮▮▮▯▯
War
 Factions can declare war on me   [ON]
```

- **Offline loss caps exist on every difficulty** outside hardcore. Hard raises them but never removes them.
- **`game_sim` bots play every preset,** so each one is balance-tested, not just Standard.
- **Settings are stored per world,** not per player, so later shared galaxies (spec §5.4) choose them at galaxy
  creation.

## Hardcore mode **[Claude, owner liked]**

- **An opt-in exception to the §2 anti-goal** "coming back to devastation." Every other mode keeps that protection.
  When promoted to spec, §2 needs that exception spelled out.
- **Chosen when you start a galaxy, and can't be switched off later.** If you could turn it off when things go
  badly, it wouldn't be hardcore. All other settings stay changeable anytime.
- **What it removes:** offline loss caps (§13.3), and §8's offline protections (slower sieges while you're away, no
  new wars against you while offline). Factions and pirates act at full strength.
- **What it keeps:** warnings. Relations still step down through the news, and fleets en route show an arrival
  time (§8). Hard, but fair, not random.
- **Offline defense becomes real gameplay:**
  - standing garrisons and planetary shields;
  - standing orders ("if attacked, pull back to Kessa");
  - allies who agree to defend you, so diplomacy works as insurance.
- **It previews the later persistent shared galaxies.**
- **The offline cap applies to the whole galaxy [Owner].** §6.7 fast-forwards at most 12 h (up to 48 h with
  upgrades), and in hardcore the whole galaxy stops at that cap, yours and theirs alike. Hardcore removes the loss
  caps, but a long trip away doesn't count against you: factions never act during time your production doesn't
  get. (Rejected: factions keep acting past the cap while your production stops.)

## Home planet **[Owner: always kept; details Claude, owner liked]**

- **Your home can be blockaded but never captured,** in every mode (matches §8). "The game never ends" holds in
  hardcore too.
- **Its core buildings can't drop below a minimum level,** so a rebuild takes days, not weeks.
- **A big loss creates news and openings:** a friendly faction offers aid, or a rival of your conqueror wants an
  ally. Being wrecked starts a comeback.
