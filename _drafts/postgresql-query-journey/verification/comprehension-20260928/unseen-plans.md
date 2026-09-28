### 未知の計画 U1

```sql
SELECT id, title FROM books WHERE lower(title) = lower('実験用の本 42');
```

```
 Seq Scan on books  (cost=0.00..22353.00 rows=5000 width=30) (actual time=328.979..328.980 rows=1.00 loops=1)
   Filter: (lower(title) = '実験用の本 42'::text)
   Rows Removed by Filter: 999999
   Buffers: shared hit=381 read=6972
 Planning Time: 0.079 ms
 Execution Time: 329.004 ms
```

### 未知の計画 U2

```sql
SELECT b.id, b.title FROM books b WHERE EXISTS (SELECT 1 FROM reading_records r WHERE r.book_id = b.id AND r.finished_at >= '2026-09-20 23:00') ORDER BY b.id LIMIT 10;
```

```
 Limit  (cost=275.73..396.74 rows=10 width=30) (actual time=0.772..1.600 rows=10.00 loops=1)
   Buffers: shared hit=69
   ->  Merge Semi Join  (cost=275.73..36156.20 rows=2965 width=30) (actual time=0.772..1.598 rows=10.00 loops=1)
         Merge Cond: (b.id = r.book_id)
         Buffers: shared hit=69
         ->  Index Scan using books_pkey on books b  (cost=0.42..33336.43 rows=1000000 width=30) (actual time=0.008..0.624 rows=4788.00 loops=1)
               Index Searches: 1
               Buffers: shared hit=54
         ->  Sort  (cost=275.30..282.72 rows=2965 width=8) (actual time=0.703..0.705 rows=11.00 loops=1)
               Sort Key: r.book_id
               Sort Method: quicksort  Memory: 97kB
               Buffers: shared hit=15
               ->  Index Only Scan using reading_records_order_idx on reading_records r  (cost=0.43..104.31 rows=2965 width=8) (actual time=0.009..0.264 rows=2974.00 loops=1)
                     Index Cond: (finished_at >= '2026-09-20 23:00:00'::timestamp without time zone)
                     Heap Fetches: 0
                     Index Searches: 1
                     Buffers: shared hit=15
 Planning:
   Buffers: shared hit=14
 Planning Time: 0.099 ms
 Execution Time: 1.629 ms
```

### 未知の計画 U3

```sql
SELECT id, title FROM books ORDER BY id LIMIT 20 OFFSET 500000;
```

```
 Limit  (cost=16668.42..16669.09 rows=20 width=30) (actual time=71.634..71.638 rows=20.00 loops=1)
   Buffers: shared hit=5048
   ->  Index Scan using books_pkey on books  (cost=0.42..33336.43 rows=1000000 width=30) (actual time=0.013..53.359 rows=500020.00 loops=1)
         Index Searches: 1
         Buffers: shared hit=5048
 Planning Time: 0.085 ms
 Execution Time: 71.658 ms
```

### 未知の計画 U4

```sql
SELECT date_trunc('week', finished_at) AS w, count(*) FROM reading_records GROUP BY 1 ORDER BY 1;
```

```
 GroupAggregate  (cost=299817.69..339817.69 rows=2000000 width=16) (actual time=628.166..840.777 rows=4.00 loops=1)
   Group Key: (date_trunc('week'::text, finished_at))
   Buffers: shared hit=1103 read=9708, temp read=2941 written=2952
   ->  Sort  (cost=299817.69..304817.69 rows=2000000 width=8) (actual time=558.846..720.305 rows=2000000.00 loops=1)
         Sort Key: (date_trunc('week'::text, finished_at))
         Sort Method: external merge  Disk: 23528kB
         Buffers: shared hit=1103 read=9708, temp read=2941 written=2952
         ->  Seq Scan on reading_records  (cost=0.00..35811.00 rows=2000000 width=8) (actual time=0.178..376.665 rows=2000000.00 loops=1)
               Buffers: shared hit=1103 read=9708
 Planning Time: 0.079 ms
 Execution Time: 843.125 ms
```

### 未知の計画 U5

```sql
SELECT r.book_id, b.title, count(*) FROM reading_records r JOIN books b ON b.id = r.book_id WHERE b.title LIKE '実験用の本 12345%' GROUP BY r.book_id, b.title ORDER BY count(*) DESC;
```

```
 Sort  (cost=55934.56..55935.06 rows=200 width=38) (actual time=322.513..322.515 rows=6.00 loops=1)
   Sort Key: (count(*)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=5533 read=12631
   ->  GroupAggregate  (cost=55922.92..55926.92 rows=200 width=38) (actual time=322.500..322.505 rows=6.00 loops=1)
         Group Key: r.book_id, b.title
         Buffers: shared hit=5533 read=12631
         ->  Sort  (cost=55922.92..55923.42 rows=200 width=30) (actual time=322.491..322.493 rows=9.00 loops=1)
               Sort Key: r.book_id, b.title
               Sort Method: quicksort  Memory: 25kB
               Buffers: shared hit=5533 read=12631
               ->  Hash Join  (cost=19854.25..55915.27 rows=200 width=30) (actual time=124.727..322.461 rows=9.00 loops=1)
                     Hash Cond: (r.book_id = b.id)
                     Buffers: shared hit=5533 read=12631
                     ->  Seq Scan on reading_records r  (cost=0.00..30811.00 rows=2000000 width=8) (actual time=0.133..135.069 rows=2000000.00 loops=1)
                           Buffers: shared hit=1291 read=9520
                     ->  Hash  (cost=19853.00..19853.00 rows=100 width=30) (actual time=65.813..65.814 rows=11.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 9kB
                           Buffers: shared hit=4242 read=3111
                           ->  Seq Scan on books b  (cost=0.00..19853.00 rows=100 width=30) (actual time=0.857..65.798 rows=11.00 loops=1)
                                 Filter: (title ~~ '実験用の本 12345%'::text)
                                 Rows Removed by Filter: 999989
                                 Buffers: shared hit=4242 read=3111
 Planning:
   Buffers: shared hit=10
 Planning Time: 0.208 ms
 Execution Time: 322.563 ms
```

### 未知の計画 U6

```sql
SELECT count(*) FROM reading_records WHERE finished_at < '2026-09-01';
```

```
 Finalize Aggregate  (cost=16754.46..16754.47 rows=1 width=8) (actual time=29.020..30.860 rows=1.00 loops=1)
   Buffers: shared hit=2198
   ->  Gather  (cost=16754.24..16754.45 rows=2 width=8) (actual time=28.897..30.853 rows=3.00 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=2198
         ->  Partial Aggregate  (cost=15754.24..15754.25 rows=1 width=8) (actual time=27.103..27.103 rows=1.00 loops=3)
               Buffers: shared hit=2198
               ->  Parallel Index Only Scan using reading_records_order_idx on reading_records  (cost=0.43..15170.49 rows=233502 width=0) (actual time=0.029..18.161 rows=190476.67 loops=3)
                     Index Cond: (finished_at < '2026-09-01 00:00:00'::timestamp without time zone)
                     Heap Fetches: 51
                     Index Searches: 1
                     Buffers: shared hit=2198
 Planning Time: 0.077 ms
 Execution Time: 30.886 ms
```

