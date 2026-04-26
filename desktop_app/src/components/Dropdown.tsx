import { useEffect, useRef, useState } from 'react';

interface DropdownOption {
  value: string;
  label: string;
}

interface DropdownProps {
  value: string;
  options: DropdownOption[];
  onChange: (value: string) => void;
  ariaLabel?: string;
  variant?: 'light' | 'dark';
}

export default function Dropdown({ value, options, onChange, ariaLabel, variant = 'light' }: DropdownProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const selected = options.find((o) => o.value === value);
  const displayLabel = selected?.label ?? value;

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    if (open) document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [open]);

  const isLight = variant === 'light';

  return (
    <div ref={ref} className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-label={ariaLabel}
        className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
          isLight
            ? 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            : 'bg-gray-800 text-gray-200 hover:bg-gray-700'
        } ${open ? (isLight ? 'bg-gray-200' : 'bg-gray-700') : ''}`}
      >
        {displayLabel}
        <svg
          className={`w-3.5 h-3.5 transition-transform ${open ? 'rotate-180' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {open && (
        <div
          className={`absolute z-50 mt-1 py-1 rounded-lg shadow-lg border min-w-[120px] ${
            isLight
              ? 'bg-white border-gray-200'
              : 'bg-gray-800 border-gray-700'
          }`}
        >
          {options.map((opt) => (
            <button
              key={opt.value}
              type="button"
              onClick={() => {
                onChange(opt.value);
                setOpen(false);
              }}
              className={`w-full text-left px-3 py-1.5 text-sm transition-colors ${
                opt.value === value
                  ? isLight
                    ? 'bg-blue-50 text-blue-700 font-medium'
                    : 'bg-blue-900/40 text-blue-300 font-medium'
                  : isLight
                    ? 'text-gray-700 hover:bg-gray-50'
                    : 'text-gray-300 hover:bg-gray-700'
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
