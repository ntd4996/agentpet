# Goku AI spritesheet prompt for AgentPet

Use this to generate a replacement spritesheet for:

`C:\Users\PC Gaming\AppData\Local\AgentPet\pets\goku-generated\spritesheet.png`

## Required output

- PNG spritesheet
- Canvas: `1536 x 1872`
- Grid: `8 columns x 9 rows`
- Each frame/cell: `192 x 208`
- Transparent background
- No text, no labels, no watermark, no borders
- Character centered in every frame with transparent gutters between cells

## Main prompt

Create a high-quality transparent PNG spritesheet for a desktop virtual pet. Canvas size exactly 1536x1872 pixels, arranged as a clean 8 columns by 9 rows grid, each frame exactly 192x208 pixels. Each frame contains the same cute chibi anime martial-arts hero inspired by Goku: small body, oversized head, spiky black hair, orange gi, blue undershirt, blue wristbands, blue belt, blue boots, warm cheerful expression, clean dark outline, soft cel-shading, polished game sprite quality. The character should be centered in each cell, with enough transparent padding/gutters between frames so every frame can be sliced automatically. Transparent background only.

Animation layout:
Row 1 idle breathing loop: 8 frames, subtle bobbing, relaxed stance, tiny hair and clothing movement.
Row 2 working/power-up loop: 8 frames, stronger stance, glowing golden energy aura, small energy sparks, body leaning forward slightly.
Row 3 waiting/concerned loop: 8 frames, thoughtful or slightly worried expression, one hand near chin or looking around.
Row 4 done/happy loop: 8 frames, smiling, thumbs up or satisfied pose, gentle bounce.
Row 5 celebrate loop: 8 frames, excited jump or victory pose, bright aura, happy face, dynamic motion.
Row 6 alternate idle loop: 8 frames, arms folded, confident stance, subtle breathing.
Row 7 alternate action loop: 8 frames, martial arts punch/kick motion, readable silhouette, no frame crosses cell boundaries.
Row 8 alternate waiting loop: 8 frames, sitting or crouched, calm expression.
Row 9 alternate celebrate loop: 8 frames, cheerful wave, spark effects, same scale and position.

Style requirements: cute chibi desktop pet, not realistic, not 3D, not pixelated too heavily, crisp outline, smooth anti-aliased sprite art, consistent character design across all 72 frames, consistent scale, consistent camera angle, full body visible in every frame, transparent background.

## Negative prompt

text, letters, captions, logo, watermark, signature, border, grid lines, background, scenery, white background, black background, colored background, cropped body, cut off hair, cut off feet, inconsistent character, multiple characters in one frame, changing outfit, changing hair color, realistic human, 3D render, blurry, low quality, messy limbs, extra arms, extra legs, deformed hands, distorted face, huge effects crossing frame boundaries, aura covering neighboring frames, non-transparent background, frame overlap, uneven grid, incorrect number of frames

## If your AI cannot produce a correct 8x9 sheet

Use this fallback prompt to generate one row at a time, then assemble rows into a 1536x1872 sheet.

### Row strip prompt template

Create a transparent PNG sprite animation strip, canvas exactly 1536x208 pixels, 8 frames in one horizontal row, each frame exactly 192x208 pixels. Same cute chibi anime martial-arts hero inspired by Goku: spiky black hair, orange gi, blue undershirt, blue wristbands, blue belt, blue boots, clean dark outline, soft cel-shading, transparent background. Full body centered in every frame with transparent gutters. No text, no watermark, no background, no borders. Animation: [ROW ANIMATION DESCRIPTION].

Replace `[ROW ANIMATION DESCRIPTION]` with:

1. idle breathing, subtle bobbing, relaxed stance
2. power-up working loop, golden aura, small energy sparks, strong stance
3. waiting/concerned loop, looking around, hand near chin
4. done/happy loop, smiling, thumbs up, gentle bounce
5. celebrate loop, victory pose, jumping slightly, bright aura
6. alternate idle, arms folded, confident stance
7. action loop, martial arts punch/kick motion
8. calm waiting loop, sitting or crouched
9. cheerful wave celebrate loop, spark effects

## Recommended generation notes

- Prefer models/settings that support transparent PNG or alpha channel.
- If the model cannot output transparency, use a flat pure green background `#00FF00`; then remove the background before saving as PNG.
- The app will look best if the character occupies about 120-155 px height inside each 192x208 cell.
- Avoid effects touching the edges of each 192x208 cell.
- Do not add invisible or low-alpha guide pixels/lines. AgentPet may treat any alpha as sprite content in fallback slicing paths.
- In the Windows app, rows only appear when `SpritePetView.Mood` changes; settings previews should cycle moods to show non-idle rows.
