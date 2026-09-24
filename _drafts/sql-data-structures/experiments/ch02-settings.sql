-- 第2章 実験用の設定を序章に揃える（設定後は psql を \q で抜けて再接続する）
ALTER DATABASE reading_log SET max_parallel_workers_per_gather = 0;
ALTER DATABASE reading_log SET jit = off;
ALTER DATABASE reading_log SET work_mem = '64MB';
