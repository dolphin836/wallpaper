import { useEffect, useState, useCallback } from 'react';
import toast from 'react-hot-toast';
import { Link } from 'react-router-dom';
import * as admin from '../../api/admin';
import type { AdminCollectionRow, AdminWallpaperRow } from '../../api/admin';
import type { Wallpaper } from '../../types';
import {
  Card,
  PageHeader,
  Spinner,
  Empty,
  Pagination,
  fmtDate,
  StatusBadge,
} from './components';
import { AddWallpaperModal } from './WeeklyPicksPage';

function currentISOWeek() {
  const d = new Date();
  const date = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((date.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
  return { year: date.getUTCFullYear(), week };
}

export default function CollectionsPage() {
  const [items, setItems] = useState<AdminCollectionRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [limit] = useState(20);
  const [search, setSearch] = useState('');
  const [publicFilter, setPublicFilter] = useState<'' | 'true' | 'false'>('');
  const [kindFilter, setKindFilter] = useState<'' | '0' | '1'>('');
  const [sort, setSort] = useState('newest');
  const [loading, setLoading] = useState(false);
  const [editing, setEditing] = useState<AdminCollectionRow | null>(null);
  const [creating, setCreating] = useState(false);

  const fetchList = useCallback(() => {
    setLoading(true);
    admin
      .listAdminCollections({
        page,
        limit,
        search: search || undefined,
        is_public: publicFilter === '' ? undefined : publicFilter === 'true',
        kind: kindFilter === '' ? undefined : Number(kindFilter),
        sort,
      })
      .then((r) => {
        setItems(r.data.data.items);
        setTotal(r.data.data.total);
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载失败'))
      .finally(() => setLoading(false));
  }, [page, limit, search, publicFilter, kindFilter, sort]);

  useEffect(() => { fetchList(); }, [fetchList]);

  const onDelete = (id: number) => {
    if (!confirm('确认删除该合集？此操作不可恢复（壁纸不会被删除，只是从合集中移除）')) return;
    admin.deleteAdminCollection(id).then(() => {
      toast.success('已删除');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '操作失败'));
  };

  return (
    <>
      <PageHeader
        title="合集管理"
        subtitle={`共 ${total} 个，可创建普通合集或首页推荐合集`}
        action={
          <button
            onClick={() => setCreating(true)}
            className="px-4 py-2 rounded-full bg-purple-600 hover:bg-purple-700 text-white text-sm font-medium"
          >
            创建合集
          </button>
        }
      />
      <div className="px-8 pb-8 space-y-4">
        <Card>
          <div className="px-5 py-3 flex flex-wrap gap-3 items-center text-sm">
            <input
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              placeholder="搜索标题 / 所有者"
              className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 w-72"
            />
            <select value={publicFilter} onChange={(e) => { setPublicFilter(e.target.value as ''); setPage(1); }} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value="">全部可见性</option>
              <option value="true">公开</option>
              <option value="false">私密</option>
            </select>
            <select value={kindFilter} onChange={(e) => { setKindFilter(e.target.value as ''); setPage(1); }} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value="">全部类型</option>
              <option value="0">普通合集</option>
              <option value="1">首页推荐合集</option>
            </select>
            <select value={sort} onChange={(e) => setSort(e.target.value)} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value="newest">最新</option>
              <option value="wallpapers">壁纸数</option>
              <option value="likes">点赞数</option>
            </select>
          </div>

          {loading ? <Spinner /> : items.length === 0 ? <Empty>暂无合集</Empty> : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 dark:bg-slate-800/50 text-slate-500 text-xs uppercase tracking-wide">
                  <tr>
                    <th className="text-left px-4 py-2 font-medium">封面</th>
                    <th className="text-left px-4 py-2 font-medium">标题 / 所有者</th>
                    <th className="text-left px-4 py-2 font-medium">类型</th>
                    <th className="text-left px-4 py-2 font-medium">可见</th>
                    <th className="text-right px-4 py-2 font-medium">壁纸 / 赞</th>
                    <th className="text-left px-4 py-2 font-medium">创建时间</th>
                    <th className="text-right px-4 py-2 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {items.map((c) => (
                    <tr key={c.id} className="hover:bg-slate-50 dark:hover:bg-slate-800/30">
                      <td className="px-4 py-2 w-20">
                        <div className="w-16 h-12 rounded bg-slate-100 dark:bg-slate-800 overflow-hidden">
                          {c.cover_url && <img src={c.cover_url} alt="" className="w-full h-full object-cover" />}
                        </div>
                      </td>
                      <td className="px-4 py-2 max-w-xs">
                        <Link to={`/collections/${c.slug}`} className="block font-medium truncate hover:underline">{c.title}</Link>
                        <div className="text-xs text-slate-400 truncate">@{c.owner_username || '?'}</div>
                      </td>
                      <td className="px-4 py-2">
                        {c.kind === 1 ? (
                          <div className="space-y-1">
                            <StatusBadge label="首页推荐" tone="info" />
                            <div className="text-[11px] text-slate-400">{c.year ? `${c.year} W${String(c.week || 0).padStart(2, '0')}` : '未绑定周'}</div>
                          </div>
                        ) : <StatusBadge label="普通" tone="mute" />}
                      </td>
                      <td className="px-4 py-2">
                        {c.is_public ? <StatusBadge label="公开" tone="good" /> : <StatusBadge label="私密" tone="mute" />}
                      </td>
                      <td className="px-4 py-2 text-right text-xs text-slate-500 whitespace-nowrap">{c.wallpaper_count} 张 · {c.like_count} 赞</td>
                      <td className="px-4 py-2 text-xs text-slate-500 whitespace-nowrap">{fmtDate(c.created_at)}</td>
                      <td className="px-4 py-2 text-right whitespace-nowrap">
                        <button onClick={() => setEditing(c)} className="text-xs text-purple-600 hover:underline mr-3">编辑</button>
                        <button onClick={() => onDelete(c.id)} className="text-xs text-rose-500 hover:underline">删除</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <Pagination page={page} limit={limit} total={total} onChange={setPage} />
        </Card>
      </div>

      {(creating || editing) && (
        <CollectionEditorModal
          collection={editing}
          onClose={() => { setCreating(false); setEditing(null); }}
          onSaved={() => { setCreating(false); setEditing(null); fetchList(); }}
        />
      )}
    </>
  );
}

function CollectionEditorModal({
  collection,
  onClose,
  onSaved,
}: {
  collection: AdminCollectionRow | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const now = currentISOWeek();
  const isCreate = !collection;
  const [loading, setLoading] = useState(Boolean(collection));
  const [title, setTitle] = useState(collection?.title || '');
  const [description, setDescription] = useState(collection?.description || '');
  const [isPublic, setIsPublic] = useState(collection?.is_public ?? true);
  const [kind, setKind] = useState<number>(collection?.kind ?? 0);
  const [year, setYear] = useState<number>(collection?.year || now.year);
  const [week, setWeek] = useState<number>(collection?.week || now.week);
  const [accentColor, setAccentColor] = useState(collection?.accent_color || '');
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [showPicker, setShowPicker] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!collection) return;
    setLoading(true);
    admin.getAdminCollection(collection.id)
      .then((r) => {
        const d = r.data.data;
        setTitle(d.title || '');
        setDescription(d.description || '');
        setIsPublic(d.is_public);
        setKind(d.kind || 0);
        setYear(d.year || now.year);
        setWeek(d.week || now.week);
        setAccentColor(d.accent_color || '');
        setWallpapers(d.wallpapers || []);
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载合集详情失败'))
      .finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [collection?.id]);

  const moveWallpaper = (index: number, dir: -1 | 1) => {
    setWallpapers((rows) => {
      const next = [...rows];
      const target = index + dir;
      if (target < 0 || target >= next.length) return rows;
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  };

  const addWallpaper = (_id: number, wallpaper?: AdminWallpaperRow) => {
    if (!wallpaper) return;
    setWallpapers((rows) => rows.some((w) => w.id === wallpaper.id) ? rows : [...rows, wallpaper]);
    setShowPicker(false);
  };

  const save = () => {
    const trimmedTitle = title.trim();
    if (!trimmedTitle) {
      toast.error('请输入合集标题');
      return;
    }
    if (kind === 1 && (!Number.isInteger(year) || !Number.isInteger(week) || year <= 0 || week < 1 || week > 53)) {
      toast.error('首页推荐合集需要有效的年份和 ISO 周');
      return;
    }
    setSaving(true);
    const payload = {
      title: trimmedTitle,
      description: description.trim(),
      is_public: isPublic,
      kind,
      year: kind === 1 ? year : 0,
      week: kind === 1 ? week : 0,
      accent_color: kind === 1 ? accentColor.trim() : '',
      wallpaper_ids: wallpapers.map((w) => w.id),
    };
    const req = isCreate
      ? admin.createAdminCollection(payload)
      : admin.updateAdminCollection(collection.id, payload);
    req.then(() => {
      toast.success(isCreate ? '合集已创建' : '合集已保存');
      onSaved();
    }).catch((e) => toast.error(e?.response?.data?.message || '保存失败'))
      .finally(() => setSaving(false));
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-white dark:bg-slate-900 rounded-xl w-full max-w-5xl max-h-[calc(100vh-2rem)] overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-3 border-b border-slate-200 dark:border-slate-800 flex justify-between items-center">
          <div>
            <h3 className="font-semibold">{isCreate ? '创建合集' : `编辑合集 #${collection.id}`}</h3>
            <p className="text-xs text-slate-500 mt-0.5">首页推荐合集会显示在官网首页和合集列表中。</p>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-700 dark:hover:text-white">×</button>
        </div>
        {loading ? <Spinner /> : (
          <div className="p-5 min-h-0 overflow-y-auto grid grid-cols-12 gap-5">
            <div className="col-span-5 space-y-3">
              <label className="block text-sm">
                <div className="text-slate-500 mb-1">标题</div>
                <input value={title} onChange={(e) => setTitle(e.target.value)} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
              </label>
              <label className="block text-sm">
                <div className="text-slate-500 mb-1">描述</div>
                <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={4} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
              </label>
              <div className="grid grid-cols-2 gap-3">
                <label className="block text-sm">
                  <div className="text-slate-500 mb-1">类型</div>
                  <select value={kind} onChange={(e) => setKind(Number(e.target.value))} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950">
                    <option value={0}>普通合集</option>
                    <option value={1}>首页推荐合集</option>
                  </select>
                </label>
                <label className="block text-sm">
                  <div className="text-slate-500 mb-1">可见性</div>
                  <select value={isPublic ? 'true' : 'false'} onChange={(e) => setIsPublic(e.target.value === 'true')} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950">
                    <option value="true">公开</option>
                    <option value="false">私密</option>
                  </select>
                </label>
              </div>
              {kind === 1 && (
                <div className="grid grid-cols-3 gap-3">
                  <label className="block text-sm">
                    <div className="text-slate-500 mb-1">年份</div>
                    <input type="number" value={year} onChange={(e) => setYear(Number(e.target.value))} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
                  </label>
                  <label className="block text-sm">
                    <div className="text-slate-500 mb-1">ISO 周</div>
                    <input type="number" min={1} max={53} value={week} onChange={(e) => setWeek(Number(e.target.value))} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
                  </label>
                  <label className="block text-sm">
                    <div className="text-slate-500 mb-1">强调色</div>
                    <input value={accentColor} onChange={(e) => setAccentColor(e.target.value)} placeholder="oklch(...)" className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
                  </label>
                </div>
              )}
            </div>
            <div className="col-span-7">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <div className="text-sm font-semibold">合集壁纸</div>
                  <div className="text-xs text-slate-500">{wallpapers.length} 张，顺序会用于合集详情和封面</div>
                </div>
                <button
                  onClick={() => setShowPicker(true)}
                  className="px-3 py-1.5 rounded-full text-xs font-medium bg-slate-900 text-white dark:bg-white dark:text-slate-900 hover:opacity-90"
                >
                  添加壁纸
                </button>
              </div>
              {wallpapers.length === 0 ? <Empty>还没有壁纸。</Empty> : (
                <div className="grid grid-cols-3 gap-3">
                  {wallpapers.map((w, index) => (
                    <div key={w.id} className="group relative aspect-[4/5] rounded-lg overflow-hidden border border-slate-200 dark:border-slate-700 bg-slate-100 dark:bg-slate-800">
                      <img src={w.thumb_url || w.preview_url} alt="" className="absolute inset-0 w-full h-full object-cover" />
                      <div className="absolute top-1.5 right-1.5 z-10 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button onClick={() => moveWallpaper(index, -1)} disabled={index === 0} className="w-6 h-6 rounded-full bg-black/55 hover:bg-black/75 text-white text-xs disabled:opacity-30">↑</button>
                        <button onClick={() => moveWallpaper(index, 1)} disabled={index === wallpapers.length - 1} className="w-6 h-6 rounded-full bg-black/55 hover:bg-black/75 text-white text-xs disabled:opacity-30">↓</button>
                        <button onClick={() => setWallpapers((rows) => rows.filter((item) => item.id !== w.id))} className="w-6 h-6 rounded-full bg-black/55 hover:bg-rose-500 text-white text-sm leading-none">×</button>
                      </div>
                      <div className="absolute inset-x-0 bottom-0 px-2 py-1 bg-gradient-to-t from-black/75 to-transparent">
                        <span className="text-[10px] text-white/90 truncate block">#{index + 1} · {w.width}×{w.height}</span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
        <div className="px-5 py-3 border-t border-slate-200 dark:border-slate-800 flex justify-end gap-2">
          <button onClick={onClose} className="px-4 py-1.5 rounded text-sm text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800">取消</button>
          <button onClick={save} disabled={saving || loading} className="px-4 py-1.5 rounded text-sm bg-purple-600 hover:bg-purple-700 text-white disabled:opacity-60">
            {saving ? '保存中…' : '保存'}
          </button>
        </div>
      </div>
      {showPicker && (
        <AddWallpaperModal
          existingIds={wallpapers.map((w) => w.id)}
          onPick={addWallpaper}
          onClose={() => setShowPicker(false)}
          qualityFilter={kind === 1 ? 'weekly_eligible' : ''}
        />
      )}
    </div>
  );
}
