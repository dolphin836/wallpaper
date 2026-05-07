import { useState, useMemo } from 'react';
import { AiOutlineWifi, AiOutlineClose } from 'react-icons/ai';
import {
  MdBatteryFull,
  MdSignalCellular4Bar,
  MdLockOutline,
  MdHome,
  MdBrightness2,
  MdWallpaper,
  MdDesktopWindows,
  MdPhoneIphone,
} from 'react-icons/md';

interface Props {
  imageUrl: string;
  platform: string;
  deviceName: string;
  deviceWidth: number;
  deviceHeight: number;
  onClose: () => void;
}

type MobileScene = 'lock' | 'home' | 'aod' | 'clean';
type DesktopScene = 'desktop' | 'clean';

function getNow() {
  const now = new Date();
  const time = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
  const weekday = now.toLocaleDateString('en-US', { weekday: 'long' });
  const date = now.toLocaleDateString('en-US', { month: 'long', day: 'numeric' });
  return { time, weekday, date };
}

// --------------- Scene overlays ---------------

function StatusBar({ width, height }: { width: number; height: number }) {
  const { time } = getNow();
  const fs = width * 0.032;
  const iconSz = width * 0.03;
  return (
    <div
      className="absolute top-0 left-0 right-0 z-10 flex items-center justify-between text-white/90 font-semibold"
      style={{ padding: `${height * 0.012}px ${width * 0.07}px 0`, fontSize: fs }}
    >
      <span style={{ textShadow: '0 1px 3px rgba(0,0,0,0.5)' }}>{time}</span>
      <div className="flex items-center" style={{ gap: iconSz * 0.4 }}>
        <MdSignalCellular4Bar style={{ width: iconSz, height: iconSz, filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.4))' }} />
        <AiOutlineWifi style={{ width: iconSz, height: iconSz, filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.4))' }} />
        <MdBatteryFull style={{ width: iconSz * 1.15, height: iconSz * 1.15, filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.4))' }} />
      </div>
    </div>
  );
}

function LockOverlay({ width, height }: { width: number; height: number }) {
  const { time, weekday, date } = getNow();
  return (
    <>
      <StatusBar width={width} height={height} />
      <div className="absolute inset-0 z-10 flex flex-col items-center text-white" style={{ paddingTop: height * 0.13 }}>
        <div className="leading-none tracking-tight" style={{ fontSize: width * 0.2, fontWeight: 200, textShadow: '0 2px 12px rgba(0,0,0,0.4)' }}>
          {time}
        </div>
        <div style={{ fontSize: width * 0.038, marginTop: height * 0.006, opacity: 0.85, textShadow: '0 1px 4px rgba(0,0,0,0.3)' }}>
          {weekday}, {date}
        </div>
        <div className="mt-auto flex items-center justify-center gap-1 opacity-50" style={{ marginBottom: height * 0.06, fontSize: width * 0.028 }}>
          <MdLockOutline style={{ width: width * 0.025, height: width * 0.025 }} />
          <span>Swipe up to unlock</span>
        </div>
      </div>
      <div className="absolute left-1/2 -translate-x-1/2 z-10 bg-white/60 rounded-full"
        style={{ bottom: height * 0.01, width: width * 0.35, height: width * 0.012 }}
      />
    </>
  );
}

function AppIcon({ x, y, size, color }: { x: number; y: number; size: number; color: string }) {
  return (
    <div className="absolute rounded-[22%] shadow-sm" style={{
      left: x, top: y, width: size, height: size,
      background: color,
      boxShadow: '0 1px 3px rgba(0,0,0,0.2), inset 0 1px 0 rgba(255,255,255,0.15)',
    }}>
      <div className="w-full h-full rounded-[22%] bg-gradient-to-b from-white/20 to-transparent" />
    </div>
  );
}

function HomeOverlay({ width, height }: { width: number; height: number }) {
  const iconSize = width * 0.145;
  const gap = width * 0.06;
  const cols = 4;
  const gridW = cols * iconSize + (cols - 1) * gap;
  const startX = (width - gridW) / 2;
  const startY = height * 0.18;
  const rowGap = iconSize + gap * 1.2;
  const colors = [
    '#3b82f6', '#ef4444', '#10b981', '#f59e0b',
    '#8b5cf6', '#ec4899', '#06b6d4', '#f97316',
    '#6366f1', '#14b8a6', '#e11d48', '#84cc16',
    '#0ea5e9', '#d946ef', '#f43f5e', '#22c55e',
  ];
  const icons = [];
  for (let row = 0; row < 4; row++) {
    for (let col = 0; col < cols; col++) {
      const idx = row * cols + col;
      icons.push(
        <AppIcon
          key={idx}
          x={startX + col * (iconSize + gap)}
          y={startY + row * rowGap}
          size={iconSize}
          color={colors[idx % colors.length]}
        />
      );
    }
  }

  const dockH = height * 0.1;
  const dockIconSize = iconSize * 0.95;
  const dockGap = (width * 0.88 - 4 * dockIconSize) / 3;
  const dockStartX = width * 0.06;
  const dockColors = ['#34d399', '#60a5fa', '#f472b6', '#a78bfa'];

  return (
    <>
      <StatusBar width={width} height={height} />
      <div className="absolute inset-0 z-10">{icons}</div>
      <div className="absolute bottom-0 left-0 right-0 z-10" style={{ height: dockH + height * 0.02 }}>
        <div className="absolute inset-x-0 bottom-0 bg-white/15 backdrop-blur-md border-t border-white/10"
          style={{ height: dockH, borderRadius: `${width * 0.06}px ${width * 0.06}px 0 0` }}
        >
          {dockColors.map((c, i) => (
            <div key={i} className="absolute rounded-[22%]" style={{
              left: dockStartX + i * (dockIconSize + dockGap),
              top: (dockH - dockIconSize) / 2,
              width: dockIconSize, height: dockIconSize,
              background: c,
              boxShadow: '0 1px 3px rgba(0,0,0,0.2), inset 0 1px 0 rgba(255,255,255,0.2)',
            }}>
              <div className="w-full h-full rounded-[22%] bg-gradient-to-b from-white/20 to-transparent" />
            </div>
          ))}
        </div>
        <div className="absolute left-1/2 -translate-x-1/2 bg-white/60 rounded-full"
          style={{ bottom: height * 0.008, width: width * 0.35, height: width * 0.012 }}
        />
      </div>
    </>
  );
}

function AODOverlay({ width, height }: { width: number; height: number }) {
  const { time, weekday, date } = getNow();
  return (
    <>
      <div className="absolute inset-0 z-10 bg-black/75" />
      <div className="absolute inset-0 z-20 flex flex-col items-center justify-center text-white">
        <div style={{ fontSize: width * 0.22, fontWeight: 100, letterSpacing: width * 0.01, opacity: 0.9 }}>
          {time}
        </div>
        <div style={{ fontSize: width * 0.035, marginTop: height * 0.005, opacity: 0.5 }}>
          {weekday}, {date}
        </div>
        <div className="flex items-center gap-3 mt-4" style={{ opacity: 0.3 }}>
          <MdBatteryFull style={{ width: width * 0.04, height: width * 0.04 }} />
          <span style={{ fontSize: width * 0.03 }}>85%</span>
        </div>
      </div>
    </>
  );
}

function DesktopOverlay({ width, height }: { width: number; height: number }) {
  const iconSz = Math.min(width * 0.04, 48);
  const labelFs = Math.max(iconSz * 0.28, 8);

  const desktopIcons = [
    { label: 'Documents', color: '#3b82f6' },
    { label: 'Photos', color: '#10b981' },
    { label: 'Music', color: '#f59e0b' },
  ];

  const dockH = height * 0.055;
  const dockIconSz = dockH * 0.7;
  const dockColors = ['#3b82f6', '#10b981', '#8b5cf6', '#ef4444', '#f59e0b', '#ec4899', '#06b6d4'];

  return (
    <>
      {/* Desktop icons top-left */}
      <div className="absolute z-10" style={{ top: height * 0.03, left: width * 0.02 }}>
        {desktopIcons.map((ic, i) => (
          <div key={i} className="flex flex-col items-center mb-1" style={{ marginBottom: iconSz * 0.3 }}>
            <div className="rounded-lg shadow-sm" style={{
              width: iconSz, height: iconSz, background: ic.color,
              boxShadow: '0 2px 6px rgba(0,0,0,0.3)',
            }}>
              <div className="w-full h-full rounded-lg bg-gradient-to-b from-white/20 to-transparent" />
            </div>
            <span className="text-white/80 text-center mt-0.5 drop-shadow-md" style={{ fontSize: labelFs, maxWidth: iconSz * 1.6 }}>
              {ic.label}
            </span>
          </div>
        ))}
      </div>
      {/* macOS-style Dock */}
      <div className="absolute bottom-0 left-0 right-0 z-10 flex justify-center" style={{ paddingBottom: height * 0.012 }}>
        <div className="flex items-center bg-white/15 backdrop-blur-xl border border-white/20 shadow-2xl"
          style={{
            padding: `${dockH * 0.15}px ${dockH * 0.2}px`,
            borderRadius: dockH * 0.35,
            gap: dockIconSz * 0.25,
          }}
        >
          {dockColors.map((c, i) => (
            <div key={i} className="rounded-[22%] flex-shrink-0" style={{
              width: dockIconSz, height: dockIconSz, background: c,
              boxShadow: '0 2px 4px rgba(0,0,0,0.25)',
            }}>
              <div className="w-full h-full rounded-[22%] bg-gradient-to-b from-white/20 to-transparent" />
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

// --------------- Device frames ---------------

const BEZEL = 12;

function PhoneFrame({ imageUrl, width, height, scene }: { imageUrl: string; width: number; height: number; scene: MobileScene }) {
  const outerW = width + BEZEL * 2;
  const outerR = outerW * 0.1;
  const innerR = outerR - BEZEL;
  const sideKeyW = 3;
  const sideKeyColor = '#374151';

  return (
    <div style={{ width: outerW }} className="relative">
      {/* Side buttons */}
      <div className="absolute bg-gradient-to-r from-gray-600 to-gray-500 rounded-r-sm"
        style={{ left: -sideKeyW, top: outerW * 0.28, width: sideKeyW, height: outerW * 0.06 }}
        title="Silent switch"
      />
      <div className="absolute bg-gradient-to-r from-gray-600 to-gray-500 rounded-r-sm"
        style={{ left: -sideKeyW, top: outerW * 0.4, width: sideKeyW, height: outerW * 0.1 }}
        title="Volume up"
      />
      <div className="absolute bg-gradient-to-r from-gray-600 to-gray-500 rounded-r-sm"
        style={{ left: -sideKeyW, top: outerW * 0.54, width: sideKeyW, height: outerW * 0.1 }}
        title="Volume down"
      />
      <div className="absolute bg-gradient-to-l from-gray-600 to-gray-500 rounded-l-sm"
        style={{ right: -sideKeyW, top: outerW * 0.45, width: sideKeyW, height: outerW * 0.14 }}
        title="Power"
      />

      {/* Frame */}
      <div className="relative overflow-hidden shadow-2xl"
        style={{
          borderRadius: outerR,
          border: `${BEZEL}px solid ${sideKeyColor}`,
          background: 'linear-gradient(135deg, #1f2937 0%, #111827 100%)',
        }}
      >
        {/* Dynamic Island */}
        <div className="absolute left-1/2 -translate-x-1/2 z-30 bg-black rounded-full flex items-center justify-center"
          style={{
            top: height * 0.008,
            width: width * 0.26,
            height: width * 0.072,
            boxShadow: '0 0 0 1px rgba(255,255,255,0.05)',
          }}
        >
          <div className="bg-gray-800 rounded-full" style={{ width: width * 0.022, height: width * 0.022, marginRight: width * 0.06 }} />
        </div>

        {/* Screen with inner radius */}
        <div className="relative overflow-hidden" style={{ width, height, borderRadius: innerR }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
          {scene === 'lock' && <LockOverlay width={width} height={height} />}
          {scene === 'home' && <HomeOverlay width={width} height={height} />}
          {scene === 'aod' && <AODOverlay width={width} height={height} />}
        </div>
      </div>
    </div>
  );
}

function TabletFrame({ imageUrl, width, height, scene }: { imageUrl: string; width: number; height: number; scene: MobileScene }) {
  const bezel = 14;
  const outerW = width + bezel * 2;
  return (
    <div style={{ width: outerW }} className="relative">
      <div className="absolute bg-gradient-to-l from-gray-600 to-gray-500 rounded-l-sm"
        style={{ right: -3, top: outerW * 0.12, width: 3, height: outerW * 0.06 }}
      />
      <div className="relative overflow-hidden shadow-2xl"
        style={{
          borderRadius: 22,
          border: `${bezel}px solid #1f2937`,
          background: 'linear-gradient(135deg, #1f2937 0%, #111827 100%)',
        }}
      >
        <div className="relative overflow-hidden" style={{ width, height, borderRadius: 10 }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
          {scene === 'lock' && <LockOverlay width={width} height={height} />}
          {scene === 'home' && <HomeOverlay width={width} height={height} />}
          {scene === 'aod' && <AODOverlay width={width} height={height} />}
        </div>
      </div>
    </div>
  );
}

function LaptopFrame({ imageUrl, width, height, scene }: { imageUrl: string; width: number; height: number; scene: DesktopScene }) {
  const bezel = 10;
  const outerW = width + bezel * 2;
  const baseW = outerW * 1.06;
  const baseH = outerW * 0.025;
  const hingeH = 6;
  const trackpadW = outerW * 0.32;
  const trackpadH = baseH * 0.4;

  return (
    <div className="flex flex-col items-center">
      {/* Screen */}
      <div style={{ width: outerW }}>
        <div className="relative overflow-hidden shadow-2xl"
          style={{
            borderRadius: '10px 10px 0 0',
            border: `${bezel}px solid #374151`,
            borderBottom: `${bezel * 0.6}px solid #374151`,
            background: 'linear-gradient(180deg, #4b5563 0%, #374151 100%)',
          }}
        >
          {/* Camera */}
          <div className="absolute left-1/2 -translate-x-1/2 z-20 rounded-full"
            style={{ top: -(bezel * 0.3 + 3), width: 5, height: 5, background: '#1f2937', border: '1px solid #4b5563' }}
          />
          <div className="relative overflow-hidden" style={{ width, height, borderRadius: 2 }}>
            <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
            {scene === 'desktop' && <DesktopOverlay width={width} height={height} />}
          </div>
        </div>
      </div>
      {/* Hinge */}
      <div className="bg-gradient-to-b from-gray-500 to-gray-600" style={{ width: baseW, height: hingeH, borderRadius: '0 0 1px 1px' }} />
      {/* Keyboard base */}
      <div className="relative bg-gradient-to-b from-gray-500 via-gray-400 to-gray-500 shadow-lg"
        style={{ width: baseW, height: baseH, borderRadius: '0 0 8px 8px' }}
      >
        {/* Trackpad indent */}
        <div className="absolute left-1/2 -translate-x-1/2 rounded-sm bg-gray-400/50 border border-gray-500/30"
          style={{ bottom: baseH * 0.15, width: trackpadW, height: trackpadH, borderRadius: 3 }}
        />
      </div>
    </div>
  );
}

function DesktopFrame({ imageUrl, width, height, scene }: { imageUrl: string; width: number; height: number; scene: DesktopScene }) {
  const bezel = 12;
  const outerW = width + bezel * 2;
  const chinH = outerW * 0.028;
  const neckW = outerW * 0.07;
  const neckH = outerW * 0.045;
  const standW = outerW * 0.22;
  const standH = 5;

  return (
    <div className="flex flex-col items-center">
      {/* Monitor */}
      <div style={{ width: outerW }}>
        <div className="relative overflow-hidden shadow-2xl"
          style={{
            borderRadius: '10px 10px 0 0',
            border: `${bezel}px solid #374151`,
            borderBottom: 'none',
            background: 'linear-gradient(180deg, #4b5563 0%, #374151 100%)',
          }}
        >
          <div className="relative overflow-hidden" style={{ width, height, borderRadius: 2 }}>
            <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
            {scene === 'desktop' && <DesktopOverlay width={width} height={height} />}
          </div>
        </div>
        {/* Chin (iMac-style) */}
        <div className="bg-gradient-to-b from-gray-400 to-gray-500 flex items-center justify-center"
          style={{ width: outerW, height: chinH, borderRadius: '0 0 10px 10px' }}
        >
          <div className="rounded-full bg-gray-600/40" style={{ width: chinH * 0.3, height: chinH * 0.3 }} />
        </div>
      </div>
      {/* Neck */}
      <div className="bg-gradient-to-b from-gray-500 to-gray-400" style={{ width: neckW, height: neckH }} />
      {/* Stand base */}
      <div className="bg-gradient-to-b from-gray-400 to-gray-500 rounded-sm shadow-md"
        style={{ width: standW, height: standH, borderRadius: '2px 2px 4px 4px' }}
      />
    </div>
  );
}

// --------------- Scene switcher ---------------

const mobileScenes: { key: MobileScene; label: string; icon: typeof MdLockOutline }[] = [
  { key: 'lock', label: 'Lock Screen', icon: MdLockOutline },
  { key: 'home', label: 'Home', icon: MdHome },
  { key: 'aod', label: 'AOD', icon: MdBrightness2 },
  { key: 'clean', label: 'Clean', icon: MdWallpaper },
];

const desktopScenes: { key: DesktopScene; label: string; icon: typeof MdLockOutline }[] = [
  { key: 'desktop', label: 'Desktop', icon: MdDesktopWindows },
  { key: 'clean', label: 'Clean', icon: MdWallpaper },
];

function SceneSwitcher<T extends string>({
  scenes,
  active,
  onChange,
}: {
  scenes: { key: T; label: string; icon: typeof MdLockOutline }[];
  active: T;
  onChange: (k: T) => void;
}) {
  return (
    <div className="flex items-center gap-1 bg-white/10 backdrop-blur-md rounded-full p-1">
      {scenes.map((s) => {
        const Icon = s.icon;
        const isActive = s.key === active;
        return (
          <button
            key={s.key}
            onClick={() => onChange(s.key)}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium transition-all duration-200 ${
              isActive
                ? 'bg-white/20 text-white shadow-sm'
                : 'text-white/50 hover:text-white/80'
            }`}
          >
            <Icon size={14} />
            <span className="hidden sm:inline">{s.label}</span>
          </button>
        );
      })}
    </div>
  );
}

// --------------- Main component ---------------

export default function DeviceMockup({ imageUrl, platform, deviceName, deviceWidth, deviceHeight, onClose }: Props) {
  const isMobile = platform === 'phone' || platform === 'tablet';
  const [mobileScene, setMobileScene] = useState<MobileScene>('lock');
  const [deskScene, setDeskScene] = useState<DesktopScene>('desktop');

  const scale = useMemo(() => {
    const frameExtra = BEZEL * 2 + 60;
    const maxW = window.innerWidth * 0.9;
    const maxH = window.innerHeight * 0.82;
    const totalW = deviceWidth + frameExtra;
    const totalH = deviceHeight + frameExtra;
    const sx = maxW / totalW;
    const sy = maxH / totalH;
    return Math.min(sx, sy, 1);
  }, [deviceWidth, deviceHeight]);

  const renderMockup = () => {
    if (platform === 'phone') return <PhoneFrame imageUrl={imageUrl} width={deviceWidth} height={deviceHeight} scene={mobileScene} />;
    if (platform === 'tablet') return <TabletFrame imageUrl={imageUrl} width={deviceWidth} height={deviceHeight} scene={mobileScene} />;
    if (platform === 'laptop') return <LaptopFrame imageUrl={imageUrl} width={deviceWidth} height={deviceHeight} scene={deskScene} />;
    if (platform === 'desktop') return <DesktopFrame imageUrl={imageUrl} width={deviceWidth} height={deviceHeight} scene={deskScene} />;
    return <PhoneFrame imageUrl={imageUrl} width={deviceWidth} height={deviceHeight} scene={mobileScene} />;
  };

  return (
    <div
      className="fixed inset-0 z-50 bg-black/85 backdrop-blur-md flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="relative flex flex-col items-center gap-3"
        onClick={(e) => e.stopPropagation()}
        style={{ transform: `scale(${scale})`, transformOrigin: 'center center' }}
      >
        <button
          onClick={onClose}
          className="absolute -top-5 -right-5 z-10 p-2.5 bg-white/10 hover:bg-white/20 text-white rounded-full transition-colors duration-200"
        >
          <AiOutlineClose size={22} />
        </button>

        <div className="transition-all duration-300 ease-in-out">
          {renderMockup()}
        </div>

        <div className="flex flex-col items-center gap-3 mt-1">
          <div className="flex items-center gap-2 text-white/70 text-sm">
            <MdPhoneIphone size={16} />
            <span>{deviceName}</span>
            <span className="text-white/40">&middot;</span>
            <span className="text-white/40">{deviceWidth}&times;{deviceHeight}</span>
          </div>

          {isMobile ? (
            <SceneSwitcher scenes={mobileScenes} active={mobileScene} onChange={setMobileScene} />
          ) : (
            <SceneSwitcher scenes={desktopScenes} active={deskScene} onChange={setDeskScene} />
          )}
        </div>
      </div>
    </div>
  );
}

export function canShowMockup(v: { width: number; height: number }): boolean {
  const sw = window.innerWidth;
  const sh = window.innerHeight;
  return sw >= v.width * 0.3 && sh >= v.height * 0.3;
}
