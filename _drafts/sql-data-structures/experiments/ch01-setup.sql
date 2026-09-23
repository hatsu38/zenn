-- 第1章 実験環境の準備（読者が psql に貼り付ける SQL と同じ内容）
CREATE TABLE books (
  id bigint PRIMARY KEY,
  title text NOT NULL
);

CREATE TABLE reading_records (
  book_id bigint NOT NULL,
  finished_at timestamp NOT NULL
);

INSERT INTO books
SELECT n, '実験用の本 ' || n
FROM generate_series(1, 1000) AS n;

INSERT INTO reading_records
SELECT ((n::bigint * 7919) % 1000) + 1,
       timestamp '2026-08-24' + ((n::bigint * 104729) % 2419200) * interval '1 second'
FROM generate_series(1, 20000) AS n;

ANALYZE books;
ANALYZE reading_records;

SELECT count(*) AS book_count FROM books;
SELECT count(*) AS record_count FROM reading_records;
