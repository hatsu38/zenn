"""本文の2接続実験を、専用の検証DBで確認する。"""
from pathlib import Path
import subprocess,re
base=Path(__file__).resolve().parent
root=base.parents[2]/'books'/'postgresql-structures-explain'
command=['docker','exec','-i','reading-log-lab','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','reading_map_reader_verify_20260922']
log=[]
class Session:
    def __init__(self,name):
        self.name=name
        self.proc=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
    def run(self,sql):
        self.proc.stdin.write(sql+'\n\\echo __READER_END__\n');self.proc.stdin.flush()
        lines=[]
        while True:
            line=self.proc.stdout.readline()
            if not line: raise RuntimeError('psql stopped: '+'\n'.join(lines))
            if line.strip()=='__READER_END__':break
            lines.append(line.rstrip())
        result='\n'.join(lines)
        log.append(f'[{self.name}] {sql}\n{result}\n')
        return result
    def close(self):
        self.proc.stdin.write('\\q\n');self.proc.stdin.flush();self.proc.wait(timeout=20)
a,b=Session('A'),Session('B')
try:
    a.run('BEGIN ISOLATION LEVEL REPEATABLE READ;')
    before=a.run('SELECT title FROM books WHERE id=42;')
    b.run("BEGIN; UPDATE books SET title='改訂版の本 42' WHERE id=42; COMMIT;")
    during=a.run('SELECT title FROM books WHERE id=42;')
    a.run('COMMIT;')
    after=a.run('SELECT title FROM books WHERE id=42;')
    assert before==during=='実験用の本 42'
    assert after=='改訂版の本 42'
    a.run("UPDATE books SET title='実験用の本 42' WHERE id=42;")
finally:
    a.close();b.close()
(base/'two-sessions.log').write_text('\n'.join(log))
text=(root/'11-mvcc-and-maintenance.md').read_text()
blocks=re.findall(r'```sql\n(.*?)```',text,re.S)
script='\\set ON_ERROR_STOP on\n\\pset pager off\n'+'\n'.join(blocks[-2:])
(base/'visibility.sql').write_text(script)
r=subprocess.run(command,input=script,capture_output=True,text=True)
(base/'visibility.log').write_text(r.stdout+r.stderr)
assert r.returncode==0,r.stderr
print('2接続のスナップショットと、更新/VACUUMのSQLを確認')
