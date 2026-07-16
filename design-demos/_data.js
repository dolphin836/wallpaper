// Real wallpapers fetched from the live API, embedded so every demo file
// works over file:// without a server. Keep ordering: index 0 is the hero
// candidate for both directions.
window.WALLPAPERS = [
  { id: 963, title: 'Leap Into the Valley',                       thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/6b370d40-f6ff-4854-8187-b4d39a0b5e91.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/c8e225b9-e500-4767-af67-0101346ba78f.webp', w: 8000, h: 4500, size: 13765412, color: '#345F5F', palette: '#345F5F,#3174AD,#64864C,#8EB658,#83ACC6', downloads: 10, observers: 14 },
  { id: 959, title: 'Frozen Lake Beneath Snowy Mountain Peaks',   thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/d163d363-ac84-41b6-9171-d8cd2495a4d2.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/182e1ca4-3076-4608-8291-0f3a19c7f794.webp', w: 9246, h: 4932, size: 11285621, color: '#4681C8', palette: '#01081A,#234E82,#3768A3,#4681C8,#659BDE', downloads: 0, observers: 3 },
  { id: 962, title: 'Quiet Moment by the Lake',                   thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/f2381b98-faea-404b-a8d3-9c3379eab645.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/ece91460-2476-43cc-99af-a079389cee37.webp', w: 3840, h: 2160, size: 5462510, color: '#052120', palette: '#052120,#153736,#325A4D,#4183B5,#93C0DC', downloads: 0, observers: 2 },
  { id: 961, title: 'Alpine Church Beneath the Dolomites',        thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/ee133377-9ef7-4b50-a957-08c40053af88.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/7d97f4a8-0a91-4ffa-a3d5-4f990d617a22.webp', w: 8000, h: 5328, size: 9900161, color: '#182A10', palette: '#182A10,#404C24,#727170,#9EA9B7,#DEDDE0', downloads: 0, observers: 5 },
  { id: 958, title: 'Mountain Sunrise Reflected in Still Lake',   thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/aa5ac2c9-1f9d-4b2b-80e4-3b9a95650b08.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/3e72aac5-71aa-498a-b1d9-89014de540b8.webp', w: 7680, h: 4320, size: 3585427, color: '#1E393A', palette: '#0C201A,#1E393A,#07617C,#4491AD,#7AADBF', downloads: 0, observers: 1 },
  { id: 957, title: 'Tropical Island Bay with Boats',             thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/516b02bc-85e5-45a8-9b3d-0aa16be3dcb7.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/b4f09be3-4f88-4d3f-a90b-4d14fc147bd3.webp', w: 5659, h: 3773, size: 4562450, color: '#9ACCD5', palette: '#181B0B,#383D2B,#5DA5B5,#9ACCD5,#D4EAEC', downloads: 0, observers: 4 },
  { id: 956, title: 'Grand Teton Sunrise Over Snake River',       thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/e622fd8c-334a-4a8c-a10c-b01fecbd6122.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/09fbaeef-c393-4c2c-902c-54efa971ee76.webp', w: 5202, h: 3468, size: 2908961, color: '#A8BECB', palette: '#1F2315,#494A1F,#83838A,#CD9D7B,#A8BECB', downloads: 0, observers: 1 },
  { id: 966, title: 'Palm-Lined Boulevard Under a Sunny City Sky', thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/393cf96d-4f41-4e1e-9dfe-ce64e8b852ac.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/3411c7f3-a27b-41b8-897b-7b614c7ae003.webp', w: 4096, h: 2304, size: 3471649, color: '#222D2F', palette: '#222D2F,#64ABC8,#7DCDDA,#B2BEB9,#F0E9D2', downloads: 1, observers: 2 },
  { id: 965, title: 'Jumbo Jet Over Sunset Freeway',              thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/b4943622-4498-4ecd-8849-589634d4eb83.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/061f356d-b13a-4817-87a6-3b1c687145e7.webp', w: 4096, h: 3070, size: 722935, color: '#68B8C9', palette: '#40262E,#45576F,#9B8F91,#E8856C,#68B8C9', downloads: 0, observers: 0 },
  { id: 964, title: 'Yellow Jet Soaring Above the Clouds',        thumb: 'https://wallpaperexchange.com/storage/wallpapers/thumbs/35527eae-de29-40d0-8fcc-ee43e74d6e7a.webp', preview: 'https://wallpaperexchange.com/storage/wallpapers/previews/a452c19f-c4fd-4b9b-bb5f-caa0bbd17907.webp', w: 7002, h: 4667, size: 11062601, color: '#9CA8B5', palette: '#08253F,#294967,#4E6984,#9CA8B5,#BCC0C3', downloads: 8, observers: 7 },
];

// Tiny helper used by both directions: format bytes.
window.fmtMB = (b) => (b / 1024 / 1024).toFixed(1) + ' MB';
window.fmtMP = (w, h) => ((w * h) / 1e6).toFixed(1) + ' MP';
window.hexToOklch = (hex) => {
  // Rough approximation for display only. Real conversion happens server-side.
  const r = parseInt(hex.slice(1, 3), 16) / 255;
  const g = parseInt(hex.slice(3, 5), 16) / 255;
  const b = parseInt(hex.slice(5, 7), 16) / 255;
  const L = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  const C = Math.sqrt((r - L) ** 2 + (g - L) ** 2 + (b - L) ** 2) * 0.4;
  const h = Math.round((Math.atan2(b - L, r - L) * 180) / Math.PI + 180) % 360;
  return `${Math.round(L * 100)}% ${C.toFixed(2)} ${h}`;
};
