import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';

interface Props {
  title?: string;
  message: string;
  actionLabel?: string;
  actionHref?: string;
  onAction?: () => void;
  className?: string;
}

export default function EmptyState({
  title,
  message,
  actionLabel,
  actionHref,
  onAction,
  className = '',
}: Props) {
  const headline = title ?? message;
  const body = title ? message : undefined;
  const action: ReactNode = actionLabel && actionHref ? (
    <Link to={actionHref} className="empty-state__action">
      {actionLabel}
    </Link>
  ) : actionLabel && onAction ? (
    <button type="button" onClick={onAction} className="empty-state__action">
      {actionLabel}
    </button>
  ) : null;

  return (
    <div className={`empty-state ${className}`}>
      <div className="empty-state__icon" aria-hidden>
        <svg width="24" height="24" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
      </svg>
      </div>
      <h2 className="empty-state__title">{headline}</h2>
      {body && <p className="empty-state__message">{body}</p>}
      {action}
    </div>
  );
}
