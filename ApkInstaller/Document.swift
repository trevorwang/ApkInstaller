//
//  Document.swift
//  ApkInstaller
//
//  Created by MingWang on 8/25/14.
//  Copyright (c) 2014 MingWang. All rights reserved.
//

import Cocoa
import IOKit

class Document: NSDocument {
    weak var currentWindow: NSWindow!
    var appInfo = [String:String]()
    
    @IBOutlet weak var appIcon: NSImageView!
    @IBOutlet weak var appLabel: NSTextField!
    @IBOutlet weak var deviceCombo: NSComboBox!
    @IBOutlet weak var uninstallOldApk: NSButton!
    @IBOutlet weak var cancelButton: NSButton!
    @IBOutlet weak var installButton: NSButton!
    @IBOutlet weak var versionCode: NSTextField!
    @IBOutlet weak var versionName: NSTextField!
    @IBOutlet weak var appSize: NSTextField!
    @IBOutlet weak var progress: NSProgressIndicator!
    @IBOutlet weak var errorMessage: NSTextField!
    
    @IBAction func install(sender: NSButton) {
        installButton.enabled = false
        progress.hidden = false
        progress.startAnimation(self)
        errorMessage.hidden = false
        errorMessage.stringValue = "Installing..."
        installApk()
    }
    
    @IBAction func cancel(sender: NSButton) {
        if currentWindow != nil {
            currentWindow.close()
        }
    }
    
    override init() {
        super.init()
        
        appInfo["iconFile"] = "/tmp/icon.png"
    }

    override func windowControllerDidLoadNib(aController: NSWindowController) {
        super.windowControllerDidLoadNib(aController)
        
        currentWindow = aController.window
        appLabel.stringValue = appInfo["label"]
        appIcon.image = NSImage(contentsOfFile: appInfo["iconFile"])
        let vcode = appInfo["versionCode"]
        let vname = appInfo["versionName"]
        let size = appInfo["size"]
        versionCode.stringValue = "Version Code: \(vcode!)"
        versionName.stringValue = "Version Name: \(vname!)"
        appSize.stringValue = "Size: \(size!)"
        deviceCombo.addItemsWithObjectValues(listDevices())
        deviceCombo.enabled = deviceCombo.objectValues.count > 0
        installButton.enabled = deviceCombo.enabled
        deviceCombo.resetCursorRects()
        if deviceCombo.objectValues.count == 0 {
            deviceCombo.stringValue = "No Device"
        } else {
            deviceCombo.selectItemAtIndex(0)
        }
                                    
    }

    override var windowNibName: String {
        // Returns the nib file name of the document
        // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this property and override -makeWindowControllers instead.
        return "Document"
    }

    override func dataOfType(typeName: String?, error outError: NSErrorPointer) -> NSData? {
        // Insert code here to write your document to data of the specified type. If outError != nil, ensure that you create and set an appropriate error when returning nil.
        // You can also choose to override fileWrapperOfType:error:, writeToURL:ofType:error:, or writeToURL:ofType:forSaveOperation:originalContentsURL:error: instead.
        outError.memory = NSError.errorWithDomain(NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        return nil
    }
    
    override func readFromURL(url: NSURL!, ofType typeName: String!, error outError: NSErrorPointer) -> Bool {
        appInfo["path"] = url.path
        NSLog("file path is %@", appInfo["path"]!)
        dumpAppInfo(appInfo["path"]!)
        return true
    }
    
    func dumpAppInfo(path: String) {
        var result = runCommand(loadAppCmd("aapt d badging \(path)"))
        appInfo["package"] = firstStringWithPattern("package: name='([\\w|.|-|_]+)'", target: result)
        appInfo["label"] = firstStringWithPattern("application-label:'([\\w|\\s|.|-|_]+)'" ,target:result)
        appInfo["icon"] = firstStringWithPattern(".*icon='(.+)'" ,target:result)
        appInfo["versionCode"] = firstStringWithPattern("versionCode='(\\d+)'" ,target:result)
        appInfo["versionName"] = firstStringWithPattern("versionName='(.+)'" ,target:result)
        let file = NSFileManager.defaultManager().attributesOfItemAtPath(appInfo["path"], error: nil) as NSDictionary!
        appInfo["size"] = NSByteCountFormatter.stringFromByteCount(Int64(file.fileSize()), countStyle: NSByteCountFormatterCountStyle.File);
        NSLog("app info : %@, result : %@", appInfo, result)
        unzipAppIcon()
    }
    
    func installApk() {
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        dispatch_async(queue, {
            NSLog("Execute cmd in block")
            let device = self.deviceCombo.objectValueOfSelectedItem as String
            let cmd = NSString(format: "adb -s %@ install -r %@", device, self.appInfo["path"]!)
            let result = self.runCommand(self.loadAppCmd(cmd))
            NSLog("Execure cmd : %@, result is:\n%@", cmd, result)
            
            dispatch_async(dispatch_get_main_queue(), {
                self.installButton.enabled = true
                self.progress.hidden = true
                
                
                let re = result.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()).componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
                NSLog("result : %@", re)
                self.errorMessage.stringValue = re.last
            })
        })
    }
    
    func listDevices() -> [String] {
        var devices : Array<String> = []
        let result = runCommand(loadAppCmd("adb devices"))
        let re = firstStringWithPattern("((\\w+\\s+device\\s+)+)", target:result)
        for string in re.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet()) {
            let dev = firstStringWithPattern("(\\w+)\\s+device", target: string)
            if !dev.isEmpty {
                devices.append(dev)
            }
        }
        NSLog("device list : %@,  reuslt :\n%@", devices, result)
        return devices
    }
    
    
    func firstStringWithPattern(pattern:String, target:String) -> String{
        var err : NSError?
        let value = target as NSString
        let options = NSRegularExpressionOptions(0)
        let re = NSRegularExpression(pattern: pattern, options: options, error: &err)
        
        let all = NSRange(location: 0, length: value.length)
        let moptions = NSMatchingOptions(0)
        let match = re.firstMatchInString(value, options: moptions, range: all) as NSTextCheckingResult!
        var range : NSRange
        if match != nil {
            if match.numberOfRanges > 1 {
                range = match.rangeAtIndex(1)
            } else {
                range = match.range
            }
            return value.substringWithRange(range)

        }
        return ""
    }
    
    func runCommand(cmd:String) -> String {
        var pipe = NSPipe()
        var file = pipe.fileHandleForReading
        var task = NSTask()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", cmd]
        task.standardOutput = pipe
        task.launch()
        return NSString(data: file.readDataToEndOfFile(), encoding: NSUTF8StringEncoding)
    }

    func loadAppCmd(cmd: String) -> String {
        return NSString(format: "%@/%@", NSBundle.mainBundle().resourcePath!, cmd)
    }
    
    func unzipAppIcon() {
        var iconFile = appInfo["iconFile"]
        runCommand("rm -rf \(iconFile!)")
        
        var path = appInfo["path"]
        var icon = appInfo["icon"]
        runCommand(NSString(format: "unzip -p %@ %@ > %@", path!, icon!, iconFile!))
    }
    
//    func SignalHandler() {
//        NSLog("\nInterrupted")
//    }
//    
//    func observeUSBDevice() {
//        var matchingDict:CFMutableDictionaryRef
//        var runLoopSource:CFRunLoopSourceRef
//        var numberRef:CFNumberRef
//        var oldHandler:sig_t
//
//        let oldHandler = signal(SIGINT, SignalHandler)
//        if oldHandler == SIG_ERR {
//            NSLog("Could not establish new signal handler.")
//        }
//    }
}

