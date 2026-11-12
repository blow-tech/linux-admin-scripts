"""Local fixtures and mocked systemctl/df only. Never contacts a target or service."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SafetyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / 'bin'; self.bin.mkdir()
        self.env = dict(os.environ, ADMIN_SCRIPTS_STATE_DIR=str(self.base/'state'), PATH=str(self.bin)+os.pathsep+os.environ['PATH'])
    def mock(self, name, body):
        p=self.bin/name; p.write_text('#!/usr/bin/env bash\n'+body+'\n'); p.chmod(0o755)
    def run_script(self, script, *args):
        return subprocess.run(['bash', str(ROOT/'scripts'/script), *map(str,args)], env=self.env, text=True, capture_output=True, timeout=15)
    def backup_fixture(self):
        source=self.base/'source with spaces'; source.mkdir(); (source/'data.txt').write_text('preserve me\n')
        dest=self.base/'backups'; dest.mkdir()
        self.env['EXPECTED_BACKUP_SOURCE']=subprocess.check_output(['findmnt','-n','-o','SOURCE','-T',str(dest)],text=True).strip()
        return source,dest
    def test_all_bash_syntax(self):
        for p in (ROOT/'scripts').rglob('*'):
            if p.is_file() and p.read_bytes().startswith(b'#!'):
                result=subprocess.run(['bash','-n',str(p)],capture_output=True,text=True)
                self.assertEqual(result.returncode,0,f'{p}: {result.stderr}')
    def test_backup_roundtrip_and_preserves_unrelated_files(self):
        src,dest=self.backup_fixture(); old=dest/'unrelated.tar.gz'; old.write_text('keep')
        result=self.run_script('backup/backup_script',src,dest)
        self.assertEqual(result.returncode,0,result.stderr)
        archives=list(dest.glob('admin-backup-*.tar.gz')); self.assertEqual(len(archives),1)
        restore=self.base/'restore'; restore.mkdir()
        subprocess.run(['tar','-xzf',str(archives[0]),'-C',str(restore)],check=True)
        self.assertEqual((restore/src.name/'data.txt').read_bytes(),(src/'data.txt').read_bytes())
        self.assertEqual(old.read_text(),'keep')
        subprocess.run(['sha256sum','-c',str(archives[0])+'.sha256'],check=True,capture_output=True)
    def test_failed_tar_never_publishes_or_rotates(self):
        src,dest=self.backup_fixture(); old=dest/'old.tar.gz'; old.write_text('keep')
        self.mock('tar','echo partial > "$2"; exit 2')
        result=self.run_script('backup/backup_script',src,dest)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(list(dest.glob('admin-backup-*.tar.gz')))
        self.assertTrue(list(dest.glob('*.partial.*')))
        self.assertEqual(old.read_text(),'keep')
        self.assertNotIn('Backup verified',result.stderr)
    def test_wrong_mount_and_recursive_destination_rejected(self):
        src,dest=self.backup_fixture(); self.env['EXPECTED_BACKUP_SOURCE']='wrong-device'
        self.assertNotEqual(self.run_script('backup/backup_script',src,dest).returncode,0)
        self.assertEqual(list(dest.iterdir()),[])
        inside=src/'backup'; inside.mkdir()
        self.assertNotEqual(self.run_script('backup/backup_script',src,inside).returncode,0)
    def test_existing_final_archive_is_never_overwritten(self):
        src,dest=self.backup_fixture(); target=dest/'existing.tar.gz'; target.write_text('not an archive')
        env=dict(self.env,SOURCE_DIR=str(src),TARGET=str(target),ENGINE=str(ROOT/'scripts/core/backup_engine.sh'))
        result=subprocess.run(['bash','-c','source "$ENGINE"; create_verified_archive "$TARGET"'],env=env,capture_output=True)
        self.assertNotEqual(result.returncode,0); self.assertEqual(target.read_text(),'not an archive')
    def test_service_states_fail_closed_without_restart(self):
        for load,active,code,expected in [('loaded','active',0,0),('loaded','failed',0,1),('loaded','inactive',0,1),('masked','inactive',0,1),('not-found','inactive',0,1),('','',1,1)]:
            self.mock('systemctl',f'[[ $1 == show ]] || exit 99\nprintf "LoadState={load}\\nActiveState={active}\\n"\nexit {code}')
            result=self.run_script('monitoring/service_uptime','nginx')
            self.assertEqual(result.returncode,expected,result.stderr)
        self.assertNotEqual(self.run_script('monitoring/service_uptime').returncode,0)
    def test_checksum_collision_never_overwrites_evidence(self):
        src,dest=self.backup_fixture()
        for kind in ['file','symlink','directory']:
            target=dest/(kind+'.tar.gz'); sidecar=Path(str(target)+'.sha256')
            evidence=dest/(kind+'-evidence'); evidence.write_text('retain')
            if kind=='file': sidecar.write_text('retain')
            elif kind=='symlink': sidecar.symlink_to(evidence)
            else: sidecar.mkdir()
            env=dict(self.env,SOURCE_DIR=str(src),TARGET=str(target),ENGINE=str(ROOT/'scripts/core/backup_engine.sh'))
            result=subprocess.run(['bash','-c','source "$ENGINE"; create_verified_archive "$TARGET"'],env=env,capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(target.exists())
            self.assertEqual(evidence.read_text(),'retain')
            if kind!='directory': self.assertEqual(sidecar.read_text(),'retain')
    def test_checksum_failure_is_not_a_verified_backup(self):
        src,dest=self.backup_fixture(); target=dest/'failed.tar.gz'
        self.mock('sha256sum','exit 1')
        env=dict(self.env,SOURCE_DIR=str(src),TARGET=str(target),ENGINE=str(ROOT/'scripts/core/backup_engine.sh'))
        result=subprocess.run(['bash','-c','source "$ENGINE"; create_verified_archive "$TARGET"'],env=env,capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(Path(str(target)+'.sha256').exists())
        self.assertNotIn('Verified archive:',result.stdout)
        self.assertTrue(list(dest.glob('*.partial.*')))
    def test_disk_preserves_mount_spaces_and_query_failure(self):
        self.mock('df',"printf 'Type 1M-blocks Used Avail Use%% Mounted on\\next4 100M 80M 20M 80%% /data with spaces\\n'")
        result=self.run_script('monitoring/disk_alert'); self.assertEqual(result.returncode,1)
        self.assertIn('/data with spaces',result.stderr)
        self.mock('df','exit 1')
        result=self.run_script('monitoring/disk_alert'); self.assertNotEqual(result.returncode,0)
        self.assertIn('UNKNOWN',result.stderr)
    def test_nginx_invalid_inputs_never_reach_system_commands(self):
        template=self.base/'template'; template.write_text('server_name {{DOMAIN}};')
        for domain in ['', '../etc', '-bad.com', 'a..com', 'x.com/../../', 'bad name.com', 'a.com;id', 'a.com.']:
            result=self.run_script('Nginx_create.sh',domain,template,'root')
            self.assertNotEqual(result.returncode,0,domain)
    def test_nginx_preview_does_not_mutate(self):
        template=self.base/'template'; template.write_text('server_name {{DOMAIN}};')
        self.mock('id','exit 0')
        for command in ['nginx','mkdir','chown','chmod','ln','systemctl','rm']:
            self.mock(command,'echo "UNEXPECTED MUTATION" >&2; exit 99')
        result=self.run_script('Nginx_create.sh','example.test',template,'root')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('server_name example.test;',result.stdout)
        self.assertNotIn('UNEXPECTED',result.stderr)
    def test_scan_rejects_invalid_address_before_network(self):
        self.mock('nc','echo NETWORK_CALLED; exit 99')
        for ip in ['256.1.1.1','1.2.3','-1.2.3.4','1.2.3.4;id']:
            result=self.run_script('audit/ScanPort.sh',ip,'--scan')
            self.assertNotEqual(result.returncode,0); self.assertNotIn('NETWORK_CALLED',result.stdout)

if __name__=='__main__': unittest.main()
