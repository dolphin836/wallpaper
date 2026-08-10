import client from './client';
import type { ApiResponse, Wallpaper, Collection, UserListItem, Category } from '../types';

export interface AdminOverview {
  user_total: number;
  user_new_today: number;
  user_new_last_7_days: number;
  user_admins: number;
  wallpaper_total: number;
  wallpaper_pending: number;
  wallpaper_failed: number;
  wallpaper_removed: number;
  wallpaper_duplicate: number;
  wallpaper_today: number;
  collection_total: number;
  report_open: number;
  report_resolved: number;
  total_views: number;
  total_likes: number;
  total_favorites: number;
  total_downloads: number;
  total_coins_circled: number;

  // Marketing metrics. dau/wau/mau are distinct active user counts in
  // their respective rolling windows; stickiness_ratio is dau/mau as a
  // 0..1 float (display as a percent).
  dau: number;
  wau: number;
  mau: number;
  stickiness_ratio: number;
  uploads_last_7_days: number;
  downloads_last_7_days: number;
  retention_d30_cohort: number;
  retention_d30_active: number;
}

export interface DailyPoint { day: string; count: number }

export interface AdminSeries {
  users: DailyPoint[];
  wallpapers: DailyPoint[];
  events: DailyPoint[];
  days: number;
}

export interface CategoryCount { category_id: number; name: string; count: number }

export interface TopWallpaper {
  id: number;
  slug: string;
  title: string;
  thumb_url: string;
  view_count: number;
  like_count: number;
  download_count: number;
}

export interface AdminTops {
  top: TopWallpaper[];
  categories: CategoryCount[];
}

export interface AdminWallpaperRow extends Wallpaper {
  uploader_username: string;
  category_name: string;
}

export interface AdminWallpaperTrafficRow {
  id: number;
  wallpaper_id: number;
  event_type: 'view' | 'like' | 'favorite' | 'download' | string;
  user_id: number;
  client: string;
  ip: string;
  created_at: string;
  username: string;
  nickname: string;
  avatar_url: string;
  email: string;
}

export interface AdminWallpaperTrafficSummary {
  event_type: string;
  count: number;
}

export interface AdminLoginLogRow {
  id: number;
  user_id: number;
  client: string;
  ip: string;
  user_agent: string;
  country: string;
  created_at: string;
  username: string;
  nickname: string;
  avatar_url: string;
  email: string;
}

export interface AdminCollectionRow extends Collection {
  owner_username: string;
}
export interface AdminCollectionDetail extends AdminCollectionRow {
  wallpapers: Wallpaper[];
}

export interface AdminReportRow {
  id: number;
  wallpaper_id: number;
  reporter_user_id: number;
  reason: string;
  note: string;
  status: number;
  created_at: string;
  reporter_username: string;
  wallpaper_slug: string;
  wallpaper_title: string;
  wallpaper_thumb: string;
  wallpaper_status: number;
}

export interface WorkerJob {
  id: number;
  worker: string;
  topic: string;
  ref_id: number;
  status: string;
  message: string;
  started_at: string;
  finished_at?: string | null;
  duration_ms: number;
}

export interface WorkerSummaryRow {
  worker: string;
  running: number;
  done_last_hour: number;
  failed_last_day: number;
  avg_ms_last_day: number;
}

export type PaginatedAdmin<T> = { items: T[]; total: number; page: number; limit: number };

export const getOverview = () => client.get<ApiResponse<AdminOverview>>('/admin/overview');
export const getSeries = (days = 30) => client.get<ApiResponse<AdminSeries>>('/admin/series', { params: { days } });
export const getTops = (by = 'views', limit = 10) => client.get<ApiResponse<AdminTops>>('/admin/tops', { params: { by, limit } });

export const listAdminWallpapers = (params: {
  page?: number; limit?: number; search?: string;
  status?: number; category_id?: number; user_id?: number; sort?: string;
  wallpaper_type?: '' | 'ai' | 'heic' | 'video' | 'image';
  quality_flag?: '' | 'unassessed' | 'flagged' | 'weekly_eligible' | string;
}) => client.get<ApiResponse<PaginatedAdmin<AdminWallpaperRow>>>('/admin/wallpapers', { params });

export const getAdminWallpaperTraffic = (id: number, params: {
  page?: number; limit?: number; event_type?: string;
}) => client.get<ApiResponse<PaginatedAdmin<AdminWallpaperTrafficRow> & { summary: AdminWallpaperTrafficSummary[] }>>(
  `/admin/wallpapers/${id}/traffic`,
  { params },
);

export const updateAdminWallpaper = (id: number, data: {
  title?: string; description?: string; category_id?: number; status?: number; is_ai_generated?: boolean;
}) => client.put<ApiResponse<null>>(`/admin/wallpapers/${id}`, data);

export const deleteAdminWallpaper = (id: number) =>
  client.delete<ApiResponse<null>>(`/admin/wallpapers/${id}`);

// Physically removes the wallpaper row, all its children, and the MinIO
// objects. Backend rejects this unless the row is in status=removed (3),
// duplicate (4) or rejected (6).
export const hardDeleteAdminWallpaper = (id: number) =>
  client.delete<ApiResponse<null>>(`/admin/wallpapers/${id}/hard`);

// One moderation action applied to up to 100 ids; each id succeeds or
// fails independently and the response reports both buckets.
export type AdminBatchAction = 'delete' | 'hard_delete' | 'approve_review' | 'reject_review';
export interface AdminBatchResult {
  succeeded: number[];
  failed: { id: number; error: string }[];
}
export const batchAdminWallpapers = (ids: number[], action: AdminBatchAction, reason?: string) =>
  client.post<ApiResponse<AdminBatchResult>>('/admin/wallpapers/batch', { ids, action, reason });

export const reprocessAdminWallpaper = (id: number) =>
  client.post<ApiResponse<null>>(`/admin/wallpapers/${id}/reprocess`);

// Clears a flagged wallpaper's quality_flag back to 'ok' and triggers a
// reprocess so device variants (which qcheck dropped when it first
// flagged the row) get regenerated.
export const approveAdminWallpaperQuality = (id: number) =>
  client.post<ApiResponse<null>>(`/admin/wallpapers/${id}/approve-quality`);

// Approve / reject for PendingReview rows. The dedicated review-queue
// page was removed — admins use these from inline buttons on the main
// /admin/wallpapers list (filter by status=5 to drain the queue).
export const approveAdminReview = (id: number) =>
  client.post<ApiResponse<null>>(`/admin/wallpapers/${id}/approve-review`);

export const rejectAdminReview = (id: number, reason: string) =>
  client.post<ApiResponse<null>>(`/admin/wallpapers/${id}/reject-review`, { reason });

export const listAdminCollections = (params: {
  page?: number; limit?: number; search?: string; is_public?: boolean; kind?: number; sort?: string;
}) => client.get<ApiResponse<PaginatedAdmin<AdminCollectionRow>>>('/admin/collections', { params });

export const getAdminCollection = (id: number) =>
  client.get<ApiResponse<AdminCollectionDetail>>(`/admin/collections/${id}`);

export const createAdminCollection = (data: {
  title: string; description?: string; is_public?: boolean; kind?: number; year?: number; week?: number;
  accent_color?: string; wallpaper_ids?: number[];
}) => client.post<ApiResponse<Collection>>('/admin/collections', data);

export const updateAdminCollection = (id: number, data: {
  title?: string; description?: string; is_public?: boolean; kind?: number; year?: number; week?: number;
  accent_color?: string; wallpaper_ids?: number[];
}) => client.put<ApiResponse<null>>(`/admin/collections/${id}`, data);

export const deleteAdminCollection = (id: number) =>
  client.delete<ApiResponse<null>>(`/admin/collections/${id}`);

export const listAdminUsers = (params: {
  page?: number; limit?: number; search?: string; status?: number;
}) => client.get<ApiResponse<PaginatedAdmin<UserListItem & { is_admin: boolean; email: string }>>>('/admin/users', { params });

export const listAdminLoginLogs = (params: {
  page?: number; limit?: number; client?: string;
}) => client.get<ApiResponse<PaginatedAdmin<AdminLoginLogRow>>>('/admin/login-logs', { params });

export const setAdminUserAdmin = (id: number, isAdmin: boolean) =>
  client.put<ApiResponse<null>>(`/admin/users/${id}/admin`, { is_admin: isAdmin });

export const setAdminUserStatus = (id: number, status: number) =>
  client.put<ApiResponse<null>>(`/admin/users/${id}/status`, { status });

export const grantAdminUserCoins = (id: number, data: { amount: number; description?: string }) =>
  client.post<ApiResponse<{ user_id: number; amount: number; balance: number }>>(
    `/admin/users/${id}/coins/grant`,
    data,
  );

export const listAdminReports = (params: {
  page?: number; limit?: number; status?: number;
}) => client.get<ApiResponse<PaginatedAdmin<AdminReportRow>>>('/admin/reports', { params });

export const resolveAdminReport = (id: number, data: {
  status: number; remove_wallpaper?: boolean; resolve_all_for_target?: boolean;
}) => client.put<ApiResponse<null>>(`/admin/reports/${id}/resolve`, data);

export const getWorkerSummary = () =>
  client.get<ApiResponse<{ summary: WorkerSummaryRow[] }>>('/admin/workers/summary');

export const getWorkerJobs = (params: {
  worker?: string; status?: string; limit?: number; cursor?: number;
}) => client.get<ApiResponse<{ items: WorkerJob[] }>>('/admin/workers/jobs', { params });

export interface BucketUsage {
  originals_bytes: number; originals_count: number;
  thumbs_bytes: number; thumbs_count: number;
  previews_bytes: number; previews_count: number;
  variants_bytes: number; variants_count: number;
  frames_bytes: number; frames_count: number;
  other_bytes: number; other_count: number;
  total_bytes: number; total_count: number;
}
export interface DiskUsage {
  total_bytes: number;
  free_bytes: number;
  used_bytes: number;
}
export interface StorageResp {
  usage: BucketUsage;
  disk: DiskUsage | null;
  cached: boolean;
  age_ms: number;
  refreshed: string;
}

export const getStorage = (refresh = false) =>
  client.get<ApiResponse<StorageResp>>('/admin/storage', {
    params: refresh ? { refresh: 1 } : undefined,
    // The first uncached call walks the whole bucket (~2s today, can grow).
    timeout: 30_000,
  });

export const listAdminCategories = () =>
  client.get<ApiResponse<Category[]>>('/categories');

// ─── Analytics ───────────────────────────────────────────────────────
// Powered by the analytics_events table — the admin Analytics page reads
// this one bundle and renders every section without further round-trips.
export interface AnalyticsDay {
  day: string;       // ISO date, UTC
  page_views: number;
  sessions: number;
  unique_ips: number;
  wallpaper_views: number;
  api_requests: number;
  api_errors: number;
  avg_api_latency_ms: number;
  p95_api_latency_ms: number;
}
export interface AnalyticsTotals {
  page_views: number;
  sessions: number;
  unique_ips: number;
  wallpaper_views: number;
  api_requests: number;
  api_errors: number;
  avg_api_latency_ms: number;
  p95_api_latency_ms: number;
}
export interface AnalyticsLabel { label: string; count: number }
export interface AnalyticsSource { source: string; count: number; hosts?: string[] }

export interface AnalyticsOverview {
  days: number;
  timezone: string;
  daily: AnalyticsDay[];
  totals: AnalyticsTotals;
  previous: AnalyticsTotals;
  countries: AnalyticsLabel[];
  sources: AnalyticsSource[];
  paths: AnalyticsLabel[];
  clients: AnalyticsLabel[];
  client_downloads: AnalyticsLabel[];
}

export interface AnalyticsPageViewDay {
  day: string;
  path: string;
  client: string;
  views: number;
  sessions: number;
  unique_users: number;
  unique_ips: number;
}

export interface AnalyticsWallpaperViewDay {
  day: string;
  wallpaper_id: number;
  slug: string;
  title: string;
  thumb_url: string;
  client: string;
  views: number;
  sessions: number;
  unique_users: number;
  unique_ips: number;
}

export interface AnalyticsAPIRequestDay {
  day: string;
  method: string;
  route: string;
  client: string;
  requests: number;
  successes: number;
  client_errors: number;
  server_errors: number;
  sessions: number;
  unique_users: number;
  unique_ips: number;
  avg_latency_ms: number;
  p95_latency_ms: number;
  max_latency_ms: number;
  request_bytes: number;
  response_bytes: number;
}

export type AnalyticsDetailPage<T> = PaginatedAdmin<T> & { days: number; timezone: string };

export interface AnalyticsDetailParams {
  days: number;
  timezone: string;
  page: number;
  limit?: number;
  client?: string;
  query?: string;
}

export const getAnalytics = (days: number, timezone: string) =>
  client.get<ApiResponse<AnalyticsOverview>>('/admin/analytics', { params: { days, timezone } });

export const getAnalyticsPages = (params: AnalyticsDetailParams) =>
  client.get<ApiResponse<AnalyticsDetailPage<AnalyticsPageViewDay>>>('/admin/analytics/pages', { params });

export const getAnalyticsWallpapers = (params: AnalyticsDetailParams) =>
  client.get<ApiResponse<AnalyticsDetailPage<AnalyticsWallpaperViewDay>>>('/admin/analytics/wallpapers', { params });

export const getAnalyticsRequests = (params: AnalyticsDetailParams) =>
  client.get<ApiResponse<AnalyticsDetailPage<AnalyticsAPIRequestDay>>>('/admin/analytics/requests', { params });

// ─── LLM Cost (local llm_usage ledger) ───────────────────────────────
// Backed by the llm_usage table: pkg/llm.Client writes one row per
// Anthropic API call with computed USD cost. The dashboard rolls those
// up — no Admin API key required.
export interface LLMDailyCost { day: string; usd: number }
export interface LLMPurposeCost { label: string; usd: number; count: number }
export interface LLMCostSummary {
  last_7d_usd: number;
  last_30d_usd: number;
  today_usd: number;
  total_calls: number;
  by_purpose: LLMPurposeCost[];
  daily: LLMDailyCost[];
  updated_at: string;
}
export interface LLMCostResp {
  configured: boolean;
  message?: string;
  summary?: LLMCostSummary;
}
export const getLLMCost = () =>
  client.get<ApiResponse<LLMCostResp>>('/admin/llm-cost');

// ─── Weekly picks ─────────────────────────────────────────────────────

export interface AdminWeekSummary {
  year: number;
  week: number;
  count: number;
  hero_thumb: string;
  hero_title: string;
  hero_wallpaper_id: number;
}
export interface AdminWeeklyPick extends Wallpaper {
  sort_order: number;
  is_hero: boolean;
}
export const adminListWeeklyPickWeeks = () =>
  client.get<ApiResponse<AdminWeekSummary[]>>('/admin/weekly-picks');

export const adminGetWeeklyPickWeek = (year: number, week: number) =>
  client.get<ApiResponse<{ year: number; week: number; picks: AdminWeeklyPick[] }>>(
    `/admin/weekly-picks/${year}/${week}`,
  );

export const adminSaveWeeklyPickWeek = (
  year: number,
  week: number,
  wallpaperIds: number[],
  heroWallpaperId: number,
) =>
  client.put<ApiResponse<{ ok: boolean }>>(
    `/admin/weekly-picks/${year}/${week}`,
    { wallpaper_ids: wallpaperIds, hero_wallpaper_id: heroWallpaperId },
  );

export const adminSetWeeklyPickHero = (year: number, week: number, wallpaperId: number) =>
  client.put<ApiResponse<{ ok: boolean }>>(
    `/admin/weekly-picks/${year}/${week}/hero`,
    { wallpaper_id: wallpaperId },
  );

export const adminDeleteWeeklyPickWeek = (year: number, week: number) =>
  client.delete<ApiResponse<{ ok: boolean }>>(`/admin/weekly-picks/${year}/${week}`);

export const adminAddWeeklyPick = (year: number, week: number, wallpaperId: number) =>
  client.post<ApiResponse<{ ok: boolean }>>(
    `/admin/weekly-picks/${year}/${week}/picks`,
    { wallpaper_id: wallpaperId },
  );

export const adminRemoveWeeklyPick = (year: number, week: number, wallpaperId: number) =>
  client.delete<ApiResponse<{ ok: boolean }>>(
    `/admin/weekly-picks/${year}/${week}/picks/${wallpaperId}`,
  );

// ─── Marketing integrations ─────────────────────────────────────────

export interface PinterestStatus {
  configured: boolean;
  connected: boolean;
  provider: string;
  account_id: string;
  account_name: string;
  scopes: string[];
  expires_at?: string | null;
  redirect_url: string;
}

export interface PinterestPinResult {
  wallpaper_id: number;
  board_id: string;
  board_name: string;
  pin_id: string;
  pin_url: string;
  already_posted: boolean;
}

export const getPinterestStatus = () =>
  client.get<ApiResponse<PinterestStatus>>('/admin/integrations/pinterest/status');

export const getPinterestAuthURL = () =>
  client.get<ApiResponse<{ auth_url: string }>>('/admin/integrations/pinterest/connect', {
    params: { format: 'json' },
  });

export const testPinterestPin = (data: { wallpaper_id?: number; force?: boolean }) =>
  client.post<ApiResponse<PinterestPinResult>>('/admin/integrations/pinterest/test-pin', data);

export interface RedditStatus {
  configured: boolean;
  connected: boolean;
  provider: string;
  account_id: string;
  account_name: string;
  scopes: string[];
  expires_at?: string | null;
  redirect_url: string;
  default_subreddit: string;
}

export interface RedditPostWallpaper {
  id: number;
  slug: string;
  title: string;
  thumb_url: string;
  preview_url: string;
  width: number;
  height: number;
}

export interface RedditCollectionSummary {
  id: number;
  slug: string;
  title: string;
  description: string;
  cover_url: string;
  wallpaper_count: number;
}

export interface RedditWeeklyPostResult {
  year: number;
  week: number;
  subreddit: string;
  post_id: string;
  post_url: string;
  already_posted: boolean;
}

export interface RedditWeeklyPreview {
  year: number;
  week: number;
  source: string;
  subreddit: string;
  title: string;
  text: string;
  collection?: RedditCollectionSummary;
  wallpapers: RedditPostWallpaper[];
  already_posted: boolean;
  existing_post?: RedditWeeklyPostResult;
}

export const getRedditStatus = () =>
  client.get<ApiResponse<RedditStatus>>('/admin/integrations/reddit/status');

export const getRedditAuthURL = () =>
  client.get<ApiResponse<{ auth_url: string }>>('/admin/integrations/reddit/connect', {
    params: { format: 'json' },
  });

export const getRedditWeeklyPreview = (params?: { year?: number; week?: number; subreddit?: string }) =>
  client.get<ApiResponse<RedditWeeklyPreview>>('/admin/integrations/reddit/weekly-preview', { params });

export const postRedditWeekly = (data: {
  year?: number;
  week?: number;
  subreddit: string;
  title: string;
  text: string;
  force?: boolean;
}) => client.post<ApiResponse<RedditWeeklyPostResult>>('/admin/integrations/reddit/weekly-post', data);
