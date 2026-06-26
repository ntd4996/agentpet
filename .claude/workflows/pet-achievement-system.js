export const meta = {
  name: 'pet-achievement-system',
  description: 'Add achievement/milestone system to AgentPet for upstream contribution',
  phases: [
    { title: 'P1: Achievement Core', detail: 'Data model + definitions + check logic (tdd)' },
    { title: 'P2: Controller + Celebrate', detail: 'Wire achievements to PetCareController (prod-only)' },
    { title: 'P3: Stats HUD UI', detail: 'Achievement badge row in PetStatsView (prod-only)' },
    { title: 'Verify', detail: 'Evidence checks + code review' },
    { title: 'Check Out', detail: 'Final test, commit' },
  ]
}

const CWD = '/Users/chun/Projects/Aurora-Pets'
const WT = CWD + '/.claude/worktrees/pet-achievement-system'
const PROJECT = 'Aurora-Pets'
const PURPOSE = 'pet-achievement-system'
const TASK = 'Achievement System — milestone unlocks (levels, streaks, tokens, sessions) with badge UI'
const UPSTREAM_BASE = 'origin/main'

const PHASE_RESULT = {
  type: 'object',
  properties: {
    testsPassed: { type: 'boolean' },
    linesChanged: { type: 'number' }
  },
  required: ['testsPassed', 'linesChanged']
}

const EVIDENCE_RESULT = {
  type: 'object',
  properties: {
    allPassed: { type: 'boolean' },
    failures: { type: 'array', items: { type: 'string' } }
  },
  required: ['allPassed', 'failures']
}

const DIFF_INFO = {
  type: 'object',
  properties: {
    linesChanged: { type: 'number' },
    hasSwift: { type: 'boolean' },
    testFileCount: { type: 'number' }
  },
  required: ['linesChanged', 'hasSwift', 'testFileCount']
}

const CODE_REVIEW_RESULT = {
  type: 'object',
  properties: {
    passed: { type: 'boolean' },
    issues: { type: 'array', items: { type: 'string' } }
  },
  required: ['passed']
}

await agent(
  'Run these commands in order:\n' +
  '1. cd ' + CWD + ' && git fetch origin\n' +
  '2. git -C ' + CWD + ' worktree add ' + WT + ' -b feat/achievement-system ' + UPSTREAM_BASE + ' 2>/dev/null || git -C ' + CWD + ' worktree add ' + WT + ' feat/achievement-system\n' +
  '3. Verify: cd ' + WT + ' && git log --oneline -1\n' +
  'Confirm worktree ready at ' + WT + ' based on origin/main.',
  { label: 'worktree', model: 'haiku', effort: 'low' }
)

phase('P1: Achievement Core')

await agent(
  'cd ' + WT + ' && echo "P1 RED"\n\n' +
  'You are working on the AgentPet macOS app (Swift 6.0, SPM). Read:\n' +
  '- Sources/AgentPetCore/PetCare.swift (full file — contains PetCareState struct + PetCare enum)\n' +
  '- Tests/AgentPetCoreTests/PetCareTests.swift\n\n' +
  'Write tests in Tests/AgentPetCoreTests/AchievementTests.swift for an Achievement system:\n\n' +
  'Achievement Design:\n' +
  '- New public enum Achievement: String, Codable, CaseIterable, Sendable with cases:\n' +
  '  firstMeal, sessions100, sessions500, tokens1M, tokens10M, tokens50M,\n' +
  '  level5, level10, level20, level35, streak7, streak14, streak30, nightOwl\n' +
  '- PetCareState gets: public var unlockedAchievements: Set<Achievement>? (Optional for backward compat)\n' +
  '- PetCare gets: public static func checkAchievements(state: PetCareState, hour: Int) -> Set<Achievement>\n' +
  '  Returns ALL achievements the state qualifies for (not just new ones)\n' +
  '- PetCare gets: public static func unlockNewAchievements(state: inout PetCareState, now: Date, calendar: Calendar) -> [Achievement]\n' +
  '  Compares checkAchievements vs already unlocked, updates state, returns newly unlocked list\n\n' +
  'Test cases:\n' +
  '1. testFirstMealUnlocksOnFirstFeeding — recordMeal then unlockNewAchievements → contains .firstMeal\n' +
  '2. testLevelMilestones — feed enough XP to reach level 5 → .level5 unlocked\n' +
  '3. testTokenMilestones — feed 1M tokens → .tokens1M unlocked\n' +
  '4. testStreakMilestones — simulate 7 consecutive days → .streak7 unlocked\n' +
  '5. testNightOwl — unlockNewAchievements at hour 2 (2am) after a feeding → .nightOwl unlocked\n' +
  '6. testNoDoubleUnlock — unlock once, call again, second time returns empty\n' +
  '7. testBackwardCompat — PetCareState JSON without achievements field decodes correctly (nil)\n' +
  '8. testCheckAchievementsIsPure — same state returns same set every time\n\n' +
  'Use the same test pattern as PetCareTests (fixed calendar, date helper). Tests should reference types that do not exist yet.\n' +
  'Run: cd ' + WT + ' && swift build 2>&1 | tail -20 to check compilation status.',
  { label: 'red:P1', phase: 'P1: Achievement Core', agentType: 'red-runner' }
)

const p1Result = await agent(
  'cd ' + WT + ' && echo "P1 GREEN"\n\n' +
  'You are working on AgentPet (Swift 6.0, SPM). The test file at Tests/AgentPetCoreTests/AchievementTests.swift defines what to implement.\n\n' +
  'Read the test file first, then implement in Sources/AgentPetCore/PetCare.swift:\n\n' +
  '1. Add Achievement enum (public, String raw value, Codable, CaseIterable, Sendable) before PetCareState\n' +
  '2. Add unlockedAchievements: Set<Achievement>? to PetCareState (Optional for backward compat, do NOT set in init)\n' +
  '3. Add checkAchievements(state:hour:) to PetCare — returns Set<Achievement> of ALL qualified\n' +
  '   Thresholds: firstMeal=totalMeals>=1, sessions100=100, sessions500=500\n' +
  '   tokens1M=1_000_000, tokens10M=10_000_000, tokens50M=50_000_000\n' +
  '   level5/10/20/35 use displayLevel(forXP:)\n' +
  '   streak7=7, streak14=14, streak30=30\n' +
  '   nightOwl: hour >= 0 && hour < 6 AND totalMeals >= 1\n' +
  '4. Add unlockNewAchievements(state:now:calendar:) — compares check vs unlocked, updates state, returns new\n' +
  '5. Call unlockNewAchievements at the end of feedTokens and recordMeal (before markFed)\n\n' +
  'After implementing, run: cd ' + WT + ' && swift test 2>&1 | tail -40\n' +
  'Report testsPassed and linesChanged.',
  { label: 'green:P1', phase: 'P1: Achievement Core', agentType: 'execute-runner', schema: PHASE_RESULT }
)

if (p1Result && p1Result.linesChanged > 20) {
  await agent(
    'cd ' + WT + ' && echo "Refactor P1"\n' +
    'Read Sources/AgentPetCore/PetCare.swift. Refactor the achievement code for clarity.\n' +
    'Run swift test after refactoring to confirm nothing breaks.',
    { label: 'refactor:P1', phase: 'P1: Achievement Core', agentType: 'code-simplifier' }
  )
}

phase('P2: Controller + Celebrate')

const p2Result = await agent(
  'cd ' + WT + ' && echo "P2 IMPL"\n\n' +
  'Read Sources/App/PetCareController.swift (especially mutateCurrent) and Sources/AgentPetCore/PetCare.swift.\n\n' +
  'Implement:\n' +
  '1. In mutateCurrent(), after level-up celebrate check: detect new achievements by comparing before/after\n' +
  '   If new achievements found -> call PetController.shared.flashCelebrate with achievement-specific line\n' +
  '2. Add computed: var achievements: Set<Achievement> { current.unlockedAchievements ?? [] }\n' +
  '3. Add helper in PetCare: public static func achievementDisplayName(_ a: Achievement) -> String\n' +
  '   Use NSLocalizedString for each achievement name\n\n' +
  'Run: cd ' + WT + ' && swift build 2>&1 | tail -20\n' +
  'Report testsPassed (true if build succeeds) and linesChanged.',
  { label: 'impl:P2', phase: 'P2: Controller + Celebrate', agentType: 'execute-runner', schema: PHASE_RESULT }
)

phase('P3: Stats HUD UI')

const p3Result = await agent(
  'cd ' + WT + ' && echo "P3 IMPL"\n\n' +
  'Read Sources/App/PetStatsView.swift and Sources/App/CareTabView.swift.\n\n' +
  'Implement:\n' +
  '1. PetStatsView: add achievementBlock() between xpBlock and statGrid:\n' +
  '   - Header: "Achievements" with count "X / 14"\n' +
  '   - Horizontal row of SF Symbol badges (20x20pt, 4pt spacing)\n' +
  '   - Unlocked: stageColor. Locked: white opacity 0.15\n' +
  '   - SF Symbols: firstMeal->fork.knife, sessions100->trophy, sessions500->trophy.fill,\n' +
  '     tokens1M->flame, tokens10M->flame.fill, tokens50M->bolt.fill,\n' +
  '     level5->star, level10->star.fill, level20->shield.fill, level35->crown.fill,\n' +
  '     streak7->calendar, streak14->calendar.badge.clock, streak30->calendar.badge.checkmark,\n' +
  '     nightOwl->moon.fill\n' +
  '   - .help(PetCare.achievementDisplayName(a)) for tooltip\n\n' +
  '2. CareTabView: add "Achievements" section after Lifetime section:\n' +
  '   - List unlocked achievements with display name\n' +
  '   - Show "X of 14 unlocked" footer text\n\n' +
  'Run: cd ' + WT + ' && swift build 2>&1 | tail -20\n' +
  'Report testsPassed and linesChanged.',
  { label: 'impl:P3', phase: 'P3: Stats HUD UI', agentType: 'execute-runner', schema: PHASE_RESULT }
)

phase('Verify')

log('Evidence verification...')
const evidence = await agent(
  'cd ' + WT + ' && echo "Evidence checks"\n\n' +
  'Verify ALL:\n' +
  '1. swift test — all tests pass\n' +
  '2. swift build — clean build\n' +
  '3. grep Achievement Sources/AgentPetCore/PetCare.swift — enum exists\n' +
  '4. grep unlockedAchievements Sources/AgentPetCore/PetCare.swift — field exists\n' +
  '5. grep -i achievement Sources/App/PetStatsView.swift — UI exists\n' +
  '6. swift test --filter AchievementTests — specific tests pass\n' +
  '7. Backward compat: unlockedAchievements is Optional (Set<Achievement>?)\n\n' +
  'Report allPassed and failures array.',
  { label: 'evidence', phase: 'Verify', model: 'haiku', schema: EVIDENCE_RESULT }
)

if (evidence && !evidence.allPassed) {
  for (let fix = 0; fix < 2; fix++) {
    await agent(
      'cd ' + WT + ' && echo "Fix evidence"\nFix these failures:\n' + evidence.failures.join('\n') + '\nRun swift test after.',
      { label: 'fix-evidence:' + (fix + 1), phase: 'Verify', agentType: 'execute-runner' }
    )
    const recheck = await agent(
      'cd ' + WT + ' && swift test && swift build\nReport allPassed and failures.',
      { label: 'recheck:' + (fix + 1), phase: 'Verify', model: 'haiku', schema: EVIDENCE_RESULT }
    )
    if (recheck && recheck.allPassed) break
  }
}

log('Code review...')
const diff = await agent(
  'cd ' + WT + ' && git diff --stat ' + UPSTREAM_BASE + '...HEAD\nReport linesChanged, hasSwift, testFileCount.',
  { label: 'diff-stats', phase: 'Verify', schema: DIFF_INFO, model: 'haiku', effort: 'low' }
)

if (diff) {
  const reviews = await parallel([
    function() {
      return agent(
        'cd ' + WT + ' && echo "Swift review"\nReview ALL changed .swift files (git diff ' + UPSTREAM_BASE + '...HEAD).\nFocus: Swift 6 concurrency, Codable backward compat, clean API, no force unwraps.\nReport passed and issues with CRITICAL/HIGH/MEDIUM rank.',
        { label: 'review:swift', phase: 'Verify', agentType: 'code-reviewer', schema: CODE_REVIEW_RESULT }
      )
    },
    function() {
      return agent(
        'cd ' + WT + ' && echo "Test review"\nReview Tests/ files. Check coverage, edge cases, meaningful assertions.\nReport passed and issues.',
        { label: 'review:test', phase: 'Verify', agentType: 'test-reviewer', schema: CODE_REVIEW_RESULT }
      )
    }
  ])

  const criticals = reviews
    .filter(Boolean)
    .flatMap(function(r) { return (r.issues || []).filter(function(iss) { return iss.includes('CRITICAL') }) })

  if (criticals.length > 0) {
    log('Fixing ' + criticals.length + ' CRITICAL findings...')
    await agent(
      'cd ' + WT + ' && echo "Fix CRITICAL"\nFix:\n' + criticals.join('\n') + '\nRun swift test after.',
      { label: 'fix-critical', phase: 'Verify', agentType: 'execute-runner' }
    )
  }
}

phase('Check Out')

log('Final test...')
await agent(
  'cd ' + WT + ' && swift test 2>&1 | tail -30',
  { label: 'final-test', phase: 'Check Out', model: 'haiku', effort: 'low' }
)

log('Committing...')
await agent(
  'cd ' + WT + ' && git add -A && git commit -m "$(cat <<\'EOF\'\nfeat(core): add achievement system with milestone unlocks and badge UI\nEOF\n)"',
  { label: 'commit', phase: 'Check Out', model: 'haiku', effort: 'low' }
)

return {
  status: 'completed',
  task: TASK,
  project: PROJECT,
  purpose: PURPOSE,
  branch: 'feat/achievement-system',
  nextStep: 'User pushes manually then creates PR'
}
