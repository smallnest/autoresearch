interface ReactMarkdownProps {
  children?: string | null;
  className?: string;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function sanitizeUrl(url: string): string | null {
  try {
    const parsed = new URL(url, 'https://example.com');
    if (['http:', 'https:', 'mailto:'].includes(parsed.protocol)) {
      return parsed.toString();
    }
  } catch {
    return null;
  }

  return null;
}

function highlightCode(code: string, language: string): string {
  const escaped = escapeHtml(code);
  const normalizedLanguage = language.toLowerCase();
  const keywordSets: Record<string, string[]> = {
    bash: ['if', 'then', 'else', 'fi', 'for', 'do', 'done', 'echo', 'export'],
    javascript: ['await', 'const', 'function', 'if', 'import', 'let', 'return'],
    js: ['await', 'const', 'function', 'if', 'import', 'let', 'return'],
    json: ['false', 'null', 'true'],
    rust: ['fn', 'if', 'impl', 'let', 'match', 'pub', 'return', 'struct'],
    sql: ['and', 'asc', 'desc', 'from', 'limit', 'order', 'select', 'where'],
    ts: ['await', 'const', 'export', 'function', 'if', 'import', 'interface', 'return'],
    tsx: ['await', 'const', 'export', 'function', 'if', 'import', 'interface', 'return'],
    typescript: ['await', 'const', 'export', 'function', 'if', 'import', 'interface', 'return'],
  };

  const keywords = keywordSets[normalizedLanguage] ?? [];
  let html = escaped;

  if (keywords.length > 0) {
    const keywordPattern = new RegExp(`\\b(${keywords.join('|')})\\b`, 'gi');
    html = html.replace(
      keywordPattern,
      '<span class="md-token-keyword">$1</span>'
    );
  }

  html = html.replace(
    /(&quot;.*?&quot;|&#39;.*?&#39;)/g,
    '<span class="md-token-string">$1</span>'
  );
  html = html.replace(
    /\b(\d+(?:\.\d+)?)\b/g,
    '<span class="md-token-number">$1</span>'
  );

  return html;
}

function parseInline(markdown: string): string {
  const codeTokens: string[] = [];
  let working = markdown.replace(/`([^`]+)`/g, (_, code: string) => {
    const token = `@@CODE_${codeTokens.length}@@`;
    codeTokens.push(`<code>${escapeHtml(code)}</code>`);
    return token;
  });

  working = escapeHtml(working);

  working = working.replace(
    /\[([^\]]+)\]\(([^)]+)\)/g,
    (_, label: string, url: string) => {
      const safeUrl = sanitizeUrl(url.trim());
      if (!safeUrl) {
        return escapeHtml(label);
      }

      return `<a href="${escapeHtml(safeUrl)}" target="_blank" rel="noreferrer">${escapeHtml(label)}</a>`;
    }
  );

  working = working.replace(
    /(^|[\s(])(https?:\/\/[^\s<]+)/g,
    (_, prefix: string, url: string) => {
      const safeUrl = sanitizeUrl(url);
      if (!safeUrl) {
        return `${prefix}${escapeHtml(url)}`;
      }

      return `${prefix}<a href="${escapeHtml(safeUrl)}" target="_blank" rel="noreferrer">${escapeHtml(url)}</a>`;
    }
  );

  working = working.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  working = working.replace(/\*(.+?)\*/g, '<em>$1</em>');

  codeTokens.forEach((token, index) => {
    working = working.replace(`@@CODE_${index}@@`, token);
  });

  return working;
}

function parseParagraph(lines: string[]): string {
  return `<p>${parseInline(lines.join(' ')).replace(/\n/g, '<br />')}</p>`;
}

function renderMarkdown(markdown: string): string {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  const blocks: string[] = [];
  let index = 0;

  while (index < lines.length) {
    const line = lines[index];

    if (!line.trim()) {
      index += 1;
      continue;
    }

    const fenceMatch = line.match(/^```([\w-]*)\s*$/);
    if (fenceMatch) {
      index += 1;
      const codeLines: string[] = [];
      while (index < lines.length && !lines[index].startsWith('```')) {
        codeLines.push(lines[index]);
        index += 1;
      }
      index += 1;

      const language = fenceMatch[1] || 'text';
      blocks.push(
        `<pre><code class="language-${escapeHtml(language)}">${highlightCode(
          codeLines.join('\n'),
          language
        )}</code></pre>`
      );
      continue;
    }

    const headingMatch = line.match(/^(#{1,6})\s+(.+)$/);
    if (headingMatch) {
      const level = headingMatch[1].length;
      blocks.push(`<h${level}>${parseInline(headingMatch[2])}</h${level}>`);
      index += 1;
      continue;
    }

    if (line.startsWith('> ')) {
      const quoteLines: string[] = [];
      while (index < lines.length && lines[index].startsWith('> ')) {
        quoteLines.push(lines[index].slice(2));
        index += 1;
      }
      blocks.push(`<blockquote>${parseParagraph(quoteLines)}</blockquote>`);
      continue;
    }

    if (/^[-*+]\s+/.test(line)) {
      const items: string[] = [];
      while (index < lines.length && /^[-*+]\s+/.test(lines[index])) {
        items.push(`<li>${parseInline(lines[index].replace(/^[-*+]\s+/, ''))}</li>`);
        index += 1;
      }
      blocks.push(`<ul>${items.join('')}</ul>`);
      continue;
    }

    if (/^\d+\.\s+/.test(line)) {
      const items: string[] = [];
      while (index < lines.length && /^\d+\.\s+/.test(lines[index])) {
        items.push(
          `<li>${parseInline(lines[index].replace(/^\d+\.\s+/, ''))}</li>`
        );
        index += 1;
      }
      blocks.push(`<ol>${items.join('')}</ol>`);
      continue;
    }

    const paragraphLines: string[] = [];
    while (
      index < lines.length &&
      lines[index].trim() &&
      !lines[index].startsWith('```') &&
      !lines[index].startsWith('> ') &&
      !/^[-*+]\s+/.test(lines[index]) &&
      !/^\d+\.\s+/.test(lines[index]) &&
      !/^(#{1,6})\s+/.test(lines[index])
    ) {
      paragraphLines.push(lines[index]);
      index += 1;
    }

    blocks.push(parseParagraph(paragraphLines));
  }

  return blocks.join('');
}

export default function ReactMarkdown({
  children,
  className,
}: ReactMarkdownProps): JSX.Element {
  return (
    <div
      className={className}
      dangerouslySetInnerHTML={{ __html: renderMarkdown(children ?? '') }}
    />
  );
}
