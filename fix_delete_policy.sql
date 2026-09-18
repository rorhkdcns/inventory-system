-- 출고 시 수량 0 자동삭제가 실패하는 경우를 대비한 점검/보정 스크립트
-- (RLS는 켜져 있는데 DELETE를 허용하는 정책이 없으면, 삭제 요청이 오류 없이
--  "0건 삭제"로 조용히 끝나버립니다.)

-- 1) 현재 inventory_items에 걸려 있는 정책을 확인합니다.
--    cmd 컬럼에 DELETE(또는 ALL)가 없다면 그게 원인입니다.
select schemaname, tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'inventory_items';

-- 2) anon 역할에게 DELETE 권한을 명시적으로 보장합니다.
--    이미 있어도 안전하게 다시 실행할 수 있습니다(기존 정책 삭제 후 재생성).
alter table inventory_items enable row level security;

drop policy if exists "anon delete access" on inventory_items;
create policy "anon delete access" on inventory_items
  for delete to anon using (true);

-- 3) inventory_logs는 출고 기록(로그)이 남아야 하므로 삭제 정책을 걸지 않습니다.
--    (로그 삭제는 앱의 "로그 삭제" 버튼에서 이미 별도로 사용 중이므로 기존 정책 유지)
