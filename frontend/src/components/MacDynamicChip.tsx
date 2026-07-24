import { MdDesktopMac } from 'react-icons/md';

export default function MacDynamicChip() {
  return (
    <span className="tile-chip is-mac" title="Mac" aria-label="Mac">
      <MdDesktopMac aria-hidden />
      Mac
    </span>
  );
}
