import { forwardRef } from 'react';
import type { InputHTMLAttributes, ReactNode } from 'react';

interface Props extends Omit<InputHTMLAttributes<HTMLInputElement>, 'children'> {
  /** Mono caps label above the input (left-aligned). */
  label: string;
  /** Optional sub-action on the right of the label row (e.g. "Forgot?"). */
  sub?: ReactNode;
  /** Helper text under the box. Replaced by `error` when present. */
  help?: ReactNode;
  /** Error text under the box (red). Also paints the border red. */
  error?: string;
  /** Optional icon glyph rendered inside the box on the left. */
  icon?: ReactNode;
}

/**
 * Editorial form field — mono caps label on top, paper input box with a
 * 4px square radius and a hair border (red when error), and a small mono
 * helper / error line underneath. Designed to compose vertically inside
 * the auth cards but works anywhere a single labeled input is needed.
 */
const Field = forwardRef<HTMLInputElement, Props>(function Field(
  { label, sub, help, error, icon, className = '', ...inputProps },
  ref,
) {
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-baseline justify-between mono text-[10px] tracking-[0.14em] uppercase text-muted">
        <label htmlFor={inputProps.id}>{label}</label>
        {sub && <span className="text-ink-2 normal-case tracking-normal">{sub}</span>}
      </div>
      <div
        className={`flex items-center gap-2.5 px-3.5 py-3 bg-paper rounded ${className}`}
        style={{ border: `1px solid ${error ? '#b1311f' : 'var(--color-hair)'}` }}
      >
        {icon && <span className="text-ink-2 flex-shrink-0">{icon}</span>}
        <input
          ref={ref}
          {...inputProps}
          className="flex-1 border-0 outline-none bg-transparent text-[14px] text-ink placeholder:text-muted"
        />
      </div>
      {(help || error) && (
        <div
          className="mono text-[10px] tracking-[0.06em]"
          style={{ color: error ? '#b1311f' : 'var(--color-muted)' }}
        >
          {error || help}
        </div>
      )}
    </div>
  );
});

export default Field;
