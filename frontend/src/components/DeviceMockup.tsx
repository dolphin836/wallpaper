import { AiOutlineWifi, AiOutlineClose } from 'react-icons/ai';
import { MdBatteryFull, MdSignalCellular4Bar } from 'react-icons/md';

interface Props {
  imageUrl: string;
  platform: string;
  deviceName: string;
  onClose: () => void;
}

function getNow() {
  const now = new Date();
  const time = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
  const weekday = now.toLocaleDateString('en-US', { weekday: 'long' });
  const date = now.toLocaleDateString('en-US', { month: 'long', day: 'numeric' });
  return { time, weekday, date };
}

function PhoneMockup({ imageUrl }: { imageUrl: string }) {
  const { time, weekday, date } = getNow();
  return (
    <div className="relative mx-auto" style={{ width: 300 }}>
      <div className="relative rounded-[3rem] border-[6px] border-gray-800 bg-black overflow-hidden shadow-2xl">
        {/* Dynamic Island */}
        <div className="absolute top-2 left-1/2 -translate-x-1/2 z-20 w-[90px] h-[25px] bg-black rounded-full" />

        <div className="relative" style={{ aspectRatio: '9/19.5' }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />

          {/* Status Bar */}
          <div className="absolute top-0 left-0 right-0 z-10 flex items-center justify-between px-8 pt-4 text-white text-[11px] font-medium">
            <span>{time}</span>
            <div className="flex items-center gap-1">
              <MdSignalCellular4Bar size={12} />
              <AiOutlineWifi size={12} />
              <MdBatteryFull size={14} />
            </div>
          </div>

          {/* Lock Screen */}
          <div className="absolute inset-0 z-10 flex flex-col items-center pt-20 text-white">
            <div className="text-[64px] font-thin leading-none tracking-tight drop-shadow-lg">
              {time}
            </div>
            <div className="text-[17px] font-normal mt-1 drop-shadow-md">
              {weekday}, {date}
            </div>
          </div>

          {/* Home Indicator */}
          <div className="absolute bottom-2 left-1/2 -translate-x-1/2 z-10 w-[120px] h-[4px] bg-white/60 rounded-full" />
        </div>
      </div>
    </div>
  );
}

function TabletMockup({ imageUrl }: { imageUrl: string }) {
  const { time, weekday, date } = getNow();
  return (
    <div className="relative mx-auto" style={{ width: 420 }}>
      <div className="relative rounded-[1.5rem] border-[6px] border-gray-800 bg-black overflow-hidden shadow-2xl">
        <div className="relative" style={{ aspectRatio: '4/3' }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />

          <div className="absolute top-0 left-0 right-0 z-10 flex items-center justify-between px-6 pt-3 text-white text-[11px] font-medium">
            <span>{time}</span>
            <div className="flex items-center gap-1">
              <AiOutlineWifi size={12} />
              <MdBatteryFull size={14} />
            </div>
          </div>

          <div className="absolute inset-0 z-10 flex flex-col items-center pt-24 text-white">
            <div className="text-[72px] font-thin leading-none tracking-tight drop-shadow-lg">
              {time}
            </div>
            <div className="text-[18px] font-normal mt-1 drop-shadow-md">
              {weekday}, {date}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function LaptopMockup({ imageUrl }: { imageUrl: string }) {
  return (
    <div className="relative mx-auto" style={{ width: 520 }}>
      {/* Screen */}
      <div className="relative rounded-t-lg border-[6px] border-gray-700 bg-black overflow-hidden shadow-2xl">
        <div className="relative" style={{ aspectRatio: '16/10' }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
          {/* Camera dot */}
          <div className="absolute top-1.5 left-1/2 -translate-x-1/2 w-2 h-2 bg-gray-800 rounded-full border border-gray-600" />
        </div>
      </div>
      {/* Base */}
      <div className="relative h-3 bg-gradient-to-b from-gray-600 to-gray-500 rounded-b-md mx-[-2%]">
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-16 h-1 bg-gray-400 rounded-b" />
      </div>
    </div>
  );
}

function DesktopMockup({ imageUrl }: { imageUrl: string }) {
  return (
    <div className="relative mx-auto" style={{ width: 520 }}>
      {/* Monitor */}
      <div className="relative rounded-lg border-[6px] border-gray-700 bg-black overflow-hidden shadow-2xl">
        <div className="relative" style={{ aspectRatio: '16/9' }}>
          <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover" />
        </div>
      </div>
      {/* Stand */}
      <div className="flex flex-col items-center">
        <div className="w-12 h-8 bg-gradient-to-b from-gray-600 to-gray-500" />
        <div className="w-24 h-2 bg-gray-500 rounded-full" />
      </div>
    </div>
  );
}

export default function DeviceMockup({ imageUrl, platform, deviceName, onClose }: Props) {
  const renderMockup = () => {
    switch (platform) {
      case 'phone':
        return <PhoneMockup imageUrl={imageUrl} />;
      case 'tablet':
        return <TabletMockup imageUrl={imageUrl} />;
      case 'laptop':
        return <LaptopMockup imageUrl={imageUrl} />;
      case 'desktop':
        return <DesktopMockup imageUrl={imageUrl} />;
      default:
        return <PhoneMockup imageUrl={imageUrl} />;
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="relative flex flex-col items-center gap-4 max-h-[90vh]"
        onClick={(e) => e.stopPropagation()}
      >
        <button
          onClick={onClose}
          className="absolute -top-2 -right-2 z-10 p-2 bg-white/10 hover:bg-white/20 text-white rounded-full transition-colors"
        >
          <AiOutlineClose size={20} />
        </button>

        {renderMockup()}

        <div className="text-center text-white/80 text-sm mt-2">
          {deviceName}
        </div>
      </div>
    </div>
  );
}
