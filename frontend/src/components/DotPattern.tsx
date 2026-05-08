import { useId } from 'react';

interface Props {
  width?: number;
  height?: number;
  cr?: number;
  className?: string;
}

export default function DotPattern({
  width = 20,
  height = 20,
  cr = 1,
  className = '',
}: Props) {
  const id = useId();

  return (
    <svg
      aria-hidden="true"
      className={`pointer-events-none absolute inset-0 h-full w-full ${className}`}
    >
      <defs>
        <pattern
          id={id}
          width={width}
          height={height}
          patternUnits="userSpaceOnUse"
        >
          <circle cx={width / 2} cy={height / 2} r={cr} fill="currentColor" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill={`url(#${id})`} />
    </svg>
  );
}
