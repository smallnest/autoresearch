import type { JSX } from 'react';
import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import type { ScoreHistoryPoint } from '../stores/iterationStore';
import {
  buildScoreTrendChartData,
  buildScoreTrendTooltipContent,
  type ScoreTrendDatum,
} from './scoreTrendData';

interface ScoreTrendChartProps {
  scoreHistory: ScoreHistoryPoint[];
  passingScore: number;
}

interface ScoreTrendTooltipProps {
  active?: boolean;
  payload?: Array<{
    payload: ScoreTrendDatum;
  }>;
}

function ScoreTrendTooltip({
  active,
  payload,
}: ScoreTrendTooltipProps): JSX.Element | null {
  if (!active || !payload?.[0]) {
    return null;
  }

  const content = buildScoreTrendTooltipContent(payload[0].payload);

  return (
    <div className="max-w-64 rounded-xl border border-gray-200 bg-white px-3 py-2 shadow-lg">
      <p className="text-xs font-semibold text-gray-700">{content.iterationLabel}</p>
      <p className="mt-1 text-sm font-medium text-gray-900">{content.scoreLabel}</p>
      <p className="mt-2 whitespace-pre-line text-xs leading-5 text-gray-500">
        {content.summaryLabel}
      </p>
    </div>
  );
}

export default function ScoreTrendChart({
  scoreHistory,
  passingScore,
}: ScoreTrendChartProps): JSX.Element | null {
  if (scoreHistory.length === 0) {
    return null;
  }

  const data = buildScoreTrendChartData(scoreHistory);

  return (
    <section className="rounded-lg border border-gray-200 bg-gray-50 p-3">
      <div className="mb-3 flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-medium text-gray-500">评分趋势</p>
          <p className="mt-1 text-xs text-gray-400">
            横轴为迭代编号，纵轴为评分（0-100）
          </p>
        </div>
        <span className="rounded-full border border-gray-200 bg-white px-2.5 py-1 text-xs font-medium text-gray-500">
          通过线 {passingScore}
        </span>
      </div>

      <div className="h-56 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart
            data={data}
            margin={{ top: 8, right: 12, bottom: 4, left: -18 }}
          >
            <CartesianGrid stroke="#e5e7eb" strokeDasharray="3 3" vertical={false} />
            <XAxis
              dataKey="iteration"
              allowDecimals={false}
              tickLine={false}
              axisLine={false}
              tick={{ fill: '#6b7280', fontSize: 12 }}
              label={{
                value: '迭代编号',
                position: 'insideBottom',
                offset: -4,
                fill: '#6b7280',
                fontSize: 12,
              }}
            />
            <YAxis
              domain={[0, 100]}
              tickCount={6}
              tickLine={false}
              axisLine={false}
              tick={{ fill: '#6b7280', fontSize: 12 }}
              label={{
                value: '评分',
                angle: -90,
                position: 'insideLeft',
                fill: '#6b7280',
                fontSize: 12,
              }}
            />
            <Tooltip content={<ScoreTrendTooltip />} />
            <ReferenceLine
              y={passingScore}
              stroke="#f59e0b"
              strokeDasharray="6 4"
              ifOverflow="extendDomain"
              label={{
                value: `Passing ${passingScore}`,
                fill: '#b45309',
                fontSize: 12,
                position: 'insideTopRight',
              }}
            />
            <Line
              type="monotone"
              dataKey="score"
              stroke="#2563eb"
              strokeWidth={2.5}
              dot={{ r: 4, strokeWidth: 2, fill: '#ffffff' }}
              activeDot={{ r: 6, strokeWidth: 2, fill: '#2563eb' }}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </section>
  );
}
