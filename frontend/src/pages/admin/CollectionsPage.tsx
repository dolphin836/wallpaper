import { useEffect, useState, useCallback } from 'react';
import toast from 'react-hot-toast';
import { Link } from 'react-router-dom';
import * as admin from '../../api/admin';
import type { AdminCollectionRow } from '../../api/admin';
import {
  Card,
  PageHeader,
  Spinner,
  Empty,
  Pagination,
  fmtDate,
  StatusBadge,
} from './components';

export default function CollectionsPage() {
  const [items, setItems] = useState<AdminCollectionRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [limit] = useState(20);
  const [search, setSearch] = useState('');
  const [publicFilter, setPublicFilter] = useState<'' | 'true' | 'false'>('');
  const [sort, setSort] = useState('newest');
  const [loading, setLoading] = useState(false);
  const [editing, setEditing] = useState<AdminCollectionRow | null>(null);

  const fetchList = useCallback(() => {
    setLoading(true);
    admin
      .listAdminCollections({
        page,
        limit,
        search: search || undefined,
        is_public: publicFilter === '' ? undefined : publicFilter === 'true',
        sort,
      })
      .then((r) => {
        setItems(r.data.data.items);
        setTotal(r.data.data.total);
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载失败'))
      .finally(() => setLoading(false));
  }, [page, limit, search, publicFilter, sort]);

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
      <PageHeader title="合集管理" subtitle={`共 ${total} 个`} />
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
              <option value="">全部</option>
              <option value="true">公开</option>
              <option value="false">私密</option>
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

      {editing && (
        <EditModal
          collection={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); fetchList(); }}
        />
      )}
    </>
  );
}

function EditModal({
  collection,
  onClose,
  onSaved,
}: {
  collection: AdminCollectionRow;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [title, setTitle] = useState(collection.title);
  const [description, setDescription] = useState(collection.description);
  const [isPublic, setIsPublic] = useState(collection.is_public);
  const [saving, setSaving] = useState(false);

  const save = () => {
    setSaving(true);
    admin.updateAdminCollection(collection.id, { title, description, is_public: isPublic })
      .then(() => { toast.success('已保存'); onSaved(); })
      .catch((e) => toast.error(e?.response?.data?.message || '保存失败'))
      .finally(() => setSaving(false));
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4">
      <div className="bg-white dark:bg-slate-900 rounded-xl w-full max-w-lg overflow-hidden">
        <div className="px-5 py-3 border-b border-slate-200 dark:border-slate-800 flex justify-between items-center">
          <h3 className="font-semibold">编辑合集 #{collection.id}</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-700">×</button>
        </div>
        <div className="p-5 space-y-3">
          <label className="block text-sm">
            <div className="text-slate-500 mb-1">标题</div>
            <input value={title} onChange={(e) => setTitle(e.target.value)} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
          </label>
          <label className="block text-sm">
            <div className="text-slate-500 mb-1">描述</div>
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={4} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isPublic} onChange={(e) => setIsPublic(e.target.checked)} />
            公开（其他用户可以看到）
          </label>
        </div>
        <div className="px-5 py-3 border-t border-slate-200 dark:border-slate-800 flex justify-end gap-2">
          <button onClick={onClose} className="px-4 py-1.5 rounded text-sm text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800">取消</button>
          <button onClick={save} disabled={saving} className="px-4 py-1.5 rounded text-sm bg-purple-600 hover:bg-purple-700 text-white disabled:opacity-60">保存</button>
        </div>
      </div>
    </div>
  );
}
