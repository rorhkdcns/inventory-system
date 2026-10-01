-- =====================================================================
--  재고관리 업데이트용 SQL  (사진 → 출고표 자동 입력)
--  하는 일: 이름 짝 기억 테이블 name_alias 생성 (+ RLS, Realtime)
--    사장님 표 제품명(sheet_name) "칼라 컬러크림 (6/30) [120㎖]"
--      → 재고 상품명(item_name) "6/30"   처럼 짝을 기억해 두는 곳입니다.
--
--  사용법: 이 파일 내용을 전체 복사해서 Supabase SQL Editor 에 붙여넣고
--          "Run" 을 한 번만 누르면 됩니다. (여러 번 눌러도 안전합니다)
--  기존 데이터는 지워지지 않습니다.
-- =====================================================================


-- =====================================================================
--  1) 테이블 생성
--     같은 사장님 제품명은 한 번만 저장 (다시 고르면 새 짝으로 덮어씀)
-- =====================================================================
create table if not exists name_alias (
  id bigint generated always as identity primary key,
  sheet_name text not null unique,   -- 사장님 표의 제품명
  item_name text not null,           -- 재고 상품명
  created_at timestamptz default now()
);


-- =====================================================================
--  2) RLS (보안 정책) - 기존 테이블들과 똑같이 anon 키에 전체 권한 부여
-- =====================================================================
alter table name_alias enable row level security;

drop policy if exists "anon full access" on name_alias;
create policy "anon full access" on name_alias
  for all to anon using (true) with check (true);

drop policy if exists "anon delete access" on name_alias;
create policy "anon delete access" on name_alias
  for delete to anon using (true);


-- =====================================================================
--  3) Realtime 활성화 (이미 추가되어 있으면 에러를 무시)
-- =====================================================================
do $$
begin
  alter publication supabase_realtime add table name_alias;
exception
  when duplicate_object then null;
  when others then null;
end $$;


-- =====================================================================
--  4) 확인용: 실행 결과에 name_alias 컬럼 4개가 보이면 성공입니다.
-- =====================================================================
select column_name as "컬럼", data_type as "타입"
from information_schema.columns
where table_schema = 'public' and table_name = 'name_alias'
order by ordinal_position;
