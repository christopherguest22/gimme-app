-- Gimme backend on Supabase (Postgres). Paste into the Supabase SQL editor.
-- Covers profiles, friends, rounds and live scores, round chat, the feed, and brand drops
-- with a server-side claim check so prizes can't be won from a couch or a fake GPS.

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null,
  avatar text not null default '🏌️',
  handicap numeric(3,1),
  share_location boolean not null default true
);

create table friendships (
  user_id uuid references profiles on delete cascade,
  friend_id uuid references profiles on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  primary key (user_id, friend_id)
);

create table courses (
  id text primary key,                    -- e.g. 'way/123456' from OpenStreetMap, or a provider id
  name text not null,
  data jsonb not null                     -- holes with tee, green front/center/back, hazards
);

create table rounds (
  id uuid primary key default gen_random_uuid(),
  course_id text references courses not null,
  created_by uuid references profiles not null default auth.uid(),
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

create table round_players (
  round_id uuid references rounds on delete cascade,
  player_id uuid references profiles,
  primary key (round_id, player_id)
);

create table scores (
  round_id uuid references rounds on delete cascade,
  player_id uuid references profiles,
  hole int not null check (hole between 1 and 36),
  strokes int not null check (strokes between 1 and 20),
  updated_at timestamptz not null default now(),
  primary key (round_id, player_id, hole)
);

create table chat_messages (
  id uuid primary key default gen_random_uuid(),
  round_id uuid references rounds on delete cascade,
  author_id uuid references profiles not null default auth.uid(),
  body text not null,
  sent_at timestamptz not null default now()
);

create table feed_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references profiles not null default auth.uid(),
  kind text not null check (kind in ('round', 'drop', 'note')),
  title text not null,
  detail text not null default '',
  posted_at timestamptz not null default now()
);

create table drops (
  id uuid primary key default gen_random_uuid(),
  brand text not null,
  prize text not null,
  detail text not null default '',
  course_id text references courses not null,
  hole int not null,
  lat double precision not null,
  lon double precision not null,
  radius_m double precision not null default 45,
  challenge text not null default 'none' check (challenge in ('none', 'parOrBetter', 'birdieOrBetter')),
  remaining int not null check (remaining >= 0),
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null
);

-- A verified visit to a drop's geofence during an active round. Challenge drops are
-- claimed after the hole is scored, so the visit is what proves the golfer was there.
create table drop_visits (
  drop_id uuid references drops on delete cascade,
  user_id uuid references profiles,
  round_id uuid references rounds,
  visited_at timestamptz not null default now(),
  primary key (drop_id, user_id)
);

create table drop_claims (
  drop_id uuid references drops on delete cascade,
  user_id uuid references profiles,
  round_id uuid references rounds,
  code text not null,
  claimed_at timestamptz not null default now(),
  redeemed_at timestamptz,
  primary key (drop_id, user_id)          -- one claim per golfer per drop
);

-- Distance in meters between two points (haversine), so no extension is required.
create function distance_m(lat1 float8, lon1 float8, lat2 float8, lon2 float8)
returns float8 language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)))
$$;

-- Called by the app when the golfer's GPS enters a drop geofence.
create function visit_drop(p_drop uuid, p_round uuid, p_lat float8, p_lon float8)
returns boolean language plpgsql security definer set search_path = public as $$
declare d drops; r rounds;
begin
  select * into d from drops where id = p_drop and now() between starts_at and expires_at;
  select * into r from rounds where id = p_round and finished_at is null
    and started_at > now() - interval '7 hours' and course_id = d.course_id;
  if d.id is null or r.id is null then raise exception 'Drops only unlock during an active round'; end if;
  if not exists (select 1 from round_players where round_id = p_round and player_id = auth.uid()) then
    raise exception 'Not in this round';
  end if;
  if distance_m(d.lat, d.lon, p_lat, p_lon) > d.radius_m then raise exception 'Outside the drop area'; end if;
  insert into drop_visits (drop_id, user_id, round_id) values (p_drop, auth.uid(), p_round)
    on conflict do nothing;
  return true;
end $$;

-- Claims the prize: needs a visit, stock left, no earlier claim, and the challenge met.
create function claim_drop(p_drop uuid, p_round uuid)
returns text language plpgsql security definer set search_path = public as $$
declare d drops; s int; par int; new_code text;
begin
  if not exists (select 1 from drop_visits where drop_id = p_drop and user_id = auth.uid() and round_id = p_round) then
    raise exception 'You need to be on the hole to claim this drop';
  end if;
  select * into d from drops where id = p_drop for update;
  if exists (select 1 from drop_claims where drop_id = p_drop and user_id = auth.uid()) then
    raise exception 'You already claimed this drop';
  end if;
  if d.remaining <= 0 then raise exception 'This drop is all gone'; end if;
  if d.challenge <> 'none' then
    select strokes into s from scores where round_id = p_round and player_id = auth.uid() and hole = d.hole;
    select (h->>'par')::int into par from courses c, jsonb_array_elements(c.data->'holes') h
      where c.id = d.course_id and (h->>'number')::int = d.hole;
    if s is null or par is null
       or (d.challenge = 'parOrBetter' and s > par)
       or (d.challenge = 'birdieOrBetter' and s >= par) then
      raise exception 'Challenge not met';
    end if;
  end if;
  new_code := 'GIMME-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
  insert into drop_claims (drop_id, user_id, round_id, code) values (p_drop, auth.uid(), p_round, new_code);
  update drops set remaining = remaining - 1 where id = p_drop;
  return new_code;
end $$;

-- Row-level security: golfers see their own data, their friends', and their rounds.
alter table profiles enable row level security;
alter table friendships enable row level security;
alter table rounds enable row level security;
alter table round_players enable row level security;
alter table scores enable row level security;
alter table chat_messages enable row level security;
alter table feed_posts enable row level security;
alter table drops enable row level security;
alter table drop_visits enable row level security;
alter table drop_claims enable row level security;
alter table courses enable row level security;

create function is_friend(other uuid) returns boolean language sql stable as $$
  select exists (select 1 from friendships
    where status = 'accepted' and ((user_id = auth.uid() and friend_id = other) or (friend_id = auth.uid() and user_id = other)))
$$;

create function in_round(r uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from round_players where round_id = r and player_id = auth.uid())
$$;

create policy "profiles readable" on profiles for select using (true);
create policy "own profile" on profiles for all using (id = auth.uid());
create policy "own friendships" on friendships for all using (auth.uid() in (user_id, friend_id));
create policy "courses readable" on courses for select using (true);
create policy "drops readable" on drops for select using (now() < expires_at);
create policy "rounds I play" on rounds for select using (in_round(id) or created_by = auth.uid());
create policy "start rounds" on rounds for insert with check (created_by = auth.uid());
create policy "finish my rounds" on rounds for update using (created_by = auth.uid());
create policy "round players" on round_players for select using (in_round(round_id));
create policy "add players" on round_players for insert
  with check (exists (select 1 from rounds where id = round_id and created_by = auth.uid()));
create policy "scores in my rounds" on scores for all using (in_round(round_id));
create policy "chat in my rounds" on chat_messages for select using (in_round(round_id));
create policy "post chat" on chat_messages for insert with check (in_round(round_id) and author_id = auth.uid());
create policy "feed from friends" on feed_posts for select using (author_id = auth.uid() or is_friend(author_id));
create policy "post to feed" on feed_posts for insert with check (author_id = auth.uid());
create policy "my claims" on drop_claims for select using (user_id = auth.uid());
-- drop_visits and drop_claims are only written through visit_drop() and claim_drop().

-- Live scorecard and chat: phones subscribe to these tables.
alter publication supabase_realtime add table scores, chat_messages;
