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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" onClick={onClose}>
      <div
        className="bg-white dark:bg-gray-800 rounded-2xl shadow-xl w-full max-w-md mx-4 overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-5 border-b border-gray-100 dark:border-gray-700">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">{guide.title}</h3>
          <button
            onClick={onClose}
            className="p-1.5 text-gray-400 hover:text-gray-600 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700"
          >
            <AiOutlineClose size={20} />
          </button>
        </div>

        <div className="p-5 space-y-3">
          {guide.steps.map((step, i) => (
            <div key={i} className="flex gap-3">
              <div className="shrink-0 w-7 h-7 rounded-full bg-indigo-100 dark:bg-indigo-900/30 text-indigo-600 dark:text-indigo-400 flex items-center justify-center text-sm font-semibold">
                {i + 1}
              </div>
              <p className="text-sm text-gray-700 dark:text-gray-300 pt-1">{step}</p>
            </div>
          ))}
        </div>

        <div className="px-5 pb-5">
          <button
            onClick={onClose}
            className="w-full py-2.5 text-sm font-medium text-gray-600 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 rounded-xl transition-colors"
          >
            Got it
          </button>
        </div>
      </div>
    </div>
  );
}
