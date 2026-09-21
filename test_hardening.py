import json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import control as c
class Hardening(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.old=c.STATE;c.STATE=Path(self.tmp.name)
 def tearDown(self): c.STATE=self.old;self.tmp.cleanup()
 def test_corrupt_checkpoint_is_ignored(self):
  (c.STATE/'pages.json').write_text('{broken')
  with patch.object(c,'aero') as aero:c.restore_pages();aero.assert_not_called()
 def test_previous_boot_does_not_move_reused_ids(self):
  (c.STATE/'pages.json').write_text(json.dumps({'boot':'old','page':'2','windows':[{'window-id':1,'app-pid':1,'workspace':'2'}]}))
  with patch.object(c,'boot_session',return_value='new'),patch.object(c,'aero') as aero:c.restore_pages();aero.assert_not_called()
 def test_active_recovery_restores_before_enabling_bindings(self):
  c.save_status('Active');events=[]
  with patch.object(c,'ready'),patch.object(c,'restore_pages',side_effect=lambda:events.append('restore')),patch.object(c,'aero',side_effect=lambda *args,**kw:events.append(args)),patch.object(c,'save_pages'),patch.object(c,'load'),patch.object(c,'run'):
   c.recover()
  self.assertEqual(events[:2],['restore',('mode','active')]);self.assertEqual(c.status(),'Active')
 def test_recovery_failure_releases_bindings(self):
  c.save_status('Active')
  with patch.object(c,'ready',side_effect=RuntimeError('unavailable')),patch.object(c,'aero') as aero:
   with self.assertRaises(RuntimeError):c.recover()
   aero.assert_any_call('mode','main',check=False);aero.assert_any_call('enable','off',check=False)
  self.assertEqual(c.status(),'Paused')
if __name__=='__main__':unittest.main()
