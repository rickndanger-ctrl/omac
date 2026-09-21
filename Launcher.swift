import Cocoa
import ApplicationServices
import WebKit
import ServiceManagement
let root = Bundle.main.resourceURL!.appendingPathComponent("Payload").path
let appExecutable = Bundle.main.executableURL!.path
func installedExecutable(_ candidates:[String])->String? {candidates.first{FileManager.default.isExecutableFile(atPath:$0)}}
let python = installedExecutable(["/opt/homebrew/bin/python3","/opt/homebrew/bin/python3.13","/opt/homebrew/opt/python@3.13/bin/python3.13","/usr/local/bin/python3","/Library/Frameworks/Python.framework/Versions/Current/bin/python3"])
let aerospace = installedExecutable(["/opt/homebrew/bin/aerospace","/usr/local/bin/aerospace"])

let state = ProcessInfo.processInfo.environment["OMAC_STATE_ROOT"].map{URL(fileURLWithPath:$0)} ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AgentControlCenter")
let runtime=state.appendingPathComponent("runtime")
func process(_ executable: String, _ args: [String]) -> (Int32, String) {
 let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
 var environment=ProcessInfo.processInfo.environment
 environment["OMAC_APP_EXECUTABLE"]=appExecutable
 environment["OMAC_STATE_ROOT"]=state.path
 if let aerospace {environment["OMAC_AEROSPACE_CLI"]=aerospace}
 environment["PYTHONDONTWRITEBYTECODE"]="1"
 p.environment=environment
 let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
 do { try p.run()
  let timeout=DispatchWorkItem {if p.isRunning {p.terminate()}}
  DispatchQueue.global().asyncAfter(deadline:.now()+30,execute:timeout)
  defer {timeout.cancel()}
  let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "") }
 catch { return (1,error.localizedDescription) }
}
func missingDependencies()->[String] {
 var missing=[String]()
 if python == nil {missing.append("Python 3 (Homebrew or python.org)")}
 if aerospace == nil {missing.append("AeroSpace command-line tool")}
 for (label,id) in [("AeroSpace","bobko.aerospace"),("Ghostty","com.mitchellh.ghostty")] {
  if NSWorkspace.shared.urlForApplication(withBundleIdentifier:id) == nil && !FileManager.default.fileExists(atPath:"/Applications/"+label+".app") {missing.append(label+" app")}
 }
 if !FileManager.default.fileExists(atPath:root+"/control.py") {missing.append("Omac bundled resources")}
 return missing
}
if CommandLine.arguments.contains("--check") {
 let missing=missingDependencies()
 let report:[String:Any] = ["ready":missing.isEmpty,"missing":missing,"resources":root,"python":python ?? "missing","aerospace":aerospace ?? "missing","accessibility":AXIsProcessTrusted(),"loginRegistered":SMAppService.mainApp.status == .enabled]
 let data=try! JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);print(String(data:data,encoding:.utf8)!);exit(missing.isEmpty ? 0:1)
}
try? FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
func prepareRuntime()->Bool {
 guard missingDependencies().isEmpty,let python else {return false}
 return process(python,[root+"/generate_config.py"]).0 == 0
}
if CommandLine.arguments.contains("--prepare-runtime") {
 guard prepareRuntime() else {fputs("Unable to prepare Omac runtime\n",stderr);exit(1)}
 print(runtime.path);exit(0)
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
 guard AXIsProcessTrusted() else { fputs("Grant Omac Accessibility access in System Settings before entering.\n",stderr); exit(2) }
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
func screenKey(_ screen:NSScreen)->String {
 String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)
}
let wallpaperBackup=state.appendingPathComponent("wallpaper-original.json")
let wallpaperChoice=state.appendingPathComponent("wallpaper.selected")
if CommandLine.arguments.contains("--apply-wallpaper") || CommandLine.arguments.contains("--restore-wallpaper") {
 let workspace=NSWorkspace.shared
 var original=(try? Data(contentsOf:wallpaperBackup)).flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:String]} ?? [:]
 let restoring=CommandLine.arguments.contains("--restore-wallpaper")
 let choice=(try? String(contentsOf:wallpaperChoice,encoding:.utf8)) ?? "storm-forge"
 guard ["obsidian","amber","pine","emerald-glass","storm-forge","crimson-etch"].contains(choice) else {exit(1)}
 let image=URL(fileURLWithPath:root+"/branding/wallpapers/omac-"+choice+".png")
 var failed=false
 for screen in NSScreen.screens {
  let key=screenKey(screen)
  if restoring {
   guard let path=original[key] else {failed=true;continue}
   do {try workspace.setDesktopImageURL(URL(fileURLWithPath:path),for:screen,options:[:])} catch {failed=true}
  } else {
   guard FileManager.default.fileExists(atPath:image.path) else {exit(1)}
   if original[key]==nil,let old=workspace.desktopImageURL(for:screen) {original[key]=old.path}
   // Persist before applying so Exit can always restore the original.
   do {try JSONSerialization.data(withJSONObject:original).write(to:wallpaperBackup,options:.atomic)
    try workspace.setDesktopImageURL(image,for:screen,options:[:])
   } catch {failed=true}
  }
 }
 if restoring && !failed {try? FileManager.default.removeItem(at:wallpaperBackup)}
 exit(failed ? 1:0)
}
if CommandLine.arguments.contains("--guide") {
 let current=process(aerospace ?? "/missing/aerospace",["list-workspaces","--focused"])
 let page=current.1.trimmingCharacters(in:.whitespacesAndNewlines)
 DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.richard.acc.showGuide"),object:nil,userInfo:["page":current.0==0 ? page:""],deliverImmediately:true)
 RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15))
 exit(0)
}
if CommandLine.arguments.contains("--login") {
 guard prepareRuntime() else {fputs("Omac dependencies are missing. Open Omac for setup.\n",stderr);exit(1)}
 guard AXIsProcessTrusted() else {fputs("Grant Omac Device Control access before login startup.\n",stderr);exit(2)}
 let result=process(python ?? "/missing/python3",[root+"/control.py","login"])
 if !result.1.isEmpty {fputs(result.1, result.0==0 ? stdout:stderr)}
 exit(result.0)
}
if !prepareRuntime() {
 let app=NSApplication.shared;app.setActivationPolicy(.regular)
 let alert=NSAlert();alert.messageText="Omac setup needed"
 alert.informativeText="Install the following prerequisites, then reopen Omac:\n\n"+missingDependencies().joined(separator:"\n")+"\n\nThis beta requires AeroSpace 0.21.3-Beta, Ghostty 1.3.1 and Python 3."
 alert.addButton(withTitle:"OK");app.activate(ignoringOtherApps:true);alert.runModal();exit(1)
}
if !CommandLine.arguments.contains("--managed") {
 FileManager.default.createFile(atPath:state.appendingPathComponent("engage.request").path,contents:Data())
 FileManager.default.createFile(atPath:state.appendingPathComponent("menu.enabled").path,contents:Data())
 let job="gui/\(getuid())/com.richard.acc.menu"
 if process("/bin/launchctl",["print",job]).0 != 0 { _=process("/bin/launchctl",["bootstrap","gui/\(getuid())",runtime.appendingPathComponent("launchd/menu.plist").path]) }
 _=process("/bin/launchctl",["kickstart",job]);
 DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.richard.acc.engage"),object:nil,userInfo:nil,deliverImmediately:true)
 RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15)); exit(0)
}
final class OmacBrandBar {
 private var wallpaperURL: URL?
 private(set) var accent=NSColor(calibratedRed:0.55,green:0.9,blue:0.35,alpha:1)
 private var silhouette=NSBezierPath()
 init(logo:String) {
  if let image=NSImage(contentsOfFile:logo),let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data) {
   let left=Int(Double(bitmap.pixelsWide)*0.239),top=Int(Double(bitmap.pixelsHigh)*0.608),right=Int(Double(bitmap.pixelsWide)*0.760),bottom=Int(Double(bitmap.pixelsHigh)*0.752)
   for y in stride(from:top,to:bottom,by:2) { for x in stride(from:left,to:right,by:2) { if let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.greenComponent>0.48 && c.greenComponent>c.blueComponent*1.2 { silhouette.appendRect(NSRect(x:Double(x-left)/Double(right-left)*47,y:Double(bottom-y)/Double(bottom-top)*13,width:0.2,height:0.2)) } } }
  }
 }
 func image(page:Int,status:String)->NSImage {
  let image=NSImage(size:NSSize(width:168,height:22));image.lockFocus();let active=status=="Active",color=active ? accent:NSColor.secondaryLabelColor
  color.setFill();silhouette.fill()
  for n in 1...5 { let r=NSRect(x:56+(n-1)*22,y:2,width:19,height:18),p=NSBezierPath(roundedRect:r,xRadius:5,yRadius:5);if n==page && active {color.withAlphaComponent(0.27).setFill();p.fill();color.setStroke();p.lineWidth=1;p.stroke()};let a:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:n==page ? .bold:.medium),.foregroundColor:color.withAlphaComponent(n==page ? 1:0.55)];let t="\(n)" as NSString,s=t.size(withAttributes:a);t.draw(at:NSPoint(x:r.midX-s.width/2,y:r.midY-s.height/2),withAttributes:a) }
  image.unlockFocus();image.isTemplate=false;return image
 }
}
class GuidePanel: NSPanel {
 override func cancelOperation(_ sender:Any?) {orderOut(nil)}
}
class Delegate: NSObject,NSApplicationDelegate {
 var item:NSStatusItem!; var busy=false; var guide:GuidePanel?
 let brandBar=OmacBrandBar(logo:root+"/branding/Omac.png");var barTimer:Timer?
 func statusTitle(_ text:String) { refreshBar() }
 func refreshBar() { guard item != nil else{return};DispatchQueue.global(qos:.utility).async { let r=process(aerospace ?? "/missing/aerospace",["list-workspaces","--focused"]),page=Int(r.1.trimmingCharacters(in:.whitespacesAndNewlines)) ?? 0,status=(try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8)) ?? "Inactive";DispatchQueue.main.async { self.item.button?.title="";self.item.button?.image=self.brandBar.image(page:page,status:status);self.item.button?.toolTip="Omac · \(status) · Page \(page) · Command 1–5 to switch" } } }
 @objc func engageNotification(_ note:Notification) {try? FileManager.default.removeItem(at:state.appendingPathComponent("engage.request"));perform("enter")}
 func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {perform("enter");return true}
 func applicationDockMenu(_ sender:NSApplication)->NSMenu? {item.menu}

 func applicationDidFinishLaunching(_ note:Notification) {
  NSAppleEventManager.shared().setEventHandler(self,andSelector:#selector(urlEvent(_:reply:)),forEventClass:AEEventClass(kInternetEventClass),andEventID:AEEventID(kAEGetURL))
  DistributedNotificationCenter.default().addObserver(self,selector:#selector(showGuideNotification(_:)),name:NSNotification.Name("com.richard.acc.showGuide"),object:nil,suspensionBehavior:.deliverImmediately)
  item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength); statusTitle("▦ Omac")
  let menu=NSMenu()
  let pages=NSMenuItem(title:"Omac Pages",action:nil,keyEquivalent:"");let pageMenu=NSMenu();for n in 1...5 {let e=NSMenuItem(title:"Page \(n)    ⌘\(n)",action:#selector(selectPage(_:)),keyEquivalent:"");e.tag=n;e.target=self;pageMenu.addItem(e)};pages.submenu=pageMenu;menu.addItem(pages);menu.addItem(.separator())
  for (title,action) in [("Engage Omac","enter"),("Open / Arrange 4 Terminals","four"),("Open / Arrange 6 Terminals","six"),("New Terminal (up to 6)","new"),("Pause Tiling and Shortcuts","pause"),("Disengage Omac — Restore Windows","exit"),("Shortcut Guide","guide"),("Accessibility Settings","access"),("Start Omac at Login","enable-login"),("Disable Login Startup","disable-login"),("Quit Omac","quit")] {
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
  let appearance=NSMenuItem(title:"Omac Appearance",action:nil,keyEquivalent:"");let appearanceMenu=NSMenu()
  for (title,value) in [("Emerald Glass","emerald-glass"),("Storm Forge","storm-forge"),("Crimson Etch","crimson-etch"),("Original Green Glass","obsidian"),("Amber Glass","amber"),("Silver Glass","pine")] {
   let entry=NSMenuItem(title:title,action:#selector(selectWallpaper(_:)),keyEquivalent:"");entry.representedObject=value;entry.target=self;appearanceMenu.addItem(entry)
  }
  let saver=NSMenuItem(title:"Wallpaper & Screen Saver…",action:#selector(openSettings(_:)),keyEquivalent:"")
  saver.representedObject="x-apple.systempreferences:com.apple.Wallpaper-Settings.extension";saver.target=self;appearanceMenu.addItem(saver)
  appearance.submenu=appearanceMenu;menu.addItem(appearance)
  item.menu=menu
  barTimer=Timer.scheduledTimer(withTimeInterval:1.5,repeats:true){[weak self] _ in self?.refreshBar()}
  let main=NSMenu();let appItem=NSMenuItem();main.addItem(appItem);appItem.submenu=menu.copy() as? NSMenu;NSApp.mainMenu=main
  DistributedNotificationCenter.default().addObserver(self,selector:#selector(engageNotification(_:)),name:NSNotification.Name("com.richard.acc.engage"),object:nil,suspensionBehavior:.deliverImmediately)
  if FileManager.default.fileExists(atPath:state.appendingPathComponent("engage.request").path) {engageNotification(Notification(name:Notification.Name("com.richard.acc.engage")));return}

  // Resume an active session after launchd restarts this menu helper.
  if (try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8)) == "Active" { perform("enter") }
 }
 @objc func urlEvent(_ event:NSAppleEventDescriptor,reply:NSAppleEventDescriptor) {
  if let text=event.paramDescriptor(forKeyword:AEKeyword(keyDirectObject))?.stringValue, let action=URL(string:text)?.host, ["exit","pause","enter","four","six","new","guide","menu","center"].contains(action) {perform(action)}
 }
 @objc func selectPage(_ sender:NSMenuItem) { guard (try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8))=="Active" else{return};DispatchQueue.global().async {_=process(aerospace ?? "/missing/aerospace",["workspace",String(sender.tag)]);DispatchQueue.main.async{self.refreshBar()}} }
 @objc func launchApp(_ sender:NSMenuItem) {
  guard let bundle=sender.representedObject as? String,let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) else {return}
  NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration())
 }
 @objc func selectWallpaper(_ sender:NSMenuItem) {
  guard let choice=sender.representedObject as? String else {return}
  try? choice.write(to:wallpaperChoice,atomically:true,encoding:.utf8)
  if (try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8))=="Active" {
   DispatchQueue.global().async {_=process(CommandLine.arguments[0],["--apply-wallpaper"])}
  }
 }
 @objc func openApplications() {NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications"))}
 @objc func openSettings(_ sender:NSMenuItem) {
  if let value=sender.representedObject as? String,let url=URL(string:value) {NSWorkspace.shared.open(url)}
 }
 @objc func selected(_ sender:NSMenuItem) { perform(sender.representedObject as! String) }
 @objc func showGuideNotification(_ notification:Notification) {
  let value=notification.userInfo?["page"] as? String
  showGuide(page: value?.isEmpty==false ? value:nil)
 }
 func showGuide(page:String?) {
   guide?.close();guide=nil
   if guide==nil {
    let panel=GuidePanel(contentRect:NSRect(x:0,y:0,width:620,height:570),styleMask:[.titled,.closable,.fullSizeContentView,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.title="Shortcuts";panel.titleVisibility = .hidden;panel.titlebarAppearsTransparent=true
    panel.isReleasedWhenClosed=false;panel.isOpaque=false;panel.hasShadow=true;panel.hidesOnDeactivate=false
    panel.backgroundColor=NSColor(calibratedRed:0.08,green:0.10,blue:0.13,alpha:0.85)
    panel.appearance=NSAppearance(named:.darkAqua)
    let web=WKWebView(frame:panel.contentView!.bounds);web.autoresizingMask=[.width,.height]
    web.setValue(false,forKey:"drawsBackground")
    web.loadFileURL(URL(fileURLWithPath:root+"/Guide.html"),allowingReadAccessTo:URL(fileURLWithPath:root))
    panel.contentView=web;guide=panel
   }
   guard let panel=guide else {return}
   // A nonactivating palette accepts keys without focusing the app's old workspace.
   panel.center();panel.makeKeyAndOrderFront(nil)

 }
 func perform(_ action:String) {
  if action=="setup" {
   let alert=NSAlert();alert.messageText="Omac setup"
   alert.informativeText="Dependencies: "+(missingDependencies().isEmpty ? "Ready" : missingDependencies().joined(separator:", "))+"\nWindow control: "+(AXIsProcessTrusted() ? "Authorized":"Permission needed")+"\nStart at Login: "+(SMAppService.mainApp.status == .enabled ? "On":"Off or awaiting approval")
   alert.runModal();return
  }
  if action=="enable-login" || action=="disable-login" {
   guard Bundle.main.bundleURL.path=="/Applications/Omac.app" else {
    let alert=NSAlert();alert.messageText="Move Omac to Applications first";alert.informativeText="Login startup must use the installed copy, not a disk image or build folder.";alert.runModal();return
   }
   do {
    if action=="enable-login" {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()}
    // Remove the old login-only job after successful registration. Other services remain supervised.
    if action=="disable-login" || SMAppService.mainApp.status == .enabled {
     DispatchQueue.global().async {_=process(python ?? "/missing/python3",[root+"/control.py","disable-login"])}
    }
    if SMAppService.mainApp.status == .requiresApproval {SMAppService.openSystemSettingsLoginItems()}
   } catch {let alert=NSAlert();alert.messageText="Could not update Omac login startup";alert.informativeText=error.localizedDescription;alert.runModal()}
   return
  }
  if action=="guide" {
   DispatchQueue.global().async {
    let current=process(aerospace ?? "/missing/aerospace",["list-workspaces","--focused"])
    let page=current.1.trimmingCharacters(in:.whitespacesAndNewlines)
    DispatchQueue.main.async {self.showGuide(page:current.0==0 ? page:nil)}
   }
   return
  }
  if action=="access" {
   let key=kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
   _=AXIsProcessTrustedWithOptions([key:true] as CFDictionary)
   NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!); return
  }
  if ["pause","exit","quit"].contains(action) {guide?.orderOut(nil)}
  guard !busy else {return}; busy=true; statusTitle("▦ Omac · Working…")
  DispatchQueue.global().async {
   let result=process(python ?? "/missing/python3",[root+"/control.py",action=="quit" ? "exit":action])
   DispatchQueue.main.async {
    self.busy=false
    let status=(try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8)) ?? "Inactive"
    self.statusTitle("▦ Omac · \(status)")
    if result.0 != 0 { let alert=NSAlert();alert.messageText="Omac needs attention";alert.informativeText=result.1;NSApp.activate(ignoringOtherApps:true);alert.runModal() }
    if action=="quit" {try? FileManager.default.removeItem(at:state.appendingPathComponent("menu.enabled"));NSApp.terminate(nil)}
   }
  }
 }
}
let app=NSApplication.shared; let delegate=Delegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
