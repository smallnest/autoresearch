import type { JSX } from 'react';

interface MarkdownRendererProps {
  content: string;
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
  const trimmed = url.trim();
  if (
    trimmed.startsWith('http://') ||
    trimmed.startsWith('https://') ||
    trimmed.startsWith('mailto:')
  ) {
    return trimmed;
  }
  return null;
}

function renderInline(markdown: string): string {
  let html = escapeHtml(markdown);

  html = html.replace(
    /`([^`]+)`/g,
    (_, code: string) => `<code>${escapeHtml(code)}</code>`
  );

  html = html.replace(
    /\[([^\]]+)\]\(([^)]+)\)/g,
    (_, text: string, href: string) => {
      const safeUrl = sanitizeUrl(href);
      if (!safeUrl) {
        return escapeHtml(text);
      }

      return `<a href="${escapeHtml(safeUrl)}" target="_blank" rel="noreferrer">${escapeHtml(
        text
      )}</a>`;
    }
  );

  html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');

  return html;
}

function highlightCode(code: string, language: string): string {
  const escaped = escapeHtml(code);
  const withStrings = escaped.replace(
    /(&quot;.*?&quot;|&#39;.*?&#39;|`.*?`)/g,
    '<span class="md-token-string">$1</span>'
  );
  const withKeywords =
    language === 'ts' ||
    language === 'tsx' ||
    language === 'js' ||
    language === 'jsx' ||
    language === 'json'
      ? withStrings.replace(
          /\b(const|let|var|function|return|if|else|await|async|import|export|from|type|interface|new|throw|try|catch)\b/g,
          '<span class="md-token-keyword">$1</span>'
        )
      : withStrings;

  return withKeywords.replace(
    /\b(\d+)\b/g,
    '<span class="md-token-number">$1</span>'
  );
}

function renderMarkdown(markdown: string): string {
  if (!markdown.trim()) {
    return '';
  }

  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  const blocks: string[] = [];
  let index = 0;

  while (index < lines.length) {
    const line = lines[index];
    const trimmed = line.trim();

    if (!trimmed) {
      index += 1;
      continue;
    }

    if (trimmed.startsWith('```')) {
      const language = trimmed.slice(3).trim().toLowerCase();
      const codeLines: string[] = [];
      index += 1;
      while (index < lines.length && !lines[index].trim().startsWith('```')) {
        codeLines.push(lines[index]);
        index += 1;
      }
      index += 1;

      blocks.push(
        `<pre><code class="language-${escapeHtml(language || 'text')}">${highlightCode(
          codeLines.join('\n'),
          language
        )}</code></pre>`
      );
      continue;
    }

    const headingMatch = trimmed.match(/^(#{1,6})\s+(.*)$/);
    if (headingMatch) {
      const level = headingMatch[1].length;
      blocks.push(`<h${level}>${renderInline(headingMatch[2])}</h${level}>`);
      index += 1;
      continue;
    }

    if (trimmed.startsWith('>')) {
      const quoteLines: string[] = [];
      while (index < lines.length && lines[index].trim().startsWith('>')) {
        quoteLines.push(lines[index].trim().replace(/^>\s?/, ''));
        index += 1;
      }
      blocks.push(`<blockquote>${renderInline(quoteLines.join(' '))}</blockquote>`);
      continue;
    }

    const unorderedMatch = trimmed.match(/^[-*]\s+(.*)$/);
    if (unorderedMatch) {
      const items: string[] = [];
      while (index < lines.length) {
        const current = lines[index].trim().match(/^[-*]\s+(.*)$/);
        if (!current) {
          break;
        }
        items.push(`<li>${renderInline(current[1])}</li>`);
        index += 1;
      }
      blocks.push(`<ul>${items.join('')}</ul>`);
      continue;
    }

    const orderedMatch = trimmed.match(/^\d+\.\s+(.*)$/);
    if (orderedMatch) {
      const items: string[] = [];
      while (index < lines.length) {
        const current = lines[index].trim().match(/^\d+\.\s+(.*)$/);
        if (!current) {
          break;
        }
        items.push(`<li>${renderInline(current[1])}</li>`);
        index += 1;
      }
      blocks.push(`<ol>${items.join('')}</ol>`);
      continue;
    }

    const paragraphLines: string[] = [];
    while (index < lines.length && lines[index].trim()) {
      paragraphLines.push(lines[index].trim());
      index += 1;
    }
    blocks.push(`<p>${renderInline(paragraphLines.join(' '))}</p>`);
  }

  return blocks.join('');
}

function MarkdownRenderer({
  content,
  className,
}: MarkdownRendererProps): JSX.Element {
  if (!content.trim()) {
    return (
      <p className={className ? `text-gray-500 ${className}` : 'text-gray-500'}>
        暂无内容
      </p>
    );
  }

  return (
    <div
      className={className}
      dangerouslySetInnerHTML={{ __html: renderMarkdown(content) }}
    />
  );
}

export default MarkdownRenderer;
