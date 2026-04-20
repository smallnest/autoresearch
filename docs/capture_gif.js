const { chromium } = require('playwright');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const fileArg = process.argv[2] || 'en';
const FILES = {
  en: { html: 'autoresearch-promo.html', gif: 'autoresearch-promo.gif' },
  cn: { html: 'autoresearch-promo-cn.html', gif: 'autoresearch-promo-cn.gif' },
};
const target = FILES[fileArg] || FILES.en;
const HTML_FILE = path.resolve(__dirname, target.html);
const FRAMES_DIR = path.resolve(__dirname, 'frames');
const OUTPUT_GIF = path.resolve(__dirname, target.gif);

const DURATION = 24;
const FPS = 10;
const TOTAL_FRAMES = DURATION * FPS;
const INTERVAL = 1000 / FPS; // ms between frames

async function main() {
  // Clean up frames dir
  if (fs.existsSync(FRAMES_DIR)) fs.rmSync(FRAMES_DIR, { recursive: true });
  fs.mkdirSync(FRAMES_DIR);

  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1920, height: 1080 });
  await page.goto(`file://${HTML_FILE}`);
  await page.waitForTimeout(500);

  // Click play to start
  await page.click('#play-btn');
  await page.waitForTimeout(200);

  for (let i = 0; i < TOTAL_FRAMES; i++) {
    const time = (i / FPS).toFixed(2);

    // Set the slider to specific time
    await page.evaluate((t) => {
      const slider = document.getElementById('time-slider');
      slider.value = t;
      slider.dispatchEvent(new Event('input'));
    }, parseFloat(time));

    await page.waitForTimeout(30);

    const framePath = path.join(FRAMES_DIR, `frame_${String(i).padStart(4, '0')}.png`);
    // Screenshot just the canvas area
    const canvas = await page.$('#canvas');
    if (canvas) {
      await canvas.screenshot({ path: framePath });
    } else {
      await page.screenshot({ path: framePath });
    }

    if (i % 20 === 0) console.log(`Captured frame ${i}/${TOTAL_FRAMES} (t=${time}s)`);
  }

  await browser.close();
  console.log('All frames captured. Generating GIF...');

  // Use ffmpeg to generate high-quality GIF
  const cmd = `ffmpeg -y -framerate ${FPS} -i "${FRAMES_DIR}/frame_%04d.png" -vf "fps=${FPS},scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" -loop 0 "${OUTPUT_GIF}"`;

  execSync(cmd, { stdio: 'inherit' });
  console.log(`\nGIF saved to: ${OUTPUT_GIF}`);

  // Get file size
  const stats = fs.statSync(OUTPUT_GIF);
  console.log(`File size: ${(stats.size / 1024 / 1024).toFixed(1)} MB`);

  // Cleanup frames
  fs.rmSync(FRAMES_DIR, { recursive: true });
  console.log('Frames cleaned up.');
}

main().catch(console.error);
