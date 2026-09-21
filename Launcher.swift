import Cocoa
import ApplicationServices
import WebKit
import ServiceManagement
import Cocoa
import ApplicationServices

// AeroSpace uses the same WindowServer ID. Resolve it on the AX element rather
// than relying on titles, list order, or whichever app window has focus.
// Private macOS API: keep this isolated and fail closed if unavailable.
typealias AXWindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

enum NativeTargetError: Error { case unavailable, permission, missing, ambiguous, geometry }

struct NativeWindowTarget {
    let element: AXUIElement
    let frame: CGRect
    let visibleFrame: CGRect

    static func resolve(id: CGWindowID, pid: pid_t) throws -> NativeWindowTarget {
        guard AXIsProcessTrusted() else { throw NativeTargetError.permission }
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            throw NativeTargetError.unavailable
        }
        let getID = unsafeBitCast(symbol, to: AXWindowIDFunction.self)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { throw NativeTargetError.missing }
        let matches = windows.filter { window in
            var candidate: CGWindowID = 0
            return getID(window, &candidate) == .success && candidate == id
        }
        guard matches.count == 1 else { throw NativeTargetError.ambiguous }
        let window = matches[0]
        func axValue(_ key: String) throws -> AXValue {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, key as CFString, &result) == .success,
                  let result, CFGetTypeID(result) == AXValueGetTypeID() else { throw NativeTargetError.geometry }
            return unsafeBitCast(result, to: AXValue.self)
        }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(try axValue(kAXPositionAttribute), .cgPoint, &point),
              AXValueGetValue(try axValue(kAXSizeAttribute), .cgSize, &size),
              size.width > 0, size.height > 0 else { throw NativeTargetError.geometry }
        let frame = CGRect(origin: point, size: size)
        // AX uses the primary display's upper-left as origin, AppKit lower-left.
        guard let primary = NSScreen.screens.first else { throw NativeTargetError.geometry }
        func axRect(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let ranked = NSScreen.screens.map { screen -> (NSScreen, CGFloat) in
            let overlap = frame.intersection(axRect(screen.frame))
            return (screen, overlap.isNull ? 0 : overlap.width * overlap.height)
        }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first, best.1 > 0,
              ranked.count == 1 || best.1 > ranked[1].1 else { throw NativeTargetError.ambiguous }
        return NativeWindowTarget(element: window, frame: frame, visibleFrame: axRect(best.0.visibleFrame))
    }
}

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
if let index = CommandLine.arguments.firstIndex(of: "--window-frame"), CommandLine.arguments.count > index + 6 {
 do {
  guard let id=UInt32(CommandLine.arguments[index+1]),let pid=Int32(CommandLine.arguments[index+2]) else {throw NativeTargetError.missing}
  let numbers=CommandLine.arguments[(index+3)...(index+6)].compactMap(Double.init)
  guard numbers.count == 4,numbers.allSatisfy({$0.isFinite}),numbers[2]>0,numbers[3]>0 else {throw NativeTargetError.geometry}
  let target=try NativeWindowTarget.resolve(id:id,pid:pid)
  var point=CGPoint(x:numbers[0],y:numbers[1]),size=CGSize(width:numbers[2],height:numbers[3])
  guard let p=AXValueCreate(.cgPoint,&point),let z=AXValueCreate(.cgSize,&size),
   AXUIElementSetAttributeValue(target.element,kAXPositionAttribute as CFString,p) == .success,
   AXUIElementSetAttributeValue(target.element,kAXSizeAttribute as CFString,z) == .success else {throw NativeTargetError.geometry}
  RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15))
  let actual=try NativeWindowTarget.resolve(id:id,pid:pid).frame
  guard abs(actual.minX-point.x)<2,abs(actual.minY-point.y)<2,abs(actual.width-size.width)<2,abs(actual.height-size.height)<2 else {throw NativeTargetError.geometry}
  print("Verified requested window frame");exit(0)
 } catch {fputs("Window frame not verified: \(error)\n",stderr);exit(1)}
}
if let index = CommandLine.arguments.firstIndex(of: "--window-half"), CommandLine.arguments.count > index + 2 {
 do {
  guard let id=UInt32(CommandLine.arguments[index+1]),let pid=Int32(CommandLine.arguments[index+2]) else {throw NativeTargetError.missing}
  let target=try NativeWindowTarget.resolve(id:id,pid:pid)
  var desired=target.visibleFrame.insetBy(dx:8,dy:8);desired.size.width=floor((desired.width-8)/2)
  func setFrame(_ frame:CGRect) throws {
   var point=frame.origin,size=frame.size
   guard let p=AXValueCreate(.cgPoint,&point),let z=AXValueCreate(.cgSize,&size),
    AXUIElementSetAttributeValue(target.element,kAXPositionAttribute as CFString,p) == .success,
    AXUIElementSetAttributeValue(target.element,kAXSizeAttribute as CFString,z) == .success else {throw NativeTargetError.geometry}
   RunLoop.current.run(until:Date(timeIntervalSinceNow:0.08))
   guard AXUIElementSetAttributeValue(target.element,kAXPositionAttribute as CFString,p) == .success else {throw NativeTargetError.geometry}
  }
  do {
   try setFrame(desired)
   // Native apps may settle their constraints on a later run-loop iteration.
   RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15))
   let actual=try NativeWindowTarget.resolve(id:id,pid:pid).frame
   guard abs(actual.minX-desired.minX)<2,abs(actual.minY-desired.minY)<2,
    abs(actual.width-desired.width)<2,abs(actual.height-desired.height)<2 else {fputs("Requested \(desired), got \(actual)\n",stderr);throw NativeTargetError.geometry}
   print("Verified exact half-screen for selected window");exit(0)
  } catch {try? setFrame(target.frame);throw error}
 } catch {fputs("Half-screen refused or rolled back: \(error)\n",stderr);exit(1)}
}
if let index = CommandLine.arguments.firstIndex(of: "--window-target"), CommandLine.arguments.count > index + 2 {
 do {
  guard let id = UInt32(CommandLine.arguments[index+1]), let pid = Int32(CommandLine.arguments[index+2]) else {throw NativeTargetError.missing}
  let target = try NativeWindowTarget.resolve(id:id,pid:pid)
  func rect(_ r:CGRect)->[Double] {[r.minX,r.minY,r.width,r.height].map(Double.init)}
  let data = try JSONSerialization.data(withJSONObject:["windowID":id,"pid":pid,"frame":rect(target.frame),"visibleFrame":rect(target.visibleFrame)])
  print(String(data:data,encoding:.utf8)!);exit(0)
 } catch {fputs("Cannot resolve exact window and display: \(error)\n",stderr);exit(1)}
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
 private(set) var accent = NSColor(calibratedRed:0.55,green:0.9,blue:0.35,alpha:1)
 private var silhouette = NSBezierPath()
 init(logo: String) {
  if let image=NSImage(contentsOfFile:logo),let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data) {
   let left=Int(Double(bitmap.pixelsWide)*0.239), top=Int(Double(bitmap.pixelsHigh)*0.608)
   let right=Int(Double(bitmap.pixelsWide)*0.760), bottom=Int(Double(bitmap.pixelsHigh)*0.752)
   for y in stride(from:top,to:bottom,by:2) {for x in stride(from:left,to:right,by:2) {
    if let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB), c.greenComponent>0.48 && c.greenComponent>c.blueComponent*1.2 {
     silhouette.appendRect(NSRect(x:Double(x-left)/Double(right-left)*47,y:Double(bottom-y)/Double(bottom-top)*13,width:0.20,height:0.20))
    }
   }}
  }
 }
 func refreshPalette() {
  guard let screen=NSScreen.main ?? NSScreen.screens.first,var url=NSWorkspace.shared.desktopImageURL(for:screen) else {return}
  // macOS can report DefaultDesktop for a wallpaper owned by its newer wallpaper service.
  // In that case use the wallpaper selected through Omac's own appearance menu.
  if url.lastPathComponent=="DefaultDesktop.heic",let choice=try? String(contentsOf:wallpaperChoice,encoding:.utf8) {
   let selected=URL(fileURLWithPath:root+"/branding/wallpapers/omac-"+choice+".png")
   if FileManager.default.fileExists(atPath:selected.path) {url=selected}
  }
  guard url != wallpaperURL else {return}
  wallpaperURL=url
  guard let image=NSImage(contentsOf:url) else {return}
  let small=NSImage(size:NSSize(width:64,height:36));small.lockFocus();image.draw(in:NSRect(x:0,y:0,width:64,height:36));small.unlockFocus()
  guard let data=small.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data) else {return}
  var bins=Array(repeating:(weight:CGFloat(0),r:CGFloat(0),g:CGFloat(0),b:CGFloat(0)),count:24)
  for y in 0..<bitmap.pixelsHigh {for x in 0..<bitmap.pixelsWide {
   guard let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.saturationComponent>0.35,c.brightnessComponent>0.15 else {continue}
   let i=min(23,Int(c.hueComponent*24)),w=c.saturationComponent*c.brightnessComponent*c.brightnessComponent
   bins[i].weight += w;bins[i].r += c.redComponent*w;bins[i].g += c.greenComponent*w;bins[i].b += c.blueComponent*w
  }}
  if let best=bins.max(by:{$0.weight<$1.weight}),best.weight>0 {
   let c=NSColor(calibratedRed:best.r/best.weight,green:best.g/best.weight,blue:best.b/best.weight,alpha:1)
   accent=NSColor(calibratedHue:c.hueComponent,saturation:min(0.65,c.saturationComponent),brightness:0.95,alpha:1)
  } else {accent = .lightGray}
 }
 func image(page:Int,status:String)->NSImage {
  refreshPalette()
  let image=NSImage(size:NSSize(width:168,height:22));image.lockFocus()
  let active=status=="Active", color=active ? accent:NSColor.secondaryLabelColor
  NSGraphicsContext.saveGraphicsState();let transform=NSAffineTransform();transform.translateX(by:0,yBy:4);transform.concat();color.setFill();silhouette.fill();NSGraphicsContext.restoreGraphicsState()
  for n in 1...5 {
   let r=NSRect(x:56+(n-1)*22,y:2,width:19,height:18)
   let p=NSBezierPath(roundedRect:r,xRadius:5,yRadius:5)
   if n==page && active {color.withAlphaComponent(0.27).setFill();p.fill();color.setStroke();p.lineWidth=1;p.stroke()}
   let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:n==page ? .bold:.medium),.foregroundColor:color.withAlphaComponent(n==page ? 1:0.55)]
   let text="\(n)" as NSString, size=text.size(withAttributes:attributes)
   text.draw(at:NSPoint(x:r.midX-size.width/2,y:r.midY-size.height/2),withAttributes:attributes)
  }
  image.unlockFocus();image.isTemplate=false;return image
 }
}

class GuidePanel: NSPanel {
 override func cancelOperation(_ sender:Any?) {orderOut(nil)}
}
class Delegate: NSObject,NSApplicationDelegate {
 var item:NSStatusItem!; var busy=false; var guide:GuidePanel?
 let brandBar=OmacBrandBar(logo:root+"/branding/Omac.png")
 var barTimer:Timer?;var barRefreshing=false
 private let shortcutQueue=DispatchQueue(label:"com.richard.omac.shortcut-routing")
 @objc func routeShortcuts(_ note:Notification? = nil) {
  let remote=NSWorkspace.shared.frontmostApplication?.bundleIdentifier=="com.apple.ScreenSharing"
  shortcutQueue.async {
   let active=(try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8))=="Active"
   let desired=active && !remote ? "active":"main"
   _=process(aerospace ?? "/missing/aerospace",["mode",desired])
  }
 }
 func statusTitle(_ text:String) { refreshBar();routeShortcuts() }
 func refreshBar() {
  guard !barRefreshing else {return};barRefreshing=true
  DispatchQueue.global(qos:.utility).async {
   let result=process(aerospace ?? "/missing/aerospace",["list-workspaces","--focused"])
   let page=Int(result.1.trimmingCharacters(in:.whitespacesAndNewlines)) ?? 0
   let status=(try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8)) ?? "Inactive"
   DispatchQueue.main.async {
    self.barRefreshing=false
    self.item.button?.title=""
    self.item.button?.image=self.brandBar.image(page:page,status:status)
    self.item.button?.toolTip="Omac · \(status) · Page \(page) · Command 1–5 to switch"
    self.item.button?.setAccessibilityLabel("Omac, \(status), page \(page) of 5")
   }
  }
 }
 @objc func engageNotification(_ note:Notification) {try? FileManager.default.removeItem(at:state.appendingPathComponent("engage.request"));perform("enter")}
 func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {perform("enter");return true}
 func applicationDockMenu(_ sender:NSApplication)->NSMenu? {item.menu}

 func applicationDidFinishLaunching(_ note:Notification) {
  NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(routeShortcuts(_:)),name:NSWorkspace.didActivateApplicationNotification,object:nil)
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
  if let text=event.paramDescriptor(forKeyword:AEKeyword(keyDirectObject))?.stringValue, let action=URL(string:text)?.host, ["exit","pause","enter","four","six","new","guide","menu","center","rescue","refocus"].contains(action) {perform(action)}
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
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.appearance=NSAppearance(named:.darkAqua)
    let web=WKWebView(frame:panel.contentView!.bounds);web.autoresizingMask=[.width,.height]
    web.setValue(false,forKey:"drawsBackground")
    web.loadFileURL(URL(fileURLWithPath:root+"/Guide.html"),allowingReadAccessTo:URL(fileURLWithPath:root))
    panel.contentView=web;guide=panel
   }
   guard let panel=guide else {return}
   // A nonactivating palette accepts keys without focusing the app's old workspace.
   panel.center();panel.makeKeyAndOrderFront(nil);panel.orderFrontRegardless()

 }
 func perform(_ action:String) {
  if action=="rescue" || action=="refocus" {
   guard (try? String(contentsOf:state.appendingPathComponent("status"),encoding:.utf8))=="Active" else {return}
   guide?.orderOut(nil);item.menu?.cancelTracking()
   DispatchQueue.global().async {
    let aero=aerospace ?? "/missing/aerospace"
    let current=process(aero,["list-workspaces","--focused"]).1.trimmingCharacters(in:.whitespacesAndNewlines)
    guard ["1","2","3","4","5"].contains(current) else {return}
    if action=="rescue" {_=process(aero,["focus","--dfs-index","0"])}
    let output=process(aero,["list-windows","--focused","--format","%{window-id} %{app-pid} %{window-layout}"])
    var fields=output.1.split(whereSeparator:{$0.isWhitespace}).map(String.init)
    let excludedLayouts=action=="rescue" ? ["floating","macos_native_window_of_hidden_app","macos_fullscreen"] : ["macos_native_window_of_hidden_app"]
    if fields.count >= 3 && excludedLayouts.contains(fields[2]) {
     let inventory=process(aero,["list-windows","--workspace",current,"--json"])
     if let data=inventory.1.data(using:.utf8),let rows=(try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]],rows.count>1 {
      for index in 1..<rows.count {
       _=process(aero,["focus","--dfs-index",String(index)])
       let next=process(aero,["list-windows","--focused","--format","%{window-id} %{app-pid} %{window-layout}"])
       fields=next.1.split(whereSeparator:{$0.isWhitespace}).map(String.init)
       if fields.count>=3 && !excludedLayouts.contains(fields[2]) {break}
      }
     }
    }
    var chosenID=(fields.count >= 3 && !excludedLayouts.contains(fields[2])) ? Int(fields[0]) : nil
    var chosenPID=(fields.count >= 3 && !excludedLayouts.contains(fields[2])) ? Int32(fields[1]) : nil
    var chosenWindow:AXUIElement?

    // Recover only a confirmed minimized window from this boot and the same
    // app instance. A stale process ID must never activate an unrelated app.
    if action=="rescue",chosenPID == nil,
       let data=try? Data(contentsOf:state.appendingPathComponent("pages.json")),
       let saved=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
       saved["boot"] as? String == process("/usr/sbin/sysctl",["-n","kern.boottime"]).1.trimmingCharacters(in:.whitespacesAndNewlines),
       let modified=(try? FileManager.default.attributesOfItem(atPath:state.appendingPathComponent("pages.json").path)[.modificationDate]) as? Date,
       let rows=saved["windows"] as? [[String:Any]] {
     var candidates:[(CGFloat,CGFloat,Int32,AXUIElement)]=[]
     for row in rows where (row["workspace"] as? String)==current {
      if excludedLayouts.contains(row["window-layout"] as? String ?? "") {continue}
      guard let rawPID=row["app-pid"] as? Int,rawPID != Int(ProcessInfo.processInfo.processIdentifier) else {continue}
      guard let pid=Int32(exactly:rawPID),let app=NSRunningApplication(processIdentifier:pid),
            let launched=app.launchDate,launched<=modified,
            app.localizedName == row["app-name"] as? String,
            let wanted=row["window-title"] as? String,!wanted.isEmpty else {continue}
      let application=AXUIElementCreateApplication(pid);var listValue:CFTypeRef?
      AXUIElementSetMessagingTimeout(application,0.5)
      guard AXUIElementCopyAttributeValue(application,kAXWindowsAttribute as CFString,&listValue) == .success,
            let list=listValue as? [AXUIElement] else {continue}
      for window in list {
       var titleValue:CFTypeRef?,minimizedValue:CFTypeRef?
       _=AXUIElementCopyAttributeValue(window,kAXTitleAttribute as CFString,&titleValue)
       _=AXUIElementCopyAttributeValue(window,kAXMinimizedAttribute as CFString,&minimizedValue)
       guard (titleValue as? String)==wanted,(minimizedValue as? Bool)==true else {continue}
       var point=CGPoint.zero,positionValue:CFTypeRef?
       if AXUIElementCopyAttributeValue(window,kAXPositionAttribute as CFString,&positionValue) == .success,
          let positionValue=positionValue,CFGetTypeID(positionValue)==AXValueGetTypeID() {
        AXValueGetValue(unsafeBitCast(positionValue,to:AXValue.self),.cgPoint,&point)
       }
       candidates.append((point.y,point.x,pid,window))
      }
     }
     if let first=candidates.sorted(by:{$0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0}).first {
      chosenID=nil;chosenPID=first.2;chosenWindow=first.3
     }
    }
    guard let pid=chosenPID else {return}
    DispatchQueue.main.async {
     guard let target=NSRunningApplication(processIdentifier:pid) else {return}
     let application=AXUIElementCreateApplication(pid);var window=chosenWindow
     if window == nil {var value:CFTypeRef?;if AXUIElementCopyAttributeValue(application,kAXFocusedWindowAttribute as CFString,&value) == .success,let value=value {window=unsafeBitCast(value,to:AXUIElement.self)}}
     if let window=window {
      AXUIElementSetAttributeValue(window,kAXMinimizedAttribute as CFString,kCFBooleanFalse)
      AXUIElementSetAttributeValue(application,kAXFocusedWindowAttribute as CFString,window)
      AXUIElementSetAttributeValue(window,kAXMainAttribute as CFString,kCFBooleanTrue)
      AXUIElementPerformAction(window,kAXRaiseAction as CFString)
     }
     target.activate(options:[])
     _=process(aero,["workspace",current])
     if let id=chosenID {_=process(aero,["focus","--window-id",String(id)])}
    }
   }
   return
  }

  if action=="menu" {
   guide?.orderOut(nil)
   guard let menu=item.menu else {return}
   let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main
   let frame=screen?.visibleFrame ?? NSRect(x:0,y:0,width:1000,height:700)
   menu.popUp(positioning:menu.items.first,at:NSPoint(x:frame.midX-140,y:frame.midY+160),in:nil)
   return
  }

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
