-- 1) 테이블 생성
create table if not exists inventory_items (
  id bigint generated always as identity primary key,
  col text not null,
  can int not null,
  floor int not null,
  name text not null,
  qty int not null default 0,
  in_date date,
  created_at timestamptz default now()
);

create table if not exists inventory_logs (
  id bigint generated always as identity primary key,
  type text not null,
  col text not null,
  can int not null,
  floor int not null,
  name text not null,
  qty int not null,
  date date,
  created_at timestamptz default now()
);

-- 2) Realtime 활성화 (postgres_changes 구독을 위해 필요)
alter publication supabase_realtime add table inventory_items;
alter publication supabase_realtime add table inventory_logs;

-- 3) RLS 활성화 + anon 키로 전체 CRUD 허용
--    (로그인 기능이 없는 내부용 앱이라 anon에게 전체 권한을 줍니다.
--     외부에 공개되는 링크라면 나중에 인증을 추가하는 걸 권장합니다.)
alter table inventory_items enable row level security;
alter table inventory_logs enable row level security;

create policy "anon full access" on inventory_items
  for all to anon using (true) with check (true);

create policy "anon full access" on inventory_logs
  for all to anon using (true) with check (true);

-- 4) 상품 이동 기능용 컬럼 추가 (이동 전 위치 기록)
alter table inventory_logs add column if not exists from_col text;
alter table inventory_logs add column if not exists from_can int;
alter table inventory_logs add column if not exists from_floor int;
