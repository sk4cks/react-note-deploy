-- Flyway baseline 확인용 (DBeaver)
-- Auth Server 를 한 번 기동한 뒤 실행하세요.

SELECT installed_rank, version, type, description, success, installed_on
FROM note.flyway_schema_history
ORDER BY installed_rank;

-- 기대: version=1, type=BASELINE (DBeaver로 먼저 만든 DB)
--      또는 type=SQL (빈 DB 에서 V1 이 실행된 경우)
