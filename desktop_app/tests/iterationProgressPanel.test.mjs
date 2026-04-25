import test from 'node:test';
import assert from 'node:assert/strict';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { ReviewScoreSection } from '../src/components/reviewScoreSection.ts';

function renderScoreSection(props) {
  return renderToStaticMarkup(createElement(ReviewScoreSection, props));
}

test('ReviewScoreSection renders score badge and summary card together', () => {
  const markup = renderScoreSection({
    score: 78,
    passingScore: 85,
    summary: '需要补充边界测试',
  });

  assert.match(markup, /78\/100/);
  assert.match(markup, /yellow/);
  assert.match(markup, /审核摘要/);
  assert.match(markup, /需要补充边界测试/);
  assert.doesNotMatch(markup, /通过/);
});

test('ReviewScoreSection shows passing banner when score reaches threshold', () => {
  const markup = renderScoreSection({
    score: 85,
    passingScore: 85,
    summary: '实现已达标',
  });

  assert.match(markup, /85\/100/);
  assert.match(markup, /green/);
  assert.match(markup, /通过/);
  assert.match(markup, /<svg/);
});

test('ReviewScoreSection hides the entire score area when score is missing', () => {
  const markup = renderScoreSection({
    score: null,
    passingScore: 85,
    summary: '不应单独显示摘要',
  });

  assert.equal(markup, '');
});
