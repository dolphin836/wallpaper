import { useEffect, useRef, useState, useCallback } from 'react';

// Square output edge written to the upload. 512 is plenty for the largest
// avatar slot in the UI (96px @3x) without ballooning the JPEG over 80 KB.
const OUTPUT_SIZE = 512;
// Square viewport drawn in the modal. Bigger than the output so the user can
// see what they're cropping on a desktop screen without a tiny preview.
const VIEWPORT = 320;

interface Props {
  file: File;
  onSave: (blob: Blob) => Promise<void> | void;
  onCancel: () => void;
}

// Tells if value is finite and not NaN — TS still considers a possibly-bad
// arithmetic result a `number` so explicit guards make the intent clear.
const fin = (n: number) => Number.isFinite(n) && !Number.isNaN(n);

export default function AvatarCropModal({ file, onSave, onCancel }: Props) {
  const [image, setImage] = useState<HTMLImageElement | null>(null);
  const [imageURL, setImageURL] = useState('');
  const [scale, setScale] = useState(1);
  const [minScale, setMinScale] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [saving, setSaving] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const draggingRef = useRef<{ startX: number; startY: number; offX: number; offY: number } | null>(null);

  // Load the file once, decoded into an HTMLImageElement. We hold an object
  // URL for the lifetime of the modal so the <img> for the canvas source has
  // somewhere to point — revoked on unmount.
  useEffect(() => {
    const url = URL.createObjectURL(file);
    setImageURL(url);
    const img = new Image();
    img.onload = () => {
      setImage(img);
      // Fit the longer side to viewport. That's the smallest scale that still
      // covers the crop circle — anything smaller would leave transparent gaps
      // inside the mask, so we clamp scale to >= this value.
      const m = Math.max(VIEWPORT / img.width, VIEWPORT / img.height);
      setMinScale(m);
      setScale(m);
      setOffset({ x: 0, y: 0 });
    };
    img.src = url;
    return () => URL.revokeObjectURL(url);
  }, [file]);

  // Re-render the canvas whenever image / scale / offset changes. Canvas is
  // 2× the CSS size for sharpness on HiDPI displays; we account for that in
  // both the draw and the offset units (offset is in CSS pixels).
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !image) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = VIEWPORT * dpr;
    canvas.height = VIEWPORT * dpr;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, VIEWPORT, VIEWPORT);

    // Drawn dimensions of the image at the current scale.
    const dw = image.width * scale;
    const dh = image.height * scale;
    // Image origin is the viewport center + offset.
    const dx = (VIEWPORT - dw) / 2 + offset.x;
    const dy = (VIEWPORT - dh) / 2 + offset.y;

    // Background image (full draw — we'll dim the area outside the circle).
    ctx.drawImage(image, dx, dy, dw, dh);

    // Overlay: dark everywhere except a clear circular hole in the middle.
    // Using even-odd fill so a rectangle + a circle subpath cuts a hole.
    ctx.save();
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.beginPath();
    ctx.rect(0, 0, VIEWPORT, VIEWPORT);
    ctx.arc(VIEWPORT / 2, VIEWPORT / 2, VIEWPORT / 2 - 1, 0, Math.PI * 2, true);
    ctx.closePath();
    ctx.fill('evenodd');
    ctx.restore();

    // Crop-circle outline so the edge is visible even on busy images.
    ctx.save();
    ctx.strokeStyle = 'rgba(255,255,255,0.9)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(VIEWPORT / 2, VIEWPORT / 2, VIEWPORT / 2 - 1, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }, [image, scale, offset]);

  // Clamp offset so the crop circle never moves outside the image. Without
  // this you can drag the photo away and end up with transparent pixels in
  // the avatar.
  const clamp = useCallback((next: { x: number; y: number }, s: number) => {
    if (!image) return next;
    const dw = image.width * s;
    const dh = image.height * s;
    // Max offset = (drawn size - viewport) / 2 in each axis. If the image is
    // smaller than the viewport on an axis we lock that axis at 0 (impossible
    // here because minScale guarantees it covers, but defensive anyway).
    const maxX = Math.max(0, (dw - VIEWPORT) / 2);
    const maxY = Math.max(0, (dh - VIEWPORT) / 2);
    return {
      x: Math.max(-maxX, Math.min(maxX, fin(next.x) ? next.x : 0)),
      y: Math.max(-maxY, Math.min(maxY, fin(next.y) ? next.y : 0)),
    };
  }, [image]);

  // Re-clamp existing offset when scale changes (zooming out may push the
  // image inside the crop circle, which clamp fixes).
  useEffect(() => {
    setOffset((o) => clamp(o, scale));
  }, [scale, clamp]);

  // Mouse drag
  const onPointerDown = (e: React.PointerEvent) => {
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    draggingRef.current = { startX: e.clientX, startY: e.clientY, offX: offset.x, offY: offset.y };
  };
  const onPointerMove = (e: React.PointerEvent) => {
    const drag = draggingRef.current;
    if (!drag) return;
    const nx = drag.offX + (e.clientX - drag.startX);
    const ny = drag.offY + (e.clientY - drag.startY);
    setOffset(clamp({ x: nx, y: ny }, scale));
  };
  const onPointerUp = () => { draggingRef.current = null; };

  // Wheel zoom — natural feel: scroll up = zoom in. The clamp on min keeps
  // the image always covering the crop circle; 4× the min is a sane upper
  // limit so the user can't blow it up past quality.
  const onWheel = (e: React.WheelEvent) => {
    e.preventDefault();
    const delta = -e.deltaY * 0.002;
    setScale((s) => Math.max(minScale, Math.min(minScale * 4, s + delta * s)));
  };

  const save = async () => {
    if (!image) return;
    // Render the cropped circle into a fresh OUTPUT_SIZE×OUTPUT_SIZE canvas.
    // We don't apply a circular clip on output because:
    //   1. JPEG can't store transparency
    //   2. The avatar slot in the UI already rounds with CSS
    // So we ship a square JPEG that's the bounding box of the visible circle.
    const out = document.createElement('canvas');
    out.width = OUTPUT_SIZE;
    out.height = OUTPUT_SIZE;
    const ctx = out.getContext('2d');
    if (!ctx) return;

    // Scale factor from on-screen viewport units to the output image.
    const k = OUTPUT_SIZE / VIEWPORT;
    const dw = image.width * scale * k;
    const dh = image.height * scale * k;
    const dx = (OUTPUT_SIZE - dw) / 2 + offset.x * k;
    const dy = (OUTPUT_SIZE - dh) / 2 + offset.y * k;

    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, OUTPUT_SIZE, OUTPUT_SIZE);
    ctx.drawImage(image, dx, dy, dw, dh);

    const blob: Blob = await new Promise((resolve) => {
      out.toBlob((b) => resolve(b!), 'image/jpeg', 0.9);
    });
    setSaving(true);
    try {
      await onSave(blob);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 backdrop-blur-[2px]"
      style={{ background: 'rgba(15,12,8,0.55)' }}
      onClick={onCancel}
    >
      <div
        className="bg-paper text-ink rounded-[20px] shadow-[0_24px_70px_rgba(0,0,0,0.28)] border border-hair p-5 w-full max-w-[420px]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="kicker text-muted">Profile image</div>
        <h3 className="display text-[22px] leading-none mt-2">裁剪头像</h3>
        <p className="text-[12px] text-muted mt-2 mb-4">拖拽调整位置，滚轮或滑块缩放</p>

        <div className="relative mx-auto" style={{ width: VIEWPORT, height: VIEWPORT }}>
          {image ? (
            <canvas
              ref={canvasRef}
              style={{ width: VIEWPORT, height: VIEWPORT, touchAction: 'none', cursor: draggingRef.current ? 'grabbing' : 'grab' }}
              className="rounded-xl bg-paper-2 border border-hair"
              onPointerDown={onPointerDown}
              onPointerMove={onPointerMove}
              onPointerUp={onPointerUp}
              onPointerCancel={onPointerUp}
              onWheel={onWheel}
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-sm text-muted bg-paper-2 border border-hair rounded-xl">加载图片中…</div>
          )}
          {/* Tiny round preview in the corner so the user sees the final result
              independent of the dim mask. */}
          {image && imageURL && (
            <div className="absolute -bottom-2 right-2 w-14 h-14 rounded-full overflow-hidden ring-2 ring-paper shadow-[0_8px_18px_rgba(0,0,0,0.22)] bg-paper-2">
              <CircleMini
                image={image}
                scale={scale}
                offset={offset}
              />
            </div>
          )}
        </div>

        <div className="flex items-center gap-3 mt-5">
          <span className="mono text-[10px] tracking-[0.14em] uppercase text-muted select-none">缩放</span>
          <input
            type="range"
            min={minScale}
            max={minScale * 4}
            step={0.01}
            value={scale}
            onChange={(e) => setScale(Number(e.target.value))}
            className="flex-1 accent-[var(--color-accent)]"
          />
        </div>

        <div className="flex gap-2 mt-5">
          <button
            onClick={onCancel}
            disabled={saving}
            className="flex-1 py-2.5 text-[13px] font-medium rounded-full border border-hair text-ink-2 hover:text-ink hover:bg-paper-2 transition-colors disabled:opacity-50"
          >取消</button>
          <button
            onClick={save}
            disabled={saving || !image}
            className="flex-1 py-2.5 text-[13px] font-semibold text-paper bg-ink hover:bg-ink-2 rounded-full transition-colors disabled:opacity-50"
          >{saving ? '上传中…' : '确定上传'}</button>
        </div>
      </div>
    </div>
  );
}

// Mini live preview that mirrors the main canvas's transform but onto a
// 56-pixel circular surface. Same draw math, just a different scale factor.
function CircleMini({ image, scale, offset }: { image: HTMLImageElement; scale: number; offset: { x: number; y: number } }) {
  const ref = useRef<HTMLCanvasElement>(null);
  const SIZE = 56;
  useEffect(() => {
    const c = ref.current;
    if (!c) return;
    const dpr = window.devicePixelRatio || 1;
    c.width = SIZE * dpr;
    c.height = SIZE * dpr;
    const ctx = c.getContext('2d');
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, SIZE, SIZE);
    const k = SIZE / VIEWPORT;
    const dw = image.width * scale * k;
    const dh = image.height * scale * k;
    const dx = (SIZE - dw) / 2 + offset.x * k;
    const dy = (SIZE - dh) / 2 + offset.y * k;
    ctx.drawImage(image, dx, dy, dw, dh);
  }, [image, scale, offset]);
  return <canvas ref={ref} style={{ width: SIZE, height: SIZE }} />;
}
