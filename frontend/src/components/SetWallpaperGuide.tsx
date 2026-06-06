import { useMemo } from 'react';
import { AiOutlineClose } from 'react-icons/ai';

interface Props {
  onClose: () => void;
}

type OS = 'ios' | 'android' | 'macos' | 'windows' | 'unknown';

function detectOS(): OS {
  const ua = navigator.userAgent;
  if (/iPhone|iPad|iPod/.test(ua)) return 'ios';
  if (/Android/.test(ua)) return 'android';
  if (/Mac/.test(ua)) return 'macos';
  if (/Win/.test(ua)) return 'windows';
  return 'unknown';
}

const guides: Record<OS, { title: string; steps: string[] }> = {
  ios: {
    title: 'Set as Wallpaper on iPhone / iPad',
    steps: [
      'Open the Photos app and find the downloaded image',
      'Tap the Share button (square with arrow)',
      'Scroll down and tap "Use as Wallpaper"',
      'Adjust position and choose "Set"',
      'Select Lock Screen, Home Screen, or Both',
    ],
  },
  android: {
    title: 'Set as Wallpaper on Android',
    steps: [
      'Open the downloaded image in your Gallery or Files app',
      'Tap the three-dot menu or "More" button',
      'Select "Set as wallpaper" or "Use as"',
      'Choose Home screen, Lock screen, or Both',
      'Adjust crop area and confirm',
    ],
  },
  macos: {
    title: 'Set as Wallpaper on macOS',
    steps: [
      'Open System Settings (Apple menu > System Settings)',
      'Click "Wallpaper" in the sidebar',
      'Click "Add Photo" or drag the downloaded image into the window',
      'Alternatively: right-click the image in Finder > "Set Desktop Picture"',
    ],
  },
  windows: {
    title: 'Set as Wallpaper on Windows',
    steps: [
      'Find the downloaded image in File Explorer',
      'Right-click the image file',
      'Select "Set as desktop background"',
      'Or go to Settings > Personalization > Background',
    ],
  },
  unknown: {
    title: 'Set as Wallpaper',
    steps: [
      'Open the downloaded image with your system image viewer',
      'Look for a "Set as wallpaper" or "Set as desktop background" option',
      'Alternatively, go to your system display/wallpaper settings and browse to the file',
    ],
  },
};

export default function SetWallpaperGuide({ onClose }: Props) {
  const os = useMemo(() => detectOS(), []);
  const guide = guides[os];

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 backdrop-blur-[2px]"
      style={{ background: 'rgba(15,12,8,0.55)' }}
      onClick={onClose}
    >
      <div
        className="bg-paper text-ink rounded-[20px] shadow-[0_24px_70px_rgba(0,0,0,0.28)] border border-hair w-full max-w-[420px] overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-4 p-5 border-b border-hair">
          <div>
            <div className="kicker text-muted">Local setup</div>
            <h3 className="display text-[22px] leading-none mt-2">{guide.title}</h3>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="w-8 h-8 rounded-full border border-hair text-ink-2 hover:text-ink hover:bg-paper-2 inline-flex items-center justify-center transition-colors"
          >
            <AiOutlineClose size={13} />
          </button>
        </div>

        <div className="p-5 space-y-3.5">
          {guide.steps.map((step, i) => (
            <div key={i} className="flex gap-3">
              <div className="shrink-0 w-7 h-7 rounded-full bg-accent-soft text-accent-ink border border-accent/20 flex items-center justify-center text-[12px] font-semibold tabular-nums">
                {i + 1}
              </div>
              <p className="text-[13px] leading-relaxed text-ink-2 pt-0.5">{step}</p>
            </div>
          ))}
        </div>

        <div className="px-5 pb-5">
          <button
            onClick={onClose}
            className="w-full py-2.5 text-[13px] font-semibold text-paper bg-ink hover:bg-ink-2 rounded-full transition-colors"
          >
            Got it
          </button>
        </div>
      </div>
    </div>
  );
}
