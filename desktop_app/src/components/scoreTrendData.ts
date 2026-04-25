import type { ScoreHistoryPoint } from '../stores/iterationStore.ts';

export interface ScoreTrendDatum {
  iteration: number;
  score: number;
  reviewSummary: string | null;
}

export interface ScoreTrendTooltipContent {
  iterationLabel: string;
  scoreLabel: string;
  summaryLabel: string;
}

export function buildScoreTrendChartData(
  scoreHistory: ScoreHistoryPoint[],
): ScoreTrendDatum[] {
  return scoreHistory.map((point) => ({
    iteration: point.iteration,
    score: point.score,
    reviewSummary: point.review_summary,
  }));
}

export function buildScoreTrendTooltipContent(
  point: ScoreTrendDatum,
): ScoreTrendTooltipContent {
  return {
    iterationLabel: `第 ${point.iteration} 次迭代`,
    scoreLabel: `评分：${point.score}/100`,
    summaryLabel: point.reviewSummary ?? '无审核摘要',
  };
}
