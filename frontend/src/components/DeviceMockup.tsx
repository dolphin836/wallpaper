import { useMemo } from 'react';
import { AiOutlineWifi, AiOutlineClose } from 'react-icons/ai';
import { MdBatteryFull, MdSignalCellular4Bar } from 'react-icons/md';

interface Props {
  imageUrl: string;
  platform: string;
  deviceName: string;
  deviceWidth: number;
  deviceHeight: number;
  onClose: () => void;
}

function getNow() {
  const now = new Date();
  const time = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
  const weekday = now.toLocaleDateString('en-US', { weekday: 'long' });
  const date = now.toLocaleDateString('en-US', { month: 'long', day: 'numeric' });
  return { time, weekday, date };
}

const BEZEL = 12;

function PhoneMockup({ imageUrl, width, height }: { imageUrl: string; width: number; height: number }) {
  const { time, weekday, date } = getNow();
  const outerW = width + BEZEL * 2;
  return (
    <div style={{ width: outerW }}>
      <div
        className="relative bg-black overflow-hidden shadow-2xl"
        style={{ borderRadius: outerW * 0.1, border: `${BEZEL}px solid #1f2937` }}
      >
        <div className="absolute top-1 left-1/2 -translate-x-1/2 z-20 bg-black rounded-full"
          style={{ width: width * 0.22, height: width * 0.06 }}
        />
        <div className="relative" style={{ width, height }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
          <div className="absolute top-0 left-0 right-0 z-10 flex items-center justify-between text-white font-medium"
            style={{ padding: `${height * 0.015}px ${width * 0.08}px`, fontSize: width * 0.032 }}
          >
            <span>{time}</span>
            <div className="flex items-center gap-1">
              <MdSignalCellular4Bar style={{ width: width * 0.03, height: width * 0.03 }} />
              <AiOutlineWifi style={{ width: width * 0.03, height: width * 0.03 }} />
              <MdBatteryFull style={{ width: width * 0.035, height: width * 0.035 }} />
            </div>
          </div>
          <div className="absolute inset-0 z-10 flex flex-col items-center text-white"
            style={{ paddingTop: height * 0.12 }}
          >
            <div className="font-thin leading-none tracking-tight drop-shadow-lg"
              style={{ fontSize: width * 0.18 }}
            >{time}</div>
            <div className="font-normal drop-shadow-md"
              style={{ fontSize: width * 0.04, marginTop: height * 0.005 }}
            >{weekday}, {date}</div>
          </div>
          <div className="absolute left-1/2 -translate-x-1/2 z-10 bg-white/60 rounded-full"
            style={{ bottom: height * 0.01, width: width * 0.35, height: width * 0.012 }}
          />
        </div>
      </div>
    </div>
  );
}

function TabletMockup({ imageUrl, width, height }: { imageUrl: string; width: number; height: number }) {
  const { time, weekday, date } = getNow();
  return (
    <div style={{ width: width + BEZEL * 2 }}>
      <div
        className="relative bg-black overflow-hidden shadow-2xl"
        style={{ borderRadius: 24, border: `${BEZEL}px solid #1f2937` }}
      >
        <div className="relative" style={{ width, height }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
          <div className="absolute top-0 left-0 right-0 z-10 flex items-center justify-between text-white font-medium"
            style={{ padding: `${height * 0.015}px ${width * 0.04}px`, fontSize: width * 0.02 }}
          >
            <span>{time}</span>
            <div className="flex items-center gap-1">
              <AiOutlineWifi style={{ width: width * 0.02, height: width * 0.02 }} />
              <MdBatteryFull style={{ width: width * 0.025, height: width * 0.025 }} />
            </div>
          </div>
          <div className="absolute inset-0 z-10 flex flex-col items-center text-white"
            style={{ paddingTop: height * 0.15 }}
          >
            <div className="font-thin leading-none tracking-tight drop-shadow-lg"
              style={{ fontSize: width * 0.1 }}
            >{time}</div>
            <div className="font-normal drop-shadow-md"
              style={{ fontSize: width * 0.025, marginTop: height * 0.005 }}
            >{weekday}, {date}</div>
          </div>
        </div>
      </div>
    </div>
  );
}

function LaptopMockup({ imageUrl, width, height }: { imageUrl: string; width: number; height: number }) {
  const outerW = width + BEZEL * 2;
  return (
    <div style={{ width: outerW }}>
      <div
        className="relative bg-black overflow-hidden shadow-2xl"
        style={{ borderRadius: '12px 12px 0 0', border: `${BEZEL}px solid #374151` }}
      >
        <div className="relative" style={{ width, height }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
          <div className="absolute top-1.5 left-1/2 -translate-x-1/2 w-2 h-2 bg-gray-800 rounded-full border border-gray-600" />
        </div>
      </div>
      <div className="relative h-3 bg-gradient-to-b from-gray-600 to-gray-500 rounded-b-md"
        style={{ marginLeft: '-2%', marginRight: '-2%' }}
      >
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-16 h-1 bg-gray-400 rounded-b" />
      </div>
    </div>
  );
}

function DesktopMockup({ imageUrl, width, height }: { imageUrl: string; width: number; height: number }) {
  const outerW = width + BEZEL * 2;
  return (
    <div style={{ width: outerW }}>
      <div
        className="relative bg-black overflow-hidden shadow-2xl"
        style={{ borderRadius: 12, border: `${BEZEL}px solid #374151` }}
      >
        <div className="relative" style={{ width, height }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
        </div>
      </div>
      <div className="flex flex-col items-center">
        <div className="bg-gradient-to-b from-gray-600 to-gray-500" style={{ width: outerW * 0.08, height: outerW * 0.05 }} />
        <div className="bg-gray-500 rounded-full" style={{ width: outerW * 0.15, height: 4 }} />
      </div>
    </div>
  );
}

export default function DeviceMockup({ imageUrl, platform, deviceName, deviceWidth, deviceHeight, onClose }: Props) {
  const scale = useMemo(() => {
    const frameExtra = BEZEL * 2 + 20;
    const maxW = window.innerWidth * 0.9;
    const maxH = window.innerHeight * 0.85;
    const totalW = deviceWidth + frameExtra;
    const totalH = deviceHeight + frameExtra;
    const sx = maxW / totalW;
    const sy = maxH / totalH;
    return Math.min(sx, sy, 1);
  }, [deviceWidth, deviceHeight]);

  const renderMockup = () => {
    const props = { imageUrl, width: deviceWidth, height: deviceHeight };
    switch (platform) {
      case 'phone': return <PhoneMockup {...props} />;
      case 'tablet': return <TabletMockup {...props} />;
      case 'laptop': return <LaptopMockup {...props} />;
      case 'desktop': return <DesktopMockup {...props} />;
      default: return <PhoneMockup {...props} />;
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="relative flex flex-col items-center gap-4"
        onClick={(e) => e.stopPropagation()}
        style={{ transform: `scale(${scale})`, transformOrigin: 'center center' }}
      >
        <button
          onClick={onClose}
          className="absolute -top-4 -right-4 z-10 p-2 bg-white/10 hover:bg-white/20 text-white rounded-full transition-colors"
        >
          <AiOutlineClose size={24} />
        </button>

        {renderMockup()}

        <div className="text-center text-white/80 text-sm mt-2">
          {deviceName} &middot; {deviceWidth}&times;{deviceHeight}
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
