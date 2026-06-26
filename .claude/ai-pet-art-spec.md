# AI pet art handoff spec

Use this when creating replacement artwork for generated AgentPet local packs.

## Required spritesheet format

- File: `spritesheet.png`
- Canvas: `1536 x 1872` px
- Grid: `8 columns x 9 rows`
- Cell size: `192 x 208` px
- Background: fully transparent PNG with alpha
- Keep every frame centered inside its cell with transparent gutters/margins between frames.
- Use a chibi desktop-pet style: small body, large head, clean outline, readable silhouette at 48-80 px thumbnail size.
- Avoid a solid background. Avoid huge effects touching neighboring frames; the app slices rows/columns by alpha gutters.

## Row/mood mapping used by Windows

- Row 1: idle
- Row 2: working
- Row 3: waiting / needs input
- Row 4: done
- Row 5: celebrate
- Rows 6-9: alternate loops are okay; Windows currently uses rows 1-5, but extra rows can be useful later.

## Frame guidance per row

Each row has 8 frames:

- Idle: subtle breathing/bobbing
- Working: faster energy/action loop
- Waiting: concerned/paused look
- Done: happy/relieved
- Celebrate: stronger excited loop/effects

## Local target folders

Replace only the `spritesheet.png` file in each folder below. Keep `pet.json` as-is unless you rename the pet.

- Goku: `%LOCALAPPDATA%\\AgentPet\\pets\\goku-generated\\spritesheet.png`
- Saitama: `%LOCALAPPDATA%\\AgentPet\\pets\\saitama-generated\\spritesheet.png`
- One-Punch Man: `%LOCALAPPDATA%\\AgentPet\\pets\\one-punch-man-generated\\spritesheet.png`
- Batmeme: `%LOCALAPPDATA%\\AgentPet\\pets\\batmeme-generated\\spritesheet.png`

On this machine that resolves to:

- `C:\Users\PC Gaming\AppData\Local\AgentPet\pets\goku-generated\spritesheet.png`
- `C:\Users\PC Gaming\AppData\Local\AgentPet\pets\saitama-generated\spritesheet.png`
- `C:\Users\PC Gaming\AppData\Local\AgentPet\pets\one-punch-man-generated\spritesheet.png`
- `C:\Users\PC Gaming\AppData\Local\AgentPet\pets\batmeme-generated\spritesheet.png`

## Suggested AI prompt template

Create a transparent PNG spritesheet for a desktop virtual pet. Canvas 1536x1872, 8 columns and 9 rows, each cell 192x208 px. Character is a cute chibi [CHARACTER DESCRIPTION]. Large head, small body, clean dark outline, soft cel-shading, transparent background, centered in each cell, consistent scale, no text, no borders. Row 1 idle breathing animation, row 2 working/action animation, row 3 waiting/concerned animation, row 4 done/happy animation, row 5 celebrate animation, rows 6-9 alternate loops. Keep transparent gutters between all frames so each frame can be sliced automatically.

## After replacing artwork

Restart AgentPet Windows:

```powershell
Get-Process AgentPet.Windows -ErrorAction SilentlyContinue | Stop-Process -Force
& "E:\TOOL DUNG CODE\PET-agent\Windows\src\AgentPet.Windows\bin\Debug\net8.0-windows\AgentPet.Windows.exe"
```
