import { createElement, Fragment, type ReactElement } from 'react';
import { scoreBadgeClass } from './iterationProgressView.ts';

interface ScoreDisplayProps {
  score: number;
  passingScore: number;
}

interface ReviewSummaryCardProps {
  summary: string;
}

export interface ReviewScoreSectionProps {
  score: number | null;
  passingScore: number;
  summary: string | null;
}

function ScoreDisplay({ score, passingScore }: ScoreDisplayProps): ReactElement {
  const isPassing = score >= passingScore;

  return createElement(
    'div',
    { className: 'space-y-2' },
    createElement(
      'div',
      { className: 'flex items-center justify-between' },
      createElement(
        'span',
        { className: 'text-xs font-medium text-gray-500' },
        '审核评分',
      ),
      createElement(
        'span',
        {
          className: `rounded-full border px-3 py-1 text-sm font-semibold ${scoreBadgeClass(score)}`,
        },
        `${score}/100`,
      ),
    ),
    isPassing
      ? createElement(
          'div',
          {
            className:
              'flex items-center gap-2 rounded-lg border border-green-200 bg-green-50 px-3 py-2',
          },
          createElement(
            'svg',
            {
              className: 'h-4 w-4 shrink-0 text-green-600',
              fill: 'none',
              viewBox: '0 0 24 24',
              stroke: 'currentColor',
              strokeWidth: 2.5,
            },
            createElement('path', {
              strokeLinecap: 'round',
              strokeLinejoin: 'round',
              d: 'M5 13l4 4L19 7',
            }),
          ),
          createElement(
            'span',
            { className: 'text-sm font-medium text-green-700' },
            '通过',
          ),
        )
      : null,
  );
}

function ReviewSummaryCard({ summary }: ReviewSummaryCardProps): ReactElement {
  return createElement(
    'div',
    { className: 'rounded-lg border border-gray-200 bg-gray-50 px-3 py-2' },
    createElement(
      'p',
      { className: 'mb-1 text-xs font-medium text-gray-500' },
      '审核摘要',
    ),
    createElement(
      'p',
      { className: 'whitespace-pre-line text-sm text-gray-700' },
      summary,
    ),
  );
}

export function ReviewScoreSection({
  score,
  passingScore,
  summary,
}: ReviewScoreSectionProps): ReactElement | null {
  if (score == null) {
    return null;
  }

  return createElement(
    Fragment,
    null,
    createElement(ScoreDisplay, { score, passingScore }),
    summary != null ? createElement(ReviewSummaryCard, { summary }) : null,
  );
}
