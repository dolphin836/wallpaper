interface Props {
  className?: string;
  height?: string;
  blurLevels?: number[];
}

export default function ProgressiveBlur({
  className = '',
  height = '30%',
  blurLevels = [0.5, 1, 2, 4, 8, 16, 32, 64],
}: Props) {
  const midLayers = Array(blurLevels.length - 2).fill(null);

  return (
    <div
      className={`pointer-events-none absolute inset-x-0 bottom-0 z-10 ${className}`}
      style={{ height }}
    >
      <div
        className="absolute inset-0"
        style={{
          zIndex: 1,
          backdropFilter: `blur(${blurLevels[0]}px)`,
          WebkitBackdropFilter: `blur(${blurLevels[0]}px)`,
          maskImage: `linear-gradient(to bottom, rgba(0,0,0,0) 0%, rgba(0,0,0,1) 12.5%, rgba(0,0,0,1) 25%, rgba(0,0,0,0) 37.5%)`,
          WebkitMaskImage: `linear-gradient(to bottom, rgba(0,0,0,0) 0%, rgba(0,0,0,1) 12.5%, rgba(0,0,0,1) 25%, rgba(0,0,0,0) 37.5%)`,
        }}
      />

      {midLayers.map((_, i) => {
        const blurIdx = i + 1;
        const start = blurIdx * 12.5;
        const mid = (blurIdx + 1) * 12.5;
        const end = (blurIdx + 2) * 12.5;
        const mask = `linear-gradient(to bottom, rgba(0,0,0,0) ${start}%, rgba(0,0,0,1) ${mid}%, rgba(0,0,0,1) ${end}%, rgba(0,0,0,0) ${end + 12.5}%)`;
        return (
          <div
            key={i}
            className="absolute inset-0"
            style={{
              zIndex: i + 2,
              backdropFilter: `blur(${blurLevels[blurIdx]}px)`,
              WebkitBackdropFilter: `blur(${blurLevels[blurIdx]}px)`,
              maskImage: mask,
              WebkitMaskImage: mask,
            }}
          />
        );
      })}

      <div
        className="absolute inset-0"
        style={{
          zIndex: blurLevels.length,
          backdropFilter: `blur(${blurLevels[blurLevels.length - 1]}px)`,
          WebkitBackdropFilter: `blur(${blurLevels[blurLevels.length - 1]}px)`,
          maskImage: `linear-gradient(to bottom, rgba(0,0,0,0) 87.5%, rgba(0,0,0,1) 100%)`,
          WebkitMaskImage: `linear-gradient(to bottom, rgba(0,0,0,0) 87.5%, rgba(0,0,0,1) 100%)`,
        }}
      />
    </div>
  );
}
