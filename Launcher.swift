import Cocoa
import ApplicationServices
import WebKit
let root = "/Users/richardholguin/Documents/Codex/2026-09-20/is-x20/outputs/agent-control-center"
let state = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AgentControlCenter")
try? FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
func process(_ executable: String, _ args: [String]) -> (Int32, String) {
 let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
 let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
 do { try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "") }
 catch { return (1,error.localizedDescription) }
}
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
 var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success else { return nil }; return value
}
func eachWindow(_ body: (NSRunningApplication,AXUIElement,Int)->Void) {
 for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
  let ax = AXUIElementCreateApplication(app.processIdentifier)
  AXUIElementSetMessagingTimeout(ax, 0.5)
  for (index,w) in ((attribute(ax,kAXWindowsAttribute) as? [AXUIElement]) ?? []).enumerated() { body(app,w,index) }
 }
}
let snapshot = state.appendingPathComponent("windows.json")
if let index=CommandLine.arguments.firstIndex(of:"--center"), CommandLine.arguments.count>index+1, let pid=Int32(CommandLine.arguments[index+1]) {
 guard AXIsProcessTrusted() else { fputs("Accessibility access required.\n",stderr);exit(2) }
 let target=AXUIElementCreateApplication(pid)
 guard let raw=attribute(target,kAXFocusedWindowAttribute),CFGetTypeID(raw)==AXUIElementGetTypeID() else {exit(3)}
 let window=raw as! AXUIElement
 var old=CGPoint.zero
 if let value=attribute(window,kAXPositionAttribute),CFGetTypeID(value)==AXValueGetTypeID() { AXValueGetValue(value as! AXValue,.cgPoint,&old) }
 let top=NSScreen.screens.first?.frame.maxY ?? 0
 let screen=NSScreen.screens.first(where:{$0.frame.contains(CGPoint(x:old.x+10,y:top-old.y-10))}) ?? NSScreen.main!
 let frame=screen.visibleFrame
 var size=CGSize(width:frame.width*0.72,height:frame.height*0.80)
 var point=CGPoint(x:frame.midX-size.width/2,y:top-frame.midY-size.height/2)
 let a=AXUIElementSetAttributeValue(window,kAXSizeAttribute as CFString,AXValueCreate(.cgSize,&size)!)
 let b=AXUIElementSetAttributeValue(window,kAXPositionAttribute as CFString,AXValueCreate(.cgPoint,&point)!)
 if a != .success || b != .success {fputs("Could not center the terminal.\n",stderr);exit(4)}
 print("Centered terminal");exit(0)
}
if CommandLine.arguments.contains("--snapshot") {
 guard AXIsProcessTrusted() else { fputs("Grant Agent Control Center Accessibility access in System Settings before entering.\n",stderr); exit(2) }
 if !FileManager.default.fileExists(atPath:snapshot.path) {
  var saved = [[String:Any]]()
  eachWindow { app,w,index in
   guard let pos = attribute(w,kAXPositionAttribute), let size = attribute(w,kAXSizeAttribute), CFGetTypeID(pos)==AXValueGetTypeID(),CFGetTypeID(size)==AXValueGetTypeID() else {return}
   var point = CGPoint.zero; var dimensions = CGSize.zero
   AXValueGetValue(pos as! AXValue,.cgPoint,&point); AXValueGetValue(size as! AXValue,.cgSize,&dimensions)
   saved.append(["pid":Int(app.processIdentifier),"index":index,"title":attribute(w,kAXTitleAttribute) as? String ?? "","x":point.x,"y":point.y,"w":dimensions.width,"h":dimensions.height])
  }
  do {try JSONSerialization.data(withJSONObject:saved).write(to:snapshot,options:.atomic)} catch {exit(1)}
 }
 exit(0)
}
if CommandLine.arguments.contains("--restore") {
 if AXIsProcessTrusted(), let data=try? Data(contentsOf:snapshot), let saved=(try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]] {
  eachWindow { app,w,index in
   let title=attribute(w,kAXTitleAttribute) as? String ?? ""
   guard let entry=saved.first(where:{($0["pid"] as? Int)==Int(app.processIdentifier) && ($0["index"] as? Int)==index && ($0["title"] as? String)==title}), let x=entry["x"] as? Double,let y=entry["y"] as? Double, let width=entry["w"] as? Double,let height=entry["h"] as? Double else {return}
   var pos=CGPoint(x:x,y:y); var size=CGSize(width:width,height:height)
   if let value=AXValueCreate(.cgSize,&size) {AXUIElementSetAttributeValue(w,kAXSizeAttribute as CFString,value)}
   if let value=AXValueCreate(.cgPoint,&pos) {AXUIElementSetAttributeValue(w,kAXPositionAttribute as CFString,value)}
  }
  try? FileManager.default.removeItem(at:snapshot)
 }
 exit(0)
}
if !CommandLine.arguments.contains("--managed") {
 FileManager.default.createFile(atPath:state.appendingPathComponent("menu.enabled").path,contents:Data())
 let job="gui/\(getuid())/com.richard.acc.menu"
 if process("/bin/launchctl",["print",job]).0 != 0 { _=process("/bin/launchctl",["bootstrap","gui/\(getuid())",root+"/launchd/menu.plist"]) }
 _=process("/bin/launchctl",["kickstart",job]); exit(0)
}
class GuidePanel: NSPanel {
 override func cancelOperation(_ sender:Any?) {orderOut(nil)}
}
class Delegate: NSObject,NSApplicationDelegate {
 var item:NSStatusItem!; var busy=false; var guide:GuidePanel?
 func applicationDidFinishLaunching(_ note:Notification) {
  NSAppleEventManager.shared().setEventHandler(self,andSelector:#selector(urlEvent(_:reply:)),forEventClass:AEEventClass(kInternetEventClass),andEventID:AEEventID(kAEGetURL))
  item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength); item.button?.title="▦ Control"
  let menu=NSMenu()
  for (title,action) in [("Enter / Resume Five Pages","enter"),("Open / Arrange 4 Terminals","four"),("Open / Arrange 6 Terminals","six"),("New Terminal (up to 6)","new"),("Pause Tiling and Shortcuts","pause"),("Exit and Restore Windows","exit"),("Shortcut Guide","guide"),("Accessibility Settings","access"),("Quit Launcher","quit")] {
   let m=NSMenuItem(title:title,action:#selector(selected(_:)),keyEquivalent:""); m.representedObject=action; m.target=self; menu.addItem(m)
  }
  menu.addItem(.separator())
  let apps=NSMenuItem(title:"Apps",action:nil,keyEquivalent:"")
  let appMenu=NSMenu()
  for (title,bundle) in [("Codex","com.openai.codex"),("Claude","com.anthropic.claudefordesktop"),("Hermes","com.nousresearch.hermes.setup"),("Cursor","com.todesktop.230313mzl4w4u92"),("VS Code","com.microsoft.VSCode"),("Telegram","ru.keepcoder.Telegram"),("Messages","com.apple.MobileSMS"),("Mail","com.apple.mail"),("Chrome","com.google.Chrome"),("Finder","com.apple.finder")] {
   guard NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) != nil else {continue}
   let entry=NSMenuItem(title:title,action:#selector(launchApp(_:)),keyEquivalent:"")
   entry.representedObject=bundle;entry.target=self;appMenu.addItem(entry)
  }
  appMenu.addItem(.separator())
  let all=NSMenuItem(title:"All Applications…",action:#selector(openApplications),keyEquivalent:"");all.target=self;appMenu.addItem(all)
  apps.submenu=appMenu;menu.addItem(apps)
  let settings=NSMenuItem(title:"Settings",action:nil,keyEquivalent:"");let settingsMenu=NSMenu()
  for (title,url) in [("System Settings","x-apple.systempreferences:"),("Displays","x-apple.systempreferences:com.apple.Displays-Settings.extension"),("Keyboard","x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),("Accessibility Permission","x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")] {
   let entry=NSMenuItem(title:title,action:#selector(openSettings(_:)),keyEquivalent:"");entry.representedObject=url;entry.target=self;settingsMenu.addItem(entry)
  }
  settings.submenu=settingsMenu;menu.addItem(settings)
  item.menu=menu
  // Recover safely after a launcher crash: release management, preserve sessions.
  if (try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8)) == "Active" { perform("pause") }
 }
 @objc func urlEvent(_ event:NSAppleEventDescriptor,reply:NSAppleEventDescriptor) {
  if let text=event.paramDescriptor(forKeyword:AEKeyword(keyDirectObject))?.stringValue, let action=URL(string:text)?.host, ["exit","pause","enter","four","six","new","guide","center"].contains(action) {perform(action)}
 }
 @objc func launchApp(_ sender:NSMenuItem) {
  guard let bundle=sender.representedObject as? String,let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) else {return}
  NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration())
 }
 @objc func openApplications() {NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications"))}
 @objc func openSettings(_ sender:NSMenuItem) {
  if let value=sender.representedObject as? String,let url=URL(string:value) {NSWorkspace.shared.open(url)}
 }
 @objc func selected(_ sender:NSMenuItem) { perform(sender.representedObject as! String) }
 func perform(_ action:String) {
  if action=="guide" {
   // Capture the page before focusing the panel; open -g prevents premature activation.
   let current=process("/opt/homebrew/bin/aerospace",["list-workspaces","--focused"])
   let page=current.1.trimmingCharacters(in:.whitespacesAndNewlines)
   if guide==nil {
    let panel=GuidePanel(contentRect:NSRect(x:0,y:0,width:620,height:570),styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
    panel.title="Shortcuts";panel.titleVisibility = .hidden;panel.titlebarAppearsTransparent=true
    panel.isReleasedWhenClosed=false;panel.isOpaque=false;panel.hasShadow=true
    panel.backgroundColor=NSColor(calibratedRed:0.08,green:0.10,blue:0.13,alpha:0.85)
    panel.appearance=NSAppearance(named:.darkAqua)
    let web=WKWebView(frame:panel.contentView!.bounds);web.autoresizingMask=[.width,.height]
    web.setValue(false,forKey:"drawsBackground")
    web.loadFileURL(URL(fileURLWithPath:root+"/Guide.html"),allowingReadAccessTo:URL(fileURLWithPath:root))
    panel.contentView=web;guide=panel
   }
   guard let panel=guide else {return}
   if current.0==0 {
    _=process("/opt/homebrew/bin/aerospace",["move-node-to-workspace","--window-id",String(panel.windowNumber),page])
   }
   panel.center();panel.orderFrontRegardless()
   // Newly shown windows are detected asynchronously by AeroSpace.
   DispatchQueue.main.asyncAfter(deadline:.now()+0.15) {
    if current.0==0 {
     let moved=process("/opt/homebrew/bin/aerospace",["move-node-to-workspace","--window-id",String(panel.windowNumber),page])
     if moved.0 != 0 {panel.orderOut(nil);return}
     _=process("/opt/homebrew/bin/aerospace",["layout","--window-id",String(panel.windowNumber),"floating"])
     _=process("/opt/homebrew/bin/aerospace",["focus","--window-id",String(panel.windowNumber)])
    }
    panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
   }
   return
  }
  if action=="access" {
   let key=kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
   _=AXIsProcessTrustedWithOptions([key:true] as CFDictionary)
   NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!); return
  }
  guard !busy else {return}; busy=true; item.button?.title="▦ Working…"
  DispatchQueue.global().async {
   let result=process("/opt/homebrew/bin/python3",[root+"/control.py",action=="quit" ? "exit":action])
   DispatchQueue.main.async {
    self.busy=false
    let status=(try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8)) ?? "Inactive"
    self.item.button?.title="▦ \(status)"
    if result.0 != 0 { let alert=NSAlert();alert.messageText="Control Center needs attention";alert.informativeText=result.1;NSApp.activate(ignoringOtherApps:true);alert.runModal() }
    if action=="quit" {try? FileManager.default.removeItem(at:state.appendingPathComponent("menu.enabled"));NSApp.terminate(nil)}
   }
  }
 }
}
let app=NSApplication.shared; let delegate=Delegate();app.delegate=delegate;app.setActivationPolicy(.accessory);app.run()
