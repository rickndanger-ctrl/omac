"""Exercise the installer's bounded lifecycle gate with local command stubs."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
INSTALLER = REPO / "Install Omac.command"


class InstallerLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = INSTALLER.read_text()
        match = re.search(r"wait_for_active\(\) \{.*?\n\}", source, re.S)
        if not match:
            raise AssertionError("wait_for_active function not found")
        cls.function = match.group(0)

    def run_gate(self, scenario):
        with tempfile.TemporaryDirectory(prefix="omac-gate-") as folder:
            root = Path(folder)
            stub = root / "aerospace"
            stub.write_text("""#!/bin/sh
case "$1" in
 config) echo "$AERO_CONFIG" ;;
 list-workspaces) [ "$AERO_RESPONSIVE" = yes ] && echo 1 ;;
 list-windows) [ "$AERO_RESPONSIVE" = yes ] || exit 1; echo "$AERO_LIVE_WINDOWS" ;;
esac
""")
            stub.chmod(0o755)
            launcher = root / "launchctl"
            launcher.write_text("""#!/bin/sh
if [ "$JOB_RUNNING" = yes ]; then echo 'state = running'; else echo 'state = waiting'; fi
""")
            launcher.chmod(0o755)
            state = root / "state"
            state.mkdir()
            (state / "status").write_text("Active")
            expected = str(root / "runtime/config/aerospace.toml")
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       GATE_STATE=str(state), AERO_CONFIG=expected,
                       AERO_RESPONSIVE="yes", AERO_HAS_WINDOWS="yes",
                       JOB_RUNNING="yes",
                       AERO_LIVE_WINDOWS='[{"window-id":7,"app-pid":70},{"window-id":8,"app-pid":80}]')
            if scenario == "registered-stopped":
                env["JOB_RUNNING"] = "no"
            elif scenario == "wrong-config":
                env["AERO_CONFIG"] = "/wrong/config.toml"
            elif scenario == "delayed-recovery":
                # The first iterations see Recovering, then enter completes.
                (state / "status").write_text("Recovering")
            elif scenario == "recovers-then-recovers-again":
                (state / "status").write_text("Active")
            elif scenario == "window-loss":
                env["AERO_LIVE_WINDOWS"] = "[]"
            elif scenario == "partial-window-loss":
                expected_pages = root / "expected-pages.json"
                expected_pages.write_text('{"windows":[{"window-id":7,"app-pid":70,"app-name":"Ghostty"},{"window-id":8,"app-pid":80,"app-name":"ChatGPT"}]}')
                env["AERO_LIVE_WINDOWS"] = '[{"window-id":8,"app-pid":80,"app-name":"ChatGPT"}]'
                env["PAGES_BASELINE"] = str(expected_pages)
            sleep_stub = 'sleep() { :; }\n'
            if scenario == "delayed-recovery":
                sleep_stub = 'sleep() { echo Active > "$GATE_STATE/status"; }\n'
            if scenario == "recovers-then-recovers-again":
                sleep_stub = 'sleep() { echo Recovering > "$GATE_STATE/status"; }\n'
            script = 'state="$GATE_STATE"\n' + sleep_stub + self.function + '\nwait_for_active "$AERO_BIN" "$AERO_CONFIG_EXPECTED" "${PAGES_BASELINE:-}"; exit $?\n'
            env["AERO_BIN"] = str(stub)
            env["AERO_CONFIG_EXPECTED"] = expected
            env["OMAC_STATE_ROOT"] = str(root)
            result = subprocess.run(["/bin/zsh", "-c", script], env=env,
                                    capture_output=True, text=True)
            return result.returncode

    def test_registered_but_stopped_job_is_not_ready(self):
        self.assertEqual(self.run_gate("registered-stopped"), 1)

    def test_wrong_aerospace_config_is_not_ready(self):
        self.assertEqual(self.run_gate("wrong-config"), 1)

    def test_delayed_recovery_is_allowed(self):
        self.assertEqual(self.run_gate("delayed-recovery"), 0)

    def test_missing_windows_is_an_explicit_degraded_result(self):
        self.assertEqual(self.run_gate("window-loss"), 2)

    def test_current_recovering_status_cannot_pass_after_active_sample(self):
        self.assertEqual(self.run_gate("recovers-then-recovers-again"), 1)

    def test_missing_ghostty_with_chatgpt_still_present_is_degraded(self):
        self.assertEqual(self.run_gate("partial-window-loss"), 2)

    def test_reengage_success_and_rollback_use_isolated_stubs(self):
        for fail_new_enter in (False, True):
            with self.subTest(rollback=fail_new_enter), tempfile.TemporaryDirectory(prefix="omac-reengage-") as folder:
                root = Path(folder)
                bin_dir = root / "bin"
                bin_dir.mkdir()
                state = root / "state"
                state.mkdir()
                (state / "status").write_text("Inactive")
                target = root / "Applications/Omac.app"
                old_exec = target / "Contents/MacOS/AgentControlCenter"
                old_exec.parent.mkdir(parents=True)
                source = root / "download/Omac.app/Contents/MacOS/AgentControlCenter"
                source.parent.mkdir(parents=True)
                source.parent.parent.parent.joinpath("Resources/Payload").mkdir(parents=True)
                aero = bin_dir / "aerospace"
                aero.write_text(f"""#!/bin/sh
case "$1" in
 config) echo '{state}/runtime/config/aerospace.toml' ;;
 list-workspaces) echo 1 ;;
 list-windows) echo '[1]' ;;
esac
""")
                aero.chmod(0o755)
                fake_python = bin_dir / "python-stub"
                marker = root / "new-enter-attempted"
                fake_python.write_text(f"""#!/bin/sh
if [ "$2" = enter ]; then
 if [ "$FAIL_NEW_ENTER" = yes ] && [ ! -e '{marker}' ]; then touch '{marker}'; exit 7; fi
 echo Active > "$OMAC_STATE_ROOT/status"
fi
exit 0
""")
                fake_python.chmod(0o755)
                fake_app = f"""#!/bin/sh
case "$1" in
 --check) echo '{{"ready":true,"python":"{fake_python}","aerospace":"{aero}"}}' ;;
 --prepare-runtime) mkdir -p "$OMAC_STATE_ROOT/runtime/config" "$OMAC_STATE_ROOT/runtime/launchd"; touch "$OMAC_STATE_ROOT/runtime/config/aerospace.toml"; exit 0 ;;
esac
exit 0
"""
                for executable in (source, old_exec):
                    executable.write_text(fake_app)
                    executable.chmod(0o755)
                # Preserve a pre-existing app only for the forced failure path.
                if not fail_new_enter:
                    shutil.rmtree(target)
                saver = root / "Screen Savers"
                saver.mkdir()
                for name, body in {
                    "codesign": "#!/bin/sh\nexit 0\n",
                    "pgrep": "#!/bin/sh\nexit 1\n",
                    "launchctl": "#!/bin/sh\necho 'state = running'\nexit 0\n",
                }.items():
                    command = bin_dir / name
                    command.write_text(body)
                    command.chmod(0o755)
                installer = root / "download/Install Omac.command"
                shutil.copy2(INSTALLER, installer)
                env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                           OMAC_INSTALL_DESTINATION=str(target), OMAC_STATE_ROOT=str(state),
                           OMAC_SAVER_DESTINATION=str(saver), OMAC_BACKUP_ROOT=str(root / "backups"),
                           OMAC_NO_LAUNCH="1", OMAC_REENGAGE_AFTER_INSTALL="1",
                           FAIL_NEW_ENTER="yes" if fail_new_enter else "no")
                completed = subprocess.run(["/bin/zsh", str(installer)], env=env,
                                           capture_output=True, text=True, timeout=30)
                if fail_new_enter:
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertIn("Previous Omac installation returned to Active", completed.stderr)
                    self.assertTrue((target / "old-app-marker").exists() or old_exec.exists())
                else:
                    self.assertEqual(completed.returncode, 0, completed.stderr)
                    self.assertEqual((state / "status").read_text(), "Active\n")


if __name__ == "__main__":
    unittest.main()
