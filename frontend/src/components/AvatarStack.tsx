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
            className="relative block rounded-full ring-2 ring-paper hover:z-10 hover:scale-110 transition-transform duration-150"
          >
            {u.avatar_url ? (
              <img
                src={u.avatar_url}
                alt=""
                loading="lazy"
                decoding="async"
                className="rounded-full object-cover"
                style={{ width: size, height: size }}
              />
            ) : (
              <div
                className="rounded-full bg-accent-soft text-accent-ink flex items-center justify-center font-semibold"
                style={{ width: size, height: size, fontSize: size * 0.4 }}
              >
                {(u.nickname || u.username).charAt(0).toUpperCase()}
              </div>
            )}
          </Link>
        ))}
        {overflow > 0 && (
          <div
            className="relative rounded-full bg-paper-2 text-muted border border-hair flex items-center justify-center font-semibold ring-2 ring-paper"
            style={{ width: size, height: size, fontSize: size * 0.36 }}
          >
            +{overflow > 99 ? '99' : overflow}
          </div>
        )}
      </div>
    </div>
  );
}
