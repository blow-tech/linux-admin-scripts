"""Disposable inputs and mocked collectors only; no operational targets."""
import gzip
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base=Path(self.tmp.name); self.bin=self.base/'bin'; self.bin.mkdir()
        self.env=dict(os.environ,PATH=str(self.bin)+os.pathsep+os.environ['PATH'])
    def mock(self,name,body):
        p=self.bin/name;p.write_text('#!/usr/bin/env bash\n'+body+'\n');p.chmod(0o755)
    def run_script(self,path,*args):
        return subprocess.run(['bash',str(ROOT/'scripts'/path),*map(str,args)],env=self.env,text=True,capture_output=True,timeout=15)
    def healthy(self):
        self.mock('nproc','echo 2');self.mock('cut','echo 0.10')
        self.mock('free',"printf 'Mem: 1000 100 900 0 0 900\\nSwap: 0 0 0\\n'")
        self.mock('df',"printf 'Filesystem Size Used Avail Use%% Mounted on\\n/dev/fake 100G 1G 99G 1%% /data with spaces\\n'")
    def test_health_healthy_and_spaces(self):
        self.healthy();p=self.run_script('monitoring/healthcare_check.sh')
        self.assertEqual(p.returncode,0,p.stderr);self.assertIn('/data with spaces',p.stdout)
    def test_health_failed_collectors(self):
        for collector in ['nproc','free','df']:
            with self.subTest(collector=collector):
                self.healthy();self.mock(collector,'exit 1');p=self.run_script('monitoring/healthcare_check.sh')
                self.assertEqual(p.returncode,3,p.stderr);self.assertNotIn('All checks passed',p.stdout)
    def test_health_malformed_or_empty_evidence(self):
        for collector,body in [('df','echo "Filesystem Size Used Avail Use% Mounted on"'),('df','echo invalid'),('free','echo invalid'),('nproc','echo 0')]:
            with self.subTest(collector=collector,body=body):
                self.healthy();self.mock(collector,body)
                self.assertEqual(self.run_script('monitoring/healthcare_check.sh').returncode,3)
    def test_health_high_disk(self):
        self.healthy();self.mock('df',"printf 'Filesystem Size Used Avail Use%% Mounted on\\n/dev/fake 100G 99G 1G 99%% /data\\n'")
        self.assertEqual(self.run_script('monitoring/healthcare_check.sh').returncode,1)
    def test_health_memory_collected_once(self):
        self.healthy();counter=self.base/'calls';self.env['CALLS']=str(counter)
        self.mock('free',"echo called >> \"$CALLS\"; printf 'Mem: 1000 100 900 0 0 900\\nSwap: 0 0 0\\n'")
        self.assertEqual(self.run_script('monitoring/healthcare_check.sh').returncode,0)
        self.assertEqual(counter.read_text().splitlines(),['called'])
    def test_health_usage(self):
        self.healthy()
        self.assertEqual(self.run_script('monitoring/healthcare_check.sh','--disk-threshold','08').returncode,0)
        for args in [('--disk-threshold',),('--mem-threshold','-1'),('--cpu-threshold','nan'),('--disk-threshold','101')]:
            self.assertEqual(self.run_script('monitoring/healthcare_check.sh',*args).returncode,2)
    def test_backup_age_boundary_and_future(self):
        backup=self.base/'backup.bin';backup.write_text('backup');now=1800000000;self.mock('date',f'echo {now}')
        for age,expected in [(86400,0),(86401,1),(88200,1),(-10,3)]:
            os.utime(backup,(now-age,now-age));p=self.run_script('backup/backup_verify.sh','-d',self.base,'-m','24')
            self.assertEqual(p.returncode,expected,p.stdout+p.stderr)
    def test_backup_newline_filename(self):
        (self.base/'backup\nsecond line.bin').write_text('backup')
        self.assertEqual(self.run_script('backup/backup_verify.sh','-d',self.base).returncode,0)
    def test_backup_collection_failure_and_unsupported_integrity(self):
        (self.base/'backup.bin').write_text('backup')
        p=self.run_script('backup/backup_verify.sh','-d',self.base,'--verify-archive')
        self.assertEqual(p.returncode,3);self.assertNotIn('verification passed',p.stdout)
        self.mock('find','exit 1');self.assertEqual(self.run_script('backup/backup_verify.sh','-d',self.base).returncode,3)
    def test_backup_valid_and_corrupt_archive(self):
        (self.base/'source').write_text('preserved');archive=self.base/'backup.tar.gz'
        subprocess.run(['tar','-czf',str(archive),'-C',str(self.base),'source'],check=True)
        args=('-d',self.base,'--pattern','*.tar.gz','--verify-archive')
        self.assertEqual(self.run_script('backup/backup_verify.sh',*args).returncode,0)
        archive.write_text('corrupt');self.assertEqual(self.run_script('backup/backup_verify.sh',*args).returncode,1)
    def test_backup_usage_and_empty_directory(self):
        for args in [('-d',),('-d',self.base,'-m','x'),('-d',self.base,'-m','-1')]:
            self.assertEqual(self.run_script('backup/backup_verify.sh',*args).returncode,2)
        self.assertEqual(self.run_script('backup/backup_verify.sh','-d',self.base).returncode,1)
    def test_log_invalid_regex_and_no_matches(self):
        log=self.base/'app.log';log.write_text('normal operation\n')
        p=self.run_script('monitoring/log_summary.sh','-f',log,'-p','[')
        self.assertEqual(p.returncode,2);self.assertNotIn('No matches',p.stdout)
        p=self.run_script('monitoring/log_summary.sh','-f',log)
        self.assertEqual(p.returncode,0,p.stderr);self.assertIn('No matches',p.stdout)
    def test_log_rotations_and_corrupt_gzip(self):
        log=self.base/'app.log';log.write_text('Jan 01 00:00 error one\n')
        (self.base/'app.log.1').write_text('Jan 01 00:00 error two\n')
        with gzip.open(self.base/'app.log.2.gz','wt') as f:f.write('Jan 01 00:00 error three\n')
        (self.base/'app.log.unrelated').write_text('error ignored\n')
        args=('-f',log,'--include-rotated');p=self.run_script('monitoring/log_summary.sh',*args)
        self.assertEqual(p.returncode,0,p.stderr);self.assertIn('Total matching lines: 3',p.stdout)
        (self.base/'app.log.2.gz').write_bytes(b'not gzip');p=self.run_script('monitoring/log_summary.sh',*args)
        self.assertEqual(p.returncode,3,p.stderr)
    def test_log_read_failure_or_timeout(self):
        log=self.base/'app.log';log.write_text('error\n')
        for status in [2,124]:
            self.mock('timeout',f'exit {status}');p=self.run_script('monitoring/log_summary.sh','-f',log)
            self.assertEqual(p.returncode,3);self.assertNotIn('No matches',p.stdout)
    def test_log_large_summary_no_sigpipe(self):
        log=self.base/'app.log'
        log.write_text(''.join('Jan 01 00:00 error '+chr(65+i//100)+chr(65+i%100)+'x'*80+'\n' for i in range(5000)))
        self.assertEqual(self.run_script('monitoring/log_summary.sh','-f',log,'-n','1').returncode,0)
    def test_help_and_missing_argument(self):
        for path in ['backup/backup_verify.sh','monitoring/log_summary.sh','monitoring/healthcare_check.sh']:
            self.assertEqual(self.run_script(path,'--help').returncode,0)
        self.assertEqual(self.run_script('monitoring/log_summary.sh','-f').returncode,2)
if __name__=='__main__':unittest.main()
