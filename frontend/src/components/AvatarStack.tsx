import { Link } from 'react-router-dom';
import type { EngagementUser } from '../types';

interface Props {
  users: EngagementUser[];
  total: number;
  size?: number;
}

export default function AvatarStack({ users, total, size = 28 }: Props) {
  if (users.length === 0 && total === 0) return null;

  const overflow = total - users.length;

  return (
    <div className="flex items-center mt-2">
      <div className="flex -space-x-2">
        {users.map((u) => (
          <Link
            key={u.id}
            to={`/user/${u.username}`}
            title={u.nickname || u.username}
            className="relative block rounded-full ring-2 ring-white dark:ring-gray-800 hover:z-10 hover:scale-110 transition-transform duration-150"
          >
            {u.avatar_url ? (
              <img
                src={u.avatar_url}
                alt=""
                className="rounded-full object-cover"
                style={{ width: size, height: size }}
              />
            ) : (
              <div
                className="rounded-full bg-indigo-100 dark:bg-indigo-900/40 text-indigo-600 dark:text-indigo-400 flex items-center justify-center font-semibold"
                style={{ width: size, height: size, fontSize: size * 0.4 }}
              >
                {(u.nickname || u.username).charAt(0).toUpperCase()}
              </div>
            )}
          </Link>
        ))}
        {overflow > 0 && (
          <div
            className="relative rounded-full bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-300 flex items-center justify-center font-semibold ring-2 ring-white dark:ring-gray-800"
            style={{ width: size, height: size, fontSize: size * 0.36 }}
          >
            +{overflow > 99 ? '99' : overflow}
          </div>
        )}
      </div>
    </div>
  );
}
