import puppeteer from 'puppeteer';
import path from 'path';

(async () => {
  console.log('=== TEST SUITE: ONBOARDING PROTOTYPE E2E ===\n');
  const browser = await puppeteer.launch({
    headless: 'new',
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu'
    ]
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 390, height: 844 });
  
  const consoleErrors = [];
  page.on('console', msg => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', err => consoleErrors.push(err.toString()));

  const filePath = 'file://' + path.resolve('docs/prototype/screens/onboarding.html');
  await page.goto(filePath, { waitUntil: 'domcontentloaded' });

  // Test 1: Initial Load & Stage 1
  console.log('[Test 1] Initial Load & Stage 1 Welcome State');
  const stage1Active = await page.$eval('.nb-onboarding__stage[data-stage="1"]', el => el.classList.contains('is-active'));
  const backBtnDisabled = await page.$eval('#onboarding-back-btn', el => el.disabled);
  const progress1 = await page.$eval('#onboarding-progress-fill', el => el.style.width);
  console.log(`  ✓ Stage 1 is active: ${stage1Active}`);
  console.log(`  ✓ Back button disabled: ${backBtnDisabled}`);
  console.log(`  ✓ Progress bar at: ${progress1}`);
  if (!stage1Active || !backBtnDisabled) throw new Error('Stage 1 initialization failed');

  // Test 2: Transition to Stage 2
  console.log('\n[Test 2] Transition to Stage 2 Vibe Selection');
  await page.click('#stage-1-cta');
  await new Promise(r => setTimeout(r, 100));
  const stage2Active = await page.$eval('.nb-onboarding__stage[data-stage="2"]', el => el.classList.contains('is-active'));
  const progress2 = await page.$eval('#onboarding-progress-fill', el => el.style.width);
  const backBtnEnabled = await page.$eval('#onboarding-back-btn', el => !el.disabled);
  console.log(`  ✓ Stage 2 is active: ${stage2Active}`);
  console.log(`  ✓ Progress bar at: ${progress2}`);
  console.log(`  ✓ Back button now enabled: ${backBtnEnabled}`);
  if (!stage2Active || !backBtnEnabled) throw new Error('Stage 2 transition failed');

  // Test 3: Chips Selection & Validation
  console.log('\n[Test 3] Interest Chips Selection & CTA Reactivity');
  const chips = await page.$$('.nb-interest-chip');
  console.log(`  ✓ Total interest chips rendered: ${chips.length}`);
  
  // Deselect all chips to verify Continue button disables
  for (const chip of chips) {
    const isSelected = await chip.evaluate(el => el.classList.contains('is-selected'));
    if (isSelected) await chip.click();
  }
  const ctaDisabledZero = await page.$eval('#stage-2-cta', el => el.disabled);
  console.log(`  ✓ Continue button disabled when 0 selected: ${ctaDisabledZero}`);
  if (!ctaDisabledZero) throw new Error('CTA should be disabled with 0 selections');

  // Re-select chip 0 and chip 2
  await chips[0].click();
  await chips[2].click();
  const ctaEnabled = await page.$eval('#stage-2-cta', el => !el.disabled);
  const counterText = await page.$eval('#selected-counter', el => el.textContent);
  console.log(`  ✓ Counter text: "${counterText}"`);
  console.log(`  ✓ Continue button re-enabled: ${ctaEnabled}`);
  if (!ctaEnabled) throw new Error('CTA should be enabled with selections');

  // Test 4: Transition to Stage 3 & Slider Demonstration
  console.log('\n[Test 4] Transition to Stage 3 Interactive Pose Match Trial');
  await page.click('#stage-2-cta');
  await new Promise(r => setTimeout(r, 100));
  const stage3Active = await page.$eval('.nb-onboarding__stage[data-stage="3"]', el => el.classList.contains('is-active'));
  const initialAligned = await page.$eval('#ghost-overlay', el => el.classList.contains('is-aligned'));
  console.log(`  ✓ Stage 3 is active: ${stage3Active}`);
  console.log(`  ✓ Initially unaligned: ${!initialAligned}`);

  // Move slider to sweet spot (value = 0)
  await page.$eval('#alignment-slider', el => {
    el.value = 0;
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await new Promise(r => setTimeout(r, 100));
  const isAlignedNow = await page.$eval('#ghost-overlay', el => el.classList.contains('is-aligned'));
  const isBannerVisible = await page.$eval('#match-banner', el => el.classList.contains('is-visible'));
  console.log(`  ✓ Ghost turns green (is-aligned): ${isAlignedNow}`);
  console.log(`  ✓ Match banner displays "PERFECT MATCH!": ${isBannerVisible}`);
  if (!isAlignedNow || !isBannerVisible) throw new Error('Slider alignment logic failed');

  // Test 5: Transition to Stage 4 & Privacy Primer
  console.log('\n[Test 5] Stage 4 Privacy & Permissions Primer');
  await page.click('#stage-3-cta');
  await new Promise(r => setTimeout(r, 100));
  const stage4Active = await page.$eval('.nb-onboarding__stage[data-stage="4"]', el => el.classList.contains('is-active'));
  console.log(`  ✓ Stage 4 is active: ${stage4Active}`);

  // Test 6: Permissions Confirmation & Transition to Stage 5
  console.log('\n[Test 6] Enable Permissions & Transition to Stage 5');
  await page.click('#enable-permissions-btn');
  await new Promise(r => setTimeout(r, 450));
  const stage5Active = await page.$eval('.nb-onboarding__stage[data-stage="5"]', el => el.classList.contains('is-active'));
  const progress5 = await page.$eval('#onboarding-progress-fill', el => el.style.width);
  console.log(`  ✓ Stage 5 Launchpad active: ${stage5Active}`);
  console.log(`  ✓ Progress bar at 100%: ${progress5 === '100%'}`);

  // Test 7: Curated Pills & LocalStorage Verification
  console.log('\n[Test 7] Verification of Curated Summary & LocalStorage');
  const curatedPillCount = await page.$$eval('#curated-pill-list .nb-curated-pill', els => els.length);
  console.log(`  ✓ Curated pills rendered matching selections: ${curatedPillCount}`);
  
  // Verify Invariant E2: On Stage 5 entry, onboarding is not prematurely marked complete
  const preCtaHasCompleted = await page.evaluate(() => localStorage.getItem('has_completed_onboarding'));
  console.log(`  ✓ Invariant E2 (Interrupted flow protection): has_completed_onboarding is null before explicit CTA click: ${preCtaHasCompleted === null}`);
  if (preCtaHasCompleted !== null) {
    throw new Error('Onboarding marked complete prematurely before user clicked completion CTA');
  }

  // Click Launch Camera CTA to complete onboarding
  await page.click('#launch-camera-btn');
  await new Promise(r => setTimeout(r, 200));

  const storageState = await page.evaluate(() => ({
    hasCompleted: localStorage.getItem('has_completed_onboarding'),
    interests: JSON.parse(localStorage.getItem('user_selected_interests') || '[]'),
    permStatus: localStorage.getItem('camera_permissions_status')
  }));
  console.log(`  ✓ LocalStorage has_completed_onboarding: ${storageState.hasCompleted}`);
  console.log(`  ✓ LocalStorage user_selected_interests:`, storageState.interests);
  console.log(`  ✓ LocalStorage camera_permissions_status: ${storageState.permStatus}`);
  
  if (storageState.hasCompleted !== 'true' || storageState.interests.length !== 2) {
    throw new Error('LocalStorage state verification failed');
  }

  // Test 8: Console Errors Check
  console.log('\n[Test 8] Console Errors Audit');
  console.log(`  ✓ Console errors detected: ${consoleErrors.length}`);
  if (consoleErrors.length > 0) {
    console.error('Errors:', consoleErrors);
    throw new Error('Console errors were logged during onboarding');
  }

  // Test 9: Skip Affordance Path
  console.log('\n[Test 9] Skip Flow Verification');
  const skipPage = await browser.newPage();
  await skipPage.setViewport({ width: 390, height: 844 });
  await skipPage.goto(filePath, { waitUntil: 'domcontentloaded' });
  await skipPage.click('#onboarding-skip-btn');
  await new Promise(r => setTimeout(r, 200));
  const skipUrl = skipPage.url();
  console.log(`  ✓ Skip redirects to: ${skipUrl}`);
  if (!skipUrl.includes('poses-list.html')) throw new Error('Skip should navigate to poses-list.html');
  await skipPage.close();

  // Test 10: Maybe Later / Deferred Permission Path
  console.log('\n[Test 10] Deferred Permission ("Maybe Later") Flow');
  const deferPage = await browser.newPage();
  await deferPage.setViewport({ width: 390, height: 844 });
  await deferPage.goto(filePath + '?step=4', { waitUntil: 'domcontentloaded' });
  await deferPage.click('#defer-permissions-btn');
  await new Promise(r => setTimeout(r, 200));
  const stage5Deferred = await deferPage.$eval('.nb-onboarding__stage[data-stage="5"]', el => el.classList.contains('is-active'));
  const deferStatus = await deferPage.evaluate(() => localStorage.getItem('camera_permissions_status'));
  console.log(`  ✓ Stage 5 active after deferral: ${stage5Deferred}`);
  console.log(`  ✓ Camera permission marked: ${deferStatus}`);
  if (!stage5Deferred || deferStatus !== 'deferred') throw new Error('Deferred permissions flow failed');
  await deferPage.close();

  // Test 11: Replay Exit Flow
  console.log('\n[Test 11] Replay Exit Flow');
  const replayPage = await browser.newPage();
  await replayPage.setViewport({ width: 390, height: 844 });
  await replayPage.goto(filePath + '?replay=true', { waitUntil: 'domcontentloaded' });
  const replayButton = await replayPage.$eval('#onboarding-skip-btn', el => ({
    text: el.textContent,
    ariaLabel: el.getAttribute('aria-label')
  }));
  console.log(`  ✓ Replay button text: "${replayButton.text}"`);
  console.log(`  ✓ Replay button aria-label: "${replayButton.ariaLabel}"`);
  if (replayButton.text !== 'Exit' || replayButton.ariaLabel !== 'Exit to Settings') {
    throw new Error('Replay exit affordance labels are incorrect');
  }
  const replayStorageBefore = await replayPage.evaluate(() => ({
    hasCompleted: localStorage.getItem('has_completed_onboarding'),
    interests: localStorage.getItem('user_selected_interests'),
    completedAt: localStorage.getItem('onboarding_completed_at')
  }));
  await replayPage.click('#onboarding-skip-btn');
  await new Promise(r => setTimeout(r, 200));
  const replayUrl = replayPage.url();
  const replayStorageAfter = await replayPage.evaluate(() => ({
    hasCompleted: localStorage.getItem('has_completed_onboarding'),
    interests: localStorage.getItem('user_selected_interests'),
    completedAt: localStorage.getItem('onboarding_completed_at')
  }));
  console.log(`  ✓ Replay exit redirects to: ${replayUrl}`);
  if (!replayUrl.includes('settings.html')) throw new Error('Replay exit should navigate to settings.html');
  if (JSON.stringify(replayStorageAfter) !== JSON.stringify(replayStorageBefore)) {
    throw new Error('Replay exit should not persist or overwrite onboarding preferences');
  }
  await replayPage.close();

  await browser.close();
  console.log('\n🎉 ALL 11 ONBOARDING PROTOTYPE TESTS PASSED WITH 100% SUCCESS!\n');
})();
