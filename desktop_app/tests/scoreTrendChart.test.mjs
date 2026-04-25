import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  buildScoreTrendChartData,
  buildScoreTrendTooltipContent,
} from '../src/components/scoreTrendData.ts';

test('buildScoreTrendChartData preserves iteration order and review summaries', () => {
  const data = buildScoreTrendChartData([
    { iteration: 1, score: 71, review_summary: '需要补测试' },
    { iteration: 2, score: 86, review_summary: null },
  ]);

  assert.deepEqual(data, [
    { iteration: 1, score: 71, reviewSummary: '需要补测试' },
    { iteration: 2, score: 86, reviewSummary: null },
  ]);
});

test('buildScoreTrendTooltipContent exposes score and summary for hover card', () => {
  const tooltip = buildScoreTrendTooltipContent({
    iteration: 3,
    score: 92,
    reviewSummary: '边界条件已覆盖',
  });

  assert.equal(tooltip.iterationLabel, '第 3 次迭代');
  assert.equal(tooltip.scoreLabel, '评分：92/100');
  assert.equal(tooltip.summaryLabel, '边界条件已覆盖');
});

test('ScoreTrendChart component uses Recharts primitives and passing reference line', () => {
  const source = readFileSync(
    resolve(import.meta.dirname, '../src/components/ScoreTrendChart.tsx'),
    'utf8',
  );

  assert.match(source, /LineChart/);
  assert.match(source, /ReferenceLine/);
  assert.match(source, /Tooltip/);
  assert.match(source, /评分趋势/);
  assert.match(source, /通过线/);
});
