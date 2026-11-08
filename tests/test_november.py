import os,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class November(unittest.TestCase):
 def test_cpu_statuses(self):
  with tempfile.TemporaryDirectory() as d:
   b=pathlib.Path(d)
   def mock(n,s):
    p=b/n;p.write_text('#!/bin/bash\n'+s);p.chmod(0o700)
   env={**os.environ,'PATH':str(b)+':'+os.environ['PATH']}
   mock('vmstat',"echo '0 0 0 0 0 0 0 0 0 0 0 0 0 0 10'\n")
   mock('free',"printf 'Mem: 1000 100 0 0 0 900\\n'\n")
   def run(): return subprocess.run(['bash',str(ROOT/'scripts/monitoring/cpu_memory_monitor')],env=env,capture_output=True,timeout=5)
   self.assertEqual(run().returncode,1)
   mock('vmstat',"echo malformed\n");self.assertEqual(run().returncode,3)
   mock('vmstat',"exit 1\n");self.assertEqual(run().returncode,3)
 def test_security_argument_checks(self):
  for args,code in [(['--help'],0),(['--scan-path'],2),(['--failed-login-count','x'],2)]:
   r=subprocess.run(['bash',str(ROOT/'scripts/audit/security-audit.sh'),*args],capture_output=True,timeout=5)
   self.assertEqual(r.returncode,code)
