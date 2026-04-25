import test from 'node:test';
import assert from 'node:assert/strict';
import { buildIssueRunRequest } from '../src/components/issueRunRequest.ts';

test('buildIssueRunRequest maps the current run config into startRun payload', () => {
  const request = buildIssueRunRequest('/tmp/project', 29, {
    maxIterations: 24,
    passingScore: 92,
    continueMode: true,
  });

  assert.deepEqual(request, {
    projectPath: '/tmp/project',
    issueNumber: 29,
    maxIter: 24,
    passingScore: 92,
    continueMode: true,
  });
});
