import { useMemo, useCallback } from 'react';

// --- Types ---

interface DiffLine {
  type: 'added' | 'removed' | 'context' | 'hunk' | 'fileHeader';
  content: string;
}

interface FileDiff {
  filePath: string;
  lines: DiffLine[];
}

// --- Parser ---

/**
 * Parse unified diff text into structured file blocks.
 * Pure function: string → FileDiff[]
 */
export function parseUnifiedDiff(diffText: string): FileDiff[] {
  if (!diffText || !diffText.trim()) return [];

  const files: FileDiff[] = [];
  const lines = diffText.split('\n');
  let currentFile: FileDiff | null = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // New file diff header: "diff --git a/path b/path"
    if (line.startsWith('diff --git ')) {
      // Extract file path from "diff --git a/path b/path"
      const match = line.match(/^diff --git a\/(.+?) b\/(.+)$/);
      if (match) {
        currentFile = { filePath: match[2], lines: [] };
        files.push(currentFile);
      }
      continue;
    }

    if (!currentFile) continue;

    // Skip diff metadata lines
    if (
      line.startsWith('index ') ||
      line.startsWith('old mode ') ||
      line.startsWith('new mode ') ||
      line.startsWith('similarity index ') ||
      line.startsWith('copy from ') ||
      line.startsWith('copy to ') ||
      line.startsWith('rename from ') ||
      line.startsWith('rename to ') ||
      line.startsWith('Binary files ')
    ) {
      continue;
    }

    // File header lines: --- a/path or +++ b/path
    if (line.startsWith('--- ') || line.startsWith('+++ ')) {
      currentFile.lines.push({
        type: 'fileHeader',
        content: line,
      });
      continue;
    }

    // Hunk header: @@ -a,b +c,d @@
    if (line.startsWith('@@')) {
      currentFile.lines.push({
        type: 'hunk',
        content: line,
      });
      continue;
    }

    // Added lines
    if (line.startsWith('+')) {
      currentFile.lines.push({
        type: 'added',
        content: line.slice(1),
      });
      continue;
    }

    // Removed lines
    if (line.startsWith('-')) {
      currentFile.lines.push({
        type: 'removed',
        content: line.slice(1),
      });
      continue;
    }

    // Context lines (space prefix or empty in diff context)
    if (line.startsWith(' ') || (line === '' && i > 0 && i < lines.length - 1)) {
      currentFile.lines.push({
        type: 'context',
        content: line.startsWith(' ') ? line.slice(1) : '',
      });
      continue;
    }

    // No newline at end of file marker
    if (line.startsWith('\\ No newline')) {
      currentFile.lines.push({
        type: 'context',
        content: line,
      });
    }
  }

  return files;
}

// --- File ID from path (for scroll target) ---
function filePathToId(path: string): string {
  return `diff-file-${path.replace(/[^a-zA-Z0-9]/g, '-')}`;
}

// --- Sub-components ---

function FileNavList({
  files,
  onFileClick,
}: {
  files: FileDiff[];
  onFileClick: (id: string) => void;
}): JSX.Element {
  return (
    <div className="flex flex-wrap gap-1.5 mb-3">
      {files.map((file) => {
        const id = filePathToId(file.filePath);
        const additions = file.lines.filter((l) => l.type === 'added').length;
        const deletions = file.lines.filter((l) => l.type === 'removed').length;
        return (
          <button
            key={file.filePath}
            onClick={() => onFileClick(id)}
            className="inline-flex items-center gap-1.5 px-2 py-1 rounded text-xs font-mono bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors border border-gray-200"
            title={file.filePath}
          >
            <span className="truncate max-w-[200px]">
              {file.filePath.split('/').pop()}
            </span>
            {additions > 0 && (
              <span className="text-green-600">+{additions}</span>
            )}
            {deletions > 0 && (
              <span className="text-red-500">-{deletions}</span>
            )}
          </button>
        );
      })}
    </div>
  );
}

function DiffLineRow({ line }: { line: DiffLine }): JSX.Element {
  let bgClass = '';
  let textClass = '';
  let prefix = '';

  switch (line.type) {
    case 'added':
      bgClass = 'bg-green-50';
      textClass = 'text-green-800';
      prefix = '+';
      break;
    case 'removed':
      bgClass = 'bg-red-50';
      textClass = 'text-red-800';
      prefix = '-';
      break;
    case 'context':
      bgClass = '';
      textClass = 'text-gray-700';
      prefix = ' ';
      break;
    case 'hunk':
      bgClass = 'bg-blue-50';
      textClass = 'text-blue-600';
      prefix = '';
      break;
    case 'fileHeader':
      bgClass = 'bg-gray-100';
      textClass = 'text-gray-600';
      prefix = '';
      break;
  }

  return (
    <div className={`flex font-mono text-xs leading-5 ${bgClass} ${textClass}`}>
      <span className="w-6 flex-shrink-0 text-right pr-1 select-none opacity-40">
        {prefix}
      </span>
      <span className="whitespace-pre-wrap break-all">{line.content}</span>
    </div>
  );
}

function FileDiffBlock({ file }: { file: FileDiff }): JSX.Element {
  const id = filePathToId(file.filePath);
  return (
    <div id={id} className="mb-4">
      <div className="sticky top-0 z-10 bg-gray-800 text-gray-100 px-3 py-1.5 text-xs font-mono rounded-t-md truncate">
        {file.filePath}
      </div>
      <div className="border border-t-0 border-gray-200 rounded-b-md overflow-x-auto">
        {file.lines.map((line, idx) => (
          <DiffLineRow key={idx} line={line} />
        ))}
      </div>
    </div>
  );
}

// --- Main Component ---

function DiffViewer({ diffText }: { diffText: string }): JSX.Element {
  const files = useMemo(() => parseUnifiedDiff(diffText), [diffText]);

  const handleFileClick = useCallback((id: string) => {
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  }, []);

  if (!diffText.trim()) {
    return (
      <div className="py-6 text-center text-sm text-gray-400">
        暂无 Diff 数据
      </div>
    );
  }

  if (files.length === 0) {
    return (
      <div className="py-6 text-center text-sm text-gray-400">
        无法解析 Diff 内容
      </div>
    );
  }

  return (
    <div>
      {/* File navigation */}
      <FileNavList files={files} onFileClick={handleFileClick} />

      {/* Diff blocks */}
      <div className="max-h-[600px] overflow-y-auto border border-gray-200 rounded-lg p-2 bg-white">
        {files.map((file) => (
          <FileDiffBlock key={file.filePath} file={file} />
        ))}
      </div>
    </div>
  );
}

export default DiffViewer;
