import { useEffect, useState, useCallback } from 'react';
import toast from 'react-hot-toast';
import { Link } from 'react-router-dom';
import * as admin from '../../api/admin';
import * as api from '../../api';
import type { AdminWallpaperRow } from '../../api/admin';
import type { Category } from '../../types';
import {
  Card,
  PageHeader,
  Spinner,
  StatusBadge,
  Empty,
  Pagination,
  fmtDate,
  fmtNumber,
  WALLPAPER_STATUS,
} from './components';

export default function WallpapersPage() {
  const [items, setItems] = useState<AdminWallpaperRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [limit] = useState(20);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<number | -1>(-1);
  const [categoryFilter, setCategoryFilter] = useState<number>(0);
  const [sort, setSort] = useState<string>('newest');
  const [loading, setLoading] = useState(false);
  const [categories, setCategories] = useState<Category[]>([]);
  const [editing, setEditing] = useState<AdminWallpaperRow | null>(null);

  useEffect(() => {
    api.getCategories().then((r) => setCategories(r.data.data));
  }, []);

  const fetchList = useCallback(() => {
    setLoading(true);
    admin
      .listAdminWallpapers({
        page,
        limit,
        search: search || undefined,
        status: statusFilter >= 0 ? statusFilter : undefined,
        category_id: categoryFilter || undefined,
        sort,
      })
      .then((r) => {
        setItems(r.data.data.items);
        setTotal(r.data.data.total);
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载失败'))
      .finally(() => setLoading(false));
  }, [page, limit, search, statusFilter, categoryFilter, sort]);

  useEffect(() => { fetchList(); }, [fetchList]);

  const onDelete = (id: number) => {
    if (!confirm('确认下架这张壁纸吗？（status -> 已下架，软删）')) return;
    admin.deleteAdminWallpaper(id).then(() => {
      toast.success('已下架');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '操作失败'));
  };

  const onChangeStatus = (id: number, status: number) => {
    admin.updateAdminWallpaper(id, { status }).then(() => {
      toast.success('状态已更新');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '更新失败'));
  };

  const onReprocess = (id: number) => {
    if (!confirm('重新处理这张壁纸？将重置为"处理中"并重新发送给 image worker。')) return;
    admin.reprocessAdminWallpaper(id).then(() => {
      toast.success('已重新入队，刷新后查看状态');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '重处理失败'));
  };

  return (
    <>
      <PageHeader title="壁纸管理" subtitle={`共 ${total} 张`} />
      <div className="px-8 pb-8 space-y-4">
        <Card>
          <div className="px-5 py-3 flex flex-wrap gap-3 items-center text-sm">
            <input
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              placeholder="搜索标题 / 描述 / 上传者"
              className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 w-72"
            />
            <select value={statusFilter} onChange={(e) => { setStatusFilter(Number(e.target.value)); setPage(1); }} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value={-1}>全部状态</option>
              <option value={0}>处理中</option>
              <option value={1}>已发布</option>
              <option value={2}>处理失败</option>
              <option value={3}>已下架</option>
              <option value={4}>重复</option>
            </select>
            <select value={categoryFilter} onChange={(e) => { setCategoryFilter(Number(e.target.value)); setPage(1); }} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value={0}>全部分类</option>
              {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
            <select value={sort} onChange={(e) => setSort(e.target.value)} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value="newest">最新</option>
              <option value="views">浏览最多</option>
              <option value="likes">点赞最多</option>
              <option value="downloads">下载最多</option>
            </select>
          </div>

          {loading ? <Spinner /> : items.length === 0 ? <Empty>无符合条件的壁纸</Empty> : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 dark:bg-slate-800/50 text-slate-500 text-xs uppercase tracking-wide">
                  <tr>
                    <th className="text-left px-4 py-2 font-medium">封面</th>
                    <th className="text-left px-4 py-2 font-medium">标题 / 上传者</th>
                    <th className="text-left px-4 py-2 font-medium">分类</th>
                    <th className="text-left px-4 py-2 font-medium">状态</th>
                    <th className="text-right px-4 py-2 font-medium">数据</th>
                    <th className="text-left px-4 py-2 font-medium">上传时间</th>
                    <th className="text-right px-4 py-2 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {items.map((w) => {
                    const st = WALLPAPER_STATUS[w.status] ?? { label: String(w.status), tone: 'mute' as const };
                    return (
                      <tr key={w.id} className="hover:bg-slate-50 dark:hover:bg-slate-800/30">
                        <td className="px-4 py-2 w-20">
                          <div className="w-16 h-12 rounded bg-slate-100 dark:bg-slate-800 overflow-hidden">
                            {w.thumb_url && <img src={w.thumb_url} alt="" className="w-full h-full object-cover" />}
                          </div>
                        </td>
                        <td className="px-4 py-2 max-w-xs">
                          <Link to={`/wallpaper/${w.slug}`} className="block font-medium truncate hover:underline">{w.title || `#${w.id}`}</Link>
                          <div className="text-xs text-slate-400 truncate">@{w.uploader_username || '?'} · {w.width}×{w.height}{w.is_dynamic ? ` · ${w.dynamic_type}` : ''}</div>
                        </td>
                        <td className="px-4 py-2 text-slate-500">{w.category_name || '-'}</td>
                        <td className="px-4 py-2"><StatusBadge label={st.label} tone={st.tone} /></td>
                        <td className="px-4 py-2 text-right text-xs text-slate-500 whitespace-nowrap">
                          <div>{fmtNumber(w.view_count)} 浏览</div>
                          <div>{fmtNumber(w.like_count)} 赞 · {fmtNumber(w.download_count)} 下载</div>
                        </td>
                        <td className="px-4 py-2 text-xs text-slate-500 whitespace-nowrap">{fmtDate(w.created_at)}</td>
                        <td className="px-4 py-2 text-right whitespace-nowrap">
                          <button onClick={() => setEditing(w)} className="text-xs text-purple-600 hover:underline mr-3">编辑</button>
                          {/* Reprocess: re-queue the wallpaper through the
                              image worker. Available for failed (2) and
                              stuck processing (0) rows. */}
                          {(w.status === 0 || w.status === 2) && (
                            <button onClick={() => onReprocess(w.id)} className="text-xs text-amber-600 hover:underline mr-3">重新处理</button>
                          )}
                          {w.status === 1 && (
                            <button onClick={() => onDelete(w.id)} className="text-xs text-rose-500 hover:underline">下架</button>
                          )}
                          {w.status === 3 && (
                            <button onClick={() => onChangeStatus(w.id, 1)} className="text-xs text-emerald-600 hover:underline">恢复</button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
          <Pagination page={page} limit={limit} total={total} onChange={setPage} />
        </Card>
      </div>

      {editing && (
        <EditModal
          wallpaper={editing}
          categories={categories}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); fetchList(); }}
        />
      )}
    </>
  );
}

function EditModal({
  wallpaper,
  categories,
  onClose,
  onSaved,
}: {
  wallpaper: AdminWallpaperRow;
  categories: Category[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [title, setTitle] = useState(wallpaper.title);
  const [description, setDescription] = useState(wallpaper.description);
  const [categoryId, setCategoryId] = useState(wallpaper.category_id);
  const [status, setStatus] = useState(wallpaper.status);
  const [saving, setSaving] = useState(false);

  const save = () => {
    setSaving(true);
    admin
      .updateAdminWallpaper(wallpaper.id, { title, description, category_id: categoryId, status })
      .then(() => { toast.success('已保存'); onSaved(); })
      .catch((e) => toast.error(e?.response?.data?.message || '保存失败'))
      .finally(() => setSaving(false));
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4">
      <div className="bg-white dark:bg-slate-900 rounded-xl w-full max-w-lg overflow-hidden">
        <div className="px-5 py-3 border-b border-slate-200 dark:border-slate-800 flex justify-between items-center">
          <h3 className="font-semibold">编辑壁纸 #{wallpaper.id}</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-700">×</button>
        </div>
        <div className="p-5 space-y-3">
          <label className="block text-sm">
            <div className="text-slate-500 mb-1">标题</div>
            <input value={title} onChange={(e) => setTitle(e.target.value)} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
          </label>
          <label className="block text-sm">
            <div className="text-slate-500 mb-1">描述</div>
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block text-sm">
              <div className="text-slate-500 mb-1">分类</div>
              <select value={categoryId} onChange={(e) => setCategoryId(Number(e.target.value))} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950">
                <option value={0}>未分类</option>
                {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </label>
            <label className="block text-sm">
              <div className="text-slate-500 mb-1">状态</div>
              <select value={status} onChange={(e) => setStatus(Number(e.target.value))} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950">
                <option value={0}>处理中</option>
                <option value={1}>已发布</option>
                <option value={2}>处理失败</option>
                <option value={3}>已下架</option>
                <option value={4}>重复</option>
              </select>
            </label>
          </div>
        </div>
        <div className="px-5 py-3 border-t border-slate-200 dark:border-slate-800 flex justify-end gap-2">
          <button onClick={onClose} className="px-4 py-1.5 rounded text-sm text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800">取消</button>
          <button onClick={save} disabled={saving} className="px-4 py-1.5 rounded text-sm bg-purple-600 hover:bg-purple-700 text-white disabled:opacity-60">保存</button>
        </div>
      </div>
    </div>
  );
}
