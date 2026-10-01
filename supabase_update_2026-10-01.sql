-- =====================================================================
--  재고관리 업데이트용 SQL  (2026-10-01)
--  하는 일 2가지
--   (1) 수량(qty)을 소수점 둘째 자리까지 저장할 수 있게 타입 변경
--   (2) 출고표 저장용 새 테이블 shipping_sheet 생성 (+ RLS, Realtime)
--
--  사용법: 이 파일 내용을 전체 복사해서 Supabase SQL Editor 에 붙여넣고
--          "Run" 을 한 번만 누르면 됩니다. (여러 번 눌러도 안전합니다)
--  기존 데이터는 지워지지 않습니다.
-- =====================================================================


-- =====================================================================
--  1) 수량 컬럼을 정수(int) -> 소수(numeric) 으로 변경
--     numeric(12,2) = 전체 12자리, 소수점 아래 2자리  (예: 24.00, 3.50)
--     기존 값 24 는 24.00 으로 그대로 보존됩니다.
-- =====================================================================
alter table inventory_items
  alter column qty type numeric(12,2) using qty::numeric(12,2);

alter table inventory_items
  alter column qty set default 0;

alter table inventory_logs
  alter column qty type numeric(12,2) using qty::numeric(12,2);


-- =====================================================================
--  2) 출고표 테이블 생성
--     PC와 휴대폰 어디서 봐도 같은 내용이 보이도록 Supabase에 저장합니다.
-- =====================================================================
create table if not exists shipping_sheet (
  id bigint generated always as identity primary key,
  col text not null,              -- 열 (A / B / C)
  can int not null,               -- 칸 번호
  floor int not null,             -- 층
  name text not null,             -- 상품명
  qty numeric(12,2) not null,     -- 수량 (소수점 두 자리)
  date date,                      -- 출고표에 올린 날짜
  created_at timestamptz default now()
);

-- 이미 테이블이 있었던 경우를 대비해 qty 타입을 한 번 더 맞춰 줍니다.
alter table shipping_sheet
  alter column qty type numeric(12,2) using qty::numeric(12,2);

-- 위치순(열 -> 칸 -> 층) 조회를 빠르게 하기 위한 인덱스
create index if not exists shipping_sheet_loc_idx
  on shipping_sheet (col, can, floor, id);


-- =====================================================================
--  3) RLS (보안 정책) - 기존 테이블들과 똑같이 anon 키에 전체 권한 부여
-- =====================================================================
alter table shipping_sheet enable row level security;

drop policy if exists "anon full access" on shipping_sheet;
create policy "anon full access" on shipping_sheet
  for all to anon using (true) with check (true);

-- 출고표 행 삭제 / 전체 비우기 기능을 위해 delete 권한도 명시적으로 보장
drop policy if exists "anon delete access" on shipping_sheet;
create policy "anon delete access" on shipping_sheet
  for delete to anon using (true);


-- =====================================================================
--  4) Realtime 활성화 (다른 기기에서 바꾸면 바로 반영되도록)
--     이미 추가되어 있으면 에러가 나므로, 에러를 무시하도록 감쌌습니다.
-- =====================================================================
do $$
begin
  alter publication supabase_realtime add table shipping_sheet;
exception
  when duplicate_object then null;   -- 이미 추가됨
  when others then null;
end $$;


-- =====================================================================
--  5) 확인용 (실행하면 결과가 표 형태로 나옵니다)
--     qty 의 data_type 이 numeric 으로 나오면 성공입니다.
-- =====================================================================
select table_name as "테이블", column_name as "컬럼", data_type as "타입",
       numeric_precision as "전체자리", numeric_scale as "소수자리"
from information_schema.columns
where table_schema = 'public'
  and table_name in ('inventory_items', 'inventory_logs', 'shipping_sheet')
  and column_name = 'qty'
order by table_name;
