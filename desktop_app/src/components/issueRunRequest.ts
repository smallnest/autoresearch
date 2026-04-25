import type { RunConfigState } from '../stores/runConfigStore';

export interface IssueRunRequest {
  projectPath: string;
  issueNumber: number;
  maxIter: number;
  passingScore: number;
  continueMode: boolean;
}

type RunConfigSnapshot = Pick<
  RunConfigState,
  'maxIterations' | 'passingScore' | 'continueMode'
>;

export function buildIssueRunRequest(
  projectPath: string,
  issueNumber: number,
  runConfig: RunConfigSnapshot
): IssueRunRequest {
  return {
    projectPath,
    issueNumber,
    maxIter: runConfig.maxIterations,
    passingScore: runConfig.passingScore,
    continueMode: runConfig.continueMode,
  };
}
