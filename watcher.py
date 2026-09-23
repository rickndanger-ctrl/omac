#!/opt/homebrew/bin/python3
"""Event-driven page checkpointing. launchd supervises this process and its child."""
import fcntl,os,selectors,signal,subprocess,time
import control as c

def main():
 child=subprocess.Popen([c.AERO,'subscribe','--all','--no-send-initial'],stdout=subprocess.PIPE)
 def stop(*_):
  child.terminate()
  raise SystemExit(0)
 signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
 selector=selectors.DefaultSelector();selector.register(child.stdout,selectors.EVENT_READ)
 pending=None
 try:
  while child.poll() is None:
   timeout=None if pending is None else max(0,pending-time.monotonic())
   events=selector.select(timeout)
   if events:
    if not os.read(child.stdout.fileno(),65536): break
    pending=time.monotonic()+0.3
   if pending is not None and time.monotonic()>=pending:
    pending=None
    with (c.STATE/'controller.lock').open('a') as lock:
     try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
     except BlockingIOError:
      pending=time.monotonic()+0.3;continue
     try:
      if c.status()=='Active':
       c.reconcile_page_recovery(late_only=True)
       c.save_pages()
     except (RuntimeError,ValueError,OSError): pass
 finally:
  selector.close()
  if child.poll() is None:child.terminate()
  try:child.wait(timeout=2)
  except subprocess.TimeoutExpired:child.kill();child.wait()
if __name__=='__main__':main()
