-- 유통기한(exp_date) 필드 추가 마이그레이션
-- 기존 inventory_items 테이블/데이터에는 영향 없음 (nullable 컬럼 추가라 기존 행은 exp_date = NULL)
alter table inventory_items add column if not exists exp_date date;
